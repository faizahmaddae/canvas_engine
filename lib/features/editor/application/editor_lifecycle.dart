import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../canvas/application/canvas_tool_controller.dart';
import '../crop/application/crop_controller.dart';
import '../engine/modules/paint/paint_layer.dart';
import '../image/application/image_tool_controller.dart';
import '../paint/application/paint_tool_controller.dart';
import '../shape/application/shape_tool_controller.dart';
import '../sticker/application/sticker_tool_controller.dart';
import '../text/application/text_tool_controller.dart';
import 'context_toolbar_controller.dart';
import 'document_controller.dart';
import 'editing_controller.dart';
import 'mask_edit_controller.dart';
import 'selection_controller.dart';
import 'viewport_controller.dart';

/// Wipes every piece of ephemeral, per-session editor state so a
/// freshly-opened project starts from a clean slate.
///
/// Why this exists: tool controllers (`textToolControllerProvider`,
/// `paintToolControllerProvider`, …) are global non-autoDispose
/// `NotifierProvider`s — their `build()` runs once on app boot, never
/// again. Without an explicit reset at the project boundary the next
/// project inherits the previous one's open sub-tool sheet, sticky
/// preset chip, default text/paint style, recent colour MRU,
/// viewport zoom/pan, multi-select mode, and editing-target id
/// (which now points at a layer that no longer exists). All of that
/// is purely UX state — saved layer styles live on the document and
/// are NOT touched by this helper.
///
/// Call this **before** pushing the editor screen, after the new
/// document has been seeded but before the first build. Both the
/// "new project" and "open existing project" paths must go through
/// it; saved-style fidelity comes from `documentControllerProvider`,
/// not from any of the providers reset here.
void resetEditorEphemeralState(WidgetRef ref) {
  ref.read(textToolControllerProvider.notifier).resetSession();
  ref.read(contextToolbarControllerProvider.notifier).closePanel();
  ref.read(paintToolControllerProvider.notifier).resetSession();
  // The other four dock tools. Text and paint reset their whole
  // session above, but Canvas / Image / Shape / Sticker only ever got
  // closed by an in-editor gesture (tap-empty, selection change), and
  // neither of those happens on the way out to Home — so an open
  // sub-tool panel rode the route boundary into the next project.
  // Open the Canvas panel, back out, create a new canvas, and the
  // fresh editor mounted with that panel still expanded over a
  // document it had nothing to do with.
  //
  // NOT routed through [closeObjectSubPanels] on purpose: that helper
  // defers to an open mask session (it is a mid-editing seam, and the
  // panels it collapses are what the session's Done/Cancel returns the
  // user to). At a project boundary there is nothing to return to —
  // the mask session is being discarded outright a few lines below —
  // so the guard would make the reset silently incomplete in exactly
  // the case it matters most.
  ref.read(canvasToolControllerProvider.notifier).closePanel();
  ref.read(imageToolControllerProvider.notifier).closePanel();
  ref.read(shapeToolControllerProvider.notifier).closePanel();
  ref.read(stickerToolControllerProvider.notifier).closePanel();
  ref.read(editingControllerProvider.notifier).stop();
  ref.read(selectionModeProvider.notifier).exitMulti();
  ref.read(viewportControllerProvider.notifier).reset();
  // Crop is a global non-autoDispose Notifier; without this reset a
  // session left active by a previous editor instance survives the
  // home-screen round-trip and the next editor opens with crop
  // mode already active (worse: pointing at a layer that no
  // longer exists in the new document).
  ref.read(cropControllerProvider.notifier).cancelCrop();
  // Mask-edit is the same class of global non-autoDispose modal
  // session as crop — reset it at the project boundary for the same
  // reason. Uses the explicitly-named project-boundary discard, not
  // `cancel()`, so this stays distinguishable from a user-facing
  // abandon: see [MaskEditController.resetForNewProject].
  ref.read(maskEditControllerProvider.notifier).resetForNewProject();
}

