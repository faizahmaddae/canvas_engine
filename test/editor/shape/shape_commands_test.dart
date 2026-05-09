import 'dart:ui';

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/shape_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    c
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    addTearDown(c.dispose);
    return c;
  }

  ShapeLayer addShape(
    ProviderContainer c, {
    String id = 'shape1',
    ShapeKind kind = ShapeKind.rectangle,
  }) {
    final layer = ShapeLayer(
      id: id,
      transform: const LayerTransform(
        position: Offset(100, 100),
        size: Size(300, 200),
      ),
      kind: kind,
    );
    c
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(layer));
    return layer;
  }

  ShapeLayer? readShape(ProviderContainer c, String id) {
    final list = c
        .read(documentControllerProvider)
        .layers
        .where((l) => l.id == id)
        .toList();
    return list.isEmpty ? null : list.first as ShapeLayer;
  }

  group('ShapeLayer model', () {
    test('default fill is white, opacity is 1, no stroke, radius 0', () {
      final c = makeContainer();
      addShape(c);
      final s = readShape(c, 'shape1')!;
      expect(s.fillColor, const Color(0xFFFFFFFF));
      expect(s.fillOpacity, 1);
      expect(s.strokeColor, isNull);
      expect(s.strokeWidth, 0);
      expect(s.cornerRadius, 0);
    });

    test('copyWith preserves unspecified fields', () {
      const a = ShapeLayer(
        id: 's',
        transform: LayerTransform(
          position: Offset.zero,
          size: Size(100, 100),
        ),
        kind: ShapeKind.rectangle,
        fillColor: Color(0xFFFF0000),
        fillOpacity: 0.5,
        strokeColor: Color(0xFF00FF00),
        strokeWidth: 4,
        cornerRadius: 12,
      );
      final b = a.copyWith(fillColor: const Color(0xFF0000FF));
      expect(b.fillColor, const Color(0xFF0000FF));
      expect(b.fillOpacity, 0.5);
      expect(b.strokeColor, const Color(0xFF00FF00));
      expect(b.strokeWidth, 4);
      expect(b.cornerRadius, 12);
      expect(b.kind, ShapeKind.rectangle);
    });

    test('copyWith(clearStroke: true) drops the stroke colour', () {
      const a = ShapeLayer(
        id: 's',
        transform: LayerTransform(
          position: Offset.zero,
          size: Size(100, 100),
        ),
        kind: ShapeKind.rectangle,
        strokeColor: Color(0xFF00FF00),
        strokeWidth: 4,
      );
      final b = a.copyWith(clearStroke: true);
      expect(b.strokeColor, isNull);
      expect(b.strokeWidth, 4);
    });

    test('toJson / fromJson round-trips all style fields', () {
      const original = ShapeLayer(
        id: 'rt',
        transform: LayerTransform(
          position: Offset(10, 20),
          size: Size(300, 200),
          rotation: 0.5,
        ),
        kind: ShapeKind.circle,
        fillColor: Color(0xFFAABBCC),
        fillOpacity: 0.4,
        strokeColor: Color(0xFF112233),
        strokeWidth: 6.5,
        cornerRadius: 8,
      );
      final json = original.toJson();
      final decoded = ShapeLayer.fromJson(Map<String, dynamic>.from(json));
      expect(decoded.kind, ShapeKind.circle);
      expect(decoded.fillColor, const Color(0xFFAABBCC));
      expect(decoded.fillOpacity, closeTo(0.4, 1e-6));
      expect(decoded.strokeColor, const Color(0xFF112233));
      expect(decoded.strokeWidth, 6.5);
      expect(decoded.cornerRadius, 8);
    });

    test('== includes opacity + cornerRadius', () {
      const a = ShapeLayer(
        id: 'x',
        transform: LayerTransform(
          position: Offset.zero,
          size: Size(10, 10),
        ),
        kind: ShapeKind.rectangle,
      );
      final b = a.copyWith(fillOpacity: 0.5);
      final c = a.copyWith(cornerRadius: 4);
      expect(a == b, isFalse);
      expect(a == c, isFalse);
      expect(b == a.copyWith(fillOpacity: 0.5), isTrue);
    });
  });

  group('SetShapeFillCommand', () {
    test('changes fill color, preserves stroke and radius', () {
      final c = makeContainer();
      final s0 = ShapeLayer(
        id: 'shape1',
        transform: const LayerTransform(
          position: Offset.zero,
          size: Size(100, 100),
        ),
        kind: ShapeKind.rectangle,
        strokeColor: const Color(0xFF112233),
        strokeWidth: 3,
        cornerRadius: 16,
      );
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(s0));
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeFillCommand(
              layerId: 'shape1',
              color: Color(0xFFEE0011),
            ),
          );
      final s1 = readShape(c, 'shape1')!;
      expect(s1.fillColor, const Color(0xFFEE0011));
      expect(s1.strokeColor, const Color(0xFF112233));
      expect(s1.strokeWidth, 3);
      expect(s1.cornerRadius, 16);
    });

    test('opacity-only change leaves color untouched', () {
      final c = makeContainer();
      addShape(c);
      c
          .read(documentControllerProvider.notifier)
          .execute(const SetShapeFillCommand(
            layerId: 'shape1',
            color: Color(0xFFFF00FF),
          ));
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeFillCommand(layerId: 'shape1', opacity: 0.3),
          );
      final s = readShape(c, 'shape1')!;
      expect(s.fillColor, const Color(0xFFFF00FF));
      expect(s.fillOpacity, closeTo(0.3, 1e-6));
    });

    test('undo restores previous fill color and opacity', () {
      final c = makeContainer();
      addShape(c);
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeFillCommand(
              layerId: 'shape1',
              color: Color(0xFFAABBCC),
              opacity: 0.5,
            ),
          );
      expect(readShape(c, 'shape1')!.fillColor, const Color(0xFFAABBCC));
      c.read(documentControllerProvider.notifier).undo();
      expect(readShape(c, 'shape1')!.fillColor, const Color(0xFFFFFFFF));
      expect(readShape(c, 'shape1')!.fillOpacity, 1);
    });
  });

  group('SetShapeStrokeCommand', () {
    test('changes stroke color+width, preserves fill', () {
      final c = makeContainer();
      addShape(c);
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeFillCommand(
              layerId: 'shape1',
              color: Color(0xFFFF0000),
            ),
          );
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeStrokeCommand(
              layerId: 'shape1',
              color: Color(0xFF000000),
              width: 4,
            ),
          );
      final s = readShape(c, 'shape1')!;
      expect(s.fillColor, const Color(0xFFFF0000));
      expect(s.strokeColor, const Color(0xFF000000));
      expect(s.strokeWidth, 4);
    });

    test('clearColor: true drops the stroke', () {
      final c = makeContainer();
      addShape(c);
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeStrokeCommand(
              layerId: 'shape1',
              color: Color(0xFF111111),
              width: 2,
            ),
          );
      expect(readShape(c, 'shape1')!.strokeColor, isNotNull);
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeStrokeCommand(
              layerId: 'shape1',
              clearColor: true,
              width: 0,
            ),
          );
      expect(readShape(c, 'shape1')!.strokeColor, isNull);
      expect(readShape(c, 'shape1')!.strokeWidth, 0);
    });

    test('undo restores prior stroke', () {
      final c = makeContainer();
      addShape(c);
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeStrokeCommand(
              layerId: 'shape1',
              color: Color(0xFF333333),
              width: 6,
            ),
          );
      c.read(documentControllerProvider.notifier).undo();
      expect(readShape(c, 'shape1')!.strokeColor, isNull);
      expect(readShape(c, 'shape1')!.strokeWidth, 0);
    });
  });

  group('SetShapeRadiusCommand', () {
    test('sets corner radius on rectangle', () {
      final c = makeContainer();
      addShape(c);
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeRadiusCommand(layerId: 'shape1', radius: 24),
          );
      expect(readShape(c, 'shape1')!.cornerRadius, 24);
    });

    test('no-op for circle', () {
      final c = makeContainer();
      addShape(c, id: 'circle1', kind: ShapeKind.circle);
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeRadiusCommand(layerId: 'circle1', radius: 24),
          );
      expect(readShape(c, 'circle1')!.cornerRadius, 0);
    });

    test('clamps negative input to zero', () {
      final c = makeContainer();
      addShape(c);
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeRadiusCommand(layerId: 'shape1', radius: -5),
          );
      expect(readShape(c, 'shape1')!.cornerRadius, 0);
    });

    test('undo restores prior radius', () {
      final c = makeContainer();
      addShape(c);
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeRadiusCommand(layerId: 'shape1', radius: 16),
          );
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeRadiusCommand(layerId: 'shape1', radius: 32),
          );
      expect(readShape(c, 'shape1')!.cornerRadius, 32);
      c.read(documentControllerProvider.notifier).undo();
      expect(readShape(c, 'shape1')!.cornerRadius, 16);
      c.read(documentControllerProvider.notifier).undo();
      expect(readShape(c, 'shape1')!.cornerRadius, 0);
    });

    test('preserves fill and stroke', () {
      final c = makeContainer();
      addShape(c);
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeFillCommand(
              layerId: 'shape1',
              color: Color(0xFF00FF00),
              opacity: 0.7,
            ),
          );
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeStrokeCommand(
              layerId: 'shape1',
              color: Color(0xFF000000),
              width: 2,
            ),
          );
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeRadiusCommand(layerId: 'shape1', radius: 18),
          );
      final s = readShape(c, 'shape1')!;
      expect(s.fillColor, const Color(0xFF00FF00));
      expect(s.fillOpacity, closeTo(0.7, 1e-6));
      expect(s.strokeColor, const Color(0xFF000000));
      expect(s.strokeWidth, 2);
      expect(s.cornerRadius, 18);
    });
  });

  group('Integration: add → edit → undo', () {
    test('full edit chain restores original after undos', () {
      final c = makeContainer();
      addShape(c);
      final original = readShape(c, 'shape1')!;
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeFillCommand(
              layerId: 'shape1',
              color: Color(0xFF123456),
            ),
          );
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeStrokeCommand(
              layerId: 'shape1',
              color: Color(0xFFABCDEF),
              width: 3,
            ),
          );
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeRadiusCommand(layerId: 'shape1', radius: 12),
          );
      final edited = readShape(c, 'shape1')!;
      expect(edited.fillColor, const Color(0xFF123456));
      expect(edited.strokeColor, const Color(0xFFABCDEF));
      expect(edited.cornerRadius, 12);
      // Undo each edit.
      c.read(documentControllerProvider.notifier).undo();
      c.read(documentControllerProvider.notifier).undo();
      c.read(documentControllerProvider.notifier).undo();
      final restored = readShape(c, 'shape1')!;
      expect(restored.fillColor, original.fillColor);
      expect(restored.strokeColor, original.strokeColor);
      expect(restored.strokeWidth, original.strokeWidth);
      expect(restored.cornerRadius, original.cornerRadius);
    });
  });
}
