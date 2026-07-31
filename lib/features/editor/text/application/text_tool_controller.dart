import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../application/document_controller.dart';
import '../../application/editing_controller.dart';
import '../../engine/commands/layer_state_commands.dart';
import '../../engine/commands/text_commands.dart';
import '../../engine/commands/transform_commands.dart';
import '../../engine/core/canvas_sizing.dart';
import '../../engine/core/layer_transform.dart';
import '../../engine/modules/text/text_layer.dart';
import '../../application/recent_colors_controller.dart';
import '../../application/selection_controller.dart';
import '../domain/text_style_presets.dart';
import 'text_color_resolver.dart';
import 'text_metrics.dart';
import 'text_session.dart';
import 'text_style_writer.dart';

export 'text_session.dart';

const _uuid = Uuid();

/// Reactive text-tool state.
///
/// Acts as the single mutation point for all text styling. The
/// controller is intentionally split between **mode state** (panel
/// open/close) and **style state** (defaults + selection sync). Style
/// setters route through [TextStyleWriter.applyStyle] which:
///
///   1. Updates the session's default style (so the toolbar always
///      reflects the latest user intent).
///   2. If a [TextLayer] is currently selected, mirrors the change to
///      that layer via [UpdateTextCommand] — every style edit becomes
///      one undoable step.
///
/// This is the same pattern used by Figma / Pages / Keynote: when a
/// text layer is selected the toolbar drives that layer; when nothing
/// is selected the toolbar is configuring the *next* layer to be
/// created.
///
/// Three responsibilities used to live in this one class; roadmap 5.6
/// split the latter two out and left this file owning the first:
///
///   * **Dock UI state** — [TextSession] plus the panel / sheet
///     mutators below, and the public setter vocabulary the panels
///     call.
///   * **[TextStyleWriter]** (`text_style_writer.dart`) — the single
///     guarded gateway through which every style / content / resize
///     write reaches history, plus the live-edit and style-drag
///     sessions that decide whether a write lands on the overlay or
///     in the undo stack.
///   * **[TextMetrics]** (`text_metrics.dart`) — the measurement and
///     insertion-size maths (bounding-box measures, canvas-relative
///     font scaling, the visual-scale write/readout pair).
class TextToolController extends Notifier<TextSession> {
  @override
  TextSession build() {
    // Sheet persistence rule: sheets close on
    //   * explicit user action (Done pill, re-tap same tile,
    //     mode-exit, sibling-swipe), AND
    //   * any selection change — wired centrally from
    //     `closeObjectSubPanels` in `editor_lifecycle.dart` via the
    //     selection-change listener in `EditorScreen.build`. This
    //     prevents the "panel silently re-mounts on re-select"
    //     class of bug (e.g. Font sheet reopening after the user
    //     tapped through to another layer and back).
    return TextSession.initial;
  }

  /// The write seam. Owns the live-edit / style-drag sessions and
  /// every document write that carries text style, content, or a
  /// measured transform. See `text_style_writer.dart`.
  ///
  /// Initialized as a lazy field rather than inside [build] on
  /// purpose: the sessions it holds are per-notifier-instance state
  /// (they were plain nullable fields on this class before the
  /// split), so a `build()` re-run must not hand out a fresh writer
  /// and silently orphan an open session.
  late final TextStyleWriter _writer = TextStyleWriter(
    ref: ref,
    readDefaultStyle: () => state.defaultStyle,
    writeDefaultStyle: (next) => state = state.copyWith(defaultStyle: next),
  );

  // ─── mode ────────────────────────────────────────────────────────

  void openPanel() {
    if (state.panelOpen) return;
    state = state.copyWith(panelOpen: true);
  }

  void closePanel() {
    if (!state.panelOpen) return;
    // Closing the panel also clears the editing flag so the inline
    // text field is dismissed; selection is intentionally preserved
    // so the user can re-open and keep working with the same layer.
    ref.read(editingControllerProvider.notifier).stop();
    state = state.copyWith(panelOpen: false, clearOpenSheet: true);
  }

