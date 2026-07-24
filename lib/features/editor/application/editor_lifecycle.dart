import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../canvas/application/canvas_tool_controller.dart';
import '../crop/application/crop_controller.dart';
import '../engine/commands/transform_commands.dart';
import '../engine/core/layer_transform.dart';
import '../engine/modules/image/image_layer.dart';
import '../image/application/image_tool_controller.dart';
import '../paint/application/paint_tool_controller.dart';
import '../shape/application/shape_tool_controller.dart';
import '../sticker/application/sticker_tool_controller.dart';
import '../text/application/text_tool_controller.dart';
import 'context_toolbar_controller.dart';
import 'document_controller.dart';
import 'editing_controller.dart';
import 'editor_session.dart';
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
  // reason.
  ref.read(maskEditControllerProvider.notifier).cancel();
}

/// Start a brand-new document INSIDE an open editor session.
///
/// Order is load-bearing. The session is rebound to a fresh unsaved
/// one BEFORE the new document exists: autosave and Save read the
/// session at flush time, so from the rebind onward nothing can
/// upsert the new document (or its journal) under the old
/// projectId. Previously the old session stayed bound and the first
/// commit's debounced autosave silently overwrote the still-open
/// project — and its recovery journal — with the fresh blank
/// document, unrecoverably. Ephemeral tool state is reset next
/// (crop/mask sessions still point at layers of the outgoing
/// document) and only then is the document swapped.
///
/// Confirmation UX (dialogs) stays with the caller; this helper is
/// the pure state transition so it can be exercised by tests.
void startNewDocument(
  WidgetRef ref, {
  required double width,
  required double height,
  required String sessionName,
  String? imageUrl,
}) {
  ref.read(editorSessionProvider.notifier).state = EditorSession(
    name: sessionName,
  );
  resetEditorEphemeralState(ref);

  final docCtrl = ref.read(documentControllerProvider.notifier);
  docCtrl.newDocument(width: width, height: height);
  ref.read(selectionControllerProvider.notifier).clear();

  if (imageUrl != null) {
    final id = _uuid.v4();
    docCtrl.execute(
      AddLayerCommand(
        ImageLayer(
          id: id,
          transform: LayerTransform(
            position: Offset.zero,
            size: Size(width, height),
          ),
          source: ImageSource.network(imageUrl),
        ),
      ),
    );
    ref.read(selectionControllerProvider.notifier).select(id);
  }
}

const _uuid = Uuid();

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
  // Mask-edit mode: an off-canvas tap is an explicit "I'm done" —
  // cancel (draft-first, so this discards cleanly with no command).
  ref.read(maskEditControllerProvider.notifier).cancel();
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
///   * Paint tool — it is mode-scoped (its `openSlot` configures
///     the next stroke, not a selected layer); selection changes
///     are unrelated to paint sheet visibility.
///   * Text mode `panelOpen` — text mode itself is preserved so
///     re-tapping a text layer keeps the user in text mode without
///     having to re-enter it. Only the per-selection sheet/slot
///     state is cleared.
void closeObjectSubPanels(WidgetRef ref) {
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
  // Mask-edit is scoped to the layer it opened on — any selection
  // change ends the session (cancel is idempotent and draft-first).
  ref.read(maskEditControllerProvider.notifier).cancel();
}
