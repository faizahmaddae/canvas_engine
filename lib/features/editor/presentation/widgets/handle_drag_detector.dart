import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'selection_overlay.dart' show DragPhase;

/// A drag-capture widget that claims the gesture arena **on pointer-down**,
/// not on first movement.
///
/// History of the bug this fixes:
///
/// We previously used [ImmediateMultiDragGestureRecognizer]. Despite the
/// name, that recognizer only resolves itself in the gesture arena once
/// the pointer has moved past `kTouchSlop` (~18 px on Android). That
/// produced a subtle but maddening UX bug:
///
///   * Tap a handle and immediately drag fast → works (movement crosses
///     slop before the parent's tap recogniser wins).
///   * Tap a handle, pause for a fraction of a second, then drag → fails
///     (with no movement during the pause, the parent `GestureDetector`'s
///     tap recogniser wins the arena via the sweep, the pointer is given
///     away, and the subsequent move never reaches the handle).
///
/// The fix is to claim the arena the *instant* a pointer lands on the
/// handle. Once we have called `resolve(GestureDisposition.accepted)` on
/// pointer-down, every other recogniser competing for the same pointer
/// (parent tap / scale / long-press / canvas pan) is rejected, and the
/// handle keeps the pointer regardless of how long the user pauses
/// before moving.
class HandleDragDetector extends StatelessWidget {
  const HandleDragDetector({
    super.key,
    this.child,
    required this.onDrag,
    this.behavior = HitTestBehavior.opaque,
  });

  /// Optional child. When omitted the detector fills its parent, which is
  /// useful for drag surfaces (e.g. the layer body) that have no visible
  /// content of their own.
  final Widget? child;
  final HitTestBehavior behavior;
  final void Function(Offset globalPointer, DragPhase phase) onDrag;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: behavior,
      gestures: <Type, GestureRecognizerFactory>{
        _HandleDragRecognizer:
            GestureRecognizerFactoryWithHandlers<_HandleDragRecognizer>(
              () => _HandleDragRecognizer(),
              (instance) => instance.onDrag = onDrag,
            ),
      },
      child: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            // Transparent but opaque-to-hit-test surface. Guarantees hit
            // tests land anywhere in the parent box even if the visual
            // child is smaller (e.g. a 14dp glyph centred in a 48dp
            // touch target).
            const Positioned.fill(child: ColoredBox(color: Color(0x00000000))),
            ?child,
          ],
        ),
      ),
    );
  }
}

/// One-sequence gesture recogniser that claims the arena on pointer-down
/// (zero slop, zero delay) and dispatches start / update / end callbacks
/// directly from the raw pointer stream.
///
/// Why subclass [OneSequenceGestureRecognizer] instead of using
/// [Listener] + [EagerGestureRecognizer]?
///
///   * Both approaches successfully claim the arena, but a recogniser
///     centralises pointer-tracking + arena claim in one object, which
///     makes ownership semantics easier to reason about (especially when
///     the pointer is cancelled mid-gesture).
///   * We need the *last known global position* on cancel — keeping that
///     state inside the recogniser avoids an extra widget-state field.
class _HandleDragRecognizer extends OneSequenceGestureRecognizer {
  void Function(Offset globalPointer, DragPhase phase)? onDrag;

  int? _activePointer;
  Offset _lastGlobalPosition = Offset.zero;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    // Only one finger drives a single handle. If a second pointer lands
    // on the same handle while we already have one, ignore it — the
    // multi-touch viewport gesture is handled by the parent.
    if (_activePointer != null) {
      return;
    }
    _activePointer = event.pointer;
    _lastGlobalPosition = event.position;
    startTrackingPointer(event.pointer, event.transform);

    // Claim the arena immediately. Any competing tap / scale / long-press
    // recogniser on an ancestor is rejected before it can fire, so the
    // user can pause arbitrarily long after touching the handle without
    // losing ownership of the gesture.
    resolve(GestureDisposition.accepted);

    onDrag?.call(event.position, DragPhase.start);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _activePointer) return;

    if (event is PointerMoveEvent) {
      _lastGlobalPosition = event.position;
      onDrag?.call(event.position, DragPhase.update);
    } else if (event is PointerUpEvent) {
      _lastGlobalPosition = event.position;
      onDrag?.call(event.position, DragPhase.end);
      _finish(event.pointer);
    } else if (event is PointerCancelEvent) {
      onDrag?.call(_lastGlobalPosition, DragPhase.end);
      _finish(event.pointer);
    }
  }

  void _finish(int pointer) {
    _activePointer = null;
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    // No additional cleanup — _finish already resets _activePointer and
    // the framework removes the arena entry.
  }

  @override
  void rejectGesture(int pointer) {
    // We claim accepted on pointer-down, so this should never fire in
    // practice. Defensive: if the framework rejects us anyway (e.g. the
    // widget is unmounted mid-gesture), emit an end so the controller
    // doesn't hang on a stale session.
    if (pointer == _activePointer) {
      onDrag?.call(_lastGlobalPosition, DragPhase.end);
      _finish(pointer);
    }
    super.rejectGesture(pointer);
  }

  @override
  String get debugDescription => 'handle-drag (claims-on-down)';
}
