import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../application/document_controller.dart';
import '../../application/editing_controller.dart';
import '../../application/live_overlay_controller.dart';
import '../../application/selection_controller.dart';
import '../../engine/commands/editor_command.dart';
import '../../engine/commands/layer_state_commands.dart';
import '../../engine/commands/text_commands.dart';
import '../../engine/commands/transform_commands.dart';
import '../../engine/core/canvas_sizing.dart';
import '../../engine/core/editor_document.dart';
import '../../engine/core/layer_transform.dart';
import '../../engine/modules/text/text_layer.dart';
import '../../application/recent_colors_controller.dart';
import '../domain/text_style_presets.dart';
import 'text_color_resolver.dart';

const _uuid = Uuid();

/// Snapshot of the user's current text-tool configuration.
///
/// Holds **two** distinct concerns:
///   * Mode state: whether the text panel is open (`panelOpen`).
///   * Default style: [defaultStyle] — applied to NEW text layers
///     created while in text mode. Changing it without an active
///     selection updates the default; with a selection, the controller
///     also pushes the change to the selected layer (see
///     [TextToolController.applyStyleChange]).
///
/// Adding a new style dimension (font family, stroke, shadow, …) is a
/// single field on [TextStyleSpec] + a single setter here.
@immutable
class TextSession {
  const TextSession({
    this.panelOpen = false,
    this.openSheet,
    this.defaultStyle = const TextStyleSpec(),
    this.recentColors = const <Color>[],
    this.selectedSizePreset,
  });

  static const TextSession initial = TextSession();

  /// Whether the text-mode dock is currently shown.
  final bool panelOpen;

  /// Identifier of the tool sheet currently rendered inside the
  /// dock's expanded slot (e.g. `'style'`, `'background'`,
  /// `'border'`, `'size'`, …). `null` means no sheet is open and
  /// the dock collapses to just the tile strip. The sheet is
  /// rendered **inline** in the dock so the canvas reflows above
  /// it instead of being overlaid — mirrors Canva's mobile UX.
  final String? openSheet;

  /// Style applied to newly-added text layers. Also represents the
  /// "last known good" style when nothing is selected — the toolbar
  /// always renders against this when there's no selected text layer.
  final TextStyleSpec defaultStyle;

  /// MRU list of colours the user picked from the picker. Capped at
  /// [_recentsCap]; index 0 is the most recently used. Same convention
  /// as paint, so the picker UX feels identical between modes.
  final List<Color> recentColors;

  /// Sticky highlight for the Text Size sub-tool's S/M/L/XL/XXL chip
  /// row. Stored here (rather than in a transient `StatefulWidget`
  /// inside the sheet) because the sheet body widget can be
  /// dismounted and remounted across rebuilds — e.g. when the
  /// selected text layer momentarily goes null between a
  /// `setFontSize` write and the resulting auto-resize. Keyed by
  /// the layer id so switching to a different text layer does not
  /// inherit the previous layer's pinned preset. Cleared by any
  /// non-preset font-size mutation (A+/A−/slider/exact px).
  final ({String label, String layerId})? selectedSizePreset;

  static const int _recentsCap = 8;

  TextSession copyWith({
    bool? panelOpen,
    String? openSheet,
    bool clearOpenSheet = false,
    TextStyleSpec? defaultStyle,
    List<Color>? recentColors,
    ({String label, String layerId})? selectedSizePreset,
    bool clearSelectedSizePreset = false,
  }) {
    return TextSession(
      panelOpen: panelOpen ?? this.panelOpen,
      openSheet: clearOpenSheet ? null : (openSheet ?? this.openSheet),
      defaultStyle: defaultStyle ?? this.defaultStyle,
      recentColors: recentColors ?? this.recentColors,
      selectedSizePreset: clearSelectedSizePreset
          ? null
          : (selectedSizePreset ?? this.selectedSizePreset),
    );
  }
}

