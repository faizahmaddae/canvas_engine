// Entry-flow audit: covers the two ways the user enters the
// editor from Home and asserts every contract listed in the
// spec. Goes through the same providers + commands the home
// flow uses, just without the picker/dialog UI.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/editor_lifecycle.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/crop/application/crop_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/image/application/image_target_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Probe extends ConsumerWidget {
  const _Probe();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    _ref = ref;
    return const SizedBox.shrink();
  }

  static WidgetRef? _ref;
}

void main() {
  /// Mirror of `_onImport` from `home_screen.dart`, minus the
  /// picker / file I/O. Any drift between this helper and the
  /// real flow is what the spec calls "mismatch between current
  /// and expected behavior".
  void importPhotoFlow(
    ProviderContainer c, {
    String id = 'photo',
    Size dims = const Size(800, 600),
  }) {
    final docCtrl = c.read(documentControllerProvider.notifier);
    docCtrl.newDocument(
      width: dims.width,
      height: dims.height,
      kind: ProjectKind.photo,
    );
    docCtrl.execute(
      CompositeCommand([
        AddLayerCommand(
          ImageLayer(
            id: id,
            transform: LayerTransform(position: Offset.zero, size: dims),
            source: const ImageSource.asset('photo.jpg'),
            locked: true,
          ),
        ),
        SetBasePhotoCommand(id),
      ], labelOverride: 'Import photo'),
    );
    docCtrl.clearHistory();
    c.read(selectionControllerProvider.notifier).clear();
  }

  /// Mirror of `_seedAndOpen` -- the path used by every blank /
  /// preset / sized canvas entry from Home.
  void blankCanvasFlow(
    ProviderContainer c, {
    double width = 1080,
    double height = 1080,
  }) {
    c
        .read(documentControllerProvider.notifier)
        .newDocument(width: width, height: height);
    c.read(selectionControllerProvider.notifier).clear();
  }

  group('photo import flow', () {
    test('projectKind == photo and basePhotoLayerId is set', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      importPhotoFlow(c);
      final doc = c.read(documentControllerProvider);
      expect(doc.projectKind, ProjectKind.photo);
      expect(doc.basePhotoLayerId, 'photo');
    });

    test('imported photo is locked', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      importPhotoFlow(c);
      final layer =
          c.read(documentControllerProvider).layerById('photo') as ImageLayer;
      expect(layer.locked, isTrue);
    });

    test('selection is empty after import (no object chrome)', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      importPhotoFlow(c);
      expect(c.read(selectionControllerProvider).selectedId, isNull);
    });

    test('undo immediately after import does NOT remove the photo', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      importPhotoFlow(c);
      expect(c.read(documentControllerProvider.notifier).canUndo, isFalse);
      c.read(documentControllerProvider.notifier).undo(); // no-op
      final doc = c.read(documentControllerProvider);
      expect(doc.layerById('photo'), isNotNull);
      expect(doc.basePhotoLayerId, 'photo');
    });

    test('Crop/Filters/Adjust resolve the base photo with NO selection', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      importPhotoFlow(c);
      final doc = c.read(documentControllerProvider);
      final outcome = resolveImageTarget(doc, selectedId: null);
      expect(outcome, isA<ImageTargetAutoSelect>());
      expect((outcome as ImageTargetAutoSelect).layer.id, 'photo');
    });
  });

  testWidgets('photo import: editor entry leaves crop session inactive', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: _Probe())),
    );
    final ref = _Probe._ref!;
    // Pre-pollute crop state to simulate leftover from a previous
    // editor instance.
    final docCtrl = ref.read(documentControllerProvider.notifier);
    docCtrl.newDocument(width: 100, height: 100);
    docCtrl.execute(
      AddLayerCommand(
        ImageLayer(
          id: 'leftover',
          transform: LayerTransform(
            position: Offset.zero,
            size: const Size(80, 80),
          ),
          source: const ImageSource.asset('a.png'),
        ),
      ),
    );
    ref.read(cropControllerProvider.notifier).openCrop('leftover');
    expect(ref.read(cropControllerProvider).active, isTrue);
    // Now the home flow: import + ephemeral reset (the latter is
    // what `_push` calls right before navigating).
    importPhotoFlow(ref.container, id: 'photo');
    resetEditorEphemeralState(ref);
    expect(
      ref.read(cropControllerProvider).active,
      isFalse,
      reason: 'crop session must not leak across editor entries',
    );
  });

  group('blank canvas flow', () {
    test('projectKind defaults to design', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      blankCanvasFlow(c);
      expect(
        c.read(documentControllerProvider).projectKind,
        ProjectKind.design,
      );
    });

    test('document starts with zero layers and no base photo', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      blankCanvasFlow(c);
      final doc = c.read(documentControllerProvider);
      expect(doc.layers, isEmpty);
      expect(doc.basePhotoLayerId, isNull);
    });

    test('selection is empty', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      blankCanvasFlow(c);
      expect(c.read(selectionControllerProvider).selectedId, isNull);
    });

    test('added image is NOT a protected base photo (normal layer)', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      blankCanvasFlow(c);
      c
          .read(documentControllerProvider.notifier)
          .execute(
            AddLayerCommand(
              ImageLayer(
                id: 'i',
                transform: LayerTransform(
                  position: Offset.zero,
                  size: const Size(200, 200),
                ),
                source: const ImageSource.asset('a.png'),
              ),
            ),
          );
      final doc = c.read(documentControllerProvider);
      expect(doc.basePhotoLayerId, isNull);
      expect(doc.isProtectedBasePhoto('i'), isFalse);
      final layer = doc.layerById('i') as ImageLayer;
      expect(layer.locked, isFalse);
    });

    test('added shape is selectable and undoable (normal design behavior)', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      blankCanvasFlow(c);
      final ctrl = c.read(documentControllerProvider.notifier);
      ctrl.execute(
        AddLayerCommand(
          ShapeLayer(
            id: 's',
            transform: LayerTransform(
              position: Offset.zero,
              size: const Size(50, 50),
            ),
            kind: ShapeKind.rectangle,
            fillColor: const Color(0xFFFFFFFF),
          ),
        ),
      );
      c.read(selectionControllerProvider.notifier).select('s');
      expect(c.read(selectionControllerProvider).selectedId, 's');
      // Undo removes the shape (per-action history works).
      ctrl.undo();
      expect(c.read(documentControllerProvider).layers, isEmpty);
    });
  });
}
