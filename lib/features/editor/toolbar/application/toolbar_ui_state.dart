import 'package:flutter/foundation.dart';

import '../domain/mode_id.dart';

/// Shared UI state for the editor toolbar system.
///
/// Owns "which mode is active" and "which slot is currently open"
/// — the two facts every toolbar surface needs. Per-mode value
/// state (active brush, active text style, …) stays in its
/// existing controller; this Notifier orchestrates only the
/// toolbar UI.
@immutable
class ToolbarUiState {
  const ToolbarUiState({
    this.activeMode = ModeId.main,
    this.openSlotId,
  });

  /// Currently active mode. [ModeId.main] when no tool mode is
  /// engaged.
  final ModeId activeMode;

  /// Id of the slot whose sub-tool is currently revealed in the
  /// dock's expanded region. `null` when no slot is open.
  final String? openSlotId;

  bool get inMode => activeMode != ModeId.main;
  bool get hasOpenSlot => openSlotId != null;

  ToolbarUiState copyWith({
    ModeId? activeMode,
    String? openSlotId,
    bool clearOpenSlot = false,
  }) {
    return ToolbarUiState(
      activeMode: activeMode ?? this.activeMode,
      openSlotId: clearOpenSlot ? null : (openSlotId ?? this.openSlotId),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ToolbarUiState &&
      other.activeMode == activeMode &&
      other.openSlotId == openSlotId;

  @override
  int get hashCode => Object.hash(activeMode, openSlotId);
}