  /// Wipe all ephemeral text-tool UI state back to [TextSession.initial].
  /// Intended for project-switch boundaries (open/new project, leave
  /// editor) so a fresh project never inherits the previous one's
  /// open sheet, active category, sticky preset highlight, recent
  /// colours, or `defaultStyle` overrides. Saved layer styles are
  /// untouched — they live on the document, not on the session.
  void resetSession() {
    ref.read(editingControllerProvider.notifier).stop();
    state = TextSession.initial;
  }

  // ─── in-dock tool sheets ────────────────────────────────
  //
  // The text dock's tile strip opens per-tool sheets that render
  // inline in the dock's `expanded` slot. Canvas reflows above
  // the dock so the user always sees the layer they're editing.

  /// Open a tool sheet (e.g. `'style'`, `'background'`, `'size'`).
  /// Tapping the same id while open closes it.
  void toggleSheet(String sheetId) {
    if (state.openSheet == sheetId) {
      state = state.copyWith(clearOpenSheet: true);
    } else {
      state = state.copyWith(openSheet: sheetId);
    }
  }

  /// Non-toggling variant: opens the sheet for [sheetId] if it's
  /// not already the active one. Re-tapping the active tile is a
  /// no-op so users can't accidentally dismiss the sheet by
  /// tapping the same tile twice. Dismissal is via the drag
  /// handle, swipe-down, or the Done pill.
  void openSheet(String sheetId) {
    if (state.openSheet == sheetId) return;
    state = state.copyWith(openSheet: sheetId);
  }

  /// Force the in-dock tool sheet closed. Also clears any sticky
  /// preset highlight so the dismissal is visually total — used
  /// both by the Done pill and by empty-canvas / pasteboard taps
  /// when no layer remains selected. The user-tuned `defaultStyle`,
  /// recent colours, and saved layer styles are preserved.
  void closeSheet() {
    if (state.openSheet == null && state.selectedSizePreset == null) {
      return;
    }
    state = state.copyWith(clearOpenSheet: true, clearSelectedSizePreset: true);
  }

  // ─── style writes ────────────────────────────────────────────────
  //
  // Every setter below is a thin vocabulary layer over the write
  // seam: it shapes the [TextStyleSpec] mutation (and any dock-state
  // side effect such as clearing the sticky size-preset highlight)
  // and hands it to [TextStyleWriter.applyStyle], which owns session
  // resolution, the re-measure policy, and the single guarded path to
  // history.

  void setColor(Color color) =>
      _writer.applyStyle((s) => s.copyWith(color: color));

  /// [live] marks the write as part of a stepper/nudge burst (the
  /// −/＋ pair repeat-firing) — the sanctioned use of history-window
  /// coalescing after the tb2 6/16 merge-gate flip. Slider ticks
  /// arrive inside a style-drag session (overlay-only) and exact-px
  /// entries are discrete, so both leave it `false`.
  void setFontSize(double size, {bool live = false}) {
    // Manual size mutation (A+/A−/slider/exact px) clears any
    // sticky preset highlight so the chip row no longer pretends
    // the user is still on M/L/XL/etc.
    if (state.selectedSizePreset != null) {
      state = state.copyWith(clearSelectedSizePreset: true);
    }
    final translated = TextMetrics.translateFontSizeForVisualScale(
      selectedTextLayer(),
      size,
    );
    _writer.applyStyle((s) => s.copyWith(fontSize: translated), live: live);
  }

  /// Apply a font size that came from tapping a named preset chip
  /// (S/M/L/XL/XXL). Pins the chip row to [presetLabel] for the
  /// active layer so subsequent rebuilds keep the right chip
  /// highlighted, even when canvas-aware preset values land
  /// numerically close to one another (e.g. on a 100×100 canvas).
  void setFontSizeFromPreset({
    required double size,
    required String presetLabel,
    required String layerId,
  }) {
    state = state.copyWith(
      selectedSizePreset: (label: presetLabel, layerId: layerId),
    );
    final translated = TextMetrics.translateFontSizeForVisualScale(
      selectedTextLayer(),
      size,
    );
    _writer.applyStyle((s) => s.copyWith(fontSize: translated));
  }

  /// Visual (rendered) px of [layer]'s glyphs — what the size chip
  /// and quick-capsule readouts must display. Delegates to
  /// [TextMetrics.visualFontSizeOf], which mirrors the WRITE space of
  /// [TextMetrics.translateFontSizeForVisualScale] exactly. Writes
  /// stay raw; only readouts consume this.
  double visualFontSizeOf(TextLayer layer) =>
      TextMetrics.visualFontSizeOf(layer);

