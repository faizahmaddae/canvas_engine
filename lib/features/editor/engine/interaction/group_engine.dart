import 'dart:math' as math;
import 'dart:ui';

import '../core/layer_transform.dart';

/// Immutable result of a group [GroupEngine.scale] / [GroupEngine.pinch]
/// operation.
///
/// Bundles the final clamped layer [transforms] with the single
/// [appliedScale] that produced them, so a caller drawing selection
/// chrome can build the group frame from the *same* scale the engine
/// actually applied — never the requested scale. Without this, a
/// per-layer min/max constraint that tightens the shared factor would
/// leave the frame tracking the requested scale while the layers use the
/// clamped one, and the chrome would visibly detach from the content.
class GroupScaleResult {
  GroupScaleResult({
    required Map<String, LayerTransform> transforms,
    required this.appliedScale,
  }) : transforms = Map.unmodifiable(transforms);

  /// Final transforms for every participant, keyed by layer id. Wrapped
  /// with [Map.unmodifiable] at construction — the engine hands back a
  /// read-only snapshot the caller must not mutate.
  final Map<String, LayerTransform> transforms;

  /// The exact shared uniform scale applied to *every* transform in
  /// [transforms] after all group constraints — the absolute
  /// `[minScale, maxScale]` clamp and the per-layer `minLayerSide` /
  /// `maxLayerSide` floors/ceilings — were resolved. Equals the accepted
  /// requested scale when nothing clamps.
  final double appliedScale;
}

/// Pure, stateless math for group transforms.
///
/// A "group" is a set of [LayerTransform]s identified by stable string
/// ids. The engine reasons about them via two derived quantities:
///
///   * **bounds**: the axis-aligned bounding rectangle that encloses
///     every layer's *rotated* corner set. This is what the UI draws
///     as the shared selection rectangle.
///   * **anchor**: the point a transform is performed around — the
///     opposite corner for resize, the bounds centre for rotate /
///     pinch.
///
/// All operations are pure functions of `(initials, args) -> next`.
/// They never mutate; the controller is responsible for diffing, snap,
/// smoothing, and history.
class GroupEngine {
  const GroupEngine();

