import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/interaction/alignment_engine.dart';
import 'package:flutter_test/flutter_test.dart';

LayerTransform t(double x, double y, double w, double h) =>
    LayerTransform(position: Offset(x, y), size: Size(w, h));

Map<String, LayerTransform> mapOf(List<LayerTransform> ts) {
  final out = <String, LayerTransform>{};
  for (var i = 0; i < ts.length; i++) {
    out['L$i'] = ts[i];
  }
  return out;
}

void main() {
  const engine = AlignmentEngine();

  group('AlignmentEngine.align', () {
    test('returns input unchanged when fewer than two layers', () {
      final input = mapOf([t(0, 0, 50, 50)]);
      expect(identical(engine.align(input, AlignAxis.left), input), isTrue);
    });

    test('align left moves all rects to bounds.left', () {
      final out = engine.align(
        mapOf([t(10, 0, 50, 50), t(40, 100, 30, 30), t(80, 200, 20, 20)]),
        AlignAxis.left,
      );
      expect(out['L0']!.position.dx, 10);
      expect(out['L1']!.position.dx, 10);
      expect(out['L2']!.position.dx, 10);
    });

    test('align right snaps trailing edge to bounds.right', () {
      final out = engine.align(
        mapOf([t(10, 0, 50, 50), t(40, 100, 30, 30), t(80, 200, 20, 20)]),
        AlignAxis.right,
      );
      // bounds.right = 100 (80 + 20). Each layer trailing edge → 100.
      expect(out['L0']!.position.dx + 50, closeTo(100, 0.001));
      expect(out['L1']!.position.dx + 30, closeTo(100, 0.001));
      expect(out['L2']!.position.dx + 20, closeTo(100, 0.001));
    });

    test('align centerX centres each rect on bounds centre', () {
      final out = engine.align(
        mapOf([t(0, 0, 50, 50), t(100, 100, 30, 30)]),
        AlignAxis.centerX,
      );
      // bounds: left=0, right=130 → centre.x = 65.
      expect(out['L0']!.position.dx + 25, closeTo(65, 0.001));
      expect(out['L1']!.position.dx + 15, closeTo(65, 0.001));
    });

    test('align top / bottom only touch Y', () {
      final out = engine.align(
        mapOf([t(10, 5, 50, 50), t(40, 100, 30, 30)]),
        AlignAxis.top,
      );
      expect(out['L0']!.position.dy, 5);
      expect(out['L1']!.position.dy, 5);
      expect(out['L0']!.position.dx, 10);
      expect(out['L1']!.position.dx, 40);
    });

    test('preserves size and rotation', () {
      final input = mapOf([
        LayerTransform(
          position: const Offset(0, 0),
          size: const Size(50, 50),
          rotation: 0.7,
        ),
        t(100, 100, 30, 30),
      ]);
      final out = engine.align(input, AlignAxis.left);
      expect(out['L0']!.size, const Size(50, 50));
      expect(out['L0']!.rotation, 0.7);
    });

    test('alignToRect aligns a single transform to a target rect', () {
      final out = engine.alignToRect(
        t(10, 20, 50, 40),
        const Rect.fromLTWH(0, 0, 200, 100),
        AlignAxis.bottom,
      );
      expect(out.position.dx, 10);
      expect(out.position.dy, 60);
      expect(out.size, const Size(50, 40));
    });
  });

  group('AlignmentEngine.distribute', () {
    test('returns input unchanged when fewer than three layers', () {
      final input = mapOf([t(0, 0, 50, 50), t(100, 0, 50, 50)]);
      expect(
        identical(engine.distribute(input, DistributeAxis.horizontal), input),
        isTrue,
      );
    });

    test('horizontal distribute equalises gaps; outer rects fixed', () {
      // Three rects: 0..50, 80..110, 200..250. Outer fixed.
      // Inner rect width=30. Total span = 250. Sum extents = 50+30+50=130.
      // Total gaps = 250-130 = 120; per gap = 60. Inner rect at 50+60=110..140.
      final out = engine.distribute(
        mapOf([t(0, 0, 50, 50), t(80, 0, 30, 30), t(200, 0, 50, 50)]),
        DistributeAxis.horizontal,
      );
      expect(out['L0']!.position.dx, 0);
      expect(out['L2']!.position.dx, 200);
      expect(out['L1']!.position.dx, closeTo(110, 0.001));
    });

    test('vertical distribute touches only Y', () {
      final out = engine.distribute(
        mapOf([t(10, 0, 50, 50), t(20, 80, 50, 30), t(30, 200, 50, 50)]),
        DistributeAxis.vertical,
      );
      expect(out['L1']!.position.dx, 20);
      // Span 0..250, sum 130, per-gap 60; inner Y = 50+60 = 110.
      expect(out['L1']!.position.dy, closeTo(110, 0.001));
    });

    test('refuses to distribute when inner rects overflow available span', () {
      // Outer rects flush against each other with no room for inner.
      final input = mapOf([
        t(0, 0, 50, 50),
        t(40, 0, 50, 50),
        t(60, 0, 50, 50),
      ]);
      final out = engine.distribute(input, DistributeAxis.horizontal);
      expect(identical(out, input), isTrue);
    });

    test('handles unsorted input by re-ordering internally', () {
      final out = engine.distribute(
        mapOf([t(200, 0, 50, 50), t(0, 0, 50, 50), t(80, 0, 30, 30)]),
        DistributeAxis.horizontal,
      );
      // Same outcome as sorted test: leftmost stays at 0, rightmost at 200,
      // middle rect (id=L2 here) lands at 110.
      expect(out['L1']!.position.dx, 0);
      expect(out['L0']!.position.dx, 200);
      expect(out['L2']!.position.dx, closeTo(110, 0.001));
    });
  });
}
