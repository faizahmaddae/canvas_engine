import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/mode_id.dart';
import 'toolbar_ui_state.dart';

/// Orchestrates toolbar UI transitions: mode entry/exit and slot
/// open/close/toggle.
///
/// Phase 1 ships the controller with no consumers wired into it
/// yet — the existing `PaintToolController` and `TextToolController`
/// continue to drive their own panels. Later phases route those
/// controllers (and any new mode controllers) through this single
/// orchestrator so the dock host has one source of truth.
///
/// **Interaction rules** enforced here (apply uniformly to every
/// future mode):
///   * Entering a mode always clears any previously open slot.
///   * Exiting a mode always closes its open slot.
///   * Tapping the active slot is a no-op (use [closeSlot] / the
///     drag-handle / swipe-down to dismiss). Tapping a different
///     slot reveals it.
class ToolbarController extends Notifier<ToolbarUiState> {
  @override
  ToolbarUiState build() => const ToolbarUiState();

  /// Switch to [mode]. Calling with the current mode is a no-op.
  /// Always closes any open slot.
  void enterMode(ModeId mode) {
    if (state.activeMode == mode && !state.hasOpenSlot) return;
    state = ToolbarUiState(activeMode: mode);
  }

  /// Return to [ModeId.main] and close any open slot.
  void exitMode() {
    if (state.activeMode == ModeId.main && !state.hasOpenSlot) return;
    state = const ToolbarUiState();
  }

  /// Reveal the sub-tool for [slotId]. Replaces any currently open
  /// slot. Re-opening the same slot is a no-op (use [closeSlot] /
  /// [toggleSlot] for dismissal).
  void openSlot(String slotId) {
    if (state.openSlotId == slotId) return;
    state = state.copyWith(openSlotId: slotId);
  }

  /// Close the currently open slot (mode stays active).
  void closeSlot() {
    if (!state.hasOpenSlot) return;
    state = state.copyWith(clearOpenSlot: true);
  }

  /// Open [slotId] if not open; close it if it's the active slot.
  /// Useful for toolbars that want a single tap gesture to both
  /// open and dismiss.
  void toggleSlot(String slotId) {
    if (state.openSlotId == slotId) {
      closeSlot();
    } else {
      openSlot(slotId);
    }
  }
}

final toolbarControllerProvider =
    NotifierProvider<ToolbarController, ToolbarUiState>(
  ToolbarController.new,
);
