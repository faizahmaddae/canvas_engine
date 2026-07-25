// A selection can outlive the layers it names — an undo, a delete, a
// document swap. The dock's mode derivation has always filtered those
// out; the multi-select chip and the layers-panel header did not, and
// on a real document the chip announced «چندانتخاب · ۱۰» over six
// layers with one of them selected while the dock correctly showed
// that single layer's own tools. One derivation now feeds all three.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/editor_mode_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ShapeLayer shape(String id) => ShapeLayer(
    id: id,
    kind: ShapeKind.rectangle,
    transform: const LayerTransform(
      position: Offset.zero,
      size: Size(100, 100),
    ),
  );

  ImageLayer photo(String id) => ImageLayer(
    id: id,
    source: const ImageSource.asset('a.png'),
    transform: const LayerTransform(
      position: Offset.zero,
      size: Size(100, 100),
    ),
  );

  ProviderContainer harness(EditorDocument doc) {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(documentControllerProvider.notifier).loadDocument(doc);
    return c;
  }

  test('counts only layers that still exist', () {
    final c = harness(
      EditorDocument(width: 100, height: 100, layers: [shape('a'), shape('b')]),
    );
    c.read(selectionControllerProvider.notifier).select('a');
    c.read(selectionControllerProvider.notifier).add('b');
    // A ghost: an id the document has never heard of.
    c.read(selectionControllerProvider.notifier).add('gone');

    expect(c.read(selectionControllerProvider).count, 3);
    expect(
      c.read(actionableSelectionCountProvider),
      2,
      reason: 'the ghost cannot be acted on, so it must not be counted',
    );
  });

  test('a selection of only ghosts is not a multi-selection', () {
    final c = harness(
      EditorDocument(width: 100, height: 100, layers: [shape('a')]),
    );
    c.read(selectionControllerProvider.notifier).select('a');
    for (final id in ['g1', 'g2', 'g3']) {
      c.read(selectionControllerProvider.notifier).add(id);
    }

    expect(c.read(selectionControllerProvider).count, 4);
    expect(c.read(actionableSelectionCountProvider), 1);
    expect(
      c.read(editorToolModeProvider),
      isNot(EditorToolMode.multi),
      reason:
          'the chip and the dock have to agree — this is the state '
          'where they used to disagree',
    );
  });

  test('the protected base photo does not count toward a group', () {
    final doc = EditorDocument(
      width: 100,
      height: 100,
      layers: [photo('base'), shape('a')],
      basePhotoLayerId: 'base',
      // Protection only applies to photo projects.
      projectKind: ProjectKind.photo,
    );
    final c = harness(doc);
    c.read(selectionControllerProvider.notifier).select('base');
    c.read(selectionControllerProvider.notifier).add('a');

    expect(c.read(selectionControllerProvider).count, 2);
    expect(c.read(actionableSelectionCountProvider), 1);
    expect(c.read(editorToolModeProvider), isNot(EditorToolMode.multi));
  });

  test('two real layers ARE a multi-selection', () {
    final c = harness(
      EditorDocument(width: 100, height: 100, layers: [shape('a'), shape('b')]),
    );
    c.read(selectionControllerProvider.notifier).select('a');
    c.read(selectionControllerProvider.notifier).add('b');

    expect(c.read(actionableSelectionCountProvider), 2);
    expect(c.read(editorToolModeProvider), EditorToolMode.multi);
  });

  test('an empty selection counts zero', () {
    final c = harness(
      EditorDocument(width: 100, height: 100, layers: [shape('a')]),
    );
    expect(c.read(actionableSelectionCountProvider), 0);
    expect(c.read(editorToolModeProvider), EditorToolMode.idle);
  });
}
