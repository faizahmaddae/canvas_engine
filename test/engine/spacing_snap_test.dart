import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/interaction/snap_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SnapEngine.findSpacingSnap', () {
    const engine = SnapEngine(threshold: 6);

    test('no spacing snap with fewer than two peers', () {
      final result = engine.findSpacingSnap(
        proposed: const Offset(100, 100),
        size: const Size(50, 50),
        peerRects: const [Rect.fromLTWH(0, 100, 50, 50)],
      );
      expect(result.guides, isEmpty);
      expect(result.position, const Offset(100, 100));
    });

    test('snaps moved rect to equal horizontal gap between two peers', () {
      // Peer A: 0..50 on X. Peer B: 250..300 on X. Both span Y=100..150.
      // Equal-gap slot for a 50w moved rect: gap = (300-150)/2 = 75 →
      // moved.left = 125. Propose moved.left = 127 (2 off).
      final result = engine.findSpacingSnap(
        proposed: const Offset(127, 100),
        size: const Size(50, 50),
        peerRects: const [
          Rect.fromLTWH(0, 100, 50, 50),
          Rect.fromLTWH(250, 100, 50, 50),
        ],
      );
      expect(result.guides.length, 1);
      final g = result.guides.single;
      expect(g.axis, SnapAxis.vertical);
      expect(g.gap, closeTo(75, 0.001));
      expect(result.position.dx, closeTo(125, 0.001));
      expect(result.position.dy, 100);
    });

    test('snaps moved rect to equal vertical gap between two peers', () {
      final result = engine.findSpacingSnap(
        proposed: const Offset(100, 127),
        size: const Size(50, 50),
        peerRects: const [
          Rect.fromLTWH(100, 0, 50, 50),
          Rect.fromLTWH(100, 250, 50, 50),
        ],
      );
      expect(result.guides.length, 1);
      expect(result.guides.single.axis, SnapAxis.horizontal);
      expect(result.position.dy, closeTo(125, 0.001));
    });

    test('no snap when peers do not share row / column', () {
      // Peers are far apart on Y, so they don't form a "row" the moved
      // rect can be placed between for horizontal spacing.
      final result = engine.findSpacingSnap(
        proposed: const Offset(100, 100),
        size: const Size(50, 50),
        peerRects: const [
          Rect.fromLTWH(0, 0, 50, 50),
          Rect.fromLTWH(250, 500, 50, 50),
        ],
      );
      expect(result.guides, isEmpty);
    });

    test('respects threshold — gap diff > 2*threshold is rejected', () {
      // Equal-gap position would shift moved by ~10px; threshold is 6.
      final result = engine.findSpacingSnap(
        proposed: const Offset(140, 100),
        size: const Size(50, 50),
        peerRects: const [
          Rect.fromLTWH(0, 100, 50, 50),
          Rect.fromLTWH(250, 100, 50, 50),
        ],
      );
      expect(result.guides, isEmpty);
      expect(result.position, const Offset(140, 100));
    });

    test('emits guide segments aligned to gap edges', () {
      // Equal slot for size=50 between peers 0..50 and 200..250 is
      // moved.left = 100 (gap=50 each side).
      final result = engine.findSpacingSnap(
        proposed: const Offset(100, 100),
        size: const Size(50, 50),
        peerRects: const [
          Rect.fromLTWH(0, 100, 50, 50),
          Rect.fromLTWH(200, 100, 50, 50),
        ],
      );
      expect(result.guides.length, 1);
      final g = result.guides.single;
      // Left segment runs from peer-A.right(50) to moved.left(100).
      expect(g.fromStart, closeTo(50, 0.001));
      expect(g.fromEnd, closeTo(100, 0.001));
      // Right segment runs from moved.right(150) to peer-B.left(200).
      expect(g.toStart, closeTo(150, 0.001));
      expect(g.toEnd, closeTo(200, 0.001));
      expect(g.gap, closeTo(50, 0.001));
    });
  });
}
