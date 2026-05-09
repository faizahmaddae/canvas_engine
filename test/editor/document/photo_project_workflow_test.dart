// Photo-mode end-to-end semantics at the controller layer.
//
// Mirrors the home-screen Import flow and the LayerActions delete
// path WITHOUT invoking the gallery picker / dialogs:
//   * `importPhoto(c, ...)` reproduces newDocument(kind: photo) +
//     CompositeCommand(AddLayer(locked) + SetBasePhoto).
//   * `removeBasePhotoUserConfirmed(c, id)` reproduces what
//     LayerActions.delete dispatches once the confirm dialog has
//     returned `true`: a composite of RemoveLayer + flip back to
//     ProjectKind.design as one undoable step.
//
// Together these tests pin down the contract the production UI
// is responsible for honouring.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/image/application/image_target_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer makePhotoProject({Size dims = const Size(800, 600)}) {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(documentControllerProvider.notifier).newDocument(
          width: dims.width,
          height: dims.height,
          kind: ProjectKind.photo,
        );
    return c;
  }

  ImageLayer makeBasePhoto(
    String id, {
    Size dims = const Size(800, 600),
  }) =>
      ImageLayer(
        id: id,
        transform: LayerTransform(position: Offset.zero, size: dims),
        source: ImageSource.asset('assets/$id.png'),
        // Photo-mode imports always lock the base photo.
        locked: true,
      );

  ShapeLayer makeShape(String id) => ShapeLayer(
        id: id,
        transform: LayerTransform(
          position: Offset.zero,
          size: const Size(100, 100),
        ),
        kind: ShapeKind.rectangle,
        fillColor: const Color(0xFFFFFFFF),
      );

  void importPhoto(
    ProviderContainer c,
    ImageLayer layer,
  ) {
    c.read(documentControllerProvider.notifier).execute(
          CompositeCommand(
            [AddLayerCommand(layer), SetBasePhotoCommand(layer.id)],
            labelOverride: 'Import photo',
          ),
        );
    c.read(selectionControllerProvider.notifier).select(layer.id);
  }

  /// Mirrors what LayerActions.delete executes once the user
  /// confirms removing the base photo: a single composite that
  /// removes the layer AND flips the project back to design so the
  /// document is no longer in an inconsistent "photo project with
  /// no photo" state.
  void removeBasePhotoUserConfirmed(ProviderContainer c, String id) {
    c.read(documentControllerProvider.notifier).execute(
          CompositeCommand(
            [
              const SetBasePhotoCommand(null),
              RemoveLayerCommand(id),
              const SetProjectKindCommand(ProjectKind.design),
            ],
            labelOverride: 'Remove base photo',
          ),
        );
  }

  group('home import flow creates a photo-style project', () {
    test('newDocument(kind: photo) marks the project, no layers yet', () {
      final c = makePhotoProject();
      final doc = c.read(documentControllerProvider);
      expect(doc.projectKind, ProjectKind.photo);
      expect(doc.layers, isEmpty);
      expect(doc.basePhotoLayerId, isNull);
    });

    test('importing the photo: locked, selected, marked as base', () {
      final c = makePhotoProject();
      importPhoto(c, makeBasePhoto('p1'));

      final doc = c.read(documentControllerProvider);
      expect(doc.basePhotoLayerId, 'p1');
      expect(doc.projectKind, ProjectKind.photo);
      expect(doc.layerById('p1')!.locked, isTrue);
      expect(c.read(selectionControllerProvider).selectedId, 'p1');
    });

    test('isProtectedBasePhoto guards the imported photo', () {
      final c = makePhotoProject();
      importPhoto(c, makeBasePhoto('p1'));
      final doc = c.read(documentControllerProvider);
      expect(doc.isProtectedBasePhoto('p1'), isTrue);
    });

    test('Crop / Filters / Adjust resolve to the base photo even when '
        'a sticker is the current selection', () {
      final c = makePhotoProject();
      importPhoto(c, makeBasePhoto('photo'));
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(makeShape('sticker')));
      c.read(selectionControllerProvider.notifier).select('sticker');

      final outcome = resolveImageTarget(
        c.read(documentControllerProvider),
        selectedId: 'sticker',
      );
      expect(outcome, isA<ImageTargetAutoSelect>());
      expect((outcome as ImageTargetAutoSelect).layer.id, 'photo');
    });
  });

  group('confirmed base-photo removal flips back to design', () {
    test('after confirmed remove: layer gone, kind=design, base cleared, '
        'one undo restores everything', () {
      final c = makePhotoProject();
      importPhoto(c, makeBasePhoto('p1'));

      removeBasePhotoUserConfirmed(c, 'p1');

      var doc = c.read(documentControllerProvider);
      expect(doc.layers, isEmpty);
      expect(doc.basePhotoLayerId, isNull);
      expect(doc.projectKind, ProjectKind.design);

      // ONE undo restores BOTH the photo AND the photo-project flag.
      c.read(documentControllerProvider.notifier).undo();
      doc = c.read(documentControllerProvider);
      expect(doc.layers.single.id, 'p1');
      expect(doc.basePhotoLayerId, 'p1');
      expect(doc.projectKind, ProjectKind.photo);
    });

    test('removing a non-base layer in a photo project keeps kind=photo', () {
      final c = makePhotoProject();
      importPhoto(c, makeBasePhoto('photo'));
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(makeShape('sticker')));

      // Removing a sticker uses the normal RemoveLayerCommand path
      // (no project-kind flip).
      c
          .read(documentControllerProvider.notifier)
          .execute(const RemoveLayerCommand('sticker'));

      final doc = c.read(documentControllerProvider);
      expect(doc.projectKind, ProjectKind.photo);
      expect(doc.basePhotoLayerId, 'photo');
      expect(doc.layers.single.id, 'photo');
    });
  });

  group('design projects unchanged', () {
    test('newDocument with default kind = design', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(documentControllerProvider.notifier)
          .newDocument(width: 1080, height: 1080);
      final doc = c.read(documentControllerProvider);
      expect(doc.projectKind, ProjectKind.design);
      expect(doc.basePhotoLayerId, isNull);
    });

    test('adding an image in a design project does NOT lock it', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(documentControllerProvider.notifier)
          .newDocument(width: 1080, height: 1080);
      // Mirror editor _addImage in design mode: claim base photo
      // pointer (for resolver) but do NOT lock the layer.
      final layer = ImageLayer(
        id: 'i1',
        transform: LayerTransform(
          position: Offset.zero,
          size: const Size(400, 300),
        ),
        source: ImageSource.asset('assets/i1.png'),
      );
      c.read(documentControllerProvider.notifier).execute(
            CompositeCommand(
              [AddLayerCommand(layer), SetBasePhotoCommand('i1')],
              labelOverride: 'Add image',
            ),
          );

      final doc = c.read(documentControllerProvider);
      expect(doc.projectKind, ProjectKind.design);
      expect(doc.layerById('i1')!.locked, isFalse);
      expect(doc.isProtectedBasePhoto('i1'), isFalse);
    });

    test('design-mode RemoveLayer of base photo does NOT need confirm-flip '
        '(kind stays design, base auto-clears)', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(documentControllerProvider.notifier)
          .newDocument(width: 1080, height: 1080);
      final layer = ImageLayer(
        id: 'i1',
        transform: LayerTransform(
          position: Offset.zero,
          size: const Size(400, 300),
        ),
        source: ImageSource.asset('assets/i1.png'),
      );
      c.read(documentControllerProvider.notifier).execute(
            CompositeCommand(
              [AddLayerCommand(layer), SetBasePhotoCommand('i1')],
            ),
          );
      c
          .read(documentControllerProvider.notifier)
          .execute(const RemoveLayerCommand('i1'));

      final doc = c.read(documentControllerProvider);
      expect(doc.projectKind, ProjectKind.design);
      expect(doc.basePhotoLayerId, isNull);
    });
  });
}
