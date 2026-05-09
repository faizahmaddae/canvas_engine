import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../core/layer_transform.dart';
import '../core/selection_state.dart';

/// Snapshot captured at the moment a gesture starts. Everything the
/// interaction engine needs to compute deltas lives here – nothing is read
/// back from the "live" document mid-gesture, which keeps math deterministic
/// and avoids feedback loops where rounding errors accumulate frame by frame.
@immutable
class InteractionSession {
  const InteractionSession({
    required this.layerId,
    required this.handle,
    required this.initialTransform,
    required this.pointerStart,
    required this.pointerStartAngle,
  });

  /// Which layer is being manipulated.
  final String layerId;

  /// Which grab point the gesture started on.
  final InteractionHandle handle;

  /// Reference transform used to compute deltas in the math engine.
  ///
  /// IMPORTANT: this is NOT guaranteed to be the transform at gesture
  /// start. Multi-touch sessions (`InteractionHandle.gesture`) rebase
  /// this field on every pointer-count transition (1↔≥2) inside
  /// `InteractionController.updateGesture` — without rebasing, a
  /// second finger landing mid-drag moves the focal to the pointers'
  /// midpoint while the gesture's `scale` restarts near 1.0, so the
  /// layer would visibly jump. Rebasing resets the math reference to
  /// the current live state so the gesture continues seamlessly.
  ///
  /// Consequence: do NOT use this field to decide whether a gesture
  /// "changed anything" (e.g. at commit time). Compare the live
  /// transform against the document's transform instead — the
  /// document is untouched by the gesture until commit, so it is
  /// the only reliable pre-gesture reference.
  final LayerTransform initialTransform;

  /// Pointer position (canvas space) at gesture start.
  final Offset pointerStart;

  /// For rotate: angle (rad) of (pointerStart - center) at gesture start.
  /// Unused for move/resize but stored to keep the record uniform.
  final double pointerStartAngle;
}
