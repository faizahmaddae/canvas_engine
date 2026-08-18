import 'dart:ui';

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/live_overlay_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/paint/application/paint_stroke_controller.dart';
import 'package:canvas_engine/features/editor/paint/application/paint_tool_controller.dart';
import 'package:canvas_engine/features/editor/paint/domain/paint_tool_type.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer harness() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    return container;
  }

  PaintLayer stroke(String id, Offset position) => PaintLayer(
    id: id,
    transform: LayerTransform(position: position, size: const Size(100, 80)),
    kind: PaintKind.line,
    normalizedPoints: const [Offset(0, 0.5), Offset(1, 0.5)],
  );

  test('commitDot dispatches one application-owned AddLayer command', () {
    final container = harness();
    container
        .read(paintToolControllerProvider.notifier)
        .selectTool(PaintToolType.freestyle);
    final version = container.read(documentCommitVersionProvider);

    container
        .read(paintStrokeControllerProvider.notifier)
        .commitDot(const Offset(120, 160), docSize: const Size(800, 800));

    final doc = container.read(documentControllerProvider);
    expect(doc.layers, hasLength(1));
    expect(doc.layers.single, isA<PaintLayer>());
    expect(container.read(documentCommitVersionProvider), version + 1);
  });

  test('commitDot selects the layer it just added, tool stays armed', () {
    final container = harness();
    container
        .read(paintToolControllerProvider.notifier)
        .selectTool(PaintToolType.freestyle);

    container
        .read(paintStrokeControllerProvider.notifier)
        .commitDot(const Offset(120, 160), docSize: const Size(800, 800));

    final doc = container.read(documentControllerProvider);
    expect(
      container.read(selectionControllerProvider).selectedId,
      doc.layers.single.id,
      reason: 'contract §10: an A-scope command ends with its layer selected',
    );
    expect(
      container.read(paintToolControllerProvider).activeTool,
      PaintToolType.freestyle,
      reason: 'selecting the new stroke must not disarm continuous drawing',
    );
  });

  test('sweep stages removals, commits once, and one undo restores order', () {
    final container = harness();
    final documents = container.read(documentControllerProvider.notifier);
    documents.execute(AddLayerCommand(stroke('a', const Offset(100, 100))));
    documents.execute(AddLayerCommand(stroke('b', const Offset(260, 100))));
    container.read(selectionControllerProvider.notifier).select('a');
    final version = container.read(documentCommitVersionProvider);
    final strokes = container.read(paintStrokeControllerProvider.notifier);

    strokes.beginEraserSweep();
    strokes.sweepEraseAt(const Offset(150, 140));
    strokes.sweepEraseAt(const Offset(310, 140));

    expect(container.read(documentCommitVersionProvider), version);
    expect(container.read(documentControllerProvider).layers, hasLength(2));
    expect(container.read(liveOverlayProvider).removals, {'a', 'b'});

    strokes.commitEraserSweep();

    expect(container.read(documentCommitVersionProvider), version + 1);
    expect(container.read(documentControllerProvider).layers, isEmpty);
    expect(container.read(liveOverlayProvider).isEmpty, isTrue);
    expect(container.read(selectionControllerProvider).hasSelection, isFalse);

    documents.undo();
    expect(container.read(documentControllerProvider).layers.map((l) => l.id), [
      'a',
      'b',
    ]);
  });
}