  /// Switch the typeface. Pass `null` to fall back to the system
  /// default. Family must match a registered entry in
  /// `pubspec.yaml` / `kFontCatalog`.
  void setFontFamily(String? family) => _writer.applyStyle(
    (s) => s.copyWith(fontFamily: family, clearFontFamily: family == null),
  );

  /// Bold is exposed as a boolean toggle in Phase-1; mapped to the
  /// nearest standard weight (w400 / w700) so the change is visually
  /// crisp regardless of the font's available weights.
  /// w700 / w400 — deliberately straddling the w600 synthesis
  /// threshold (see [TextStyleSpec.isBold]) so the toggle is visible
  /// on single-face families, which is most of the catalogue.
  void setBold(bool bold) => _writer.applyStyle(
    (s) => s.copyWith(fontWeight: bold ? FontWeight.w700 : FontWeight.w400),
  );

  void setItalic(bool italic) =>
      _writer.applyStyle((s) => s.copyWith(italic: italic));

  void setUnderline(bool underline) =>
      _writer.applyStyle((s) => s.copyWith(underline: underline));

  void setAlignment(TextAlign alignment) =>
      _writer.applyStyle((s) => s.copyWith(alignment: alignment));

  void setLetterSpacing(double value) =>
      _writer.applyStyle((s) => s.copyWith(letterSpacing: value));

  void setLineHeight(double value) =>
      _writer.applyStyle((s) => s.copyWith(lineHeight: value));

  /// Keep color hue while changing alpha in [0..1].
  void setOpacity(double opacity) {
    final clamped = opacity.clamp(0.0, 1.0);
    _writer.applyStyle(
      (s) => s.copyWith(color: s.color.withValues(alpha: clamped)),
    );
  }

  // ─── shadow ──────────────────────────────────────────────────────
  //
  // Shadow is fully removed when [shadowColor] is null. Toggling on
  // seeds a sensible default (semi-transparent black, light blur, 2 px
  // down) so the user sees an immediate visual change without having
  // to dial in three numbers first. Blur and offset are seeded
  // canvas-aware via [CanvasSizing.scaleDimension] so the seeded
  // shadow reads at the same visual proportion on a 100×100 sticker
  // and on a 12000×12000 poster — the reference values
  // ([TextColorResolver.kDefaultShadowBlur] /
  // [TextMetrics.referenceShadowOffsetDy]) are authored against the
  // 1080-px reference canvas, just like every other text default.

  static const Color _defaultShadowColor = Color(0x66000000);

  void setShadowEnabled(bool enabled) {
    if (enabled) {
      final doc = ref.read(documentControllerProvider);
      final blur = CanvasSizing.scaleDimension(
        TextColorResolver.kDefaultShadowBlur,
        doc,
      );
      final offset = Offset(
        0,
        CanvasSizing.scaleDimension(TextMetrics.referenceShadowOffsetDy, doc),
      );
      _writer.applyStyle(
        (s) => s.shadowColor == null
            ? s.copyWith(
                shadowColor: _defaultShadowColor,
                shadowBlur: blur,
                shadowOffset: offset,
              )
            : s,
      );
    } else {
      _writer.applyStyle((s) => s.copyWith(clearShadow: true));
    }
  }

  void setShadowColor(Color color) =>
      _writer.applyStyle((s) => s.copyWith(shadowColor: color));

  void setShadowBlur(double blur) =>
      _writer.applyStyle((s) => s.copyWith(shadowBlur: blur.clamp(0.0, 40.0)));

  void setShadowOffset(Offset offset) =>
      _writer.applyStyle((s) => s.copyWith(shadowOffset: offset));

  // ─── outline (border) ────────────────────────────────────────────
  //
  // Glyph outline rendered as a stroked silhouette behind the fill.
  // Toggling on seeds opaque black at a canvas-aware width so the
  // outline reads at the same visual proportion regardless of
  // export size. The reference width is authored against the
  // 1080-px canvas; [CanvasSizing.scaleDimension] handles tiny /
  // huge canvases without per-size special cases.

