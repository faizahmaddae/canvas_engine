import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/commands/history_stack.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:flutter_test/flutter_test.dart';

TextLayer _layer(String id) => TextLayer(
  id: id,
  transform: const LayerTransform(position: Offset(0, 0), size: Size(100, 50)),
  content: 'hi',
  style: const TextStyleSpec(),
);

void main() {
  group('EditorDocument', () {
    test('add / replace / remove', () {
      final doc = EditorDocument.empty;
      final a = _layer('a');
      final d1 = doc.addLayer(a);
      expect(d1.layers.length, 1);
      expect(d1.layerById('a'), a);

      final a2 = a.copyWith(content: 'bye');
      final d2 = d1.replaceLayer(a2);
      expect((d2.layerById('a') as TextLayer).content, 'bye');

      final d3 = d2.removeLayer('a');
      expect(d3.layers, isEmpty);
    });
  });

  group('HistoryStack', () {
    test('execute/undo/redo round-trip', () {
      final history = HistoryStack();
      var doc = EditorDocument.empty;
      final a = _layer('a');

      doc = history.execute(doc, AddLayerCommand(a));
      expect(doc.layers.length, 1);
      expect(history.canUndo, true);
      expect(history.canRedo, false);

      doc = history.undo(doc);
      expect(doc.layers, isEmpty);
      expect(history.canRedo, true);

      doc = history.redo(doc);
      expect(doc.layers.length, 1);
    });

    test('execute clears redo', () {
      final history = HistoryStack();
      var doc = EditorDocument.empty;
      doc = history.execute(doc, AddLayerCommand(_layer('a')));
      doc = history.undo(doc);
      expect(history.canRedo, true);
      doc = history.execute(doc, AddLayerCommand(_layer('b')));
      expect(history.canRedo, false);
    });

    test('SetLayerTransformCommand undoes to previous transform', () {
      final history = HistoryStack();
      var doc = EditorDocument.empty.addLayer(_layer('a'));
      final before = doc.layerById('a')!.transform;

      doc = history.execute(
        doc,
        SetLayerTransformCommand(
          layerId: 'a',
          transform: before.copyWith(position: const Offset(50, 50)),
        ),
      );
      expect(doc.layerById('a')!.transform.position, const Offset(50, 50));
      doc = history.undo(doc);
      expect(doc.layerById('a')!.transform, before);
    });
  });
}
