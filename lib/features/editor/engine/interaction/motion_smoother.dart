import 'dart:math' as math;
import 'dart:ui';

/// Time-based exponential smoother for gesture outputs.
///
/// During a gesture the controller computes a fresh "target" transform from
/// the raw pointer stream every frame. On real hardware that stream carries
/// high-frequency jitter (trackpads round to integer pixels, touch digitizers
/// resample, snap engines can cause step discontinuities). Piping the target
/// through this smoother produces a visually smoother motion path without
/// adding perceptible lag:
///
///     alpha = 1 - exp(-dt / tau)
///     shown = shown + (target - shown) * alpha
///
/// **Why time-based, not frame-based?** The previous implementation used a
/// constant per-frame alpha (e.g. 0.55). At 60 Hz that produces one feel;
/// at 120 Hz the same alpha applies twice as often per second, so motion
/// reaches the target ~2\u00d7 faster \u2014 ProMotion / 120 Hz devices felt
/// snappier and 90 Hz felt in-between. Computing alpha from the actual
/// frame [dt] and a per-axis time constant [tau] (in seconds) makes the
/// response identical at every refresh rate: at any device, the smoother
/// reaches \u224863% of the target in `tau` seconds.
///
/// Time constants are calibrated so 60 Hz behaviour matches the previous
/// hand-tuned alphas:
///   * position: \u2248 21 ms (was alpha 0.55)
///   * rotation: \u2248 33 ms (was alpha 0.40)
///   * size:     \u2248 18 ms (was alpha 0.60)
///
/// Snap-ins: because the engine writes the snapped target into the smoother
/// input, the on-screen object eases into the snap target over a few
/// frames rather than jumping \u2014 the magnetic feel we want.
class MotionSmoother {
  MotionSmoother({
    this.positionTau = 0.021,
    this.rotationTau = 0.033,
    this.sizeTau = 0.018,
  });

  /// Time constants in seconds. Smaller = snappier response.
  final double positionTau;
  final double rotationTau;
  final double sizeTau;

  Offset? _position;
  double? _rotation;
  Size? _size;

  /// Seed the smoother with the initial (un-smoothed) values. Call this at
  /// session start with the layer's current transform so the first frame
  /// after smoothing starts at the true position rather than easing in
  /// from origin.
  void seed({
    required Offset position,
    required double rotation,
    required Size size,
  }) {
    _position = position;
    _rotation = rotation;
    _size = size;
  }

  /// Compute the EMA blend factor for a given [dt] and time constant [tau].
  /// Bounded in [0, 1]; degenerate dt (\u22640) or tau (\u22640) collapses to 1
  /// (snap-to-target) so a single-frame anomaly never freezes the smoother.
  static double _alpha(double dt, double tau) {
    if (dt <= 0 || tau <= 0) return 1;
    return 1 - math.exp(-dt / tau);
  }

  Offset smoothPosition(Offset target, {required double dt}) {
    final prev = _position;
    if (prev == null) {
      _position = target;
      return target;
    }
    final a = _alpha(dt, positionTau);
    final next = Offset(
      prev.dx + (target.dx - prev.dx) * a,
      prev.dy + (target.dy - prev.dy) * a,
    );
    // Snap-to-target once within a sub-pixel threshold so the EMA does not
    // asymptote forever and leave 0.1 px drift at rest.
    if ((target - next).distanceSquared < 0.25) {
      _position = target;
      return target;
    }
    _position = next;
    return next;
  }

  /// Smooth an angle in radians using the *shortest signed delta* so we
  /// never interpolate the long way around the circle.
  double smoothRotation(double target, {required double dt}) {
    final prev = _rotation;
    if (prev == null) {
      _rotation = target;
      return target;
    }
    // Shortest delta in (-pi, pi].
    var d = target - prev;
    while (d > math.pi) {
      d -= 2 * math.pi;
    }
    while (d <= -math.pi) {
      d += 2 * math.pi;
    }
    final a = _alpha(dt, rotationTau);
    final next = prev + d * a;
    if (d.abs() < 0.001) {
      _rotation = target;
      return target;
    }
    _rotation = next;
    return next;
  }

  Size smoothSize(Size target, {required double dt}) {
    final prev = _size;
    if (prev == null) {
      _size = target;
      return target;
    }
    final a = _alpha(dt, sizeTau);
    final w = prev.width + (target.width - prev.width) * a;
    final h = prev.height + (target.height - prev.height) * a;
    final next = Size(w, h);
    if ((target.width - w).abs() < 0.5 &&
        (target.height - h).abs() < 0.5) {
      _size = target;
      return target;
    }
    _size = next;
    return next;
  }
}
