import 'dart:math' as math;
import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/core/viewport_state.dart';
import 'package:canvas_engine/features/editor/engine/interaction/layer_space_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 3.2 geometry: layer-local ↔ canvas ↔ screen round-trips
/// under rotation + zoom (design §5).
void main() {
  Matcher closeToOffset(Offset e, [double tol = 1e-9]) => predicate<Offset>(
        (o) => (o.dx - e.dx).abs() < tol && (o.dy - e.dy).abs() < tol,
        'close to $e',
      );

  test('no rotation, identity viewport: layerToCanvas is a translation',
      () {
    const mapper = LayerSpaceMapper(
      transform: LayerTransform(
        position: Offset(100, 50),
        size: Size(200, 100),
      ),
      viewport: ViewportState(scale: 1, translation: Offset.zero),
    );
    expect(mapper.layerToCanvas(Offset.zero),
        closeToOffset(const Offset(100, 50)));
    expect(mapper.layerToCanvas(const Offset(200, 100)),
        closeToOffset(const Offset(300, 150)));
  });

  test('90° rotation maps corners around the layer centre', () {
    final mapper = LayerSpaceMapper(
      transform: LayerTransform(
        position: const Offset(0, 0),
        size: const Size(200, 100),
        rotation: math.pi / 2,
      ),
      viewport: const ViewportState(scale: 1, translation: Offset.zero),
    );
    // Centre is (100,50). Local top-left (0,0) → v=(-100,-50) →
    // rotated 90° → (50,-100) → canvas (150,-50).
    expect(mapper.layerToCanvas(Offset.zero),
        closeToOffset(const Offset(150, -50)));
  });

  test('screen mapping matches the selection-overlay convention '
      '(p·scale + translation)', () {
    const mapper = LayerSpaceMapper(
      transform: LayerTransform(position: Offset.zero, size: Size(10, 10)),
      viewport: ViewportState(scale: 2.5, translation: Offset(30, -12)),
    );
    expect(mapper.canvasToScreen(const Offset(4, 8)),
        closeToOffset(const Offset(40, 8)));
    expect(mapper.screenToCanvas(const Offset(40, 8)),
        closeToOffset(const Offset(4, 8)));
  });

  test('full round-trip under rotation + zoom + pan is exact', () {
    final mapper = LayerSpaceMapper(
      transform: LayerTransform(
        position: const Offset(37, 91),
        size: const Size(240, 133),
        rotation: 0.7,
      ),
      viewport: const ViewportState(
        scale: 1.75,
        translation: Offset(-58, 23),
      ),
    );
    const points = [
      Offset.zero,
      Offset(240, 133),
      Offset(120, 66.5),
      Offset(13, 121),
    ];
    for (final p in points) {
      expect(mapper.screenToLayer(mapper.layerToScreen(p)),
          closeToOffset(p, 1e-8));
      final c = mapper.layerToCanvas(p);
      expect(mapper.canvasToLayer(c), closeToOffset(p, 1e-8));
    }
  });
}
