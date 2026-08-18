import 'dart:math' as math;
import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/interaction/layer_space_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('containsCanvasPoint uses oriented canvas-space bounds', () {
    const transform = LayerTransform(
      position: Offset(100, 100),
      size: Size(100, 40),
      rotation: math.pi / 2,
    );

    expect(
      LayerSpaceMapper.containsCanvasPoint(transform, transform.center),
      isTrue,
    );
    expect(
      LayerSpaceMapper.containsCanvasPoint(transform, const Offset(150, 160)),
      isTrue,
    );
    expect(
      LayerSpaceMapper.containsCanvasPoint(transform, const Offset(190, 120)),
      isFalse,
      reason: 'point is in the unrotated rect but outside the rotated layer',
    );
    expect(
      LayerSpaceMapper.containsCanvasPoint(transform, const Offset(150, 50)),
      isFalse,
    );
  });

  test('mirroring does not change the outer hit bounds', () {
    const normal = LayerTransform(
      position: Offset(10, 20),
      size: Size(80, 60),
      rotation: 0.3,
    );
    const mirrored = LayerTransform(
      position: Offset(10, 20),
      size: Size(80, 60),
      rotation: 0.3,
      flipH: true,
      flipV: true,
    );
    const points = [Offset(50, 50), Offset.zero, Offset(85, 75)];

    for (final point in points) {
      expect(
        LayerSpaceMapper.containsCanvasPoint(mirrored, point),
        LayerSpaceMapper.containsCanvasPoint(normal, point),
      );
    }
  });
}