  static const Color _defaultOutlineColor = Color(0xFF000000);

  /// Reference outline width (px against the 1080 canvas). Mirrors
  /// [TextStyleSpec.outlineWidth]'s default so a freshly-toggled
  /// outline matches the spec's at-rest value on the reference
  /// canvas.
  static const double _referenceOutlineWidth = 2.0;

  void setOutlineEnabled(bool enabled) {
    if (enabled) {
      final doc = ref.read(documentControllerProvider);
      final width = CanvasSizing.scaleDimension(
        _referenceOutlineWidth,
        doc,
      ).clamp(0.5, 20.0);
      _writer.applyStyle(
        (s) => s.outlineColor == null
            ? s.copyWith(
                outlineColor: _defaultOutlineColor,
                outlineWidth: width,
              )
            : s,
      );
    } else {
      _writer.applyStyle((s) => s.copyWith(clearOutline: true));
    }
  }

  void setOutlineColor(Color color) =>
      _writer.applyStyle((s) => s.copyWith(outlineColor: color));

  void setOutlineWidth(double width) => _writer.applyStyle(
    (s) => s.copyWith(outlineWidth: width.clamp(0.5, 20.0)),
  );

  // ─── background ──────────────────────────────────────────────────
  //
  // Same on/off model as shadow. Toggling on seeds a contrast-aware
  // fill so the text stays readable: light text gets a dark backplate
  // and vice versa. The default uses ~85% alpha so the underlying
  // canvas still peeks through, signalling the fill is configurable.
  // Padding around the text is seeded canvas-aware via
  // [CanvasSizing.scaleDimension] so the pill's breathing room
  // matches every other text default's "author-against-1080" rule.

  /// Reference horizontal padding (px against the 1080 canvas).
  /// Mirrors [TextStyleSpec.backgroundPaddingX]'s default.
  static const double _referenceBackgroundPaddingX = 8.0;

  /// Reference vertical padding (px against the 1080 canvas).
  /// Mirrors [TextStyleSpec.backgroundPaddingY]'s default.
  static const double _referenceBackgroundPaddingY = 4.0;

