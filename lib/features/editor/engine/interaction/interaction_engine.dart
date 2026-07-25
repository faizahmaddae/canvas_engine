import 'dart:math' as math;
import 'dart:ui';

import '../../../../core/constants/engine_constants.dart';
import '../../../../core/utils/geometry.dart';
import '../core/layer_capabilities.dart';
import '../core/layer_transform.dart';
import '../core/selection_state.dart';
import 'interaction_session.dart';

/// Pure, stateless math for move/resize/rotate. No Flutter widgets, no
/// providers. Every method returns either an [InteractionSession] or a new
/// [LayerTransform] — the caller is responsible for wiring them into the
/// document.
class InteractionEngine {
  const InteractionEngine();

  // ---------- session factories ----------

  InteractionSession startMove({
    required String layerId,
    required LayerTransform transform,
    required Offset pointer,
  }) {
    return InteractionSession(
      layerId: layerId,
      handle: InteractionHandle.body,
      initialTransform: transform,
      pointerStart: pointer,
      pointerStartAngle: 0,
    );
  }

  InteractionSession startResize({
    required String layerId,
    required LayerTransform transform,
    required InteractionHandle corner,
    required Offset pointer,
  }) {
    assert(_isCorner(corner), 'startResize requires a corner handle');
    return InteractionSession(
      layerId: layerId,
      handle: corner,
      initialTransform: transform,
      pointerStart: pointer,
      pointerStartAngle: 0,
    );
  }

  InteractionSession startRotate({
    required String layerId,
    required LayerTransform transform,
    required Offset pointer,
  }) {
    final angle = angleOf(transform.center, pointer);
    return InteractionSession(
      layerId: layerId,
      handle: InteractionHandle.rotate,
      initialTransform: transform,
      pointerStart: pointer,
      pointerStartAngle: angle,
    );
  }

  /// Multi-touch gesture session. [focalPoint] is the initial midpoint of
  /// the active pointers in canvas space and becomes the gesture's
  /// translation reference: the layer centre is displaced by
  /// `focalPoint - pointerStart` on every [updateGesture] frame.
  /// Scale and rotation are applied around the layer's own centre
  /// (scale-in-place), not around the focal \u2014 see the comment in
  /// [updateGesture] for why.
  InteractionSession startGesture({
    required String layerId,
    required LayerTransform transform,
    required Offset focalPoint,
  }) {
    return InteractionSession(
      layerId: layerId,
      handle: InteractionHandle.gesture,
      initialTransform: transform,
      pointerStart: focalPoint,
      pointerStartAngle: 0,
    );
  }

  // ---------- updates ----------

  LayerTransform updateMove(InteractionSession session, Offset pointer) {
    final dx = pointer.dx - session.pointerStart.dx;
    final dy = pointer.dy - session.pointerStart.dy;
    return session.initialTransform.copyWith(
      position: session.initialTransform.position + Offset(dx, dy),
    );
  }

  LayerTransform updateRotate(
    InteractionSession session,
    Offset pointer, {
    bool snap = true,
  }) {
    final currentAngle = angleOf(session.initialTransform.center, pointer);
    final delta = currentAngle - session.pointerStartAngle;
    var next = session.initialTransform.rotation + delta;
    if (snap) next = snapRotation(next);
    return session.initialTransform.copyWith(rotation: next);
  }

  /// True when [angle] lies inside the magnetic snap zone of the nearest
  /// multiple of [EngineConstants.rotationSnapIncrement]. The overlay uses
  /// this to provide subtle visual feedback without the UI having to
  /// re-implement the math. Cardinal angles (0 / 90 / 180 / 270) use a
  /// wider threshold than diagonals so they feel "stickier" — that
  /// matches designer muscle memory.
  bool isNearSnap(double angle) {
    const step = EngineConstants.rotationSnapIncrement;
    final nearest = (angle / step).round() * step;
    final threshold = _thresholdFor(nearest);
    return (angle - nearest).abs() <= threshold;
  }

  // --- gesture (pinch + rotate + translate) -------------------------------

