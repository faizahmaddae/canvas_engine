import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../application/document_controller.dart';
import '../../application/live_overlay_controller.dart';
import '../../application/selection_controller.dart';
import '../../engine/commands/editor_command.dart';
import '../../engine/commands/text_commands.dart';
import '../../engine/commands/transform_commands.dart';
import '../../engine/core/editor_document.dart';
import '../../engine/core/layer_transform.dart';
import '../../engine/modules/text/text_layer.dart';
import '../domain/text_style_presets.dart';
import 'text_color_resolver.dart';
import 'text_metrics.dart';

const _uuid = Uuid();

/// THE WRITE SEAM (tb2 12/16, contract §1/§2). Session resolution
/// for text writes lives in exactly two places:
///   * [applyStyle] — resolves default-style vs live-session
///     overlay vs style-drag overlay vs committed write, including
///     each branch's measure policy;
///   * [applyStylePreset] — same resolution minus the auto-resize
///     (presets must never move the user's box).
/// Every path that finally REACHES history does so through
/// [executeTextWrite] below, which asserts no session is open —
/// a future setter that bypasses the resolvers and calls execute
/// directly while a session is live trips the assert in debug
/// instead of silently corrupting the session's docBefore
/// invariant (the audit's three-write-paths problem, reduced to
/// one guarded gateway). The only sanctioned direct executes are
/// the session terminators themselves ([endStyleDrag],
/// [commitLiveEdit]) — they run while their own session is being
/// closed — and structural layer ops (add/duplicate/lock/reorder)
/// that are not style writes.
///
/// Extracted from `TextToolController` (roadmap 5.6). The controller
/// owns dock UI state and the public setter vocabulary; this class
/// owns the two in-flight sessions ([_live], [_styleDrag]) and every
/// document write that carries a text style, content, or measured
/// transform. It reaches back into the controller for the session
/// default style through the [readDefaultStyle] / [writeDefaultStyle]
/// pair only — no other controller state is visible here.
class TextStyleWriter {
  TextStyleWriter({
    required Ref ref,
    required TextStyleSpec Function() readDefaultStyle,
    required void Function(TextStyleSpec) writeDefaultStyle,
  }) : _ref = ref,
       _readDefaultStyle = readDefaultStyle,
       _writeDefaultStyle = writeDefaultStyle;

  final Ref _ref;

  /// Reads `TextSession.defaultStyle` — the style a write falls back
  /// to when nothing is selected (the toolbar is configuring the
  /// *next* layer rather than an existing one).
  final TextStyleSpec Function() _readDefaultStyle;

  /// Writes `TextSession.defaultStyle`. Only ever called from the
  /// no-selection branch of [applyStyle] / [applyStylePreset].
  final void Function(TextStyleSpec) _writeDefaultStyle;

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

  /// Active slider-drag session. While non-null, every [applyStyle]
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

  /// True while a style-drag session is open. Exposed so preview
  /// hosts (the All-fonts sheet's debounced highlight path) can
  /// make late callbacks inert after the session ended — a timer
  /// firing post-dismiss must not fall through to a real execute.
  bool get isStyleDragOpen => _styleDrag != null;

  /// Single committed-write gateway for text style/content/resize
  /// writes. See the seam note above.
  void executeTextWrite(EditorCommand command) {
    assert(
      _live == null && _styleDrag == null,
      'text write dispatched to history while a live/style-drag session '
      'is open — route through _applyStyle/applyStylePreset so it stages '
      'on the overlay instead',
    );
    _ref.read(documentControllerProvider.notifier).execute(command);
  }

