// Photo-editor crop integration: covers the user-story
//   "import photo -> tap Crop -> crop opens for that photo"
// at the controller layer. We exercise the same providers the
// editor screen wires together, but skip image-picker plumbing by
// constructing the ImageLayer directly the way `_addImage` does
// (AddLayer + SetBasePhoto in one undoable composite + selection).
//
// Contract §10: main-strip Crop is P scope. It targets the protected
// base photo and nothing else, so every container here is a PHOTO
// project — in a design project the tile does not exist at all, which
// `toolbar_group_order_test.dart` pins instead.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/crop/application/crop_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/layer_state_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/image/application/image_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer makeContainer({ProjectKind kind = ProjectKind.photo}) {
    final c = ProviderContainer();
    c
        .read(documentControllerProvider.notifier)
        .newDocument(width: 1080, height: 1080, kind: kind);
    addTearDown(c.dispose);
    return c;
  }

  ImageLayer makeImage(String id, {Size size = const Size(400, 300)}) =>
      ImageLayer(
        id: id,
        transform: LayerTransform(position: Offset.zero, size: size),
        source: ImageSource.asset('assets/$id.png'),
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

  /// Mirror of `_addImage` import semantics: AddLayer + (when the
  /// document is a PHOTO project with no base yet) SetBasePhoto in
  /// one composite, then auto-select. The project-kind gate is §10.1
  /// — a design import claims nothing.
  void importPhoto(ProviderContainer c, ImageLayer layer) {
    final doc = c.read(documentControllerProvider);
    if (doc.basePhotoLayerId == null && doc.projectKind == ProjectKind.photo) {
      c
          .read(documentControllerProvider.notifier)
          .execute(
            CompositeCommand([
              AddLayerCommand(layer),
              SetBasePhotoCommand(layer.id),
            ], labelOverride: 'Import photo'),
          );
    } else {
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(layer));
    }
    c.read(selectionControllerProvider.notifier).select(layer.id);
  }

  /// Mirror of `EditorScreen._openCrop` minus the recovery snackbar.
  /// Returns true iff Crop opened.
  bool openCrop(ProviderContainer c) {
    final doc = c.read(documentControllerProvider);
    final priorSelectionId = c.read(selectionControllerProvider).selectedId;
    final target = resolveRoleTarget(doc);
    if (target == null) return false;
    c.read(selectionControllerProvider.notifier).select(target.id);
    c
        .read(cropControllerProvider.notifier)
        .openCrop(target.id, priorSelectionId: priorSelectionId);
    return true;
  }

  group('photo import flow', () {
    test('importing a photo selects it AND marks it as base photo', () {
      final c = makeContainer();
      importPhoto(c, makeImage('p1'));
      expect(c.read(selectionControllerProvider).selectedId, 'p1');
      expect(c.read(documentControllerProvider).basePhotoLayerId, 'p1');
    });

    test('importing a second image keeps the first as base photo', () {
      final c = makeContainer();
      importPhoto(c, makeImage('p1'));
      importPhoto(c, makeImage('p2'));
      expect(c.read(documentControllerProvider).basePhotoLayerId, 'p1');
      expect(c.read(selectionControllerProvider).selectedId, 'p2');
    });

    test('removing the base photo clears basePhotoLayerId', () {
      final c = makeContainer();
      importPhoto(c, makeImage('p1'));
      c
          .read(documentControllerProvider.notifier)
          .execute(const RemoveLayerCommand('p1'));
      expect(c.read(documentControllerProvider).basePhotoLayerId, isNull);
    });

    test('the import composite is a single undo step (photo + base '
        'pointer revert together)', () {
      final c = makeContainer();
      importPhoto(c, makeImage('p1'));
      c.read(documentControllerProvider.notifier).undo();
      final doc = c.read(documentControllerProvider);
      expect(doc.layers, isEmpty);
      expect(doc.basePhotoLayerId, isNull);
    });
  });

  group('main toolbar Crop user-story', () {
    test('user imports a photo then taps Crop -> crop opens for it', () {
      final c = makeContainer();
      importPhoto(c, makeImage('p1'));
      final opened = openCrop(c);
      expect(opened, isTrue);
      expect(c.read(cropControllerProvider).active, isTrue);
      expect(c.read(cropControllerProvider).layerId, 'p1');
    });

    test('base photo, no selection -> Crop opens for it and selects it', () {
      final c = makeContainer();
      importPhoto(c, makeImage('p1'));
      c.read(selectionControllerProvider.notifier).clear();
      final opened = openCrop(c);
      expect(opened, isTrue);
      expect(c.read(cropControllerProvider).layerId, 'p1');
      expect(c.read(selectionControllerProvider).selectedId, 'p1');
    });

    test('a shape is selected -> Crop still targets the base photo: the '
        'role names the target, not the selection (§10)', () {
      final c = makeContainer();
      importPhoto(c, makeImage('p1'));
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(makeShape('s1')));
      c.read(selectionControllerProvider.notifier).select('s1');

      final opened = openCrop(c);
      expect(opened, isTrue);
      expect(c.read(selectionControllerProvider).selectedId, 'p1');
      expect(c.read(cropControllerProvider).layerId, 'p1');
    });

    test('a second image is an overlay, never a candidate: Crop targets '
        'the base photo even when the overlay is selected (§10.2)', () {
      final c = makeContainer();
      importPhoto(c, makeImage('photo'));
      importPhoto(c, makeImage('overlay'));
      expect(c.read(selectionControllerProvider).selectedId, 'overlay');

      final opened = openCrop(c);
      expect(opened, isTrue);
      expect(c.read(cropControllerProvider).layerId, 'photo');
    });

    test('images with no base pointer -> Crop bails; there is no ladder '
        'down to "the first one" and no chooser (§10)', () {
      final c = makeContainer();
      // Add two images directly so neither becomes base.
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(makeImage('a')));
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(makeImage('b')));
      final opened = openCrop(c);
      expect(opened, isFalse);
      expect(c.read(cropControllerProvider).active, isFalse);
    });

    test('a hidden base photo does not qualify -> Crop bails rather than '
        'falling back to the visible overlay (§10.2)', () {
      final c = makeContainer();
      importPhoto(c, makeImage('photo'));
      importPhoto(c, makeImage('overlay'));
      c
          .read(documentControllerProvider.notifier)
          .execute(
            const SetLayerVisibilityCommand(layerId: 'photo', visible: false),
          );

      final opened = openCrop(c);
      expect(opened, isFalse);
      expect(c.read(cropControllerProvider).active, isFalse);
    });

    test('a design project never resolves a role target, however many '
        'images it holds (§10.1)', () {
      final c = makeContainer(kind: ProjectKind.design);
      importPhoto(c, makeImage('a'));
      importPhoto(c, makeImage('b'));
      expect(c.read(documentControllerProvider).basePhotoLayerId, isNull);
      expect(openCrop(c), isFalse);
    });

    test('no images at all -> openCrop bails', () {
      final c = makeContainer();
      final opened = openCrop(c);
      expect(opened, isFalse);
      expect(c.read(cropControllerProvider).active, isFalse);
    });
  });

  group('crop Done / Cancel', () {
    test('Done with a changed draft commits a crop on the layer', () {
      final c = makeContainer();
      importPhoto(c, makeImage('p1'));
      openCrop(c);
      c
          .read(cropControllerProvider.notifier)
          .updateDraft(const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9));
      c.read(cropControllerProvider.notifier).commitCrop();

      final layer =
          c.read(documentControllerProvider).layerById('p1') as ImageLayer;
      // Crop is baked into transform.size; cropRect resets to full
      // so the renderer no longer scales the image anisotropically.
      expect(layer.cropRect, ImageLayer.fullCrop);
      // Source layer was 400x300; (0.8 x 0.8) crop -> 320 x 240.
      expect(layer.transform.size.width, closeTo(320, 1e-6));
      expect(layer.transform.size.height, closeTo(240, 1e-6));
      expect(c.read(cropControllerProvider).active, isFalse);
    });

    test('Cancel reverts: layer cropRect untouched, session closed', () {
      final c = makeContainer();
      importPhoto(c, makeImage('p1'));
      openCrop(c);
      c
          .read(cropControllerProvider.notifier)
          .updateDraft(const Rect.fromLTRB(0.2, 0.3, 0.8, 0.7));
      c.read(cropControllerProvider.notifier).cancelCrop();

      final layer =
          c.read(documentControllerProvider).layerById('p1') as ImageLayer;
      expect(layer.cropRect, ImageLayer.fullCrop);
      expect(c.read(cropControllerProvider).active, isFalse);
    });

    test('Done without changes does not push a history entry', () {
      final c = makeContainer();
      importPhoto(c, makeImage('p1'));
      // After import: 1 history entry (Import photo composite).
      // Open + commit with unchanged draft: still 1 entry.
      openCrop(c);
      c.read(cropControllerProvider.notifier).commitCrop();
      // One undo restores empty document; nothing left to undo.
      c.read(documentControllerProvider.notifier).undo();
      expect(c.read(documentControllerProvider).layers, isEmpty);
      expect(c.read(documentControllerProvider.notifier).canUndo, isFalse);
    });

    test('aspect / reset / free chips drive the draft as expected', () {
      final c = makeContainer();
      importPhoto(c, makeImage('p1'));
      openCrop(c);
      // 1:1 preset
      c.read(cropControllerProvider.notifier).setAspectRatio(1.0);
      expect(c.read(cropControllerProvider).aspectRatio, 1.0);
      // free
      c.read(cropControllerProvider.notifier).setAspectRatio(null);
      expect(c.read(cropControllerProvider).aspectRatio, isNull);
      // reset
      c
          .read(cropControllerProvider.notifier)
          .updateDraft(const Rect.fromLTRB(0.2, 0.2, 0.6, 0.6));
      c.read(cropControllerProvider.notifier).resetCrop();
      expect(c.read(cropControllerProvider).draftCrop, ImageLayer.fullCrop);
    });
  });

  group('photo project crop semantics', () {
    /// Photo-mode container: matches what the home Import flow
    /// builds — `newDocument(kind: photo)` + AddLayer + SetBasePhoto
    /// + `clearHistory()` so the imported state is the new origin.
    ProviderContainer makePhotoContainer({
      Size photoSize = const Size(800, 600),
    }) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final ctrl = c.read(documentControllerProvider.notifier);
      ctrl.newDocument(
        width: photoSize.width,
        height: photoSize.height,
        kind: ProjectKind.photo,
      );
      final layer = ImageLayer(
        id: 'photo',
        transform: LayerTransform(position: Offset.zero, size: photoSize),
        source: const ImageSource.asset('assets/photo.png'),
        locked: true,
      );
      ctrl.execute(
        CompositeCommand([
          AddLayerCommand(layer),
          SetBasePhotoCommand('photo'),
        ], labelOverride: 'Import photo'),
      );
      ctrl.clearHistory();
      c.read(selectionControllerProvider.notifier).select('photo');
      return c;
    }

    test('photo-mode crop resizes the canvas to match the new layer', () {
      final c = makePhotoContainer(photoSize: const Size(800, 600));
      c.read(cropControllerProvider.notifier).openCrop('photo');
      // 1:1 crop on a 4:3 photo (centred).
      c.read(cropControllerProvider.notifier).setAspectRatio(1.0);
      final draft = c.read(cropControllerProvider).draftCrop;
      c.read(cropControllerProvider.notifier).commitCrop();

      final doc = c.read(documentControllerProvider);
      final layer = doc.layerById('photo') as ImageLayer;
      // The renderer must NOT be asked to scale anisotropically.
      expect(layer.cropRect, ImageLayer.fullCrop);
      // Layer is anchored at the canvas origin in photo mode.
      expect(layer.transform.position, Offset.zero);
      // Layer + canvas have identical dimensions, AND those
      // dimensions are square (because the user picked 1:1).
      final w = layer.transform.size.width;
      final h = layer.transform.size.height;
      expect(
        w,
        closeTo(h, 1e-6),
        reason: '1:1 crop must produce a square layer (no deform)',
      );
      expect(doc.width, closeTo(w, 1e-6));
      expect(doc.height, closeTo(h, 1e-6));
      // Sanity-check sizing matches the draft proportions.
      expect(w, closeTo(800 * draft.width, 1e-6));
      expect(h, closeTo(600 * draft.height, 1e-6));
    });

    test('design-mode crop does NOT resize the canvas', () {
      final c = makeContainer(kind: ProjectKind.design);
      importPhoto(c, makeImage('p1', size: const Size(400, 300)));
      // Reached the way a design user reaches Crop: select the image
      // and use the image-mode strip (§10.1). openCrop is the same
      // surface either way.
      c.read(cropControllerProvider.notifier).openCrop('p1');
      c
          .read(cropControllerProvider.notifier)
          .updateDraft(const Rect.fromLTRB(0.0, 0.0, 0.5, 0.5));
      c.read(cropControllerProvider.notifier).commitCrop();
      final doc = c.read(documentControllerProvider);
      // Canvas unchanged.
      expect(doc.width, 1080);
      expect(doc.height, 1080);
      final layer = doc.layerById('p1') as ImageLayer;
      expect(layer.transform.size.width, closeTo(200, 1e-6));
      expect(layer.transform.size.height, closeTo(150, 1e-6));
    });

    test('undo immediately after import does NOT remove the photo', () {
      final c = makePhotoContainer();
      // History was cleared post-import; canUndo is false.
      expect(c.read(documentControllerProvider.notifier).canUndo, isFalse);
      c.read(documentControllerProvider.notifier).undo(); // no-op
      expect(c.read(documentControllerProvider).layerById('photo'), isNotNull);
      expect(c.read(documentControllerProvider).basePhotoLayerId, 'photo');
    });

    test('crop in photo mode is undoable in one step', () {
      final c = makePhotoContainer(photoSize: const Size(800, 600));
      final originalSize =
          (c.read(documentControllerProvider).layerById('photo') as ImageLayer)
              .transform
              .size;
      c.read(cropControllerProvider.notifier).openCrop('photo');
      c
          .read(cropControllerProvider.notifier)
          .updateDraft(const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9));
      c.read(cropControllerProvider.notifier).commitCrop();
      // After commit: layer + canvas shrank.
      final docAfter = c.read(documentControllerProvider);
      expect(docAfter.width, isNot(800));
      // Single undo restores both layer transform AND canvas size.
      c.read(documentControllerProvider.notifier).undo();
      final docUndone = c.read(documentControllerProvider);
      expect(docUndone.width, 800);
      expect(docUndone.height, 600);
      expect(
        (docUndone.layerById('photo') as ImageLayer).transform.size,
        originalSize,
      );
      // Photo is still present (not undone past origin).
      expect(docUndone.basePhotoLayerId, 'photo');
    });
  });

  // -----------------------------------------------------------------
  // Selection-restore behaviour: opening Crop must NOT strand the
  // user in image sub-tools after Done. The selection that existed
  // BEFORE Crop opened is restored on commit AND on cancel.
  // -----------------------------------------------------------------
  group('crop returns user to the prior toolbar context', () {
    test(
      'main-toolbar entry (no selection) -> commit -> selection cleared',
      () {
        final c = makeContainer();
        importPhoto(c, makeImage('p1'));
        c.read(selectionControllerProvider.notifier).clear();

        // Mirrors EditorScreen._openCrop: snapshot prior selection
        // BEFORE auto-selecting the resolved target.
        openCrop(c);
        // Auto-select happened.
        expect(c.read(selectionControllerProvider).selectedId, 'p1');

        c
            .read(cropControllerProvider.notifier)
            .updateDraft(const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9));
        c.read(cropControllerProvider.notifier).commitCrop();

        // Back to no selection -> main toolbar.
        expect(c.read(cropControllerProvider).active, isFalse);
        expect(c.read(selectionControllerProvider).selectedId, isNull);
      },
    );

    test(
      'main-toolbar entry (no selection) -> cancel -> selection cleared',
      () {
        final c = makeContainer();
        importPhoto(c, makeImage('p1'));
        c.read(selectionControllerProvider.notifier).clear();

        openCrop(c);
        expect(c.read(selectionControllerProvider).selectedId, 'p1');

        c.read(cropControllerProvider.notifier).cancelCrop();
        expect(c.read(selectionControllerProvider).selectedId, isNull);
      },
    );

    test(
      'main-toolbar entry with unrelated selection -> commit restores it',
      () {
        final c = makeContainer();
        importPhoto(c, makeImage('p1'));
        c
            .read(documentControllerProvider.notifier)
            .execute(AddLayerCommand(makeShape('s1')));
        c.read(selectionControllerProvider.notifier).select('s1');

        openCrop(c);
        // Auto-selected the photo to know what to crop.
        expect(c.read(selectionControllerProvider).selectedId, 'p1');

        c.read(cropControllerProvider.notifier).cancelCrop();
        // Prior unrelated selection restored.
        expect(c.read(selectionControllerProvider).selectedId, 's1');
      },
    );

    test(
      'image-sub-tools entry (image already selected) -> commit keeps it',
      () {
        // Mirrors the ImageModeToolbar Crop slot: the image is the
        // current selection and openCrop is called with
        // priorSelectionId = layer.id, so it stays selected after.
        final c = makeContainer();
        importPhoto(c, makeImage('p1'));
        c.read(selectionControllerProvider.notifier).select('p1');

        c
            .read(cropControllerProvider.notifier)
            .openCrop('p1', priorSelectionId: 'p1');
        c
            .read(cropControllerProvider.notifier)
            .updateDraft(const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9));
        c.read(cropControllerProvider.notifier).commitCrop();

        expect(c.read(selectionControllerProvider).selectedId, 'p1');
      },
    );

    test(
      'no-op commit (Done without changes) still restores prior selection',
      () {
        // Re-opening crop on an unchanged layer hits the early-return
        // branch in commitCrop. That branch must also restore.
        final c = makeContainer();
        importPhoto(c, makeImage('p1'));
        c.read(selectionControllerProvider.notifier).clear();

        openCrop(c);
        // Don't move anything; just press Done.
        c.read(cropControllerProvider.notifier).commitCrop();
        expect(c.read(selectionControllerProvider).selectedId, isNull);
      },
    );
  });
}