  /// Result of a single gesture frame. Holds the new transform and whether
  /// the gesture is currently snapped to a rotation target, so the controller
  /// can surface that without re-running the math.
  ({LayerTransform transform, bool snapped}) updateGesture(
    InteractionSession session, {
    required Offset focalPoint,
    required double scale,
    required double rotation,
    LayerCapabilities capabilities = const LayerCapabilities(),
    bool snap = true,
  }) {
    final t0 = session.initialTransform;
    final focal0 = session.pointerStart;

    // Uniform scale the size, clamped to max(engineFloor, capability) on
    // either axis. If a side hits its minimum we reduce the effective scale
    // so aspect ratio is preserved — pinch never distorts.
    final minW = math.max(EngineConstants.minLayerSize, capabilities.minWidth);
    final minH = math.max(EngineConstants.minLayerSize, capabilities.minHeight);
    const maxSide = EngineConstants.maxLayerSize;
    // Hard-clamp the gesture scale first so a single frame with a huge
    // ratio (e.g. fingers jumping apart) cannot push the layer past the
    // allowed envelope. Prevents runaway growth and "disappearing" objects.
    var effective = scale.clamp(
      EngineConstants.minGestureScale,
      EngineConstants.maxGestureScale,
    );
    // Shrink to respect per-layer / engine minimums, aspect preserved.
    if (t0.size.width * effective < minW) {
      effective = minW / t0.size.width;
    }
    if (t0.size.height * effective < minH) {
      effective = math.max(effective, minH / t0.size.height);
    }
    // Enforce upper bound on either axis, aspect preserved.
    if (t0.size.width * effective > maxSide) {
      effective = maxSide / t0.size.width;
    }
    if (t0.size.height * effective > maxSide) {
      effective = math.min(effective, maxSide / t0.size.height);
    }
    final newW = t0.size.width * effective;
    final newH = t0.size.height * effective;

    // Rotation with optional snap.
    final rawRotation = t0.rotation + rotation;
    final newRot = snap ? snapRotation(rawRotation) : rawRotation;
    final snapped = snap && isNearSnap(rawRotation);

    // Scale + rotate happen around the layer's OWN centre; translation is
    // the gesture focal's delta. Rationale:
    //
    // The previous implementation anchored the point under the initial
    // focal to stay under the current focal ("Procreate free-transform"
    // model). That is mathematically defensible \u2014 the point under
    // your fingers at t=0 remains under your fingers at t=n \u2014 but it
    // produces visible *positional* drift whenever the focal is not
    // exactly on the object's centre: scaling a 100 px object with
    // fingers 50 px below its centre shifts the object upward by
    // `(1 - scale) * 50 px` on every frame. Users experience this as
    // "the object flies away when I pinch" and, for off-object focals
    // (two fingers on empty canvas to scale a selected layer), as
    // unconstrained drift.
    //
    // Decoupling fixes this without losing any capability:
    //   * Scale  \u2192 applied around the layer's current centre (in-place
    //     growth/shrink, no positional side-effect).
    //   * Rotate \u2192 applied around the layer's current centre (in-place
    //     spin, no positional side-effect).
    //   * Translate \u2192 `focalPoint - focal0`, so dragging the fingers
    //     still drags the object 1:1.
    //
    // Nets the same three degrees of freedom but each feels stable on
    // its own, matching Canva / CapCut / Figma-mobile behaviour.
    final newCenter = t0.center + (focalPoint - focal0);

    return (
      transform: t0.copyWith(
        position: Offset(newCenter.dx - newW / 2, newCenter.dy - newH / 2),
        size: Size(newW, newH),
        rotation: newRot,
      ),
      snapped: snapped,
    );
  }

  /// Soft snap to the nearest multiple of
  /// [EngineConstants.rotationSnapIncrement] when within the active
  /// threshold. Outside that zone the input angle is returned unchanged,
  /// so fine rotation is never prevented. Cardinals are "stickier" (see
  /// [EngineConstants.rotationCardinalSnapThreshold]).
  double snapRotation(double angle) {
    const step = EngineConstants.rotationSnapIncrement;
    final nearest = (angle / step).round() * step;
    final threshold = _thresholdFor(nearest);
    final diff = (angle - nearest).abs();
    if (diff <= threshold) return nearest;
    return angle;
  }

  /// Return the magnetic threshold to use near [nearestSnapTarget]. A
  /// cardinal target (0, ±π/2, π) gets the wider zone.
  double _thresholdFor(double nearestSnapTarget) {
    // Normalize to [-pi, pi) so e.g. 2π counts as 0.
    var n = nearestSnapTarget % (2 * math.pi);
    if (n > math.pi) n -= 2 * math.pi;
    if (n <= -math.pi) n += 2 * math.pi;
    // Allow a tiny float fudge in case the modulo leaves
    // 1e-16 residue on a cardinal.
    const eps = 1e-6;
    final isCardinal =
        n.abs() < eps ||
        (n - math.pi / 2).abs() < eps ||
        (n + math.pi / 2).abs() < eps ||
        (n - math.pi).abs() < eps ||
        (n + math.pi).abs() < eps;
    return isCardinal
        ? EngineConstants.rotationCardinalSnapThreshold
        : EngineConstants.rotationSnapThreshold;
  }