  /// Read the currently-selected text layer (if any). Used by the
  /// toolbar to render against the selected layer's style instead of
  /// the session default.
  ///
  /// Emoji-sticker layers are intentionally filtered out: the Text
  /// tool's session/style/measure logic doesn't apply to a single
  /// emoji glyph (no font, no colour, no wrap), and surfacing the
  /// Text toolbar for them would be misleading.
  TextLayer? selectedTextLayer() {
    final selection = _ref.read(selectionControllerProvider);
    if (!selection.hasSelection) return null;
    // Read the MERGED view so an in-flight live session (Add Text
    // composer's staged layer, slider-drag style preview) is found
    // even though it does not yet exist in the committed document.
    // Falling back to the committed read would null out the staged
    // layer mid-session and silently break every per-frame style /
    // content update routed through this method.
    final layer = _ref
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
  void applyStyle(
    TextStyleSpec Function(TextStyleSpec) mutate, {
    bool live = false,
  }) {
    final layer = selectedTextLayer();
    final base = layer?.style ?? _readDefaultStyle();
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
      _writeDefaultStyle(next);
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
      final doc = _ref.read(documentControllerProvider);
      final newSize = TextMetrics.measureForNewLayer(
        layer.content,
        next,
        doc,
        textDirectionMode: layer.textDirectionMode,
      );
      final newTransform = layer.transform.copyWith(
        position: TextMetrics.centerOnCanvas(newSize, doc),
        size: newSize,
      );
      final updated =
          layer.copyWith(style: next).withTransform(newTransform) as TextLayer;
      _ref.read(liveOverlayProvider.notifier).updateAddedLayer(updated);
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
      if (TextMetrics.affectsMetrics(base, next)) {
        liveSize = TextMetrics.scalePreservedEditSize(
          TextMetrics.measureForMode(
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
      _ref.read(liveOverlayProvider.notifier).replaceLayer(updated);
      return;
    }

    // Only re-measure when fields that affect text metrics change.
    // Decoration-only changes (color, opacity, shadow, background)
    // must NOT snap the box back to the natural text size — that
    // would silently undo any prior resize the user did.
    final metricsChanged = TextMetrics.affectsMetrics(base, next);
    Size? newSize;
    if (metricsChanged) {
      newSize = TextMetrics.measureForMode(
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
      _ref.read(liveOverlayProvider.notifier).replaceLayer(updated);
      return;
    }
    executeTextWrite(
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

  /// Apply a one-tap *visual* style preset to the currently-selected
  /// text layer (or to `TextSession.defaultStyle` when nothing is
  /// selected, so the next add inherits the look).
  ///
  /// Implementation note: we deliberately bypass [applyStyle]'s
  /// auto-resize path. Even if `fontWeight` toggle widens glyph
  /// metrics, the layer's bounding box must remain *exactly* what
  /// the user set — otherwise tapping a Style would silently move
  /// or rescale their text. We push the [UpdateTextCommand] directly
  /// with no `transform` so history records one undoable step that
  /// only swaps the style.
  void applyStylePreset(TextStyleSpec preset) {
    final layer = selectedTextLayer();
    if (layer == null) {
      // No selection → configuring the next add. Merge onto the
      // current default style so the preset's look is layered over
      // whatever font / size the user has been using.
      final current = _readDefaultStyle();
      final next = mergePresetVisual(current: current, preset: preset);
      if (next == current) return;
      _writeDefaultStyle(next);
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
      _ref.read(liveOverlayProvider.notifier).replaceLayer(updated);
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
      final overlay = _ref.read(liveOverlayProvider.notifier);
      if (live.isNew) {
        overlay.updateAddedLayer(updated);
      } else {
        overlay.replaceLayer(updated);
      }
      return;
    }
    executeTextWrite(
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

  // ─── style-drag session (slider undo coalescing) ──────────────
  //
  // Sliders fire onChange every gesture frame. Without a session
  // wrapper that would push N undo entries per drag. Begin/end
  // is invoked by the slider widget on touch-down / release; the
  // [applyStyle] writer above switches between liveReplace (no
  // history) and execute (one history entry) based on whether a
  // session is active.

  /// Open a style-drag session. Idempotent — nested begins are
  /// ignored so a chip tap inside an open drag still uses the
  /// existing snapshot.
  void beginStyleDrag() {
    if (_styleDrag != null) return;
    final docBefore = _ref.read(documentControllerProvider);
    _styleDrag = _StyleDragSession(
      docBefore: docBefore,
      commitVersionAtBegin: _ref.read(documentCommitVersionProvider),
    );
  }

  /// Abandon the style-drag session WITHOUT committing: the staged
  /// overlay preview is dropped and zero history entries are
  /// pushed. Used by preview surfaces whose dismissal means "keep
  /// what I had" — the All-fonts sheet closing un-picked (tb2
  /// 12/16). Safe no-op if no session is active.
  void cancelStyleDrag() {
    final session = _styleDrag;
    _styleDrag = null;
    if (session == null) return;
    _ref.read(liveOverlayProvider.notifier).clear();
  }

  /// Commit the live drag as one undo entry. Restores [docBefore]
  /// then re-applies the layer's current (drag-end) style via the
  /// normal [execute] path. Safe no-op if no session is active.
  void endStyleDrag() {
    final session = _styleDrag;
    _styleDrag = null;
    if (session == null) return;
    final layer = selectedTextLayer();
    final overlay = _ref.read(liveOverlayProvider.notifier);
    // The committed document can legitimately change under an open
    // drag: the AppBar Undo button (or the multi-finger undo
    // shortcut) stays live while a dock slider is held — a second
    // finger can fire it. Committing the drag on top would execute a
    // full-layer restore built from pre-undo state, silently
    // overwriting the user's undo (and the identity assert below
    // crashed debug builds). The undo wins: drop the in-flight
    // overlay and end the session without committing.
    if (_ref.read(documentCommitVersionProvider) !=
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
      identical(session.docBefore, _ref.read(documentControllerProvider)),
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
    _ref
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

  // ─── live text session ───────────────────────────────────────────

  /// Begin editing the currently selected text layer. No-op if nothing
  /// is selected or the selection is not a [TextLayer].
  void beginEditText() {
    final layer = selectedTextLayer();
    if (layer == null) return;
    final doc = _ref.read(documentControllerProvider);
    final selection = _ref.read(selectionControllerProvider);
    _live = _LiveSession(
      docBefore: doc,
      layerBefore: layer,
      layerId: layer.id,
      selectionBefore: selection.selectedId,
      isNew: false,
      scaleAtBegin: TextMetrics.visualScaleOf(layer),
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
    final doc = _ref.read(documentControllerProvider);
    final selection = _ref.read(selectionControllerProvider);
    final id = _uuid.v4();
    // Canvas-relative font size: the controller's `defaultStyle` is
    // authored against a 1080-px reference canvas — scale it down
    // for sticker-sized canvases and up for poster-sized ones so
    // text reads as the same visual proportion regardless of
    // export dimensions.
    final scaledStyle = TextMetrics.scaleStyleToCanvas(
      _readDefaultStyle(),
      doc,
    );
    // Bounding box always equals the natural text size at the current
    // style. For an empty initial layer we measure a single space so
    // the box has one line worth of height to receive the caret.
    final initialSize = TextMetrics.measureForNewLayer('', scaledStyle, doc);
    final position = TextMetrics.centerOnCanvas(initialSize, doc);
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
    final styled = TextMetrics.seedDefaultShadowIfMissing(readableStyle, doc);
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
    _ref.read(liveOverlayProvider.notifier).addLayer(layer);
    _ref.read(selectionControllerProvider.notifier).select(id);
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
    final doc = _ref.read(documentControllerProvider);
    final merged = _ref.read(renderedDocumentProvider);
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
        ? TextMetrics.measureForNewLayer(
            content,
            current.style,
            doc,
            textDirectionMode: current.textDirectionMode,
          )
        : TextMetrics.scalePreservedEditSize(
            TextMetrics.measureForMode(
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
            position: TextMetrics.centerOnCanvas(newSize, doc),
            size: newSize,
          )
        : (newSize == current.transform.size
              ? current.transform
              : current.transform.copyWith(size: newSize));
    if (newTransform != current.transform) {
      next = next.withTransform(newTransform) as TextLayer;
    }
    if (next == current) return;
    final overlay = _ref.read(liveOverlayProvider.notifier);
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
    final docCtrl = _ref.read(documentControllerProvider.notifier);
    final overlay = _ref.read(liveOverlayProvider.notifier);
    // Invariant: the live session never dispatches `execute`, so the
    // committed document must still be the same instance captured at
    // session begin. If this fails, someone snuck an `execute` in
    // mid-session and the `clear()` below would NOT reproduce the
    // historical `liveReplace(docBefore)` rewind — silent corruption.
    assert(
      identical(s.docBefore, _ref.read(documentControllerProvider)),
      'committed document changed during live text-edit session — '
      'something dispatched execute() mid-session',
    );
    // Capture the staged layer's *current* state BEFORE we drop the
    // overlay — clearing it loses any pre-commit tweaks the user made
    // via the composer's quick-style strip (Bold, Color). Snapshot
    // .style is frozen at session begin and would otherwise lose
    // those edits. Read from the merged view so a new-add staged
    // layer (which only lives in the overlay) is still found.
    final liveLayerBeforeRestore = _ref
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
      final doc = _ref.read(documentControllerProvider);
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
      final layout = TextMetrics.resolveNewLayerLayout(
        trimmed,
        finalStyle,
        doc,
        textDirectionMode: s.layerBefore.textDirectionMode,
      );
      final finalLayer = TextLayer(
        id: s.layerId,
        transform: s.layerBefore.transform.copyWith(
          position: TextMetrics.centerOnCanvas(layout.size, doc),
          size: layout.size,
        ),
        content: trimmed,
        style: finalStyle,
        resizeMode: layout.mode,
        textDirectionMode: s.layerBefore.textDirectionMode,
      );
      docCtrl.execute(AddLayerCommand(finalLayer));
      _ref.read(selectionControllerProvider.notifier).select(s.layerId);
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
      final measured = TextMetrics.scalePreservedEditSize(
        TextMetrics.measureForMode(
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
      identical(s.docBefore, _ref.read(documentControllerProvider)),
      'committed document changed during live text-edit session — '
      'something dispatched execute() mid-session',
    );
    _ref.read(liveOverlayProvider.notifier).clear();
    _restoreSelection(s);
  }

  void _restoreSelection(_LiveSession s) {
    final selCtrl = _ref.read(selectionControllerProvider.notifier);
    final prior = s.selectionBefore;
    if (prior == null) {
      selCtrl.clear();
    } else {
      selCtrl.select(prior);
    }
  }
}

/// Snapshot of an in-flight live text-edit session. Captured at
/// [TextStyleWriter.beginAddText] / [TextStyleWriter.beginEditText]
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
/// slider thumb so [TextStyleWriter.endStyleDrag] can rewind
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
