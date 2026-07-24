import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/paint/application/paint_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaintDraft', () {
    test('toLayer returns null for empty points', () {
      final draft = PaintDraft(
        kind: PaintKind.line,
        strokeColor: const Color(0xFF000000),
        strokeWidth: 4,
        points: [],
      );
      expect(draft.toLayer(id: 'x', docSize: const Size(100, 100)), isNull);
    });

    test('toLayer returns null for line with single point (degenerate)', () {
      final draft = PaintDraft(
        kind: PaintKind.line,
        strokeColor: const Color(0xFF000000),
        strokeWidth: 4,
        points: [const Offset(10, 10)],
      );
      expect(draft.toLayer(id: 'x', docSize: const Size(100, 100)), isNull);
    });

    test('freestyle single tap commits a one-point layer', () {
      final draft = PaintDraft(
        kind: PaintKind.freestyle,
        strokeColor: const Color(0xFF000000),
        strokeWidth: 4,
        points: [const Offset(50, 60)],
      );
      final layer = draft.toLayer(id: 'a', docSize: const Size(200, 200));
      expect(layer, isNotNull);
      expect(layer!.kind, PaintKind.freestyle);
      expect(layer.normalizedPoints, hasLength(1));
    });

    test('rectangle drag normalizes endpoints to bounding box corners', () {
      final draft = PaintDraft(
        kind: PaintKind.rectangle,
        strokeColor: const Color(0xFFFF0000),
        strokeWidth: 6,
        points: [const Offset(20, 30), const Offset(120, 80)],
      );
      final layer = draft.toLayer(id: 'r', docSize: const Size(500, 500));
      expect(layer, isNotNull);
      // Bounding box is padded by max(strokeWidth, 2) = 6 around the
      // raw extents, so the start point lands at (pad, pad) of the
      // local 0..1 space.
      final n = layer!.normalizedPoints;
      expect(n.first.dx, closeTo(6 / layer.transform.size.width, 1e-6));
      expect(n.first.dy, closeTo(6 / layer.transform.size.height, 1e-6));
      expect(
        n.last.dx,
        closeTo((120 - 20 + 6) / layer.transform.size.width, 1e-6),
      );
    });

    test('toLayer round-trips through JSON', () {
      final draft = PaintDraft(
        kind: PaintKind.arrow,
        strokeColor: const Color(0xFF112233),
        strokeWidth: 8,
        points: [const Offset(0, 0), const Offset(40, 60)],
      );
      final layer = draft.toLayer(id: 'arrow-1', docSize: const Size(800, 600));
      final json = layer!.toJson();
      final restored = PaintLayer.fromJson(json);
      expect(restored.kind, PaintKind.arrow);
      expect(restored.id, 'arrow-1');
      expect(restored.strokeColor, const Color(0xFF112233));
      expect(restored.strokeWidth, 8);
      expect(restored.normalizedPoints, hasLength(2));
      expect(
        restored.normalizedPoints.first.dx,
        closeTo(layer.normalizedPoints.first.dx, 1e-6),
      );
      expect(
        restored.transform.position.dx,
        closeTo(layer.transform.position.dx, 1e-6),
      );
    });

    test('rectangle keeps fill colour at commit', () {
      final draft = PaintDraft(
        kind: PaintKind.rectangle,
        strokeColor: const Color(0xFF000000),
        strokeWidth: 4,
        fillColor: const Color(0xFFAABBCC),
        points: [const Offset(0, 0), const Offset(40, 40)],
      );
      final layer = draft.toLayer(id: 'r', docSize: const Size(200, 200));
      expect(layer!.fillColor, const Color(0xFFAABBCC));
    });

    test('line discards fill colour at commit (shape-only field)', () {
      final draft = PaintDraft(
        kind: PaintKind.line,
        strokeColor: const Color(0xFF000000),
        strokeWidth: 4,
        fillColor: const Color(0xFFAABBCC),
        points: [const Offset(0, 0), const Offset(40, 40)],
      );
      final layer = draft.toLayer(id: 'l', docSize: const Size(200, 200));
      expect(layer!.fillColor, isNull);
    });
  });
}