  /// Rotated resize: we work in the layer's *local* (unrotated) space, resize
  /// there, then translate back so the anchor (opposite corner) stays fixed
  /// in canvas space. This matches the behaviour users expect from Figma /
  /// Keynote etc., including when the layer is rotated.
  LayerTransform updateResize(
    InteractionSession session,
    Offset pointer, {
    LayerCapabilities capabilities = const LayerCapabilities(),
  }) {
    final t0 = session.initialTransform;
    final handle = session.handle;
    if (!_isCorner(handle)) return t0;

    final center0 = t0.center;
    final rot = t0.rotation;

    // Move pointer into local (unrotated) space around the original center.
    final localPointer = pointer.rotateAround(center0, -rot);
    final localStart = session.pointerStart.rotateAround(center0, -rot);

    // Identify the anchor corner (opposite of the grabbed one) in local
    // unrotated coords. Local rect = Rect.fromLTWH(position, size).
    final r0 = t0.unrotatedRect;
    final (anchorLocal, grabLocal) = _anchorAndGrabLocal(r0, handle);

    // Delta in local space: how far the grabbed corner has moved.
    final dx = localPointer.dx - localStart.dx;
    final dy = localPointer.dy - localStart.dy;

    // Direction the grabbed corner sits in relative to the anchor. Using
    // this sign (rather than the current newGrab position) prevents the
    // "flipped" state where the grabbed corner crosses past the anchor
    // and the rect inverts to the other side — we simply clamp the
    // grabbed corner at (anchor ± min).
    final signX = grabLocal.dx >= anchorLocal.dx ? 1 : -1;
    final signY = grabLocal.dy >= anchorLocal.dy ? 1 : -1;

    // Per-layer minimums trump the engine-wide floor.
    final minW = math.max(EngineConstants.minLayerSize, capabilities.minWidth);
    final minH = math.max(EngineConstants.minLayerSize, capabilities.minHeight);

    // Proposed grabbed corner, then clamped to stay on its side of the
    // anchor at distance ≥ min*.
    var newGrabX = grabLocal.dx + dx;
    var newGrabY = grabLocal.dy + dy;
    if (signX > 0) {
      if (newGrabX < anchorLocal.dx + minW) newGrabX = anchorLocal.dx + minW;
    } else {
      if (newGrabX > anchorLocal.dx - minW) newGrabX = anchorLocal.dx - minW;
    }
    if (signY > 0) {
      if (newGrabY < anchorLocal.dy + minH) newGrabY = anchorLocal.dy + minH;
    } else {
      if (newGrabY > anchorLocal.dy - minH) newGrabY = anchorLocal.dy - minH;
    }
    final newGrab = Offset(newGrabX, newGrabY);

    // Build new rect from (anchor, clamped grab).
    double left = math.min(anchorLocal.dx, newGrab.dx);
    double top = math.min(anchorLocal.dy, newGrab.dy);
    double width = (newGrab.dx - anchorLocal.dx).abs();
    double height = (newGrab.dy - anchorLocal.dy).abs();

    // Optional aspect ratio lock.
    if (capabilities.keepsAspectRatio) {
      final aspect = r0.width / r0.height;
      if (width / height > aspect) {
        width = height * aspect;
        if (signX < 0) left = anchorLocal.dx - width;
      } else {
        height = width / aspect;
        if (signY < 0) top = anchorLocal.dy - height;
      }
      // The aspect correction SHRINKS one axis, so it can undo the
      // min-size clamp applied above: a 1080×1350 layer dragged fully
      // in bottomed out at 19.2 × 24 rather than 24 × 24. Scale the
      // locked pair back up until both axes clear their floor again —
      // one uniform bump, so the ratio survives.
      final bump = math.max(
        width <= 0 ? 1.0 : minW / width,
        height <= 0 ? 1.0 : minH / height,
      );
      if (bump > 1) {
        if (signX < 0) left = anchorLocal.dx - width * bump;
        if (signY < 0) top = anchorLocal.dy - height * bump;
        width *= bump;
        height *= bump;
      }
    }

    final newLocalRect = Rect.fromLTWH(left, top, width, height);

    // The layer's center moved in *local* space by the difference between
    // the new center and the old center. Rotate that delta back into canvas
    // space to figure out where the layer should sit now.
    final oldLocalCenter = r0.center;
    final newLocalCenter = newLocalRect.center;
    final localCenterDelta = newLocalCenter - oldLocalCenter;
    final canvasCenterDelta = Offset.zero
        .translate(localCenterDelta.dx, localCenterDelta.dy)
        .rotateAround(Offset.zero, rot);
    final newCenter = center0 + canvasCenterDelta;

    final newPosition = Offset(
      newCenter.dx - width / 2,
      newCenter.dy - height / 2,
    );

    return t0.copyWith(position: newPosition, size: Size(width, height));
  }

  // ---------- helpers ----------

  bool _isCorner(InteractionHandle h) =>
      h == InteractionHandle.topLeft ||
      h == InteractionHandle.topRight ||
      h == InteractionHandle.bottomLeft ||
      h == InteractionHandle.bottomRight;

  /// Returns (anchor, grabbed) corners in local unrotated space for the
  /// given handle.
  (Offset, Offset) _anchorAndGrabLocal(Rect r, InteractionHandle h) {
    switch (h) {
      case InteractionHandle.topLeft:
        return (r.bottomRight, r.topLeft);
      case InteractionHandle.topRight:
        return (r.bottomLeft, r.topRight);
      case InteractionHandle.bottomLeft:
        return (r.topRight, r.bottomLeft);
      case InteractionHandle.bottomRight:
        return (r.topLeft, r.bottomRight);
      case InteractionHandle.body:
      case InteractionHandle.rotate:
      case InteractionHandle.gesture:
        throw StateError('Not a corner handle: $h');
    }
  }
}
