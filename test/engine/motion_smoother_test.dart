import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/interaction/motion_smoother.dart';
import 'package:flutter_test/flutter_test.dart';

/// At equivalent total wall-clock time, smoothers ticked at different
/// frame rates must converge to the same value. Frame-based EMA fails
/// this; time-based EMA passes it.
void main() {
  group('MotionSmoother — frame-rate independence', () {
    test('60Hz, 90Hz, and 120Hz converge to the same value over 100ms', () {
      const target = Offset(100, 100);

      Offset run({required double dtMs, required int frames}) {
        final s = MotionSmoother()
          ..seed(position: Offset.zero, rotation: 0, size: const Size(10, 10));
        var p = Offset.zero;
        for (var i = 0; i < frames; i++) {
          p = s.smoothPosition(target, dt: dtMs / 1000);
        }
        return p;
      }

      final at60 = run(dtMs: 1000 / 60, frames: 6);
      final at120 = run(dtMs: 1000 / 120, frames: 12);
      final at90 = run(dtMs: 1000 / 90, frames: 9);

      // All within ~1 px of each other after the same wall-clock budget.
      // (A constant-alpha EMA would diverge by tens of pixels here.)
      expect((at60 - at120).distance, lessThan(1.0));
      expect((at60 - at90).distance, lessThan(1.0));
    });

    test('huge dt collapses to target (catch-up after a long pause)', () {
      final s = MotionSmoother()
        ..seed(position: Offset.zero, rotation: 0, size: const Size(10, 10));
      // After a 10 s pause the next frame should be effectively at
      // target — the user moved on, the smoother should not fight back.
      final p = s.smoothPosition(const Offset(200, 200), dt: 10);
      expect(p.dx, closeTo(200, 0.001));
      expect(p.dy, closeTo(200, 0.001));
    });

    test('dt<=0 anomaly safeguard: alpha clamps to 1 so the smoother '
        'cannot freeze on bad input', () {
      final s = MotionSmoother()
        ..seed(
          position: const Offset(50, 50),
          rotation: 0,
          size: const Size(10, 10),
        );
      // Documented behaviour: dt<=0 treats the frame as "infinite time
      // since last tick" and snaps to target. Prevents a stuck smoother
      // if the controller ever feeds in a non-positive dt.
      final p = s.smoothPosition(const Offset(100, 100), dt: 0);
      expect(p, const Offset(100, 100));
    });
  });
}
