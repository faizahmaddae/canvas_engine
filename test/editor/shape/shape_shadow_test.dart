import 'dart:ui';

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/shape_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shadow-specific coverage for the Shape Tool. Companion to
/// shape_commands_test.dart and shape_kinds_test.dart — focuses on
/// the Phase 3 shadow surface.
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
        position: Offset(40, 40),
        size: Size(220, 220),
      ),
      kind: kind,
    );
    c
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(layer));
    return layer;
  }

  ShapeLayer read(ProviderContainer c, String id) =>
      c.read(documentControllerProvider).layerById(id)! as ShapeLayer;

  group('ShapeLayer shadow defaults', () {
    test('default shadow is invisible (opacity 0)', () {
      final c = makeContainer();
      addShape(c);
      final s = read(c, 'shape1');
      expect(s.shadowOpacity, 0);
      expect(s.shadowBlur, 0);
      expect(s.shadowOffset, Offset.zero);
      expect(s.shadowColor, const Color(0xFF000000));
    });

    test('copyWith preserves shadow fields when not specified', () {
      const a = ShapeLayer(
        id: 's',
        transform: LayerTransform(
          position: Offset.zero,
          size: Size(100, 100),
        ),
        kind: ShapeKind.rectangle,
        shadowColor: Color(0xFFAABBCC),
        shadowBlur: 12,
        shadowOffset: Offset(4, 8),
        shadowOpacity: 0.5,
      );
      final b = a.copyWith(fillColor: const Color(0xFFFF0000));
      expect(b.shadowColor, const Color(0xFFAABBCC));
      expect(b.shadowBlur, 12);
      expect(b.shadowOffset, const Offset(4, 8));
      expect(b.shadowOpacity, 0.5);
    });

    test('== / hashCode include shadow fields', () {
      const base = ShapeLayer(
        id: 's',
        transform: LayerTransform(
          position: Offset.zero,
          size: Size(100, 100),
        ),
        kind: ShapeKind.rectangle,
        shadowColor: Color(0xFFAABBCC),
        shadowBlur: 12,
        shadowOffset: Offset(4, 8),
        shadowOpacity: 0.5,
      );
      final same = base.copyWith();
      final diff = base.copyWith(shadowBlur: 13);
      expect(same, base);
      expect(same.hashCode, base.hashCode);
      expect(diff == base, isFalse);
    });
  });

  group('ShapeLayer shadow JSON round-trip', () {
    test('shadow fields survive a JSON round-trip', () {
      const original = ShapeLayer(
        id: 'rt',
        transform: LayerTransform(
          position: Offset(10, 20),
          size: Size(120, 80),
        ),
        kind: ShapeKind.rectangle,
        shadowColor: Color(0xFF332211),
        shadowBlur: 18,
        shadowOffset: Offset(-3, 7),
        shadowOpacity: 0.4,
      );
      final decoded = ShapeLayer.fromJson(
        Map<String, dynamic>.from(original.toJson()),
      );
      expect(decoded.shadowColor, original.shadowColor);
      expect(decoded.shadowBlur, original.shadowBlur);
      expect(decoded.shadowOffset, original.shadowOffset);
      expect(decoded.shadowOpacity, original.shadowOpacity);
      expect(decoded, original);
    });

    test('legacy JSON without shadow keys decodes with default shadow', () {
      // Mimic a pre-shadow document — none of the shadow* keys exist.
      final json = <String, dynamic>{
        'id': 'legacy',
        'type': 'shape',
        'transform': const LayerTransform(
          position: Offset.zero,
          size: Size(100, 100),
        ).toJson(),
        'kind': 'rectangle',
        'fillColor': 0xFFFFFFFF,
        'strokeWidth': 0,
        'visible': true,
        'locked': false,
      };
      final decoded = ShapeLayer.fromJson(json);
      expect(decoded.shadowOpacity, 0);
      expect(decoded.shadowBlur, 0);
      expect(decoded.shadowOffset, Offset.zero);
      expect(decoded.shadowColor, const Color(0xFF000000));
    });

    test('shadow keys are omitted from JSON when shadow is invisible', () {
      const noShadow = ShapeLayer(
        id: 'ns',
        transform: LayerTransform(
          position: Offset.zero,
          size: Size(100, 100),
        ),
        kind: ShapeKind.rectangle,
      );
      final json = noShadow.toJson();
      expect(json.containsKey('shadowOpacity'), isFalse);
      expect(json.containsKey('shadowBlur'), isFalse);
      expect(json.containsKey('shadowOffsetX'), isFalse);
      expect(json.containsKey('shadowOffsetY'), isFalse);
      expect(json.containsKey('shadowColor'), isFalse);
    });
  });

  group('SetShapeShadowCommand', () {
    test('apply updates only the specified fields', () {
      final c = makeContainer();
      addShape(c);
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeShadowCommand(
              layerId: 'shape1',
              blur: 14,
              opacity: 0.6,
            ),
          );
      final s = read(c, 'shape1');
      expect(s.shadowBlur, 14);
      expect(s.shadowOpacity, 0.6);
      // Untouched.
      expect(s.shadowOffset, Offset.zero);
      expect(s.shadowColor, const Color(0xFF000000));
    });

    test('apply preserves all non-shadow fields', () {
      final c = makeContainer();
      const id = 'preserve';
      const original = ShapeLayer(
        id: id,
        transform: LayerTransform(
          position: Offset(80, 90),
          size: Size(180, 140),
          rotation: 0.4,
        ),
        kind: ShapeKind.star,
        fillColor: Color(0xFFFF8800),
        fillOpacity: 0.6,
        strokeColor: Color(0xFF003366),
        strokeWidth: 5,
        cornerRadius: 18,
      );
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(original));
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeShadowCommand(
              layerId: id,
              blur: 20,
              opacity: 0.5,
              offset: Offset(0, 8),
              color: Color(0xFF112233),
            ),
          );
      final s = read(c, id);
      expect(s.transform, original.transform);
      expect(s.kind, original.kind);
      expect(s.fillColor, original.fillColor);
      expect(s.fillOpacity, original.fillOpacity);
      expect(s.strokeColor, original.strokeColor);
      expect(s.strokeWidth, original.strokeWidth);
      expect(s.cornerRadius, original.cornerRadius);
    });

    test('undo restores the previous shadow', () {
      final c = makeContainer();
      addShape(c);
      // Set an initial shadow.
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeShadowCommand(
              layerId: 'shape1',
              blur: 8,
              opacity: 0.3,
              offset: Offset(2, 2),
              color: Color(0xFFAA0000),
            ),
          );
      // Then bump opacity.
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeShadowCommand(
              layerId: 'shape1',
              opacity: 0.7,
            ),
          );
      expect(read(c, 'shape1').shadowOpacity, 0.7);
      c.read(documentControllerProvider.notifier).undo();
      final s = read(c, 'shape1');
      expect(s.shadowOpacity, 0.3);
      expect(s.shadowBlur, 8);
      expect(s.shadowOffset, const Offset(2, 2));
      expect(s.shadowColor, const Color(0xFFAA0000));
    });

    test('no-op when nothing changes', () {
      final c = makeContainer();
      addShape(c);
      final before = c.read(documentControllerProvider);
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeShadowCommand(layerId: 'shape1', blur: 0),
          );
      final after = c.read(documentControllerProvider);
      expect(identical(after, before), isTrue);
    });

    test('no-op when layer is missing', () {
      final c = makeContainer();
      addShape(c);
      final before = c.read(documentControllerProvider);
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeShadowCommand(layerId: 'nope', blur: 10),
          );
      final after = c.read(documentControllerProvider);
      expect(identical(after, before), isTrue);
    });
  });

  group('SetShapeShadowCommand live-merge', () {
    test('blur drag stream collapses to one undo step', () {
      final c = makeContainer();
      addShape(c);
      // Discrete: enable shadow.
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeShadowCommand(layerId: 'shape1', opacity: 0.5),
          );
      // Live drag: 3 ticks of blur.
      for (final v in [4.0, 8.0, 14.0]) {
        c.read(documentControllerProvider.notifier).execute(
              SetShapeShadowCommand(
                layerId: 'shape1',
                blur: v,
                live: true,
              ),
            );
      }
      expect(read(c, 'shape1').shadowBlur, 14);
      // One undo should rewind the entire blur stream back to 0.
      c.read(documentControllerProvider.notifier).undo();
      expect(read(c, 'shape1').shadowBlur, 0);
      expect(read(c, 'shape1').shadowOpacity, 0.5);
    });

    test('opacity drag stream collapses to one undo step', () {
      final c = makeContainer();
      addShape(c);
      for (final v in [0.1, 0.3, 0.5]) {
        c.read(documentControllerProvider.notifier).execute(
              SetShapeShadowCommand(
                layerId: 'shape1',
                opacity: v,
                live: true,
              ),
            );
      }
      expect(read(c, 'shape1').shadowOpacity, 0.5);
      c.read(documentControllerProvider.notifier).undo();
      expect(read(c, 'shape1').shadowOpacity, 0);
    });

    test('live blur stream does NOT swallow a live opacity stream', () {
      final c = makeContainer();
      addShape(c);
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeShadowCommand(
              layerId: 'shape1',
              blur: 4,
              live: true,
            ),
          );
      // Different field-set — must NOT merge.
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeShadowCommand(
              layerId: 'shape1',
              opacity: 0.3,
              live: true,
            ),
          );
      // Two undos to rewind both streams.
      c.read(documentControllerProvider.notifier).undo();
      expect(read(c, 'shape1').shadowOpacity, 0);
      c.read(documentControllerProvider.notifier).undo();
      expect(read(c, 'shape1').shadowBlur, 0);
    });

    test('live commands do NOT merge with non-live (mode mismatch)', () {
      final c = makeContainer();
      addShape(c);
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeShadowCommand(layerId: 'shape1', blur: 5),
          );
      c.read(documentControllerProvider.notifier).execute(
            const SetShapeShadowCommand(
              layerId: 'shape1',
              blur: 12,
              live: true,
            ),
          );
      // Two undos to rewind each.
      c.read(documentControllerProvider.notifier).undo();
      expect(read(c, 'shape1').shadowBlur, 5);
      c.read(documentControllerProvider.notifier).undo();
      expect(read(c, 'shape1').shadowBlur, 0);
    });
  });

  group('ReplaceShapeKindCommand preserves shadow', () {
    test('rectangle → heart keeps shadow color/blur/offset/opacity', () {
      final c = makeContainer();
      const id = 'morph';
      const original = ShapeLayer(
        id: id,
        transform: LayerTransform(
          position: Offset(40, 40),
          size: Size(200, 200),
        ),
        kind: ShapeKind.rectangle,
        shadowColor: Color(0xFF112233),
        shadowBlur: 14,
        shadowOffset: Offset(0, 6),
        shadowOpacity: 0.45,
      );
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(original));
      c.read(documentControllerProvider.notifier).execute(
            const ReplaceShapeKindCommand(
              layerId: id,
              kind: ShapeKind.heart,
            ),
          );
      final s = read(c, id);
      expect(s.kind, ShapeKind.heart);
      expect(s.shadowColor, original.shadowColor);
      expect(s.shadowBlur, original.shadowBlur);
      expect(s.shadowOffset, original.shadowOffset);
      expect(s.shadowOpacity, original.shadowOpacity);
    });
  });
}
