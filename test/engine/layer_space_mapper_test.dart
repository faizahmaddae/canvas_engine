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

  test('no rotation, identity viewport: layerToCanvas is a translation', () {
    const mapper = LayerSpaceMapper(
      transform: LayerTransform(
        position: Offset(100, 50),
        size: Size(200, 100),
      ),
      viewport: ViewportState(scale: 1, translation: Offset.zero),
    );
    expect(
      mapper.layerToCanvas(Offset.zero),
      closeToOffset(const Offset(100, 50)),
    );
    expect(
      mapper.layerToCanvas(const Offset(200, 100)),
      closeToOffset(const Offset(300, 150)),
    );
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
    expect(
      mapper.layerToCanvas(Offset.zero),
      closeToOffset(const Offset(150, -50)),
    );
  });

  test('screen mapping matches the selection-overlay convention '
      '(p·scale + translation)', () {
    const mapper = LayerSpaceMapper(
      transform: LayerTransform(position: Offset.zero, size: Size(10, 10)),
      viewport: ViewportState(scale: 2.5, translation: Offset(30, -12)),
    );
    expect(
      mapper.canvasToScreen(const Offset(4, 8)),
      closeToOffset(const Offset(40, 8)),
    );
    expect(
      mapper.screenToCanvas(const Offset(40, 8)),
      closeToOffset(const Offset(4, 8)),
    );
  });

  test('full round-trip under rotation + zoom + pan is exact', () {
    final mapper = LayerSpaceMapper(
      transform: LayerTransform(
        position: const Offset(37, 91),
        size: const Size(240, 133),
        rotation: 0.7,
      ),
      viewport: const ViewportState(scale: 1.75, translation: Offset(-58, 23)),
    );
    const points = [
      Offset.zero,
      Offset(240, 133),
      Offset(120, 66.5),
      Offset(13, 121),
    ];
    for (final p in points) {
      expect(
        mapper.screenToLayer(mapper.layerToScreen(p)),
        closeToOffset(p, 1e-8),
      );
      final c = mapper.layerToCanvas(p);
      expect(mapper.canvasToLayer(c), closeToOffset(p, 1e-8));
    }
  });

  group(
    'Phase 4 §4.4: mapper ≡ the three pre-consolidation _rotate copies',
    () {
      // The exact formula every duplicated `_rotate(point, pivot, angle)`
      // helper used (selection_overlay, floating_toolbar_positioner) —
      // kept here as the oracle the consolidation is checked against.
      Offset legacyRotate(Offset point, Offset pivot, double angle) {
        final c = math.cos(angle);
        final s = math.sin(angle);
        final dx = point.dx - pivot.dx;
        final dy = point.dy - pivot.dy;
        return Offset(pivot.dx + dx * c - dy * s, pivot.dy + dx * s + dy * c);
      }

      test('layerToCanvas matches legacyRotate(cornerCanvasPoint, centre, '
          'rotation) — the invariant every call site relied on', () {
        const position = Offset(37, 91);
        const size = Size(240, 133);
        const rotation = 0.7;
        final center = Offset(
          position.dx + size.width / 2,
          position.dy + size.height / 2,
        );
        const mapper = LayerSpaceMapper(
          transform: LayerTransform(
            position: position,
            size: size,
            rotation: rotation,
          ),
          viewport: ViewportState.identity,
        );

        final corners = [
          Offset.zero,
          Offset(size.width, 0),
          Offset(0, size.height),
          Offset(size.width, size.height),
        ];
        for (final local in corners) {
          final viaMapper = mapper.layerToCanvas(local);
          final viaLegacy = legacyRotate(position + local, center, rotation);
          expect(viaMapper, closeToOffset(viaLegacy, 1e-9));
        }
      });

      test('canvasToLayer matches the manual inverse-rotation formula '
          '_pointInLayerBbox used', () {
        const transform = LayerTransform(
          position: Offset(10, 20),
          size: Size(80, 60),
          rotation: -0.4,
        );
        const mapper = LayerSpaceMapper(
          transform: transform,
          viewport: ViewportState.identity,
        );
        const point = Offset(55, 40);

        // Manual formula `_pointInLayerBbox` used before consolidation.
        final c = transform.center;
        final cos = math.cos(-transform.rotation);
        final sin = math.sin(-transform.rotation);
        final dx = point.dx - c.dx;
        final dy = point.dy - c.dy;
        final expected = Offset(
          dx * cos - dy * sin + transform.size.width / 2,
          dx * sin + dy * cos + transform.size.height / 2,
        );

        expect(mapper.canvasToLayer(point), closeToOffset(expected, 1e-9));
      });

      test('the equivalence breaks once centre diverges from '
          'position + size/2 — documents why every call site must derive '
          'centre that way, not pass an independent value', () {
        const position = Offset(0, 0);
        const size = Size(100, 100);
        const rotation = math.pi / 4;
        const mapper = LayerSpaceMapper(
          transform: LayerTransform(
            position: position,
            size: size,
            rotation: rotation,
          ),
          viewport: ViewportState.identity,
        );

        const correctCenter = Offset(50, 50);
        const wrongCenter = Offset(60, 40); // deliberately inconsistent

        final viaMapper = mapper.layerToCanvas(Offset.zero);
        final viaLegacyCorrect = legacyRotate(
          position,
          correctCenter,
          rotation,
        );
        final viaLegacyWrong = legacyRotate(position, wrongCenter, rotation);

        expect(viaMapper, closeToOffset(viaLegacyCorrect, 1e-9));
        expect((viaMapper - viaLegacyWrong).distance, greaterThan(1));
      });
    },
  );
}
