import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../crop/application/crop_controller.dart';
import '../text/application/add_text_composer_state.dart';
import 'export_session.dart';
import 'mask_edit_controller.dart';

/// The session registry (interaction contract §6): `true` while ANY
/// draft session is open —
///
///   * crop (full-screen draft overlay),
///   * mask edit (on-canvas draft),
///   * text compose (add composer sheet) / text edit (edit-flow
///     sheet — separate flag, same class of session),
///   * export render + save/share (bytes being produced from the
///     document).
///
/// While this is `true`, the affordances that mutate history from
/// OUTSIDE the session go inert: the top-bar undo/redo buttons are
/// disabled, the multi-finger undo/redo canvas shortcut aborts, and
/// the Layers drawer edge-swipe is off. The per-session document
/// listeners that CANCEL a session when the document mutates
/// underneath it (e.g. `MaskEditController`'s doc subscription, the
/// text controller's commit-version guard) are the correctness
/// backstops and stay in place — this registry only removes the
/// obvious ways to trip them.
///
/// Derived, not stored: unioning the sessions' own state means the
/// registry can never drift from reality or leak an entry.
final anyDraftSessionOpenProvider = Provider<bool>((ref) {
  final cropActive = ref.watch(cropControllerProvider.select((s) => s.active));
  final maskActive = ref.watch(
    maskEditControllerProvider.select((s) => s.active),
  );
  final composing = ref.watch(addTextComposerOpenProvider);
  final editingText = ref.watch(textEditFlowOpenProvider);
  final exporting = ref.watch(exportSessionControllerProvider);
  return cropActive || maskActive || composing || editingText || exporting;
});
