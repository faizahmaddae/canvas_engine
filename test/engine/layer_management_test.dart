import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/commands/layer_state_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ShapeLayer rect(String id) => ShapeLayer(
        id: id,
        transform: const LayerTransform(
          position: Offset.zero,
          size: Size(100, 100),
        ),
        kind: ShapeKind.rectangle,
      );

  EditorDocument seed() {
    var doc = EditorDocument.empty;
    doc = AddLayerCommand(rect('a')).apply(doc);
    doc = AddLayerCommand(rect('b')).apply(doc);
    doc = AddLayerCommand(rect('c')).apply(doc);
    return doc;
  }

  group('ReorderLayerCommand', () {
    test('moves a layer and undoes cleanly', () {
      var doc = seed();
      // move bottom 'a' to top
      final cmd = const ReorderLayerCommand(from: 0, to: 2);
      final inverse = cmd.invert(doc);
      doc = cmd.apply(doc);
      expect(doc.layers.map((l) => l.id).toList(), ['b', 'c', 'a']);
      doc = inverse.apply(doc);
      expect(doc.layers.map((l) => l.id).toList(), ['a', 'b', 'c']);
    });

    test('no-op for equal or out-of-range indices', () {
      final doc = seed();
      expect(
        const ReorderLayerCommand(from: 1, to: 1).apply(doc).layers.map((l) => l.id).toList(),
        ['a', 'b', 'c'],
      );
      expect(
        const ReorderLayerCommand(from: -1, to: 2).apply(doc).layers.map((l) => l.id).toList(),
        ['a', 'b', 'c'],
      );
      expect(
        const ReorderLayerCommand(from: 0, to: 9).apply(doc).layers.map((l) => l.id).toList(),
        ['a', 'b', 'c'],
      );
    });
  });

  group('SetLayerVisibilityCommand', () {
    test('toggles visible and inverts to previous value', () {
      var doc = seed();
      expect(doc.layerById('a')!.visible, isTrue);
      final cmd = const SetLayerVisibilityCommand(layerId: 'a', visible: false);
      final inverse = cmd.invert(doc);
      doc = cmd.apply(doc);
      expect(doc.layerById('a')!.visible, isFalse);
      doc = inverse.apply(doc);
      expect(doc.layerById('a')!.visible, isTrue);
    });

    test('no-op for missing layer', () {
      final doc = seed();
      final result =
          const SetLayerVisibilityCommand(layerId: 'x', visible: false)
              .apply(doc);
      expect(identical(result, doc), isTrue);
    });
  });

  group('SetLayerLockCommand', () {
    test('locks and unlocks with clean inverse', () {
      var doc = seed();
      expect(doc.layerById('b')!.locked, isFalse);
      final cmd = const SetLayerLockCommand(layerId: 'b', locked: true);
      final inverse = cmd.invert(doc);
      doc = cmd.apply(doc);
      expect(doc.layerById('b')!.locked, isTrue);
      doc = inverse.apply(doc);
      expect(doc.layerById('b')!.locked, isFalse);
    });
  });

  group('layer state is preserved by transform updates', () {
    test('SetLayerTransformCommand keeps visible/locked/name on any layer', () {
      var doc = EditorDocument.empty;
      final text = TextLayer(
        id: 't',
        transform: const LayerTransform(
          position: Offset.zero,
          size: Size(100, 40),
        ),
        content: 'hello',
        style: const TextStyleSpec(),
        name: 'Title',
        visible: false,
        locked: true,
      );
      doc = AddLayerCommand(text).apply(doc);
      doc = SetLayerTransformCommand(
        layerId: 't',
        transform: text.transform.copyWith(rotation: 0.5),
      ).apply(doc);

      final updated = doc.layerById('t')!;
      expect(updated, isA<TextLayer>());
      expect(updated.visible, isFalse);
      expect(updated.locked, isTrue);
      expect(updated.name, 'Title');
      expect(updated.transform.rotation, 0.5);
    });
  });

  group('EditorDocument.reorderLayer', () {
    test('moves an item between indices', () {
      final doc = seed();
      final r = doc.reorderLayer(2, 0);
      expect(r.layers.map((l) => l.id).toList(), ['c', 'a', 'b']);
    });

    test('layerById remains consistent after reorder', () {
      final doc = seed().reorderLayer(0, 2);
      expect(doc.layerById('a')!.id, 'a');
      expect(doc.indexOf('a'), 2);
      expect(doc.indexOf('b'), 0);
    });
  });

  group('EditorLayer base invariants', () {
    test('new layers default to visible=true, locked=false', () {
      final layer = rect('x');
      expect(layer.visible, isTrue);
      expect(layer.locked, isFalse);
    });

    test('withVisibility / withLocked return new instances with the flag applied', () {
      final a = rect('x');
      final b = a.withVisibility(false);
      final c = a.withLocked(true);
      expect(b.visible, isFalse);
      expect(b.locked, isFalse);
      expect(c.locked, isTrue);
      expect(c.visible, isTrue);
      // Shape-specific fields preserved.
      expect(b, isA<ShapeLayer>());
      expect((b as ShapeLayer).kind, ShapeKind.rectangle);
    });

    test('opacity defaults to 1.0 and withOpacity returns a clamped copy', () {
      final a = rect('x');
      expect(a.opacity, 1.0);
      final half = a.withOpacity(0.5);
      expect(half.opacity, 0.5);
      // Shape-specific fields preserved.
      expect((half as ShapeLayer).kind, ShapeKind.rectangle);
      // Out-of-range inputs are clamped, not thrown.
      expect(a.withOpacity(-1).opacity, 0.0);
      expect(a.withOpacity(2).opacity, 1.0);
    });

    test('SetLayerOpacityCommand applies and inverts cleanly', () {
      var doc = EditorDocument.empty;
      doc = AddLayerCommand(rect('a')).apply(doc);
      const cmd = SetLayerOpacityCommand(layerId: 'a', opacity: 0.4);
      final inverse = cmd.invert(doc);
      doc = cmd.apply(doc);
      expect(doc.layerById('a')!.opacity, closeTo(0.4, 1e-9));
      doc = inverse.apply(doc);
      expect(doc.layerById('a')!.opacity, 1.0);
    });

    test('SetLayerOpacityCommand is a no-op when value is unchanged', () {
      var doc = EditorDocument.empty;
      doc = AddLayerCommand(rect('a')).apply(doc);
      const cmd = SetLayerOpacityCommand(layerId: 'a', opacity: 1.0);
      final next = cmd.apply(doc);
      expect(identical(next, doc), isTrue);
    });

    test('opacity does not affect visibility flag', () {
      final a = rect('x');
      final invisible = a.withOpacity(0);
      expect(invisible.visible, isTrue);
      expect(invisible.opacity, 0.0);
    });
  });
}
