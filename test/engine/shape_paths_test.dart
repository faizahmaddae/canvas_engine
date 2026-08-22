import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_paths.dart';
import 'package:flutter_test/flutter_test.dart';

/// Geometry contracts for the 2026-08 catalogue growth
/// (docs/shape-studio-redesign-2026-08.md §2). Every new kind must
/// produce a real silhouette inside its box, and the two
/// boolean-geometry kinds (ring / crescent) must carry a genuine
/// hole rather than a painted-over disc.
void main() {
  const size = Size(200, 160);
  const newKinds = [
    ShapeKind.pentagon,
    ShapeKind.octagon,
    ShapeKind.semicircle,
    ShapeKind.rightTriangle,
    ShapeKind.parallelogram,
    ShapeKind.trapezoid,
    ShapeKind.ring,
    ShapeKind.sparkle,
    ShapeKind.seal,
    ShapeKind.bolt,
    ShapeKind.shield,
    ShapeKind.crescent,
    ShapeKind.cloud,
    ShapeKind.thoughtBubble,
  ];

  test('every new kind yields a non-empty path inside its box', () {
    for (final k in newKinds) {
      final bounds = shapeOutlinePath(k, size).getBounds();
      expect(bounds.isEmpty, isFalse, reason: '$k produced an empty path');
      // A small epsilon absorbs curve-tessellation overshoot.
      expect(bounds.left, greaterThanOrEqualTo(-0.6), reason: '$k left');
      expect(bounds.top, greaterThanOrEqualTo(-0.6), reason: '$k top');
      expect(
        bounds.right,
        lessThanOrEqualTo(size.width + 0.6),
        reason: '$k right',
      );
      expect(
        bounds.bottom,
        lessThanOrEqualTo(size.height + 0.6),
        reason: '$k bottom',
      );
    }
  });

  test('every new kind is filled, not stroked', () {
    for (final k in newKinds) {
      expect(isStrokedShapeKind(k), isFalse, reason: '$k');
    }
  });

  test('aspect lock classification for the new kinds', () {
    const locked = {
      ShapeKind.pentagon,
      ShapeKind.octagon,
      ShapeKind.ring,
      ShapeKind.sparkle,
      ShapeKind.seal,
      ShapeKind.bolt,
      ShapeKind.shield,
      ShapeKind.crescent,
    };
    for (final k in newKinds) {
      expect(isAspectLockedShapeKind(k), locked.contains(k), reason: '$k');
    }
  });

  test('ring has a real hole', () {
    final ring = ShapePaths.ring(size);
    expect(ring.contains(const Offset(100, 80)), isFalse, reason: 'centre');
    // A point in the band, halfway between the outer and inner edge.
    expect(ring.contains(const Offset(9, 80)), isTrue, reason: 'band');
  });

  test('crescent is a moon, not a disc', () {
    final moon = ShapePaths.crescent(size);
    // The cutter removed the centre-right; the left limb remains.
    expect(moon.contains(const Offset(120, 80)), isFalse, reason: 'cut side');
    expect(moon.contains(const Offset(20, 80)), isTrue, reason: 'limb');
  });

  test('cloud union is one solid silhouette', () {
    final cloud = ShapePaths.cloud(size);
    expect(cloud.contains(const Offset(100, 80)), isTrue, reason: 'body');
    expect(cloud.contains(const Offset(100, 5)), isFalse, reason: 'sky');
  });

  test('semicircle dome sits on its flat bottom edge', () {
    final dome = ShapePaths.semicircle(size);
    expect(dome.contains(const Offset(100, 10)), isTrue, reason: 'apex');
    expect(dome.contains(const Offset(4, 20)), isFalse, reason: 'shoulder');
    final bounds = dome.getBounds();
    expect(bounds.bottom, closeTo(size.height, 0.6));
  });
}