  /// Pick a contrast-aware default background for [textColor].
  /// Uses WCAG relative luminance: bright text → dark plate,
  /// dim text → light plate.
  static Color _defaultBackgroundFor(Color textColor) {
    // Approximate sRGB → linear → relative luminance.
    double channel(double c) => c <= 0.03928
        ? c / 12.92
        : ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055);
    final luminance =
        0.2126 * channel(textColor.r) +
        0.7152 * channel(textColor.g) +
        0.0722 * channel(textColor.b);
    final isLightText = luminance >= 0.5;
    return isLightText
        ? const Color(0xD9000000) // ~85% black plate for light text
        : const Color(0xD9FFFFFF); // ~85% white plate for dark text
  }

  void setBackgroundEnabled(bool enabled) {
    if (enabled) {
      final doc = ref.read(documentControllerProvider);
      // Seed padding canvas-aware so the pill's breathing room
      // reads at the same visual proportion on every canvas. Same
      // clamps as the manual setters so the seed value can never
      // land outside the slider range.
      final padX = CanvasSizing.scaleDimension(
        _referenceBackgroundPaddingX,
        doc,
      ).clamp(0.0, 64.0);
      final padY = CanvasSizing.scaleDimension(
        _referenceBackgroundPaddingY,
        doc,
      ).clamp(0.0, 64.0);
      _writer.applyStyle(
        (s) => s.backgroundColor == null
            ? s.copyWith(
                backgroundColor: _defaultBackgroundFor(s.color),
                backgroundPaddingX: padX,
                backgroundPaddingY: padY,
              )
            : s,
      );
    } else {
      _writer.applyStyle((s) => s.copyWith(clearBackground: true));
    }
  }

  void setBackgroundColor(Color color) =>
      _writer.applyStyle((s) => s.copyWith(backgroundColor: color));

  void setBackgroundRadius(double radius) => _writer.applyStyle(
    (s) => s.copyWith(backgroundRadius: radius.clamp(0.0, 1.0)),
  );

  void setBackgroundPaddingX(double px) => _writer.applyStyle(
    (s) => s.copyWith(backgroundPaddingX: px.clamp(0.0, 64.0)),
  );

  void setBackgroundPaddingY(double px) => _writer.applyStyle(
    (s) => s.copyWith(backgroundPaddingY: px.clamp(0.0, 64.0)),
  );

  /// Apply a one-tap *visual* style preset to the currently-selected
  /// text layer (or to [TextSession.defaultStyle] when nothing is
  /// selected, so the next add inherits the look).
  ///
  /// Styles are **cosmetic only**. Applying a preset never changes:
  ///   * `fontFamily`  — that's the Font tool's job
  ///   * `fontSize` / `letterSpacing` / `lineHeight` / `alignment`
  ///                   — those are size / paragraph tools
  ///   * `content`, position, rotation, or the layer's bounding box
  ///   * `resizeMode`
  ///
  /// What does change is the visual subset: text colour, background
  /// (color + radius + padding), outline (color + width), shadow
  /// (color + blur + offset), and `fontWeight` / `italic` /
  /// `underline` *only when the preset sets them*. The merge happens
  /// in [mergePresetVisual], so the same projection is used for the
  /// active-card highlight in the UI.
  void applyStylePreset(TextStyleSpec preset) {
    if (state.selectedSizePreset != null) {
      state = state.copyWith(clearSelectedSizePreset: true);
    }
    _writer.applyStylePreset(readableOnCanvas(preset));
  }

  /// [preset] with its text colour checked against what is actually
  /// behind the layer.
  ///
  /// Several presets are authored light-on-dark — `outline`, `neon`,
  /// `pop_3d`, `shadow_soft` all specify white with no plate — which
  /// on the default white canvas applied white text to white paper and
  /// made the layer vanish. `addCenteredText` has always run new text
  /// through [TextColorResolver]; picking a preset skipped it, so the
  /// one path where the user does NOT choose the colour was the one
  /// path with no guard.
  ///
  /// A preset that paints its own [TextStyleSpec.backgroundColor]
  /// plate is legible by construction and is left exactly as authored
  /// — the resolver samples the DOCUMENT behind the layer, which is
  /// not what such a preset sits on.
  /// Whether [preset] supplies its own contrast and must not be
  /// repainted.
  ///
  /// Three kinds of self-supplied contrast: a PLATE behind the glyphs,
  /// a STROKE around them, or a SHADOW that delineates them.
  ///
  /// Each arm asks whether the protective paint actually CONTRASTS with
  /// the fill — not merely whether it exists. Testing existence was the
  /// bug: `neon` is a near-white fill inside an opaque cyan glow, which
  /// satisfies "has a shadow, alpha high, blur > 0" and delineates
  /// nothing. Measured on the default white canvas its glyphs were
  /// 1.01:1 against the paper and 1.79:1 against their own glow — the
  /// word was only inferable from colour bleeding around letterforms
  /// with literally zero contrast. Geometry was the wrong axis.
  ///
  /// The shadow arm still needs the geometry check as well, because a
  /// zero-blur zero-offset shadow paints exactly under the glyphs and
  /// delineates nothing however dark it is.
  ///
  /// The resolver samples the DOCUMENT behind the layer, which is not
  /// what any of these three sit on.
  static bool _carriesOwnContrast(TextStyleSpec s) {
    // The plate arm has to composite. `glass` is `0x66000000` — 40%
    // black — which is opaque-vs-fill 21:1 but only 2.85:1 once it is
    // actually painted over white paper, below this module's own
    // kMinContrast. Measuring the authored colour and ignoring alpha
    // was the same existence-not-luminance mistake the shadow arm made.
    final plate = s.backgroundColor;
    if (plate != null) {
      final composited = Color.alphaBlend(plate, TextColorResolver.kCanvasFill);
      return TextColorResolver.contrastRatio(s.color, composited) >=
          TextColorResolver.kMinContrast;
    }

    const minContrast = TextColorResolver.kMinContrast;
    final outline = s.outlineColor;
    if (outline != null &&
        s.outlineWidth > 0 &&
        TextColorResolver.contrastRatio(s.color, outline) >= minContrast) {
      return true;
    }

    final shadow = s.shadowColor;
    if (shadow == null || shadow.a <= 0.25) return false;
    if (TextColorResolver.contrastRatio(s.color, shadow) < minContrast) {
      return false;
    }
    return s.shadowBlur > 0 || s.shadowOffset != Offset.zero;
  }

  /// [preset] with its text colour checked against what is actually
  /// behind the layer, so a preset can never be applied invisible.
  ///
  /// Presets that supply their own contrast are returned verbatim —
  /// see [_carriesOwnContrast]. Everything else goes through
  /// [TextColorResolver], the same guard `addCenteredText` has always
  /// run new text through; applying a preset used to skip it, so the
  /// one path where the USER does not choose the colour was the one
  /// path with no guard.
  /// [preset] with its fill re-resolved when nothing in the preset
  /// itself keeps the glyphs legible.
  ///
  /// A preset whose own paint carries the contrast (see
  /// [_carriesOwnContrast]) is returned exactly as authored — the
  /// resolver samples the DOCUMENT behind the layer, which is not what
  /// such a preset sits on. `outline` is the worked example: white fill
  /// inside a 3dp black stroke, and resolving it against white paper
  /// turned the fill near-black INSIDE that black stroke.
  ///
  /// When the preset DOES paint a plate but the plate is too weak to
  /// protect the fill, the resolve must run against the plate as
  /// painted, not against the document — the glyphs never touch the
  /// document. Resolving against the document instead made `glass`
  /// (40% black) actively worse across mid-greys: on a `#999999`
  /// backdrop it repainted white→near-black, and the near-black then
  /// landed on the plate's own `#5C5C5C`, ~4x worse than leaving it
  /// alone.
  TextStyleSpec readableOnCanvas(TextStyleSpec preset) {
    if (_carriesOwnContrast(preset)) return preset;
    final layer = selectedTextLayer();
    if (layer == null) return preset;
    final doc = ref.read(documentControllerProvider);
    final targetRect = layer.transform.position & layer.transform.size;
    final plate = preset.backgroundColor;
    final Color resolved;
    if (plate != null) {
      // The surface the glyphs actually land on: the plate composited
      // over whatever the document shows through it.
      final behind =
          TextColorResolver.sampleBackground(
            doc: doc,
            targetRect: targetRect,
          ) ??
          TextColorResolver.kCanvasFill;
      resolved = TextColorResolver.resolveAgainst(
        requested: preset.color,
        background: Color.alphaBlend(plate, behind),
      );
    } else {
      resolved = TextColorResolver.resolve(
        requested: preset.color,
        doc: doc,
        targetRect: targetRect,
      );
    }
    return resolved == preset.color ? preset : preset.copyWith(color: resolved);
  }

  /// Edit content of currently-selected text layer in one undoable step.
  void setContent(String content) {
    final layer = selectedTextLayer();
    if (layer == null || content == layer.content) return;
    _writer.executeTextWrite(
      UpdateTextCommand(
        layerId: layer.id,
        // content-only edit: leave style null so this never merges
        // with a preceding style edit.
        content: content,
      ),
    );
  }

  // ─── sessions (live edit + style drag) ───────────────────────────
  //
  // Thin delegations to [TextStyleWriter], which owns both session
  // snapshots. Kept on the controller because every caller — the
  // composer sheet, the dock sliders, the All-fonts preview — reaches
  // the text tool through this notifier.

  /// True while the user is actively editing or composing text via the
  /// bottom-sheet flow.
  bool get isLiveEditing => _writer.isLiveEditing;

  /// True while a style-drag session is open. Exposed so preview
  /// hosts (the All-fonts sheet's debounced highlight path) can
  /// make late callbacks inert after the session ended — a timer
  /// firing post-dismiss must not fall through to a real execute.
  bool get isStyleDragOpen => _writer.isStyleDragOpen;

  /// Open a style-drag session. Idempotent — nested begins are
  /// ignored so a chip tap inside an open drag still uses the
  /// existing snapshot.
  void beginStyleDrag() => _writer.beginStyleDrag();

  /// Abandon the style-drag session WITHOUT committing: the staged
  /// overlay preview is dropped and zero history entries are
  /// pushed. Used by preview surfaces whose dismissal means "keep
  /// what I had" — the All-fonts sheet closing un-picked (tb2
  /// 12/16). Safe no-op if no session is active.
  void cancelStyleDrag() => _writer.cancelStyleDrag();

  /// Commit the live drag as one undo entry. Restores the pre-drag
  /// document then re-applies the layer's current (drag-end) style
  /// via the normal execute path. Safe no-op if no session is active.
  void endStyleDrag() => _writer.endStyleDrag();

  /// Begin editing the currently selected text layer. No-op if nothing
  /// is selected or the selection is not a [TextLayer].
  void beginEditText() => _writer.beginEditText();

  /// Begin adding a new text layer. Stages an empty layer at the canvas
  /// center sized for one line of the current default style and
  /// selects it so the user immediately sees the bounding box appear
  /// where their text will land. Returns the staged layer id.
  ///
  /// On cancel / empty commit the staged layer is removed and the
  /// previous selection is restored.
  String beginAddText() {
    // Starting a new add must not inherit any open dock sheet /
    // sub-tool / sticky preset highlight from the previous layer
    // edit. Default style stays user-controlled (it represents
    // the "next layer" defaults), but every transient piece of UI
    // state is wiped so the add flow opens clean.
    if (state.openSheet != null || state.selectedSizePreset != null) {
      state = state.copyWith(
        clearOpenSheet: true,
        clearSelectedSizePreset: true,
      );
    }
    return _writer.beginAddText();
  }

  /// Live-preview [content] on the staged/edited layer. Safe no-op if
  /// no live session is active.
  void previewContent(String content) => _writer.previewContent(content);

  /// Confirm the live edit. Pushes ONE history entry covering the
  /// whole session. Empty / whitespace-only input is treated as cancel
  /// (no add for new flow, original preserved for edit flow).
  void commitLiveEdit(String content) => _writer.commitLiveEdit(content);

  /// Discard the live session. Restores docBefore + selectionBefore.
  /// Safe to call when no session is active.
  void cancelLiveEdit() => _writer.cancelLiveEdit();

  // ─── structural layer ops ────────────────────────────────────────
  //
  // Not style writes: these add / duplicate / lock / reorder whole
  // layers, so they dispatch straight to the document controller
  // rather than through the write seam (see the seam note in
  // `text_style_writer.dart`).

  /// Create a text layer centered in the current document and select it.
  /// Returns the created id (or null on empty/whitespace input).
  String? addCenteredText(String content) {
    final text = content.trim();
    if (text.isEmpty) return null;
    final doc = ref.read(documentControllerProvider);
    final id = _uuid.v4();
    // Canvas-relative font size — same proportional scaling as
    // [beginAddText] so quick-add text reads correctly on any
    // canvas size.
    final scaledStyle = TextMetrics.scaleStyleToCanvas(state.defaultStyle, doc);
    final layout = TextMetrics.resolveNewLayerLayout(text, scaledStyle, doc);
    final position = TextMetrics.centerOnCanvas(layout.size, doc);
    // Smart default colour — see [beginAddText] for the rationale.
    // Default (Persian) font seeded here too so quick-added text
    // never renders in the system face.
    final readableStyle = scaledStyle.copyWith(
      fontFamily: scaledStyle.fontFamily ?? defaultFontFamilyForContent(text),
      color: TextColorResolver.resolve(
        requested: scaledStyle.color,
        doc: doc,
        targetRect: position & layout.size,
      ),
    );
    // Default subtle drop-shadow — same rule as [beginAddText].
    final styled = TextMetrics.seedDefaultShadowIfMissing(readableStyle, doc);
    final layer = TextLayer(
      id: id,
      transform: LayerTransform(position: position, size: layout.size),
      content: text,
      style: styled,
      resizeMode: layout.mode,
    );
    ref
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(layer));
    ref.read(selectionControllerProvider.notifier).select(id);
    return id;
  }

  void duplicateSelectedText() {
    final layer = selectedTextLayer();
    if (layer == null) return;
    final id = _uuid.v4();
    final duplicate = TextLayer(
      id: id,
      transform: layer.transform.copyWith(
        position: layer.transform.position + const Offset(24, 24),
      ),
      content: layer.content,
      style: layer.style,
      resizeMode: layer.resizeMode,
      textDirectionMode: layer.textDirectionMode,
      name: layer.name,
      visible: layer.visible,
      locked: layer.locked,
    );
    ref
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(duplicate));
    ref.read(selectionControllerProvider.notifier).select(id);
  }

  void toggleSelectedLock() {
    final layer = selectedTextLayer();
    if (layer == null) return;
    ref
        .read(documentControllerProvider.notifier)
        .execute(SetLayerLockCommand(layerId: layer.id, locked: !layer.locked));
  }

  void arrangeSelectedForward() {
    final layer = selectedTextLayer();
    if (layer == null) return;
    final doc = ref.read(documentControllerProvider);
    final from = doc.indexOf(layer.id);
    if (from == null || from >= doc.layers.length - 1) return;
    ref
        .read(documentControllerProvider.notifier)
        .execute(ReorderLayerCommand(from: from, to: from + 1));
  }

  void arrangeSelectedBackward() {
    final layer = selectedTextLayer();
    if (layer == null) return;
    final doc = ref.read(documentControllerProvider);
    final from = doc.indexOf(layer.id);
    if (from == null || from <= 0) return;
    ref
        .read(documentControllerProvider.notifier)
        .execute(ReorderLayerCommand(from: from, to: from - 1));
  }

  /// Record a colour the user picked from the custom picker. Same MRU
  /// behaviour as paint: dedupe by ARGB, prepend, cap at
  /// [TextSession.recentsCap]. Presets are deliberately not added so
  /// the rail surfaces a meaningful history.
  void rememberRecentColor(Color color) {
    final argb = color.toARGB32();
    final filtered =
        state.recentColors
            .where((c) => c.toARGB32() != argb)
            .toList(growable: true)
          ..insert(0, color);
    if (filtered.length > TextSession.recentsCap) {
      filtered.removeRange(TextSession.recentsCap, filtered.length);
    }
    state = state.copyWith(recentColors: List<Color>.unmodifiable(filtered));
    // Mirror to the editor-wide store so customs picked in Text
    // surface in Shape / Image / Canvas / Paint panels too.
    ref.read(recentColorsControllerProvider.notifier).remember(color);
  }

  // ─── internal ────────────────────────────────────────────────────

  /// Read the currently-selected text layer (if any). Used by the
  /// toolbar to render against the selected layer's style instead of
  /// the session default. Delegates to the write seam, which reads the
  /// MERGED view so an in-flight live session is found.
  TextLayer? selectedTextLayer() => _writer.selectedTextLayer();

  /// Switch the resize behavior of the currently selected text layer.
  /// Bundles a re-measure of the bounding box into the same history
  /// entry so the box looks correct in the new mode immediately:
  ///
  /// * scaleText → natural text size (FittedBox will then scale 1:1).
  /// * resizeBox → keep current width, re-measure wrapped height.
  void setResizeMode(TextResizeMode mode) {
    final layer = selectedTextLayer();
    if (layer == null) return;
    if (layer.resizeMode == mode) return;
    final measured = TextMetrics.measureForMode(
      layer.content,
      layer.style,
      mode,
      layer.transform.size.width,
      textDirectionMode: layer.textDirectionMode,
    );
    final newTransform = measured == layer.transform.size
        ? null
        : layer.transform.copyWith(size: measured);
    _writer.executeTextWrite(
      SetTextResizeModeCommand(
        layerId: layer.id,
        mode: mode,
        transform: newTransform,
      ),
    );
  }

  /// Switch the paragraph direction mode of the selected text layer.
  /// Auto mode derives from the first strong script character; RTL
  /// and LTR force the base direction for mixed-script content.
  void setTextDirectionMode(TextDirectionMode mode) {
    final layer = selectedTextLayer();
    if (layer == null) return;
    if (layer.textDirectionMode == mode) return;
    final measured = TextMetrics.measureForMode(
      layer.content,
      layer.style,
      layer.resizeMode,
      layer.transform.size.width,
      textDirectionMode: mode,
    );
    final newTransform = measured == layer.transform.size
        ? null
        : layer.transform.copyWith(size: measured);
    _writer.executeTextWrite(
      SetTextDirectionModeCommand(
        layerId: layer.id,
        mode: mode,
        transform: newTransform,
      ),
    );
  }
}

final textToolControllerProvider =
    NotifierProvider<TextToolController, TextSession>(TextToolController.new);
