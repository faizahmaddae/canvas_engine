import 'package:canvas_engine/features/editor/application/alignment_controller.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/interaction/alignment_engine.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    c.read(documentControllerProvider.notifier).newDocument(
          width: 1000,
          height: 1000,
        );
    return c;
  }

  void addRect(
    ProviderContainer c, {
    required String id,
    required Offset position,
    Size size = const Size(50, 50),
  }) {
    c.read(documentControllerProvider.notifier).execute(
          AddLayerCommand(
            ShapeLayer(
              id: id,
              transform: LayerTransform(position: position, size: size),
              kind: ShapeKind.rectangle,
            ),
          ),
        );
  }

  test('align left moves every selected layer to bounds.left', () {
    final c = makeContainer();
    addRect(c, id: 'a', position: const Offset(20, 0));
    addRect(c, id: 'b', position: const Offset(80, 100));
    addRect(c, id: 'cc', position: const Offset(150, 200));
    c.read(selectionControllerProvider.notifier).select('a');
    c.read(selectionControllerProvider.notifier).add('b');
    c.read(selectionControllerProvider.notifier).add('cc');

    c.read(alignmentControllerProvider).align(AlignAxis.left);
    final doc = c.read(documentControllerProvider);
    expect(doc.layerById('a')!.transform.position.dx, 20);
    expect(doc.layerById('b')!.transform.position.dx, 20);
    expect(doc.layerById('cc')!.transform.position.dx, 20);
  });

  test('align is undoable as a single composite step', () {
    final c = makeContainer();
    addRect(c, id: 'a', position: const Offset(20, 0));
    addRect(c, id: 'b', position: const Offset(80, 100));
    addRect(c, id: 'cc', position: const Offset(150, 200));
    c.read(selectionControllerProvider.notifier).select('a');
    c.read(selectionControllerProvider.notifier).add('b');
    c.read(selectionControllerProvider.notifier).add('cc');

    c.read(alignmentControllerProvider).align(AlignAxis.left);
    c.read(documentControllerProvider.notifier).undo();
    final doc = c.read(documentControllerProvider);
    expect(doc.layerById('a')!.transform.position.dx, 20);
    expect(doc.layerById('b')!.transform.position.dx, 80);
    expect(doc.layerById('cc')!.transform.position.dx, 150);
  });

  test('distribute horizontally evens out gaps; outers fixed', () {
    final c = makeContainer();
    addRect(c, id: 'a', position: const Offset(0, 0));
    addRect(c, id: 'b', position: const Offset(80, 0), size: const Size(30, 30));
    addRect(c, id: 'cc', position: const Offset(200, 0));
    c.read(selectionControllerProvider.notifier).select('a');
    c.read(selectionControllerProvider.notifier).add('b');
    c.read(selectionControllerProvider.notifier).add('cc');

    c.read(alignmentControllerProvider)
        .distribute(DistributeAxis.horizontal);

    final doc = c.read(documentControllerProvider);
    // Span 0..250, sum extents = 50+30+50 = 130, gap = 60, mid at 110.
    expect(doc.layerById('a')!.transform.position.dx, 0);
    expect(doc.layerById('cc')!.transform.position.dx, 200);
    expect(
      doc.layerById('b')!.transform.position.dx,
      closeTo(110, 0.001),
    );
  });

  test('no-op when fewer than two movable layers selected', () {
    final c = makeContainer();
    addRect(c, id: 'a', position: const Offset(20, 0));
    c.read(selectionControllerProvider.notifier).select('a');

    c.read(alignmentControllerProvider).align(AlignAxis.left);
    final doc = c.read(documentControllerProvider);
    expect(doc.layerById('a')!.transform.position.dx, 20);
  });
}
