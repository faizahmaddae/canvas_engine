import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/interaction/snap_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hysteresis tests: an engaged guide should *retain* its engagement
/// out to a wider release tolerance than the base engagement
/// threshold — eliminates the on/off flicker that would otherwise
/// appear when the pointer hovers exactly at the threshold boundary.
///
/// All tests use peer at x=0..50, canvas 1000×1000, threshold=6,
/// releaseFactor=1.6 → release tolerance = 9.6.
void main() {
  group('SnapEngine alignment-snap hysteresis', () {
    const engine = SnapEngine(threshold: 6);
    const peers = [Rect.fromLTWH(0, 0, 50, 100)];
    const canvas = Size(1000, 1000);

    test('engages within base threshold (no previous)', () {
      // Moved.left = 4 → distance to peer.left=0 is 4, within 6.
      final r = engine.snapPosition(
        proposed: const Offset(4, 200),
        size: const Size(50, 50),
        peerRects: peers,
        canvasSize: canvas,
      );
      expect(r.position.dx, 0);
      expect(r.guides, isNotEmpty);
    });

    test('does NOT engage beyond base threshold (no previous)', () {
      // Moved.left = 7 → distance 7, outside base 6.
      final r = engine.snapPosition(
        proposed: const Offset(7, 200),
        size: const Size(50, 50),
        peerRects: peers,
        canvasSize: canvas,
      );
      expect(r.position.dx, 7);
      expect(r.guides, isEmpty);
    });

    test(
      'retains engagement out to release tolerance when previous holds it',
      () {
        // Previous frame: engaged on peer.left (coord=0, vertical guide).
        const prev = SnapResult(
          position: Offset.zero,
          guides: [
            SnapGuide(axis: SnapAxis.vertical, coord: 0, start: 0, end: 1000),
          ],
        );
        // Moved.left = 8 → distance 8, OUTSIDE base 6 but INSIDE release 9.6.
        // With hysteresis the engine should still snap.
        final r = engine.snapPosition(
          proposed: const Offset(8, 200),
          size: const Size(50, 50),
          peerRects: peers,
          canvasSize: canvas,
          previous: prev,
        );
        expect(
          r.position.dx,
          0,
          reason: 'sticky guide should retain engagement within 1.6× threshold',
        );
        expect(r.guides, isNotEmpty);
      },
    );

    test('releases beyond release tolerance', () {
      const prev = SnapResult(
        position: Offset.zero,
        guides: [
          SnapGuide(axis: SnapAxis.vertical, coord: 0, start: 0, end: 1000),
        ],
      );
      // Moved.left = 12 → distance 12, beyond release 9.6 → release.
      final r = engine.snapPosition(
        proposed: const Offset(12, 200),
        size: const Size(50, 50),
        peerRects: peers,
        canvasSize: canvas,
        previous: prev,
      );
      expect(r.position.dx, 12);
      expect(r.guides, isEmpty);
    });

    test('closer non-sticky beats farther sticky (no user trap)', () {
      // Sticky at peer.left=0, distance 8 (within release 9.6).
      // New non-sticky candidate at canvas centre x=500, distance from
      // moved.left=508 → 8 from canvas centre? Place precisely:
      // moved size 50 → centre x = moved.left + 25. For centre to land
      // on canvas centre 500, moved.left=475. Try moved.left = 472:
      //   - sticky distance to peer.left=0 → 472 (way beyond release).
      // So instead build a peer-edge target near current sticky:
      // New peer at x=14..64. moved.left=10 → distance to new peer.left=14
      // is 4 (< base 6). Distance to sticky (peer.left=0) is 10 (> release).
      const prev = SnapResult(
        position: Offset.zero,
        guides: [
          SnapGuide(axis: SnapAxis.vertical, coord: 0, start: 0, end: 1000),
        ],
      );
      const peers2 = [
        Rect.fromLTWH(0, 0, 50, 100),
        Rect.fromLTWH(14, 0, 50, 100),
      ];
      final r = engine.snapPosition(
        proposed: const Offset(10, 200),
        size: const Size(50, 50),
        peerRects: peers2,
        canvasSize: canvas,
        previous: prev,
      );
      // Should snap to closer non-sticky target (coord=14), not stay
      // glued to sticky coord=0.
      expect(r.position.dx, 14);
      expect(r.guides.first.coord, 14);
    });
  });

  group('SnapEngine spacing-snap hysteresis', () {
    const engine = SnapEngine(threshold: 6);
    // Peers A (0..50) and B (250..300) on x, both at y=100..150.
    // Equal-gap slot for 50w moved rect: gap=75 → moved.left=125.
    const peers = [
      Rect.fromLTWH(0, 100, 50, 50),
      Rect.fromLTWH(250, 100, 50, 50),
    ];

    test('engages spacing within base threshold', () {
      // moved.left=128 → correction=3, within base 6.
      final r = engine.findSpacingSnap(
        proposed: const Offset(128, 100),
        size: const Size(50, 50),
        peerRects: peers,
      );
      expect(r.position.dx, closeTo(125, 0.01));
      expect(r.guides, isNotEmpty);
    });

    test('does NOT engage spacing beyond base threshold', () {
      // moved.left=133 → correction=8, outside base 6.
      final r = engine.findSpacingSnap(
        proposed: const Offset(133, 100),
        size: const Size(50, 50),
        peerRects: peers,
      );
      expect(r.position.dx, 133);
      expect(r.guides, isEmpty);
    });

    test('retains spacing engagement within release tolerance', () {
      // Previous frame engaged with gap=75.
      const prev = SpacingSnapResult(
        position: Offset.zero,
        guides: [
          SpacingGuide(
            axis: SnapAxis.vertical,
            gap: 75,
            crossCoord: 125,
            fromStart: 50,
            fromEnd: 125,
            toStart: 175,
            toEnd: 250,
          ),
        ],
      );
      // moved.left=133 → correction=8, outside base 6 but inside release 9.6.
      final r = engine.findSpacingSnap(
        proposed: const Offset(133, 100),
        size: const Size(50, 50),
        peerRects: peers,
        previous: prev,
      );
      expect(
        r.position.dx,
        closeTo(125, 0.01),
        reason: 'sticky spacing should retain engagement within 1.6× tol',
      );
      expect(r.guides, isNotEmpty);
    });
  });
}