/// Whether an open mask-edit session owns dismissal, making every
/// dismiss seam in this file a no-op.
///
/// The shared boundary for BOTH seams — `dismissActiveEditing`
/// (tap-on-empty) and `closeObjectSubPanels` (selection change) —
/// because both used to end a mask session by calling `cancel()`, and
/// `cancel()` restores the entry mask with ZERO commands: once it runs
/// the work is gone and undo cannot reach it. A seam is a side effect
/// of some other gesture, so it can neither ask the user nor offer a
/// way back. Only the session's own exits may end it, and they confirm
/// a modified draft first (`confirmAbandonMaskEdit`).
///
/// Keeping this as one named predicate rather than two inline reads is
/// deliberate: a third seam added later gets the guard by using it, and
/// a grep for this name enumerates every place that defers to a
/// session.
bool maskSessionOwnsDismissal(WidgetRef ref) =>
    ref.read(maskEditControllerProvider).active;

/// Single dismiss seam for "user tapped empty workspace / pasteboard".
///
/// Why this exists: every tool grows its own transient UI state
/// (text sub-tool sheet, paint inline slot, future shape/sticker
/// add-flow sessions). Without one shared dismiss path each tool
/// re-discovers the same bug — "my chrome doesn't go away when the
/// user taps off-canvas". This helper centralises the contract:
///
///   1. Clear the layer selection (single + multi).
///   2. Collapse every tool controller's transient sheet/panel via
///      its `closeSheet` / `closePanel` / `closeSlot` API. Each
///      controller's close call is idempotent so this is safe to
///      fire on every empty tap.
///   3. Drop keyboard focus.
///
/// Saved layer styles, document content, recents, and user-tuned
/// defaults are NOT touched — only the transient panel + sheet state
/// belonging to the layer the user just deselected. Call from
/// `_handleTap`'s no-hit branch in [editor_canvas.dart], or from any
/// future "tap on empty workspace" path.
///
/// Adding a new tool: expose `closeSheet()` / `closePanel()` (or
/// equivalent) on its controller and append a single call below.
/// Do NOT scatter dismiss logic across UI widgets.
void dismissActiveEditing(WidgetRef ref) {
  if (maskSessionOwnsDismissal(ref)) return;
  // Selection: clear list + exit multi-mode together so the dock's
  // "I have a selection" branch (which keeps the contextual
  // toolbar mounted) collapses cleanly.
  ref.read(selectionControllerProvider.notifier).clear();
  ref.read(selectionModeProvider.notifier).exitMulti();
  // Stop any in-flight inline editing target (the layer being
  // typed into) — the layer it points at is about to be visually
  // unselected and leaving this set would re-open the editor on
  // the next selection.
  ref.read(editingControllerProvider.notifier).stop();
  // Tool controllers — collapse all transient chrome. Order is
  // not significant; each call early-returns when its state is
  // already idle.
  final textCtl = ref.read(textToolControllerProvider.notifier);
  textCtl.closeSheet();
  textCtl.closePanel();
  final paintCtl = ref.read(paintToolControllerProvider.notifier);
  paintCtl.closeSlot();
  paintCtl.closePanel();
  // Object-tool sub-panels (Image / Shape / Sticker). Their
  // `openSlot` survives across builds because the controllers are
  // global non-autoDispose Notifiers — without these calls the
  // last-opened panel (e.g. Image Border) would silently re-mount
  // the next time the user picked an image, even though they
  // explicitly dismissed it by tapping off-canvas. Saved layer
  // styles live on the document and are NOT touched here.
  closeObjectSubPanels(ref);
  // Canvas tool has no selection (it edits the document itself),
  // but a tap on the pasteboard while its panel is open is still
  // a clear "I'm done" signal — collapse it for symmetry.
  ref.read(canvasToolControllerProvider.notifier).closePanel();
  // Mask-edit is NOT dismissed here. It used to be, on the reading
  // that an off-canvas tap is an explicit "I'm done" — but the call
  // it made was cancel(), which discards the draft with no command,
  // so the gesture meaning "I'm done" threw the work away and undo
  // could not retrieve it. A mask session owns its pointers now
  // (contract §5 row 1, AbsorbPointer in MaskEditOverlay), so this
  // seam is unreachable while one is open; the guard at the top of
  // this function keeps that true for any non-canvas caller.
  // Keyboard: tapping the pasteboard reads as a true "I'm done"
  // gesture, even if the user was mid-typing inside an inline
  // field hosted by a sheet that just closed.
  FocusManager.instance.primaryFocus?.unfocus();
}

