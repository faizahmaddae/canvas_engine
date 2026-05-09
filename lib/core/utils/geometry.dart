// Math + geometry utilities used across the engine.
// All angles are radians unless named explicitly.

import 'dart:math' as math;
import 'dart:ui';

/// A 2D point/vector wrapper around [Offset] for readability.
extension OffsetMath on Offset {
  Offset rotateAround(Offset pivot, double angleRad) {
    final s = math.sin(angleRad);
    final c = math.cos(angleRad);
    final dx = this.dx - pivot.dx;
    final dy = this.dy - pivot.dy;
    return Offset(
      pivot.dx + dx * c - dy * s,
      pivot.dy + dx * s + dy * c,
    );
  }
}

/// Returns the angle in radians of vector (to - from) from +X axis.
double angleOf(Offset from, Offset to) {
  return math.atan2(to.dy - from.dy, to.dx - from.dx);
}

/// Shortest signed delta between two angles, wrapped into (-pi, pi].
double shortestAngleDelta(double a, double b) {
  var d = b - a;
  while (d > math.pi) {
    d -= 2 * math.pi;
  }
  while (d <= -math.pi) {
    d += 2 * math.pi;
  }
  return d;
}

double clampDouble(double v, double lo, double hi) {
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}