  /// Axis-aligned bounding box that encloses every transform's rotated
  /// corner set. Empty when [transforms] is empty.
  Rect computeBounds(Iterable<LayerTransform> transforms) {
    final list = transforms.toList(growable: false);
    if (list.isEmpty) return Rect.zero;
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    for (final t in list) {
      for (final c in t.corners) {
        if (c.dx < minX) minX = c.dx;
        if (c.dy < minY) minY = c.dy;
        if (c.dx > maxX) maxX = c.dx;
        if (c.dy > maxY) maxY = c.dy;
      }
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Translate every layer by [delta]. Sizes and rotations unchanged.
  /// Pure; relative layout trivially preserved.
  Map<String, LayerTransform> translate(
    Map<String, LayerTransform> initials,
    Offset delta,
  ) {
    assert(
      delta.dx.isFinite && delta.dy.isFinite,
      'GroupEngine.translate: delta must be finite',
    );
    return <String, LayerTransform>{
      for (final entry in initials.entries)
        entry.key: entry.value.copyWith(position: entry.value.position + delta),
    };
  }

  /// Uniform scale around [anchor] by [scale]. Each layer's centre is
  /// scaled around the anchor, the size is multiplied, the rotation is
  /// preserved. This keeps the relative layout of the group rigid up
  /// to the scale factor.
  ///
  /// Uniform (not separable) scale is intentional: anisotropic scale
  /// does not commute with per-layer rotation, so a rotated child
  /// would shear visibly. Uniform scale + post-translation is the
  /// only operation that preserves both the group's outer rect ratio
  /// and every child's intrinsic shape.
  ///
  /// The effective scale is reduced so that **no participant** crosses
  /// [minLayerSide] (smallest dimension floor) or [maxLayerSide]
  /// (largest dimension ceiling). Reducing the single shared factor —
  /// rather than clamping per layer — is what keeps the group rigid:
  /// the relative layout is preserved exactly, even at the constraint
  /// boundary. The trade-off is that the group cannot be scaled past
  /// the smallest member's headroom; this matches Figma / Sketch and
  /// is the only correct interpretation for a rigid-body operation.
  GroupScaleResult scale(
    Map<String, LayerTransform> initials, {
    required Offset anchor,
    required double scale,
    double minScale = 0.05,
    double maxScale = 64.0,
    double minLayerSide = 0,
    double maxLayerSide = double.infinity,
  }) {
    assert(scale.isFinite, 'GroupEngine.scale: scale must be finite');
    assert(minScale > 0, 'GroupEngine.scale: minScale must be positive');
    // Resolve the single shared factor ONCE, then reuse it for every
    // transform AND hand it back so the caller's selection frame is
    // built from the same scale the layers used.
    final s = _effectiveScale(
      initials.values,
      scale,
      minScale: minScale,
      maxScale: maxScale,
      minLayerSide: minLayerSide,
      maxLayerSide: maxLayerSide,
    );
    return GroupScaleResult(
      transforms: <String, LayerTransform>{
        for (final entry in initials.entries)
          entry.key: _scaleOne(entry.value, anchor: anchor, scale: s),
      },
      appliedScale: s,
    );
  }

  /// Effective uniform scale after all group constraints: the requested
  /// [scale] clamped to `[minScale, maxScale]`, then tightened so no
  /// participant in [layers] crosses [minLayerSide] (smallest-dimension
  /// floor) or [maxLayerSide] (largest-dimension ceiling), then
  /// re-clamped. Pure; the single source of truth shared by [scale] and
  /// [pinch] so the two constraint paths never drift.
  double _effectiveScale(
    Iterable<LayerTransform> layers,
    double scale, {
    required double minScale,
    required double maxScale,
    required double minLayerSide,
    required double maxLayerSide,
  }) {
    var s = scale.clamp(minScale, maxScale).toDouble();
    // Tighten s against per-layer floor / ceiling. We compute the
    // tightest bound across all participants and apply it once so the
    // group remains rigid.
    if (minLayerSide > 0 || maxLayerSide.isFinite) {
      for (final t in layers) {
        final smallestSide = math.min(t.size.width, t.size.height);
        final largestSide = math.max(t.size.width, t.size.height);
        if (minLayerSide > 0 && smallestSide > 0) {
          final floor = minLayerSide / smallestSide;
          if (s < floor) s = floor;
        }
        if (maxLayerSide.isFinite && largestSide > 0) {
          final ceil = maxLayerSide / largestSide;
          if (s > ceil) s = ceil;
        }
      }
      // Re-apply the absolute clamp in case constraint resolution
      // pushed s outside [minScale, maxScale].
      s = s.clamp(minScale, maxScale).toDouble();
    }
    return s;
  }

  LayerTransform _scaleOne(
    LayerTransform t, {
    required Offset anchor,
    required double scale,
  }) {
    final newCenter = anchor + (t.center - anchor) * scale;
    final newSize = Size(t.size.width * scale, t.size.height * scale);
    final newPosition = Offset(
      newCenter.dx - newSize.width / 2,
      newCenter.dy - newSize.height / 2,
    );
    return t.copyWith(position: newPosition, size: newSize);
  }

  /// Rotate every layer around [center] by [delta] radians. Each
  /// layer's centre is rotated around the group centre AND its own
  /// rotation is incremented by [delta] so children visibly turn with
  /// the group rather than orbit it.
  Map<String, LayerTransform> rotate(
    Map<String, LayerTransform> initials, {
    required Offset center,
    required double delta,
  }) {
    assert(delta.isFinite, 'GroupEngine.rotate: delta must be finite');
    if (initials.isEmpty || delta == 0) {
      return Map<String, LayerTransform>.of(initials);
    }
    final c = math.cos(delta);
    final s = math.sin(delta);
    return <String, LayerTransform>{
      for (final entry in initials.entries)
        entry.key: _rotateOne(
          entry.value,
          center: center,
          c: c,
          s: s,
          delta: delta,
        ),
    };
  }

  LayerTransform _rotateOne(
    LayerTransform t, {
    required Offset center,
    required double c,
    required double s,
    required double delta,
  }) {
    final dx = t.center.dx - center.dx;
    final dy = t.center.dy - center.dy;
    final newCenter = Offset(
      center.dx + dx * c - dy * s,
      center.dy + dx * s + dy * c,
    );
    final newPosition = Offset(
      newCenter.dx - t.size.width / 2,
      newCenter.dy - t.size.height / 2,
    );
    return t.copyWith(position: newPosition, rotation: t.rotation + delta);
  }

  /// Combined pinch transform: scale + rotate around [anchor] then
  /// translate by [translation]. Single pass so floating-point error
  /// from chaining `scale → rotate → translate` independently stays
  /// minimal. This is what a two-finger gesture maps onto.
  ///
  /// Per-layer min/max enforcement matches [scale] — the effective
  /// scale is reduced uniformly so no participant violates
  /// [minLayerSide] / [maxLayerSide] before the rotation + translation
  /// are applied.
  GroupScaleResult pinch(
    Map<String, LayerTransform> initials, {
    required Offset anchor,
    required double scale,
    required double rotation,
    Offset translation = Offset.zero,
    double minScale = 0.05,
    double maxScale = 64.0,
    double minLayerSide = 0,
    double maxLayerSide = double.infinity,
  }) {
    assert(scale.isFinite, 'GroupEngine.pinch: scale must be finite');
    assert(rotation.isFinite, 'GroupEngine.pinch: rotation must be finite');
    // Same single-pass constraint resolution as [scale]; the applied
    // scale is returned so the pinch frame is built from it, not the
    // requested scale, before the rotation + translation are layered on.
    final s = _effectiveScale(
      initials.values,
      scale,
      minScale: minScale,
      maxScale: maxScale,
      minLayerSide: minLayerSide,
      maxLayerSide: maxLayerSide,
    );
    final c = math.cos(rotation);
    final sn = math.sin(rotation);
    return GroupScaleResult(
      transforms: <String, LayerTransform>{
        for (final entry in initials.entries)
          entry.key: _pinchOne(
            entry.value,
            anchor: anchor,
            scale: s,
            c: c,
            sn: sn,
            rotation: rotation,
            translation: translation,
          ),
      },
      appliedScale: s,
    );
  }

  LayerTransform _pinchOne(
    LayerTransform t, {
    required Offset anchor,
    required double scale,
    required double c,
    required double sn,
    required double rotation,
    required Offset translation,
  }) {
    // 1. scale centre around anchor
    final scaled = anchor + (t.center - anchor) * scale;
    // 2. rotate scaled centre around anchor
    final dx = scaled.dx - anchor.dx;
    final dy = scaled.dy - anchor.dy;
    final rotated = Offset(
      anchor.dx + dx * c - dy * sn,
      anchor.dy + dx * sn + dy * c,
    );
    // 3. apply translation
    final newCenter = rotated + translation;
    final newSize = Size(t.size.width * scale, t.size.height * scale);
    return t.copyWith(
      position: Offset(
        newCenter.dx - newSize.width / 2,
        newCenter.dy - newSize.height / 2,
      ),
      size: newSize,
      rotation: t.rotation + rotation,
    );
  }
}

/// Group resize handle. Mirrors [InteractionHandle] corner enum but is
/// scoped to the group bounds — those bounds are always axis-aligned
/// (they are an AABB), so only the four corners are meaningful here.
enum GroupHandle { topLeft, topRight, bottomLeft, bottomRight }

extension GroupHandleAnchor on GroupHandle {
  /// Opposite corner — the fixed anchor when dragging this corner.
  Offset anchorIn(Rect bounds) {
    switch (this) {
      case GroupHandle.topLeft:
        return bounds.bottomRight;
      case GroupHandle.topRight:
        return bounds.bottomLeft;
      case GroupHandle.bottomLeft:
        return bounds.topRight;
      case GroupHandle.bottomRight:
        return bounds.topLeft;
    }
  }

  /// The corner the user is dragging.
  Offset cornerIn(Rect bounds) {
    switch (this) {
      case GroupHandle.topLeft:
        return bounds.topLeft;
      case GroupHandle.topRight:
        return bounds.topRight;
      case GroupHandle.bottomLeft:
        return bounds.bottomLeft;
      case GroupHandle.bottomRight:
        return bounds.bottomRight;
    }
  }
}
