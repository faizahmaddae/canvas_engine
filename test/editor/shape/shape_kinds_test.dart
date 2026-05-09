import 'dart:ui';

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/shape_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_catalogue.dart';
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
    double cornerRadius = 0,
    double strokeWidth = 0,
  }) {
    final layer = ShapeLayer(
      id: id,
      transform: const LayerTransform(
        position: Offset(40, 40),
        size: Size(220, 220),
      ),
      kind: kind,
      cornerRadius: cornerRadius,
      strokeWidth: strokeWidth,
    );
    c
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(layer));
    return layer;
  }

  ShapeLayer readShape(ProviderContainer c, String id) =>
      c.read(documentControllerProvider).layerById(id)! as ShapeLayer;

  group('ShapeKind catalogue', () {
    test('exposes the full Phase 2 set in display order', () {
      // Order is part of the picker contract — adjust deliberately.
      expect(ShapeKind.values, [
        ShapeKind.rectangle,
        ShapeKind.roundedRectangle,
        ShapeKind.circle,
        ShapeKind.oval,
        ShapeKind.triangle,
        ShapeKind.diamond,
        ShapeKind.hexagon,
        ShapeKind.star,
        ShapeKind.heart,
        ShapeKind.speechBubble,
        ShapeKind.quoteBubble,
        ShapeKind.plus,
        ShapeKind.check,
        ShapeKind.cross,
        ShapeKind.line,
        ShapeKind.arrow,
        ShapeKind.arrowLeft,
        ShapeKind.arrowUp,
        ShapeKind.arrowDown,
      ]);
    });

    test('picker catalogue contains every ShapeKind with a label', () {
      final kindsInCatalogue =
          kShapeCatalogue.map((e) => e.kind).toSet();
      expect(kindsInCatalogue, ShapeKind.values.toSet());
      // Labels are non-empty and unique so the picker reads cleanly.
      final labels = kShapeCatalogue.map((e) => e.label).toList();
      expect(labels.toSet().length, labels.length);
      for (final l in labels) {
        expect(l.trim(), isNotEmpty);
      }
    });

    test('picker catalogue order matches the spec', () {
      expect(
        kShapeCatalogue.map((e) => e.label).toList(),
        const [
          'Rectangle',
          'Rounded',
          'Circle',
          'Oval',
          'Triangle',
          'Diamond',
          'Hexagon',
          'Star',
          'Heart',
          'Speech',
          'Quote',
          'Plus',
          'Check',
          'Cross',
          'Line',
          'Arrow right',
          'Arrow left',
          'Arrow up',
          'Arrow down',
        ],
      );
    });

    test('catalogue sections cover every ShapeKind exactly once', () {
      final flat = [
        for (final s in kShapeCatalogueSections) ...s.entries.map((e) => e.kind),
      ];
      expect(flat.toSet(), ShapeKind.values.toSet());
      expect(flat.length, ShapeKind.values.length);
      // Section titles are non-empty and unique.
      final titles =
          kShapeCatalogueSections.map((s) => s.title).toList();
      expect(titles.toSet().length, titles.length);
      for (final t in titles) {
        expect(t.trim(), isNotEmpty);
      }
    });

    test('isStrokedShapeKind flags only line and arrow variants + check/cross',
        () {
      const stroked = {
        ShapeKind.line,
        ShapeKind.arrow,
        ShapeKind.arrowLeft,
        ShapeKind.arrowUp,
        ShapeKind.arrowDown,
        ShapeKind.check,
        ShapeKind.cross,
      };
      for (final k in ShapeKind.values) {
        expect(
          isStrokedShapeKind(k),
          stroked.contains(k),
          reason: '$k stroked classification',
        );
      }
    });
  });

  group('JSON round-trip', () {
    test('every ShapeKind survives a JSON round-trip', () {
      for (final k in ShapeKind.values) {
        final original = ShapeLayer(
          id: 'rt-${k.name}',
          transform: const LayerTransform(
            position: Offset(10, 20),
            size: Size(120, 80),
            rotation: 0.25,
          ),
          kind: k,
          fillColor: const Color(0xFFAABBCC),
          fillOpacity: 0.7,
          strokeColor: const Color(0xFF112233),
          strokeWidth: 3,
          cornerRadius: k == ShapeKind.rectangle ||
                  k == ShapeKind.roundedRectangle
              ? 14
              : 0,
        );
        final decoded = ShapeLayer.fromJson(
          Map<String, dynamic>.from(original.toJson()),
        );
        expect(decoded.kind, k, reason: 'kind for $k');
        expect(decoded, original, reason: '== for $k');
      }
    });

    test('unknown kind string falls back to rectangle', () {
      final original = ShapeLayer(
        id: 'fb',
        transform: const LayerTransform(
          position: Offset.zero,
          size: Size(100, 100),
        ),
        kind: ShapeKind.rectangle,
      );
      final json = Map<String, dynamic>.from(original.toJson());
      json['kind'] = 'spaceship'; // not a real kind
      final decoded = ShapeLayer.fromJson(json);
      expect(decoded.kind, ShapeKind.rectangle);
    });
  });

  group('Insert / addLayer for every kind', () {
    test('AddLayerCommand accepts every ShapeKind', () {
      for (final k in ShapeKind.values) {
        final c = makeContainer();
        addShape(c, id: 'k-${k.name}', kind: k);
        final s = readShape(c, 'k-${k.name}');
        expect(s.kind, k);
      }
    });
  });

  group('ReplaceShapeKindCommand', () {
    test('rectangle → star preserves id, transform, fill, stroke, radius', () {
      final c = makeContainer();
      const id = 'morph';
      final original = ShapeLayer(
        id: id,
        transform: const LayerTransform(
          position: Offset(80, 90),
          size: Size(180, 140),
          rotation: 0.4,
        ),
        kind: ShapeKind.rectangle,
        fillColor: const Color(0xFFFF8800),
        fillOpacity: 0.6,
        strokeColor: const Color(0xFF003366),
        strokeWidth: 5,
        cornerRadius: 18,
      );
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(original));
      c.read(documentControllerProvider.notifier).execute(
            const ReplaceShapeKindCommand(layerId: id, kind: ShapeKind.star),
          );
      final s = readShape(c, id);
      expect(s.id, id);
      expect(s.kind, ShapeKind.star);
      expect(s.transform, original.transform);
      expect(s.fillColor, original.fillColor);
      expect(s.fillOpacity, original.fillOpacity);
      expect(s.strokeColor, original.strokeColor);
      expect(s.strokeWidth, original.strokeWidth);
      expect(s.cornerRadius, original.cornerRadius);
    });

    test('undo restores the previous kind', () {
      final c = makeContainer();
      addShape(c, kind: ShapeKind.circle);
      c.read(documentControllerProvider.notifier).execute(
            const ReplaceShapeKindCommand(
              layerId: 'shape1',
              kind: ShapeKind.heart,
            ),
          );
      expect(readShape(c, 'shape1').kind, ShapeKind.heart);
      c.read(documentControllerProvider.notifier).undo();
      expect(readShape(c, 'shape1').kind, ShapeKind.circle);
    });

    test('no-op when target kind matches current', () {
      final c = makeContainer();
      addShape(c, kind: ShapeKind.diamond);
      final ctrl = c.read(documentControllerProvider.notifier);
      ctrl.execute(
        const ReplaceShapeKindCommand(
          layerId: 'shape1',
          kind: ShapeKind.diamond,
        ),
      );
      // No history pushed — undo should be a no-op.
      expect(ctrl.canUndo, isTrue); // AddLayer is still on the stack
      ctrl.undo();
      expect(c.read(documentControllerProvider).layerById('shape1'), isNull);
    });

    test('no-op when layer is missing', () {
      final c = makeContainer();
      final ctrl = c.read(documentControllerProvider.notifier);
      ctrl.execute(
        const ReplaceShapeKindCommand(
          layerId: 'ghost',
          kind: ShapeKind.star,
        ),
      );
      expect(ctrl.canUndo, isFalse);
    });
  });

  group('Slider merge (live: true) collapses undo entries', () {
    test('opacity drag stream becomes one undo step', () {
      final c = makeContainer();
      addShape(c);
      final ctrl = c.read(documentControllerProvider.notifier);
      // Simulate a drag stream of 5 ticks.
      for (final v in [0.9, 0.8, 0.6, 0.4, 0.25]) {
        ctrl.execute(
          SetShapeFillCommand(
            layerId: 'shape1',
            opacity: v,
            live: true,
          ),
        );
      }
      expect(readShape(c, 'shape1').fillOpacity, closeTo(0.25, 1e-6));
      // One undo step should jump back to the pre-stream value (1.0)
      // even though five live commands were dispatched.
      ctrl.undo();
      expect(readShape(c, 'shape1').fillOpacity, 1);
    });

    test('radius drag stream becomes one undo step', () {
      final c = makeContainer();
      addShape(c);
      final ctrl = c.read(documentControllerProvider.notifier);
      for (final r in [4.0, 8.0, 12.0, 18.0, 24.0]) {
        ctrl.execute(
          SetShapeRadiusCommand(layerId: 'shape1', radius: r, live: true),
        );
      }
      expect(readShape(c, 'shape1').cornerRadius, 24);
      ctrl.undo();
      expect(readShape(c, 'shape1').cornerRadius, 0);
    });

    test('stroke width drag stream becomes one undo step', () {
      final c = makeContainer();
      addShape(c);
      final ctrl = c.read(documentControllerProvider.notifier);
      // Seed a colour so the live width edits actually mutate state.
      ctrl.execute(
        const SetShapeStrokeCommand(
          layerId: 'shape1',
          color: Color(0xFF000000),
          width: 1,
        ),
      );
      for (final w in [2.0, 4.0, 6.0, 8.0]) {
        ctrl.execute(
          SetShapeStrokeCommand(
            layerId: 'shape1',
            color: const Color(0xFF000000),
            width: w,
            live: true,
          ),
        );
      }
      expect(readShape(c, 'shape1').strokeWidth, 8);
      // Undoing the live stream restores the seeded width=1 — one
      // undo entry consumed.
      ctrl.undo();
      expect(readShape(c, 'shape1').strokeWidth, 1);
    });

    test('live commands do NOT merge with non-live (mode mismatch)', () {
      final c = makeContainer();
      addShape(c);
      final ctrl = c.read(documentControllerProvider.notifier);
      ctrl.execute(
        const SetShapeFillCommand(
          layerId: 'shape1',
          opacity: 0.5,
        ),
      );
      ctrl.execute(
        const SetShapeFillCommand(
          layerId: 'shape1',
          opacity: 0.2,
          live: true,
        ),
      );
      // Two history entries — undo once, opacity = 0.5; undo again,
      // opacity = 1.
      ctrl.undo();
      expect(readShape(c, 'shape1').fillOpacity, closeTo(0.5, 1e-6));
      ctrl.undo();
      expect(readShape(c, 'shape1').fillOpacity, 1);
    });

    test('live opacity stream does not swallow a live colour stream', () {
      final c = makeContainer();
      addShape(c);
      final ctrl = c.read(documentControllerProvider.notifier);
      ctrl.execute(
        const SetShapeFillCommand(
          layerId: 'shape1',
          color: Color(0xFFFF0000),
          live: true,
        ),
      );
      ctrl.execute(
        const SetShapeFillCommand(
          layerId: 'shape1',
          opacity: 0.4,
          live: true,
        ),
      );
      // Different field-sets must not merge.
      ctrl.undo();
      expect(readShape(c, 'shape1').fillOpacity, 1);
      expect(readShape(c, 'shape1').fillColor, const Color(0xFFFF0000));
    });
  });
}
