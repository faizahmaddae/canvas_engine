import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/document_controller.dart';
import '../../application/selection_controller.dart';
import 'image_tool_controller.dart';

/// One in-flight "Adjust/Filters entered from the MAIN strip"
/// session (contract §4, tb2 10/16 — audit
/// crop-filters-adjust-exit-asymmetry).
///
/// Crop already records `priorSelectionId` when the main strip
/// resolves an image target and restores it on Done/Cancel, so the
/// user lands back on the main toolbar. Adjust/Filters shared the
/// same auto-selecting entry but had no exit half: closing the
/// panel STRANDED the user in image mode with a selection they
/// never made. This record is the missing half, mirroring crop's
/// semantics exactly:
///
///   * [priorSelectionId] — the selection at entry (null = came
///     from the main toolbar with nothing selected; restore =
///     clear). A user who deliberately selected the image first
///     enters through the IMAGE strip instead, which records no
///     session — they keep their selection.
///   * [targetLayerId] — the image the entry resolved. Restoration
///     only fires while this is STILL the selection; any change of
///     selection in between means another seam (tap-empty E3,
///     reselect, undo-prune) already decided the outcome.
///   * [slot] — the panel the entry opened. The session dies the
///     moment any OTHER slot fronts (sibling-swipe / chip tap =
///     the user took ownership of image mode).
@immutable
class MainStripImageEntry {
  const MainStripImageEntry({
    required this.slot,
    required this.targetLayerId,
    this.priorSelectionId,
  });

  final ImageToolSlot slot;
  final String targetLayerId;
  final String? priorSelectionId;
}

/// Owns the [MainStripImageEntry] lifecycle. The main-strip tile
/// handlers call [record] right after target resolution; the editor
/// screen forwards image-dock slot transitions to
/// [handleSlotChange], which performs the restore on the E1 close
/// of the recorded panel.
class MainStripImageEntryController extends Notifier<MainStripImageEntry?> {
  @override
  MainStripImageEntry? build() => null;

  /// Arm a session. Call after the image target is resolved (and
  /// auto-selected) but before the panel slot is opened.
  void record({
    required ImageToolSlot slot,
    required String targetLayerId,
    String? priorSelectionId,
  }) {
    state = MainStripImageEntry(
      slot: slot,
      targetLayerId: targetLayerId,
      priorSelectionId: priorSelectionId,
    );
  }

  /// React to an image-dock `openSlot` transition.
  ///
  /// Restores the prior selection exactly when the RECORDED panel
  /// closes to nothing while the auto-selected target is still the
  /// selection. Every other transition disarms the session without
  /// restoring:
  ///   * another slot fronts → the user took ownership of image
  ///     mode (deliberate interaction beats the entry shortcut);
  ///   * the selection moved on → E3 / reselect / prune already
  ///     resolved where the user goes next, and overriding a
  ///     deliberate deselect would violate §4's E3.
  void handleSlotChange(ImageToolSlot? prevSlot, ImageToolSlot? nextSlot) {
    final session = state;
    if (session == null) return;
    if (nextSlot == session.slot) return; // opening / still front
    state = null; // every path below disarms
    final closedRecordedPanel = prevSlot == session.slot && nextSlot == null;
    if (!closedRecordedPanel) return;
    if (ref.read(selectionControllerProvider).selectedId !=
        session.targetLayerId) {
      return;
    }
    final sel = ref.read(selectionControllerProvider.notifier);
    final prior = session.priorSelectionId;
    // Mirror CropController._restoreSelection: null prior → clear
    // (back to the main toolbar). Extra guard over crop: a prior
    // layer deleted while the panel was open must not leave a
    // phantom selection, so a dead id degrades to clear.
    if (prior != null &&
        ref.read(documentControllerProvider).layerById(prior) != null) {
      sel.select(prior);
    } else {
      sel.clear();
    }
  }
}

final mainStripImageEntryProvider =
    NotifierProvider<MainStripImageEntryController, MainStripImageEntry?>(
      MainStripImageEntryController.new,
    );