/// Collapse every object-tool's currently-open sub-panel
/// (Image/Shape/Sticker `openSlot`, Text `openSheet`/`openSlot`/
/// inline-edit target).
///
/// Shared between two seams that both need the same effect:
///   * `dismissActiveEditing` — user tapped off-canvas.
///   * EditorScreen's selection-change listener — user picked a
///     different layer (or deselected) without going through an
///     empty-tap dismiss first.
///
/// Each underlying close is idempotent so this is safe to call on
/// every selection change. Saved layer styles are NOT touched.
///
/// Excluded on purpose:
///   * Canvas tool — it has no selection so a selection change
///     should not collapse it; only an explicit dismiss should.
///   * Paint tool, while the selection stays paint-shaped — a paint
///     sheet FOLLOWS its target instead of closing (§10.5 N):
///     committing a stroke selects it, so closing here would slam a
///     sheet the user is drawing with after every stroke, and
///     reselecting another stroke retargets the open sheet (the
///     scope chip names the switch). Only a selection landing on a
///     NON-paint layer exits paint — the mode derivation puts
///     `panelOpen` above the selected layer's type, so leaving the
///     session armed would keep the paint dock mounted over a text
///     or image selection made from the layers drawer.
///   * Text mode `panelOpen` — text mode itself is preserved so
///     re-tapping a text layer keeps the user in text mode without
///     having to re-enter it. Only the per-selection sheet/slot
///     state is cleared.
void closeObjectSubPanels(WidgetRef ref) {
  // An open mask session outranks every panel this collapses — see
  // [maskSessionOwnsDismissal]. Returning early rather than skipping
  // just the mask line is the point: the panels below are the chrome
  // the session's own exit restores the user to, so collapsing them
  // mid-session would strand Done/Cancel with nothing to return to.
  if (maskSessionOwnsDismissal(ref)) return;
  final selection = ref.read(selectionControllerProvider);
  if (selection.hasSelection) {
    final ids = selection.selectedIds;
    final single = ids.length == 1
        ? ref.read(documentControllerProvider).layerById(ids.first)
        : null;
    if (single is! PaintLayer) {
      ref.read(paintToolControllerProvider.notifier).closePanel();
    }
  }
  ref.read(contextToolbarControllerProvider.notifier).closePanel();
  ref.read(imageToolControllerProvider.notifier).closePanel();
  ref.read(shapeToolControllerProvider.notifier).closePanel();
  ref.read(stickerToolControllerProvider.notifier).closePanel();
  // Text sheets/inline rows are scoped to the selected text layer
  // (the panel widgets render `SizedBox.shrink()` when no text is
  // selected), so a selection change must wipe them — otherwise
  // re-selecting any text layer would silently re-open the last
  // sheet (e.g. Font sheet from the previous edit). `closeSheet`
  // covers openSheet + openSlot + panelExpanded + the sticky size
  // preset highlight in one call.
  ref.read(textToolControllerProvider.notifier).closeSheet();
  // Inline content editing (text caret) is layer-scoped — leaving
  // its target id pointing at the previously-selected layer would
  // re-enter edit mode the next time that layer is reselected.
  ref.read(editingControllerProvider.notifier).stop();
  // Mask-edit is deliberately NOT ended here. It used to be, on the
  // reading that a session is scoped to the layer it opened on — but
  // the call was `cancel()`, so a selection change (including a
  // programmatic one from the layers panel) destroyed a tuned mask
  // with no command to undo. A session that outlives its selection is
  // harmless: the controller's own document listener still cancels
  // when the target layer is deleted, stops being an image, or has its
  // stack mask changed from outside, which are the cases where the
  // draft has genuinely lost its meaning.
}