/// Reactive text-tool state.
///
/// Acts as the single mutation point for all text styling. The
/// controller is intentionally split between **mode state** (panel
/// open/close) and **style state** (defaults + selection sync). Style
/// setters route through [_applyStyle] which:
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
  // THE WRITE SEAM (tb2 12/16, contract §1/§2). Session resolution
  // for text writes lives in exactly two places:
  //   * [_applyStyle] — resolves default-style vs live-session
  //     overlay vs style-drag overlay vs committed write, including
  //     each branch's measure policy;
  //   * [applyStylePreset] — same resolution minus the auto-resize
  //     (presets must never move the user's box).
  // Every path that finally REACHES history does so through
  // [_executeTextWrite] below, which asserts no session is open —
  // a future setter that bypasses the resolvers and calls execute
  // directly while a session is live trips the assert in debug
  // instead of silently corrupting the session's docBefore
  // invariant (the audit's three-write-paths problem, reduced to
  // one guarded gateway). The only sanctioned direct executes are
  // the session terminators themselves ([endStyleDrag],
  // [commitLiveEdit]) — they run while their own session is being
  // closed — and structural layer ops (add/duplicate/lock/reorder)
  // that are not style writes.

  /// Single committed-write gateway for text style/content/resize
  /// writes. See the seam note above.
  void _executeTextWrite(EditorCommand command) {
    assert(
      _live == null && _styleDrag == null,
      'text write dispatched to history while a live/style-drag session '
      'is open — route through _applyStyle/applyStylePreset so it stages '
      'on the overlay instead',
    );
    ref.read(documentControllerProvider.notifier).execute(command);
  }

  void setColor(Color color) => _applyStyle((s) => s.copyWith(color: color));

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
    final translated = _translateFontSizeForVisualScale(size);
    _applyStyle((s) => s.copyWith(fontSize: translated), live: live);
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
    final translated = _translateFontSizeForVisualScale(size);
    _applyStyle((s) => s.copyWith(fontSize: translated));
  }

  /// When a `scaleText` layer's bounding box has been corner-dragged
  /// to a different size than its natural metrics, [TextStyleSpec.fontSize]
  /// no longer reflects what the user sees on canvas — the
  /// [FittedBox] in the renderer is multiplying it by the box's
  /// scale factor. The size sheet (stepper / slider / preset chips)
  /// computes its requests against `style.fontSize`, so applying
  /// them verbatim would snap the rendered glyphs back to the
  /// natural metrics and cause a visual jump.
  ///
  /// To keep the user's intent honest, we translate the requested
  /// `size` by the same scale factor — so a +10% bump in the
  /// stepper produces a +10% bump in the rendered glyph height,
  /// regardless of any prior corner drag. After the write, the
  /// box is re-measured to natural metrics for the new fontSize
  /// (via [_applyStyle]), so the layer ends in a normalized state
  /// and subsequent size changes operate directly without any
  /// further translation.
  double _translateFontSizeForVisualScale(double requested) {
    final layer = selectedTextLayer();
    if (layer == null) return requested;
    if (layer.resizeMode != TextResizeMode.scaleText) return requested;
    if (layer.style.fontSize <= 0) return requested;
    final natural = _measureNaturalSize(
      layer.content,
      layer.style,
      textDirectionMode: layer.textDirectionMode,
    );
    if (natural.height <= 0) return requested;
    final scale = layer.transform.size.height / natural.height;
    // Only translate when the visual is *larger* than the natural
    // metrics — i.e. the user scaled the layer UP via corner drag.
    // In that direction, applying a raw font-size write would snap
    // the bounding box back to natural and shrink the rendered
    // glyphs visibly. Translating preserves the user's visual size
    // through the change.
    //
    // When scale <= 1 (box smaller than natural; FittedBox is
    // shrinking glyphs to fit), letting the raw write through keeps
    // the historical "auto-fit on style change" behaviour for
    // layers the user never enlarged.
    if (scale <= _kVisualScaleCompensationThreshold) return requested;
    final ratio = requested / layer.style.fontSize;
    return layer.style.fontSize * scale * ratio;
  }

  /// Switch the typeface. Pass `null` to fall back to the system
  /// default. Family must match a registered entry in
  /// `pubspec.yaml` / `kFontCatalog`.
  void setFontFamily(String? family) => _applyStyle(
    (s) => s.copyWith(fontFamily: family, clearFontFamily: family == null),
  );

  /// Bold is exposed as a boolean toggle in Phase-1; mapped to the
  /// nearest standard weight (w400 / w700) so the change is visually
  /// crisp regardless of the font's available weights.
  void setBold(bool bold) => _applyStyle(
    (s) => s.copyWith(fontWeight: bold ? FontWeight.w700 : FontWeight.w400),
  );

  void setItalic(bool italic) => _applyStyle((s) => s.copyWith(italic: italic));

  void setUnderline(bool underline) =>
      _applyStyle((s) => s.copyWith(underline: underline));

  void setAlignment(TextAlign alignment) =>
      _applyStyle((s) => s.copyWith(alignment: alignment));

  void setLetterSpacing(double value) =>
      _applyStyle((s) => s.copyWith(letterSpacing: value));

  void setLineHeight(double value) =>
      _applyStyle((s) => s.copyWith(lineHeight: value));

  /// Keep color hue while changing alpha in [0..1].
  void setOpacity(double opacity) {
    final clamped = opacity.clamp(0.0, 1.0);
    _applyStyle((s) => s.copyWith(color: s.color.withValues(alpha: clamped)));
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
  // ([TextColorResolver.kDefaultShadowBlur] / [_referenceShadowOffsetDy])
  // are authored against the 1080-px reference canvas, just like
  // every other text default.

  static const Color _defaultShadowColor = Color(0x66000000);
  // Reference shadow offset (designed against the 1080 canvas).
  // Only `dy` is meaningful for the default — `dx` stays 0 so the
  // halo sits straight under the glyph.
  static const double _referenceShadowOffsetDy = 2.0;

  void setShadowEnabled(bool enabled) {
    if (enabled) {
      final doc = ref.read(documentControllerProvider);
      final blur = CanvasSizing.scaleDimension(
        TextColorResolver.kDefaultShadowBlur,
        doc,
      );
      final offset = Offset(
        0,
        CanvasSizing.scaleDimension(_referenceShadowOffsetDy, doc),
      );
      _applyStyle(
        (s) => s.shadowColor == null
            ? s.copyWith(
                shadowColor: _defaultShadowColor,
                shadowBlur: blur,
                shadowOffset: offset,
              )
            : s,
      );
    } else {
      _applyStyle((s) => s.copyWith(clearShadow: true));
    }
  }

  void setShadowColor(Color color) =>
      _applyStyle((s) => s.copyWith(shadowColor: color));

  void setShadowBlur(double blur) =>
      _applyStyle((s) => s.copyWith(shadowBlur: blur.clamp(0.0, 40.0)));

  void setShadowOffset(Offset offset) =>
      _applyStyle((s) => s.copyWith(shadowOffset: offset));

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
      _applyStyle(
        (s) => s.outlineColor == null
            ? s.copyWith(
                outlineColor: _defaultOutlineColor,
                outlineWidth: width,
              )
            : s,
      );
    } else {
      _applyStyle((s) => s.copyWith(clearOutline: true));
    }
  }

  void setOutlineColor(Color color) =>
      _applyStyle((s) => s.copyWith(outlineColor: color));

  void setOutlineWidth(double width) =>
      _applyStyle((s) => s.copyWith(outlineWidth: width.clamp(0.5, 20.0)));

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
      _applyStyle(
        (s) => s.backgroundColor == null
            ? s.copyWith(
                backgroundColor: _defaultBackgroundFor(s.color),
                backgroundPaddingX: padX,
                backgroundPaddingY: padY,
              )
            : s,
      );
    } else {
      _applyStyle((s) => s.copyWith(clearBackground: true));
    }
  }

  void setBackgroundColor(Color color) =>
      _applyStyle((s) => s.copyWith(backgroundColor: color));

  void setBackgroundRadius(double radius) =>
      _applyStyle((s) => s.copyWith(backgroundRadius: radius.clamp(0.0, 1.0)));

  void setBackgroundPaddingX(double px) =>
      _applyStyle((s) => s.copyWith(backgroundPaddingX: px.clamp(0.0, 64.0)));

  void setBackgroundPaddingY(double px) =>
      _applyStyle((s) => s.copyWith(backgroundPaddingY: px.clamp(0.0, 64.0)));

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
  ///
  /// Implementation note: we deliberately bypass [_applyStyle]'s
  /// auto-resize path. Even if `fontWeight` toggle widens glyph
  /// metrics, the layer's bounding box must remain *exactly* what
  /// the user set — otherwise tapping a Style would silently move
  /// or rescale their text. We push the [UpdateTextCommand] directly
  /// with no `transform` so history records one undoable step that
  /// only swaps the style.
  void applyStylePreset(TextStyleSpec preset) {
    if (state.selectedSizePreset != null) {
      state = state.copyWith(clearSelectedSizePreset: true);
    }
    final layer = selectedTextLayer();
    if (layer == null) {
      // No selection → configuring the next add. Merge onto the
      // current default style so the preset's look is layered over
      // whatever font / size the user has been using.
      final next = mergePresetVisual(
        current: state.defaultStyle,
        preset: preset,
      );
      if (next == state.defaultStyle) return;
      state = state.copyWith(defaultStyle: next);
      return;
    }
    final next = mergePresetVisual(current: layer.style, preset: preset);
    if (next == layer.style) return;
    // Slider-drag edge case: a style preset is a discrete, one-shot
    // pick — never part of a live drag. Route through the live
    // overlay if a drag is somehow open so we don't push a stray
    // history entry mid-drag, otherwise execute the command normally.
    if (_styleDrag != null) {
      final updated = layer.copyWith(style: next);
      ref.read(liveOverlayProvider.notifier).replaceLayer(updated);
      return;
    }
    // During a live session (add OR edit — the composer's quick-style
    // strip is reachable from both), mirror onto the overlay so the
    // whole session still collapses to one history entry on commit.
    // Executing here mid-session would trip the docBefore identity
    // invariant in commitLiveEdit/cancelLiveEdit and, in release,
    // either revert the tap on commit or survive a cancel.
    final live = _live;
    if (live != null && live.layerId == layer.id) {
      final updated = layer.copyWith(style: next);
      final overlay = ref.read(liveOverlayProvider.notifier);
      if (live.isNew) {
        overlay.updateAddedLayer(updated);
      } else {
        overlay.replaceLayer(updated);
      }
      return;
    }
    _executeTextWrite(
      UpdateTextCommand(
        layerId: layer.id,
        // style-only edit; a preset tap is discrete (live stays
        // false), so it is always its own undo entry (§3).
        style: next,
        // No transform → bounding box, position, rotation,
        // resizeMode are all preserved exactly.
      ),
    );
  }

  /// Edit content of currently-selected text layer in one undoable step.
  void setContent(String content) {
    final layer = selectedTextLayer();
    if (layer == null || content == layer.content) return;
    _executeTextWrite(
      UpdateTextCommand(
        layerId: layer.id,
        // content-only edit: leave style null so this never merges
        // with a preceding style edit.
        content: content,
      ),
    );
  }

  // ─── live edit (add + edit unified) ──────────────────────────────
  //
  // Both flows share one lifecycle so the UX is identical: every
  // keystroke in the bottom-sheet input is mirrored on the canvas in
  // real time, and the whole session collapses into a single undo
  // entry on commit (an [AddLayerCommand] for new text, an
  // [UpdateTextCommand] for an existing layer). Cancel always restores
  // the exact pre-session state — doc + selection — with no history
  // entry pushed.
  //
  // Lifecycle:
  //   beginAddText()   → stage a fresh empty TextLayer onto the doc
  //                       via liveReplace, select it. Caller then opens
  //                       the bottom sheet with [previewContent] as
  //                       onLiveChange.
  //   beginEditText()  → snapshot the currently selected text layer.
  //                       No staging needed — the layer is already on
  //                       the doc.
  //   previewContent(s)→ update the staged/edited layer's content and
  //                       re-measure its bounding box to the new
  //                       natural size at the current style. Pure
  //                       liveReplace — nothing pushed to history.
  //   commitLiveEdit(s)→ restore docBefore, then push EXACTLY ONE
  //                       history entry (Add or Update) with the final
  //                       trimmed content + measured size. Empty input
  //                       → treated as cancel.
  //   cancelLiveEdit() → restore docBefore + selectionBefore. No
  //                       history entry.

  _LiveSession? _live;

  /// Active slider-drag session. While non-null, every [_applyStyle]
  /// call mutates the live document via `liveReplace` (no history
  /// entry); on [endStyleDrag] the doc is reset to [docBefore] and
  /// the *final* style is committed as ONE undoable command.
  ///
  /// Mirrors the [_live]/`commitLiveEdit` pattern used for content
  /// edits — same coalescing guarantee, applied to numeric style
  /// drags so a 60-tick font-size scrub becomes a single Undo step.
  _StyleDragSession? _styleDrag;

  /// True while the user is actively editing or composing text via the
  /// bottom-sheet flow. Exposed so the canvas / overlays can suppress
  /// transient chrome that would compete with the editor (currently
  /// unused; kept available for future polish).
  bool get isLiveEditing => _live != null;

  // ─── style-drag session (slider undo coalescing) ──────────────
  //
  // Sliders fire onChange every gesture frame. Without a session
  // wrapper that would push N undo entries per drag. Begin/end
  // is invoked by the slider widget on touch-down / release; the
  // [_applyStyle] writer below switches between liveReplace (no
  // history) and execute (one history entry) based on whether a
  // session is active.

  /// Open a style-drag session. Idempotent — nested begins are
  /// ignored so a chip tap inside an open drag still uses the
  /// existing snapshot.
  void beginStyleDrag() {
    if (_styleDrag != null) return;
    final docBefore = ref.read(documentControllerProvider);
    _styleDrag = _StyleDragSession(
      docBefore: docBefore,
      commitVersionAtBegin: ref.read(documentCommitVersionProvider),
    );
  }

  /// True while a style-drag session is open. Exposed so preview
  /// hosts (the All-fonts sheet's debounced highlight path) can
  /// make late callbacks inert after the session ended — a timer
  /// firing post-dismiss must not fall through to a real execute.
  bool get isStyleDragOpen => _styleDrag != null;

  /// Abandon the style-drag session WITHOUT committing: the staged
  /// overlay preview is dropped and zero history entries are
  /// pushed. Used by preview surfaces whose dismissal means "keep
  /// what I had" — the All-fonts sheet closing un-picked (tb2
  /// 12/16). Safe no-op if no session is active.
  void cancelStyleDrag() {
    final session = _styleDrag;
    _styleDrag = null;
    if (session == null) return;
    ref.read(liveOverlayProvider.notifier).clear();
  }

  /// Commit the live drag as one undo entry. Restores [docBefore]
  /// then re-applies the layer's current (drag-end) style via the
  /// normal [execute] path. Safe no-op if no session is active.
  void endStyleDrag() {
    final session = _styleDrag;
    _styleDrag = null;
    if (session == null) return;
    final layer = selectedTextLayer();
    final overlay = ref.read(liveOverlayProvider.notifier);
    // The committed document can legitimately change under an open
    // drag: the AppBar Undo button (or the multi-finger undo
    // shortcut) stays live while a dock slider is held — a second
    // finger can fire it. Committing the drag on top would execute a
    // full-layer restore built from pre-undo state, silently
    // overwriting the user's undo (and the identity assert below
    // crashed debug builds). The undo wins: drop the in-flight
    // overlay and end the session without committing.
    if (ref.read(documentCommitVersionProvider) !=
        session.commitVersionAtBegin) {
      overlay.clear();
      return;
    }
    // Invariant: nobody pushed a real `execute` while the style-drag
    // session was open. Sessions are pure-overlay; if this fails,
    // someone added an `execute` mid-session and the assumption that
    // `clear()` rewinds to docBefore no longer holds. (Undo/redo is
    // handled above — this guards command dispatch specifically.)
    assert(
      identical(session.docBefore, ref.read(documentControllerProvider)),
      'committed document changed during style-drag session — '
      'something dispatched execute() mid-drag',
    );
    if (layer == null) {
      // Nothing to commit — just drop the in-flight overlay so we
      // don't leak a transient state.
      overlay.clear();
      return;
    }
    final finalStyle = layer.style;
    final finalTransform = layer.transform;
    // No net-zero entries (contract §3): a session that ends where
    // it started — cancelled eyedrop restoring the pre-drag colour,
    // a wheel scrubbed back to its origin — must not push history.
    // UpdateTextCommand.apply has no own equality guard, so without
    // this check the commit below would record a do-nothing entry.
    final before = session.docBefore.layerById(layer.id);
    if (before is TextLayer &&
        before.content == layer.content &&
        before.style == finalStyle &&
        before.transform == finalTransform) {
      overlay.clear();
      return;
    }
    // Drop the overlay BEFORE pushing the command. Together they
    // produce a single Riverpod tick where the merged view goes from
    // "committed + in-flight override" to "committed (with the new
    // style baked in)" with no flicker through the pre-drag state.
    overlay.clear();
    ref
        .read(documentControllerProvider.notifier)
        .execute(
          UpdateTextCommand(
            layerId: layer.id,
            // End-of-drag commit covers the whole live session — content,
            // style and transform may all have changed, so all three are
            // captured. Session seals are discrete (live stays false):
            // one drag, one entry, never merged with a neighbour (§3).
            content: layer.content,
            style: finalStyle,
            transform: finalTransform,
          ),
        );
  }

  /// Begin editing the currently selected text layer. No-op if nothing
  /// is selected or the selection is not a [TextLayer].
  void beginEditText() {
    final layer = selectedTextLayer();
    if (layer == null) return;
    final doc = ref.read(documentControllerProvider);
    final selection = ref.read(selectionControllerProvider);
    _live = _LiveSession(
      docBefore: doc,
      layerBefore: layer,
      layerId: layer.id,
      selectionBefore: selection.selectedId,
      isNew: false,
      scaleAtBegin: _visualScaleOf(layer),
    );
  }

  /// Visual (rendered) px of [layer]'s glyphs — what the size chip
  /// and quick-capsule readouts must display (tb2 12/16, audit:
  /// size-readout-visual-scale-lie). Mirrors the WRITE space of
  /// [_translateFontSizeForVisualScale] exactly, including its
  /// deliberate asymmetry: an up-scaled `scaleText` layer reports
  /// raw × scale (the FittedBox is magnifying; a +10% nudge then
  /// moves the number +10% instead of snapping it 2×), while a
  /// down-scaled box keeps reporting raw px — the space its writes
  /// land in. Writes stay raw; only readouts consume this.
  double visualFontSizeOf(TextLayer layer) {
    final scale = _visualScaleOf(layer);
    return layer.style.fontSize *
        (scale > _kVisualScaleCompensationThreshold ? scale : 1.0);
  }

  /// Up-scale threshold above which the size pipeline treats the
  /// FittedBox magnification as user intent: writes compensate
  /// ([_translateFontSizeForVisualScale]) and readouts report the
  /// magnified px ([visualFontSizeOf]). The 2% headroom absorbs
  /// float noise from re-measures so a nominally-unscaled layer
  /// never flips between the two spaces. One constant, both
  /// directions — they must never disagree.
  static const double _kVisualScaleCompensationThreshold = 1.02;

  /// Visual scale ratio of [layer] for `scaleText` mode — the
  /// multiplier applied by the on-canvas [FittedBox] to the natural
  /// glyph height. `1.0` for `resizeBox` (where the box width is the
  /// wrap column, not a scale) and as a safety fallback.
  double _visualScaleOf(TextLayer layer) {
    if (layer.resizeMode != TextResizeMode.scaleText) return 1.0;
    final natural = _measureNaturalSize(
      layer.content,
      layer.style,
      textDirectionMode: layer.textDirectionMode,
    );
    if (natural.height <= 0) return 1.0;
    return layer.transform.size.height / natural.height;
  }

  /// Multiply [naturalSize] by the live session's [scaleAtBegin] so
  /// editing existing `scaleText` layers keeps the visual size the
  /// user manually set via corner-drag. Pass-through for `resizeBox`
  /// — that mode owns its width as the wrap column, not as a scale.
  Size _scalePreservedEditSize(
    Size naturalSize,
    TextResizeMode mode,
    double scaleAtBegin,
  ) {
    if (mode != TextResizeMode.scaleText) return naturalSize;
    if ((scaleAtBegin - 1).abs() < 0.001) return naturalSize;
    return Size(
      naturalSize.width * scaleAtBegin,
      naturalSize.height * scaleAtBegin,
    );
  }

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
    final doc = ref.read(documentControllerProvider);
    final selection = ref.read(selectionControllerProvider);
    final id = _uuid.v4();
    // Canvas-relative font size: the controller's `defaultStyle` is
    // authored against a 1080-px reference canvas — scale it down
    // for sticker-sized canvases and up for poster-sized ones so
    // text reads as the same visual proportion regardless of
    // export dimensions.
    final scaledStyle = _scaleStyleToCanvas(state.defaultStyle, doc);
    // Bounding box always equals the natural text size at the current
    // style. For an empty initial layer we measure a single space so
    // the box has one line worth of height to receive the caret.
    final initialSize = _measureForNewLayer('', scaledStyle, doc);
    final position = _centerOnCanvas(initialSize, doc);
    // Smart default colour: keep the user's chosen colour when it
    // reads against what's underneath; otherwise auto-pick black or
    // white so brand-new text is never invisible (e.g. white-on-
    // white on a fresh canvas).
    //
    // Seed the default (Persian) font at STAGE time, not just at
    // commit — the live layer previews every keystroke, and a null
    // family would flash the system face until the commit fixes it.
    final readableStyle = scaledStyle.copyWith(
      fontFamily: scaledStyle.fontFamily ?? defaultFontFamilyForContent(''),
      color: TextColorResolver.resolve(
        requested: scaledStyle.color,
        doc: doc,
        targetRect: position & initialSize,
      ),
    );
    // Default subtle drop-shadow so new text stays readable on
    // Default subtle drop-shadow so new text stays readable on
    // photos / busy backgrounds without forcing the user into the
    // Shadow panel. Only applied when the style currently has no
    // shadow (= user hasn't tuned a shadow into their default), and
    // the colour is picked opposite to the text's luminance so it
    // always reads as a halo. Users can still clear/change it from
    // the Shadow panel; existing layers are untouched because this
    // path runs only for brand-new inserts.
    final styled = _seedDefaultShadowIfMissing(readableStyle, doc);
    final layer = TextLayer(
      id: id,
      transform: LayerTransform(position: position, size: initialSize),
      content: '',
      style: styled,
    );
    _live = _LiveSession(
      docBefore: doc,
      layerBefore: layer,
      layerId: id,
      selectionBefore: selection.selectedId,
      isNew: true,
      scaleAtBegin: 1.0,
    );
    // Stage the layer onto the live overlay (NOT the committed doc)
    // so the canvas shows the bounding box where text will appear
    // without polluting the layers panel / undo rail until commit.
    ref.read(liveOverlayProvider.notifier).addLayer(layer);
    ref.read(selectionControllerProvider.notifier).select(id);
    return id;
  }

  /// Live-preview [content] on the staged/edited layer. Safe no-op if
  /// no live session is active.
  void previewContent(String content) {
    final s = _live;
    if (s == null) return;
    // Read the merged view so a new-add staged addition (which only
    // exists in the live overlay) is found alongside committed
    // layers being edited.
    final doc = ref.read(documentControllerProvider);
    final merged = ref.read(renderedDocumentProvider);
    final current = merged.layerById(s.layerId);
    if (current is! TextLayer) return;
    var next = current.copyWith(content: content);
    // For brand-new layers being live-typed: cap the natural width
    // at canvas-width × _newLayerWrapFraction so the box wraps
    // inside the canvas instead of running off the right edge, and
    // re-centre on every keystroke so growth stays symmetric around
    // the canvas centre. For existing layers the user is editing,
    // honour their resize mode + current width and never move the
    // layer — yanking placed text around on every keystroke would
    // be jarring.
    final newSize = s.isNew
        ? _measureForNewLayer(
            content,
            current.style,
            doc,
            textDirectionMode: current.textDirectionMode,
          )
        : _scalePreservedEditSize(
            _measureForMode(
              content,
              current.style,
              current.resizeMode,
              current.transform.size.width,
              textDirectionMode: current.textDirectionMode,
            ),
            current.resizeMode,
            s.scaleAtBegin,
          );
    final newTransform = s.isNew
        ? current.transform.copyWith(
            position: _centerOnCanvas(newSize, doc),
            size: newSize,
          )
        : (newSize == current.transform.size
              ? current.transform
              : current.transform.copyWith(size: newSize));
    if (newTransform != current.transform) {
      next = next.withTransform(newTransform) as TextLayer;
    }
    if (next == current) return;
    final overlay = ref.read(liveOverlayProvider.notifier);
    if (s.isNew) {
      overlay.updateAddedLayer(next);
    } else {
      overlay.replaceLayer(next);
    }
  }

  /// Confirm the live edit. Pushes ONE history entry covering the
  /// whole session. Empty / whitespace-only input is treated as cancel
  /// (no add for new flow, original preserved for edit flow).
  void commitLiveEdit(String content) {
    final s = _live;
    _live = null;
    if (s == null) return;
    final docCtrl = ref.read(documentControllerProvider.notifier);
    final overlay = ref.read(liveOverlayProvider.notifier);
    // Invariant: the live session never dispatches `execute`, so the
    // committed document must still be the same instance captured at
    // session begin. If this fails, someone snuck an `execute` in
    // mid-session and the `clear()` below would NOT reproduce the
    // historical `liveReplace(docBefore)` rewind — silent corruption.
    assert(
      identical(s.docBefore, ref.read(documentControllerProvider)),
      'committed document changed during live text-edit session — '
      'something dispatched execute() mid-session',
    );
    // Capture the staged layer's *current* state BEFORE we drop the
    // overlay — clearing it loses any pre-commit tweaks the user made
    // via the composer's quick-style strip (Bold, Color). Snapshot
    // .style is frozen at session begin and would otherwise lose
    // those edits. Read from the merged view so a new-add staged
    // layer (which only lives in the overlay) is still found.
    final liveLayerBeforeRestore = ref
        .read(renderedDocumentProvider)
        .layerById(s.layerId);
    final liveStyleAtCommit = (liveLayerBeforeRestore is TextLayer)
        ? liveLayerBeforeRestore.style
        : null;
    // Drop the overlay so the committed doc becomes the canonical
    // view again; the single command below carries all the intent.
    // Guarantees one and only one undo entry, regardless of how many
    // previews ran.
    overlay.clear();
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      // Empty result — treat as cancel for both new and edit flows.
      // For new: docBefore is already restored, so the staged layer
      // simply never lands. For edit: layerBefore is preserved.
      _restoreSelection(s);
      return;
    }
    if (s.isNew) {
      // Re-derive the canvas-scaled style for the FINAL commit so
      // the layer that lands in history matches what the user saw
      // during the live preview (which used the staged scaled
      // style on the layerBefore record). Honour the same wrap cap
      // + re-centre the committed layer so it lands exactly where
      // the live preview showed it, fully inside the canvas. Also
      // promote to resizeBox when content wrapped, so corner-drag
      // afterwards re-wraps the paragraph instead of scaling a
      // frozen wrapped layout.
      final doc = ref.read(documentControllerProvider);
      // Style source: prefer the live staged layer's *current*
      // style (captured above before we restored docBefore) over
      // the snapshot taken at session begin. Quick-style edits the
      // user made through the composer (Bold, Color) write through
      // `_applyStyle` onto the live layer; using the begin-snapshot
      // here would silently discard them. Falls back to the snapshot
      // for the defensive case where the live layer wasn't found
      // (e.g. an unexpected mid-flight removal).
      var finalStyle = liveStyleAtCommit ?? s.layerBefore.style;
      if (finalStyle.fontFamily == null) {
        finalStyle = finalStyle.copyWith(
          fontFamily: defaultFontFamilyForContent(trimmed),
        );
      }
      final layout = _resolveNewLayerLayout(
        trimmed,
        finalStyle,
        doc,
        textDirectionMode: s.layerBefore.textDirectionMode,
      );
      final finalLayer = TextLayer(
        id: s.layerId,
        transform: s.layerBefore.transform.copyWith(
          position: _centerOnCanvas(layout.size, doc),
          size: layout.size,
        ),
        content: trimmed,
        style: finalStyle,
        resizeMode: layout.mode,
        textDirectionMode: s.layerBefore.textDirectionMode,
      );
      docCtrl.execute(AddLayerCommand(finalLayer));
      ref.read(selectionControllerProvider.notifier).select(s.layerId);
    } else {
      // Style source mirrors the add path above: the live staged
      // layer's current style (quick-style Bold/Color taps write
      // through the overlay during edit sessions too), falling back
      // to the begin snapshot.
      var finalStyle = liveStyleAtCommit ?? s.layerBefore.style;
      // Re-pick an auto-default font when the dominant script
      // flipped during edit (e.g. user wiped Latin and typed
      // Persian, or vice-versa). Only auto-update when the
      // layer is still on one of the two auto-defaults the
      // controller assigned at creation time — a user-picked
      // font from the Font tool is never overwritten.
      if (isAutoDefaultFontFamily(finalStyle.fontFamily)) {
        final wanted = defaultFontFamilyForContent(trimmed);
        if (wanted != finalStyle.fontFamily) {
          finalStyle = finalStyle.copyWith(fontFamily: wanted);
        }
      }
      if (trimmed == s.layerBefore.content &&
          finalStyle == s.layerBefore.style) {
        // No effective change to content OR style — don't pollute
        // history. (A style-only session change must still commit:
        // the early-return guards on both.)
        return;
      }
      final measured = _scalePreservedEditSize(
        _measureForMode(
          trimmed,
          finalStyle,
          s.layerBefore.resizeMode,
          s.layerBefore.transform.size.width,
          textDirectionMode: s.layerBefore.textDirectionMode,
        ),
        s.layerBefore.resizeMode,
        s.scaleAtBegin,
      );
      final styleChanged = finalStyle != s.layerBefore.style;
      final newTransform = measured == s.layerBefore.transform.size
          ? s.layerBefore.transform
          : s.layerBefore.transform.copyWith(size: measured);
      docCtrl.execute(
        UpdateTextCommand(
          layerId: s.layerId,
          // Live-edit commit: a full session can mutate any of the
          // three fields, so all are captured. Session seals are
          // discrete (live stays false) — one session, one entry (§3).
          content: trimmed,
          style: finalStyle,
          transform: (newTransform == s.layerBefore.transform && !styleChanged)
              ? null
              : newTransform,
        ),
      );
    }
  }

  /// Discard the live session. Restores docBefore + selectionBefore.
  /// Safe to call when no session is active.
  void cancelLiveEdit() {
    final s = _live;
    _live = null;
    if (s == null) return;
    // Invariant: nobody pushed a real `execute` while the live edit
    // session was open. If this fails the `clear()` rewind below is
    // not equivalent to the historical `liveReplace(docBefore)`.
    assert(
      identical(s.docBefore, ref.read(documentControllerProvider)),
      'committed document changed during live text-edit session — '
      'something dispatched execute() mid-session',
    );
    ref.read(liveOverlayProvider.notifier).clear();
    _restoreSelection(s);
  }

  void _restoreSelection(_LiveSession s) {
    final selCtrl = ref.read(selectionControllerProvider.notifier);
    final prior = s.selectionBefore;
    if (prior == null) {
      selCtrl.clear();
    } else {
      selCtrl.select(prior);
    }
  }

  /// Returns the bounding-box size that [content] should occupy at
  /// [style] under [mode].
  ///
  /// * [TextResizeMode.scaleText] — natural (unwrapped) size of the
  ///   text. Width grows with longer content; aspect-locked corner
  ///   drag scales the rendered text via [FittedBox].
  /// * [TextResizeMode.resizeBox] — paragraph box. Width is fixed at
  ///   [currentWidth]; height is the wrapped layout height. Corner
  ///   drag changes the wrap width and we re-measure height for the
  ///   new column.
  Size _measureForMode(
    String content,
    TextStyleSpec style,
    TextResizeMode mode,
    double currentWidth, {
    TextDirectionMode textDirectionMode = TextDirectionMode.auto,
  }) {
    switch (mode) {
      case TextResizeMode.scaleText:
        return _measureNaturalSize(
          content,
          style,
          textDirectionMode: textDirectionMode,
        );
      case TextResizeMode.resizeBox:
        return _measureBoxHeight(
          content,
          style,
          currentWidth,
          textDirectionMode: textDirectionMode,
        );
    }
  }

  /// Measure the natural (unwrapped) size of [content] in [style].
  ///
  /// Used by [TextResizeMode.scaleText]: bounding box equals the
  /// painter's natural size, so the visual text always fits exactly.
  /// Empty content is rendered at one space's worth of height so a
  /// freshly-staged layer still has a visible, touchable box.
  Size _measureNaturalSize(
    String content,
    TextStyleSpec style, {
    TextDirectionMode textDirectionMode = TextDirectionMode.auto,
  }) {
    final painter = _layoutPainter(
      content,
      style,
      double.infinity,
      textDirectionMode: textDirectionMode,
    );
    final size = Size(painter.width, painter.height);
    painter.dispose();
    return size;
  }

  /// Measure [content] for a NEW text layer being added to [doc]:
  /// natural size, but capped to wrap at
  /// [_newLayerWrapFraction] × canvas width so the very first
  /// keystrokes of a long word / sentence don't shoot the bounding
  /// box off-canvas. The returned size is the painter's actual
  /// laid-out size (snug to the longest wrapped line), which is
  /// what callers feed into the layer transform.
  ///
  /// Falls back to a pure natural measure when the canvas has no
  /// width yet (e.g. tests with a 0-sized doc).
  Size _measureForNewLayer(
    String content,
    TextStyleSpec style,
    EditorDocument doc, {
    TextDirectionMode textDirectionMode = TextDirectionMode.auto,
  }) {
    final canvasWidth = doc.width;
    if (canvasWidth <= 0) {
      return _measureNaturalSize(
        content,
        style,
        textDirectionMode: textDirectionMode,
      );
    }
    final cap = canvasWidth * _newLayerWrapFraction;
    final painter = _layoutPainter(
      content,
      style,
      cap,
      textDirectionMode: textDirectionMode,
    );
    final size = Size(painter.width, painter.height);
    painter.dispose();
    return size;
  }

  /// Position [size] so it sits centred on the canvas. Used during
  /// the new-add live flow so the bounding box grows symmetrically
  /// around the canvas centre instead of anchored to the original
  /// (empty-content) top-left.
  Offset _centerOnCanvas(Size size, EditorDocument doc) =>
      Offset(doc.width / 2 - size.width / 2, doc.height / 2 - size.height / 2);

  /// Decide the final ([TextResizeMode], [Size]) for a brand-new
  /// text layer being committed with [content] / [style] onto [doc].
  ///
  /// Rule: if the content's natural unwrapped width fits within the
  /// new-layer wrap cap, keep the layer in [TextResizeMode.scaleText]
  /// so corner-drag scales the single-line snug box (Canva sticker
  /// behaviour). If the content is long enough that it had to wrap
  /// during the live preview, promote it to [TextResizeMode.resizeBox]
  /// at the wrap-cap width so corner-drag re-wraps the paragraph
  /// instead of scaling a frozen wrapped layout (Canva paragraph
  /// behaviour). This keeps each mode's semantics clean and matches
  /// how Keynote / Pages decide between "text label" and "text
  /// frame" on the first commit.
  ({TextResizeMode mode, Size size}) _resolveNewLayerLayout(
    String content,
    TextStyleSpec style,
    EditorDocument doc, {
    TextDirectionMode textDirectionMode = TextDirectionMode.auto,
  }) {
    final canvasWidth = doc.width;
    if (canvasWidth <= 0) {
      return (
        mode: TextResizeMode.scaleText,
        size: _measureNaturalSize(
          content,
          style,
          textDirectionMode: textDirectionMode,
        ),
      );
    }
    final natural = _measureNaturalSize(
      content,
      style,
      textDirectionMode: textDirectionMode,
    );
    final cap = canvasWidth * _newLayerWrapFraction;
    if (natural.width <= cap) {
      return (mode: TextResizeMode.scaleText, size: natural);
    }
    final wrapped = _measureBoxHeight(
      content,
      style,
      cap,
      textDirectionMode: textDirectionMode,
    );
    return (mode: TextResizeMode.resizeBox, size: wrapped);
  }

  /// Reference canvas dimension that the user-facing default
  /// font sizes (`TextStyleSpec.fontSize` defaults like 48 pt) are
  /// authored against. A 48-pt text on a 1080-square canvas
  /// occupies ~4.4 % of the canvas — the proportion is what makes
  /// it feel "right" rather than the absolute pixel count.
  ///
  /// Pinning to a baseline matches Canva / Figma / CapCut: the
  /// designer's mental model is "this text reads as a heading on
  /// my poster", not "this text is 48 logical pixels".
  ///
  /// Delegated to [CanvasSizing.referenceCanvasDim] so every insert
  /// flow shares the same "author against 1080" rule.
  static double get _referenceCanvasSize => CanvasSizing.referenceCanvasDim;

  /// Hard floor / ceiling for the auto-scaled font size. The floor
  /// keeps a 100-px sticker canvas from collapsing the type to an
  /// invisible sub-pixel value; the ceiling stops an 8000-px export
  /// from producing an unreadable wall of glyphs that overflows the
  /// frame on first insert.
  static const double _minScaledFontSize = 8.0;
  static const double _maxScaledFontSize = 400.0;

  /// Fraction of the canvas width that newly-added text is allowed
  /// to occupy before it must wrap. Matches Canva / Keynote: when
  /// you start typing a new text element it grows along the centre
  /// line and breaks onto a new line a comfortable margin before
  /// the canvas edge, instead of shooting off-canvas as a single
  /// runaway line. Existing layers the user has already placed and
  /// sized are NOT subject to this cap.
  static const double _newLayerWrapFraction = 0.9;

  /// The single representative pixel-dimension we treat the canvas
  /// as having for font-scale purposes. Delegates to
  /// [CanvasSizing.effectiveDim] so shape / sticker / text inserts
  /// all compute "what is the canvas's effective size?" the same way.
  double _effectiveCanvasDim(EditorDocument doc) =>
      CanvasSizing.effectiveDim(doc);

  /// Resolve [base] for insertion into [doc] by scaling its
  /// `fontSize` proportionally to the canvas's effective dimension.
  /// Tiny canvases get smaller default text, huge canvases get larger
  /// — the visual proportion stays constant. The result is rounded
  /// to the nearest 0.5 pt so the size shown in the slider/label
  /// reads as a clean number rather than a floating-point trail.
  ///
  /// Only `fontSize` is touched; every other field of the style
  /// (colour, weight, family, shadow…) is preserved verbatim.
  TextStyleSpec _scaleStyleToCanvas(TextStyleSpec base, EditorDocument doc) {
    final effective = _effectiveCanvasDim(doc);
    if (effective <= 0) return base;
    final raw = base.fontSize * effective / _referenceCanvasSize;
    final clamped = raw.clamp(_minScaledFontSize, _maxScaledFontSize);
    // Snap to nearest 0.5 pt for clean labels in the size slider.
    final scaled = (clamped * 2).round() / 2;
    if ((scaled - base.fontSize).abs() < 0.01) return base;
    return base.copyWith(fontSize: scaled);
  }

  /// Seed [base] with the canvas-aware default drop-shadow when it
  /// has none (`shadowColor == null`). The blur and offset are
  /// scaled via [CanvasSizing.scaleDimension] so a tiny sticker
  /// canvas gets a subtle halo and a huge poster canvas gets a
  /// proportionally chunkier one — same visual presence on both.
  /// Returns [base] unchanged when a shadow is already configured;
  /// existing layers are never overwritten through this path.
  TextStyleSpec _seedDefaultShadowIfMissing(
    TextStyleSpec base,
    EditorDocument doc,
  ) {
    if (base.shadowColor != null) return base;
    final blur = CanvasSizing.scaleDimension(
      TextColorResolver.kDefaultShadowBlur,
      doc,
    );
    final offset = Offset(
      0,
      CanvasSizing.scaleDimension(_referenceShadowOffsetDy, doc),
    );
    return base.copyWith(
      shadowColor: TextColorResolver.defaultShadowFor(base.color),
      shadowBlur: blur,
      shadowOffset: offset,
    );
  }

  /// Measure the height required to render [content] in [style]
  /// wrapped at [width]. Used by [TextResizeMode.resizeBox] so the
  /// box height tracks the wrapped paragraph as content / width / style
  /// changes.
  Size _measureBoxHeight(
    String content,
    TextStyleSpec style,
    double width, {
    TextDirectionMode textDirectionMode = TextDirectionMode.auto,
  }) {
    final painter = _layoutPainter(
      content,
      style,
      width,
      textDirectionMode: textDirectionMode,
    );
    final h = painter.height;
    painter.dispose();
    return Size(width, h);
  }

  TextPainter _layoutPainter(
    String content,
    TextStyleSpec style,
    double maxWidth, {
    TextDirectionMode textDirectionMode = TextDirectionMode.auto,
  }) {
    return TextPainter(
      text: TextSpan(
        // Empty content collapses to zero height; one space preserves
        // a line of height during a momentary clear.
        text: content.isEmpty ? ' ' : content,
        style: TextStyle(
          fontFamily: style.fontFamily,
          fontSize: style.fontSize,
          fontWeight: style.fontWeight,
          fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
          letterSpacing: style.letterSpacing,
          height: style.lineHeight,
        ),
      ),
      textAlign: style.alignment,
      textDirection: textDirectionForContent(content, mode: textDirectionMode),
      maxLines: null,
    )..layout(maxWidth: maxWidth);
  }

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
    final scaledStyle = _scaleStyleToCanvas(state.defaultStyle, doc);
    final layout = _resolveNewLayerLayout(text, scaledStyle, doc);
    final position = _centerOnCanvas(layout.size, doc);
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
    final styled = _seedDefaultShadowIfMissing(readableStyle, doc);
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
  /// [TextSession._recentsCap]. Presets are deliberately not added so
  /// the rail surfaces a meaningful history.
  void rememberRecentColor(Color color) {
    final argb = color.toARGB32();
    final filtered =
        state.recentColors
            .where((c) => c.toARGB32() != argb)
            .toList(growable: true)
          ..insert(0, color);
    if (filtered.length > TextSession._recentsCap) {
      filtered.removeRange(TextSession._recentsCap, filtered.length);
    }
    state = state.copyWith(recentColors: List<Color>.unmodifiable(filtered));
    // Mirror to the editor-wide store so customs picked in Text
    // surface in Shape / Image / Canvas / Paint panels too.
    ref.read(recentColorsControllerProvider.notifier).remember(color);
  }

  // ─── internal ────────────────────────────────────────────────────

  /// Read the currently-selected text layer (if any). Used by the
  /// toolbar to render against the selected layer's style instead of
  /// the session default.
  ///
  /// Emoji-sticker layers are intentionally filtered out: the Text
  /// tool's session/style/measure logic doesn't apply to a single
  /// emoji glyph (no font, no colour, no wrap), and surfacing the
  /// Text toolbar for them would be misleading.
  TextLayer? selectedTextLayer() {
    final selection = ref.read(selectionControllerProvider);
    if (!selection.hasSelection) return null;
    // Read the MERGED view so an in-flight live session (Add Text
    // composer's staged layer, slider-drag style preview) is found
    // even though it does not yet exist in the committed document.
    // Falling back to the committed read would null out the staged
    // layer mid-session and silently break every per-frame style /
    // content update routed through this method.
    final layer = ref
        .read(renderedDocumentProvider)
        .layerById(selection.selectedId!);
    if (layer is TextLayer && !layer.isSticker) return layer;
    return null;
  }

  /// Apply a style mutation to:
  ///   1. The session default (always — keeps toolbar state coherent).
  ///   2. The selected text layer, if any (single undoable step).
  ///
  /// Bundles a re-measure of the bounding box into the same
  /// [UpdateTextCommand] so the box always equals the natural text
  /// size at the new style — without this, raising font size makes
  /// glyphs taller and the rendered text would extend beyond the box
  /// until some other interaction forced a resize.
  ///
  /// Centralizing the logic here means every UI surface (toolbar,
  /// shortcut, future context menu) gets the same selection-sync
  /// behaviour for free.
  void _applyStyle(
    TextStyleSpec Function(TextStyleSpec) mutate, {
    bool live = false,
  }) {
    final layer = selectedTextLayer();
    final base = layer?.style ?? state.defaultStyle;
    final next = mutate(base);
    if (next == base) return;
    // Only mutate the session's default style when there is no
    // selected layer — i.e. the toolbar is genuinely configuring
    // the *next* layer to be created. When a layer is selected the
    // edit belongs to that layer alone; previously we mirrored the
    // change onto `defaultStyle` too, which leaked the last-edited
    // layer's font/colour/background/border/shadow onto the next
    // freshly-added text. Now adds always start from the user's
    // app default (or `TextStyleSpec.initial` when untouched).
    if (layer == null) {
      state = state.copyWith(defaultStyle: next);
      return;
    }

    // During a live new-add session, style changes (e.g. user drags
    // the size slider while still typing) must NOT push extra
    // history entries — the whole session collapses to one entry on
    // commit. Mirror the change onto the staged addition in the live
    // overlay and, because the new-add layer is centred + wrap-
    // capped, also re-flow the bounding box and re-centre it so the
    // live preview stays inside the canvas at the new style.
    final liveSession = _live;
    if (liveSession != null &&
        liveSession.isNew &&
        liveSession.layerId == layer.id) {
      final doc = ref.read(documentControllerProvider);
      final newSize = _measureForNewLayer(
        layer.content,
        next,
        doc,
        textDirectionMode: layer.textDirectionMode,
      );
      final newTransform = layer.transform.copyWith(
        position: _centerOnCanvas(newSize, doc),
        size: newSize,
      );
      final updated =
          layer.copyWith(style: next).withTransform(newTransform) as TextLayer;
      ref.read(liveOverlayProvider.notifier).updateAddedLayer(updated);
      return;
    }

    // During a live EDIT session the same rule applies: the composer's
    // quick-style strip must never execute() mid-session (that would
    // trip commitLiveEdit's docBefore invariant and lose the edit in
    // release). Mirror onto the overlay; commitLiveEdit folds the
    // final style into its single UpdateTextCommand. Metrics-affecting
    // changes re-measure with the corner-drag scale preserved, exactly
    // like the content-preview path.
    if (liveSession != null &&
        !liveSession.isNew &&
        liveSession.layerId == layer.id) {
      Size? liveSize;
      if (_affectsMetrics(base, next)) {
        liveSize = _scalePreservedEditSize(
          _measureForMode(
            layer.content,
            next,
            layer.resizeMode,
            layer.transform.size.width,
            textDirectionMode: layer.textDirectionMode,
          ),
          layer.resizeMode,
          liveSession.scaleAtBegin,
        );
      }
      var updated = layer.copyWith(style: next);
      if (liveSize != null && liveSize != layer.transform.size) {
        updated =
            updated.withTransform(layer.transform.copyWith(size: liveSize))
                as TextLayer;
      }
      ref.read(liveOverlayProvider.notifier).replaceLayer(updated);
      return;
    }

    // Only re-measure when fields that affect text metrics change.
    // Decoration-only changes (color, opacity, shadow, background)
    // must NOT snap the box back to the natural text size — that
    // would silently undo any prior resize the user did.
    final metricsChanged = _affectsMetrics(base, next);
    Size? newSize;
    if (metricsChanged) {
      newSize = _measureForMode(
        layer.content,
        next,
        layer.resizeMode,
        layer.transform.size.width,
        textDirectionMode: layer.textDirectionMode,
      );
    }
    final newTransform = (newSize == null || newSize == layer.transform.size)
        ? null
        : layer.transform.copyWith(size: newSize);
    // Slider-drag fast path: publish to the live overlay so the
    // canvas updates immediately without polluting history. The
    // single undo entry is pushed by [endStyleDrag] on release.
    if (_styleDrag != null) {
      var updated = layer.copyWith(style: next);
      if (newTransform != null) {
        updated = updated.withTransform(newTransform) as TextLayer;
      }
      ref.read(liveOverlayProvider.notifier).replaceLayer(updated);
      return;
    }
    _executeTextWrite(
      UpdateTextCommand(
        layerId: layer.id,
        // style edit (optionally with a re-measure transform).
        // content stays null so a live nudge burst coalesces
        // with its style-shaped neighbours but NEVER with
        // content edits. Discrete writes (live: false) are one
        // entry each — the merge gate (tb2 6/16) ignores the
        // history window for them.
        style: next,
        transform: newTransform,
        live: live,
      ),
    );
  }

  /// True when [next] differs from [base] in any field that changes
  /// the text painter's measured size. Decoration fields (color,
  /// shadow, background) are intentionally ignored.
  bool _affectsMetrics(TextStyleSpec base, TextStyleSpec next) {
    return base.fontFamily != next.fontFamily ||
        base.fontSize != next.fontSize ||
        base.fontWeight != next.fontWeight ||
        base.italic != next.italic ||
        base.letterSpacing != next.letterSpacing ||
        base.lineHeight != next.lineHeight ||
        base.alignment != next.alignment;
  }

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
    final measured = _measureForMode(
      layer.content,
      layer.style,
      mode,
      layer.transform.size.width,
      textDirectionMode: layer.textDirectionMode,
    );
    final newTransform = measured == layer.transform.size
        ? null
        : layer.transform.copyWith(size: measured);
    _executeTextWrite(
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
    final measured = _measureForMode(
      layer.content,
      layer.style,
      layer.resizeMode,
      layer.transform.size.width,
      textDirectionMode: mode,
    );
    final newTransform = measured == layer.transform.size
        ? null
        : layer.transform.copyWith(size: measured);
    _executeTextWrite(
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

/// Snapshot of an in-flight live text-edit session. Captured at
/// [TextToolController.beginAddText] / [TextToolController.beginEditText]
/// and used to:
///   * restore the document + selection on cancel / empty-commit, and
///   * synthesize a single history entry on commit.
@immutable
class _LiveSession {
  const _LiveSession({
    required this.docBefore,
    required this.layerBefore,
    required this.layerId,
    required this.selectionBefore,
    required this.isNew,
    required this.scaleAtBegin,
  });

  /// Document state before the session began. Restored verbatim on
  /// cancel; the single committed command is then applied on top of
  /// this for a clean one-step undo entry.
  final EditorDocument docBefore;

  /// Snapshot of the layer at the start of the session. For new
  /// sessions this is the freshly-created empty layer; for edits it's
  /// the existing layer's pre-edit state.
  final TextLayer layerBefore;

  /// Id of the layer being edited (whether new or existing).
  final String layerId;

  /// Whatever was selected before the session began — restored on
  /// cancel / empty-commit so an aborted add doesn't leave the user
  /// with a stale selection of a layer that no longer exists.
  final String? selectionBefore;

  /// True when the session was started by [beginAddText] (commit →
  /// AddLayerCommand). False when started by [beginEditText] (commit
  /// → UpdateTextCommand).
  final bool isNew;

  /// Visual scale of the layer at session start, captured so the
  /// edit flow can preserve any prior corner-drag scale through
  /// content / commit re-measures. `1.0` for new layers and for
  /// `resizeBox` layers (where the box width is the wrap column,
  /// not a scale).
  final double scaleAtBegin;
}

/// Snapshot kept for the duration of a slider-drag style edit.
///
/// Holds the document state at the moment the user touched the
/// slider thumb so [TextToolController.endStyleDrag] can rewind
/// the live previews and replace them with one undoable command
/// representing the final committed value.
@immutable
class _StyleDragSession {
  const _StyleDragSession({
    required this.docBefore,
    required this.commitVersionAtBegin,
  });

  /// Document state at the moment the drag began. Restored on
  /// release before the final style command is executed so the
  /// resulting history entry covers exactly one delta (start →
  /// final), regardless of how many in-flight liveReplace ticks
  /// the drag fired.
  final EditorDocument docBefore;

  /// Commit version at the moment the drag began. If it moved by
  /// drag end, an undo/redo landed mid-drag — the drag's commit is
  /// abandoned so the user's undo survives.
  final int commitVersionAtBegin;
}
