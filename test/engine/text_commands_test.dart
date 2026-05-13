import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/commands/history_stack.dart';
import 'package:canvas_engine/features/editor/engine/commands/text_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:flutter_test/flutter_test.dart';

TextLayer _layer() => const TextLayer(
      id: 't1',
      transform: LayerTransform(
        position: Offset(0, 0),
        size: Size(200, 80),
      ),
      content: 'hi',
      style: TextStyleSpec(),
    );

void main() {
  group('UpdateTextCommand.mergeWith', () {
    test('merges a style-only stream into one undo entry', () {
      // Two consecutive font-size slider frames: same touched-field
      // shape {style}. Conservative merge MUST collapse them.
      final history = HistoryStack();
      var doc = EditorDocument.empty.addLayer(_layer());

      doc = history.execute(
        doc,
        const UpdateTextCommand(
          layerId: 't1',
          style: TextStyleSpec(fontSize: 20),
        ),
      );
      doc = history.execute(
        doc,
        const UpdateTextCommand(
          layerId: 't1',
          style: TextStyleSpec(fontSize: 22),
        ),
      );

      expect(history.undoDepth, 1,
          reason: 'style-only stream should coalesce');
    });

    test('merges a content-only stream into one undo entry', () {
      // Typing keystrokes: shape {content}.
      final history = HistoryStack();
      var doc = EditorDocument.empty.addLayer(_layer());

      doc = history.execute(
        doc,
        const UpdateTextCommand(layerId: 't1', content: 'h'),
      );
      doc = history.execute(
        doc,
        const UpdateTextCommand(layerId: 't1', content: 'he'),
      );

      expect(history.undoDepth, 1,
          reason: 'content-only stream should coalesce');
    });

    test('does NOT merge a content edit and a style edit', () {
      // The bug: pre-fix mergeWith collapsed any two UpdateTextCommands
      // on the same layer regardless of which fields changed, so a
      // content edit followed by a style edit (or vice versa) became
      // a single undo entry — silently swallowing one of the user's
      // actions on undo. Post-fix: different touched-field shapes
      // ({content} vs {style}) refuse to merge.
      final history = HistoryStack();
      var doc = EditorDocument.empty.addLayer(_layer());

      doc = history.execute(
        doc,
        const UpdateTextCommand(layerId: 't1', content: 'hello'),
      );
      doc = history.execute(
        doc,
        const UpdateTextCommand(
          layerId: 't1',
          style: TextStyleSpec(fontSize: 32),
        ),
      );

      expect(history.undoDepth, 2,
          reason: 'content-edit + style-edit must remain separate');

      // Step the style change back: content stays, style reverts.
      doc = history.undo(doc);
      var t = doc.layerById('t1')! as TextLayer;
      expect(t.content, 'hello');
      expect(t.style.fontSize, const TextStyleSpec().fontSize);

      // Step the content change back: original content restored.
      doc = history.undo(doc);
      t = doc.layerById('t1')! as TextLayer;
      expect(t.content, 'hi');
    });

    test('does NOT merge across different transform shapes', () {
      // A bundled-transform command and a no-transform command have
      // different shapes — merging them would silently drop or
      // invent a re-measure. This guard predates the rule-4 fix and
      // must remain.
      final history = HistoryStack();
      var doc = EditorDocument.empty.addLayer(_layer());

      doc = history.execute(
        doc,
        const UpdateTextCommand(
          layerId: 't1',
          style: TextStyleSpec(fontSize: 24),
        ),
      );
      doc = history.execute(
        doc,
        const UpdateTextCommand(
          layerId: 't1',
          style: TextStyleSpec(fontSize: 28),
          transform: LayerTransform(
            position: Offset(0, 0),
            size: Size(200, 100),
          ),
        ),
      );

      expect(history.undoDepth, 2);
    });
  });
}
