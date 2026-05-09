import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/interaction/snap_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SnapEngine', () {
    const engine = SnapEngine(threshold: 6);
    const canvas = Size(1000, 800);

    test('near canvas horizontal center snaps center-x', () {
      // Layer 100x50, proposed so its center.x is 498 — 2px off the canvas
      // horizontal center at 500. Within threshold → snaps to 500.
      final result = engine.snapPosition(
        proposed: const Offset(448, 200),
        size: const Size(100, 50),
        peerRects: const [],
        canvasSize: canvas,
      );
      expect(result.position.dx, closeTo(450, 0.001));
      expect(result.position.dy, 200);
      expect(result.guides.length, 1);
      expect(result.guides.single.axis, SnapAxis.vertical);
      expect(result.guides.single.coord, closeTo(500, 0.001));
    });

    test('no snap when outside threshold', () {
      final result = engine.snapPosition(
        proposed: const Offset(100, 100),
        size: const Size(50, 50),
        peerRects: const [],
        canvasSize: canvas,
      );
      expect(result.position, const Offset(100, 100));
      expect(result.guides, isEmpty);
    });

    test('snaps to peer left edge', () {
      // Peer spans x=300..400. Moving layer's right edge is at 403, 3px
      // past peer.left → within threshold. Snap adjusts so right == 400
      // (by aligning center/edge/...). The closest candidate is the
      // moving rect's right edge to peer.right=400, Δ=3.
      final result = engine.snapPosition(
        proposed: const Offset(303, 100),
        size: const Size(100, 50),
        peerRects: const [Rect.fromLTWH(300, 200, 100, 50)],
        canvasSize: canvas,
      );
      // Right edge was 403 → should snap by 3 to align to peer.right=400.
      expect(result.position.dx + 100, closeTo(400, 0.001));
      expect(result.guides, isNotEmpty);
    });

    test('horizontal and vertical snap combine independently', () {
      // Near canvas vertical center (400) AND horizontal center (500).
      final result = engine.snapPosition(
        proposed: const Offset(448, 374),
        size: const Size(100, 50),
        peerRects: const [],
        canvasSize: canvas,
      );
      expect(result.position.dx, closeTo(450, 0.001));
      expect(result.position.dy, closeTo(375, 0.001));
      expect(result.guides.length, 2);
      final axes = result.guides.map((g) => g.axis).toSet();
      expect(axes, {SnapAxis.vertical, SnapAxis.horizontal});
    });

    test('empty canvas + no peers yields no snap', () {
      const tiny = SnapEngine(threshold: 6);
      final r = tiny.snapPosition(
        proposed: const Offset(100, 100),
        size: const Size(10, 10),
        peerRects: const [],
        canvasSize: Size.zero,
      );
      // Canvas edges at 0 are far from (100,100) so nothing snaps.
      expect(r.position, const Offset(100, 100));
      expect(r.guides, isEmpty);
    });

    test('closest target wins within a given axis', () {
      // Two peer-right candidates at 302 and 310; proposed left=304.
      // Closer match is 302 (Δ=2) vs 310 (Δ=6 — borderline). 302 wins.
      final r = engine.snapPosition(
        proposed: const Offset(304, 0),
        size: const Size(50, 50),
        peerRects: const [
          Rect.fromLTWH(252, 0, 50, 50), // right=302
          Rect.fromLTWH(260, 0, 50, 50), // right=310
        ],
        canvasSize: canvas,
      );
      expect(r.position.dx, closeTo(302, 0.001));
    });
  });
}
