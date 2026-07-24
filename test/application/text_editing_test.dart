import 'dart:ui';

import 'package:canvas_engine/features/editor/application/editing_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/text_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TextLayer makeLayer({String content = 'hello'}) => TextLayer(
    id: 't1',
    transform: const LayerTransform(position: Offset.zero, size: Size(120, 60)),
    content: content,
    style: const TextStyleSpec(),
  );

  group('EditingController', () {
    test('starts null and can start / stop / be idempotent', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(editingControllerProvider), isNull);
      container.read(editingControllerProvider.notifier).start('a');
      expect(container.read(editingControllerProvider), 'a');
      // Repeating start with same id is a no-op (does not throw / churn).
      container.read(editingControllerProvider.notifier).start('a');
      expect(container.read(editingControllerProvider), 'a');
      container.read(editingControllerProvider.notifier).stop();
      expect(container.read(editingControllerProvider), isNull);
      // Stop while already null is also a no-op.
      container.read(editingControllerProvider.notifier).stop();
      expect(container.read(editingControllerProvider), isNull);
    });
  });

  group('UpdateTextCommand', () {
    test('replaces content + style, preserves transform', () {
      final layer = makeLayer(content: 'old');
      final doc = EditorDocument(layers: [layer]);
      final cmd = UpdateTextCommand(
        layerId: layer.id,
        content: 'new',
        style: const TextStyleSpec(fontSize: 32),
      );
      final next = cmd.apply(doc);
      final updated = next.layerById(layer.id) as TextLayer;
      expect(updated.content, 'new');
      expect(updated.style.fontSize, 32);
      expect(updated.transform, layer.transform);
    });

    test('inverse restores previous content + style', () {
      final layer = makeLayer(content: 'old');
      final doc = EditorDocument(layers: [layer]);
      final cmd = UpdateTextCommand(
        layerId: layer.id,
        content: 'new',
        style: const TextStyleSpec(fontSize: 99),
      );
      final after = cmd.apply(doc);
      final inverse = cmd.invert(doc);
      final restored = inverse.apply(after).layerById(layer.id) as TextLayer;
      expect(restored.content, 'old');
      expect(restored.style.fontSize, const TextStyleSpec().fontSize);
    });
  });
}
