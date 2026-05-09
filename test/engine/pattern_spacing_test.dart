import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/interaction/snap_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pattern spacing tests: when two row-mate peers already share a gap
/// G, dragging a moved rect *outside* the row should snap it to
/// extend that rhythm (positioned at G distance from the nearest
/// row peer). This is the Figma "smart guides" rhythm extension.
void main() {
  group('SnapEngine pattern spacing', () {
    const engine = SnapEngine(threshold: 6);

    test('extends rhythm to the right of two equally-gapped peers', () {
      // Row: A(0..50), B(100..150). Adjacent gap = 50.
      // Moved 50w rect placed near x=200 — to extend rhythm,
      // moved.left should snap to 200 (=B.right + 50).
      // Propose moved.left = 203 (3 off, within base 6).
      final r = engine.findSpacingSnap(
        proposed: const Offset(203, 0),
        size: const Size(50, 50),
        peerRects: const [
          Rect.fromLTWH(0, 0, 50, 50),
          Rect.fromLTWH(100, 0, 50, 50),
        ],
      );
      expect(r.position.dx, closeTo(200, 0.01));
      expect(r.guides, isNotEmpty);
      expect(r.guides.first.gap, closeTo(50, 0.01));
    });

    test('extends rhythm to the left of two equally-gapped peers', () {
      // Row: A(100..150), B(200..250). gap = 50.
      // Moved 50w rect placed left of row — moved.right should snap
      // to 100 - 50 = 50 → moved.left = 0. Propose left=3.
      final r = engine.findSpacingSnap(
        proposed: const Offset(3, 0),
        size: const Size(50, 50),
        peerRects: const [
          Rect.fromLTWH(100, 0, 50, 50),
          Rect.fromLTWH(200, 0, 50, 50),
        ],
      );
      // moved.right = 50, gap = 100-50 = 50 ✓
      expect(r.position.dx, closeTo(0, 0.01));
      expect(r.guides, isNotEmpty);
    });

    test('does not engage when proposed sits inside the row span', () {
      // Moved between A and B → between-peers logic is the right tool;
      // pattern logic should bow out.
      final r = engine.findSpacingSnap(
        proposed: const Offset(60, 0),
        size: const Size(20, 50),
        peerRects: const [
          Rect.fromLTWH(0, 0, 50, 50),
          Rect.fromLTWH(100, 0, 50, 50),
        ],
      );
      // Between-peers result: gap=15 each side → moved.left=65.
      expect(r.position.dx, closeTo(65, 0.01));
    });

    test('does not engage when no row peer pair has a clean gap', () {
      // Single peer → no inter-peer gap to match.
      final r = engine.findSpacingSnap(
        proposed: const Offset(203, 0),
        size: const Size(50, 50),
        peerRects: const [Rect.fromLTWH(100, 0, 50, 50)],
      );
      expect(r.position.dx, 203);
      expect(r.guides, isEmpty);
    });

    test('respects perpendicular-overlap row filter', () {
      // Two peers but at different y (no perp overlap with moved at
      // y=0..50). Pattern should NOT fire.
      final r = engine.findSpacingSnap(
        proposed: const Offset(203, 0),
        size: const Size(50, 50),
        peerRects: const [
          Rect.fromLTWH(0, 200, 50, 50),
          Rect.fromLTWH(100, 200, 50, 50),
        ],
      );
      expect(r.position.dx, 203);
      expect(r.guides, isEmpty);
    });
  });
}
