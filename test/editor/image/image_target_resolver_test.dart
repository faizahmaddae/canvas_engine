import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/crop/application/crop_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/image/application/image_target_resolver.dart';
import 'package:canvas_engine/features/editor/image/application/image_tool_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    c
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    addTearDown(c.dispose);
    return c;
  }

  ImageLayer makeImage(String id) => ImageLayer(
    id: id,
    transform: LayerTransform(
      position: const Offset(0, 0),
      size: const Size(200, 200),
    ),
    source: ImageSource.asset('assets/$id.png'),
  );

  ShapeLayer makeShape(String id) => ShapeLayer(
    id: id,
    transform: LayerTransform(
      position: const Offset(0, 0),
      size: const Size(120, 120),
    ),
    kind: ShapeKind.rectangle,
    fillColor: const Color(0xFFFFFFFF),
  );

  void add(ProviderContainer c, dynamic layer) {
    c.read(documentControllerProvider.notifier).execute(AddLayerCommand(layer));
  }

  group('resolveImageTarget (pure)', () {
    test('selected ImageLayer -> ImageTargetSelected', () {
      final c = makeContainer();
      add(c, makeImage('img1'));
      add(c, makeImage('img2'));
      final out = resolveImageTarget(
        c.read(documentControllerProvider),
        selectedId: 'img2',
      );
      expect(out, isA<ImageTargetSelected>());
      expect((out as ImageTargetSelected).layer.id, 'img2');
    });

    test('selected non-image with exactly one image -> AutoSelect', () {
      final c = makeContainer();
      add(c, makeShape('s1'));
      add(c, makeImage('img1'));
      final out = resolveImageTarget(
        c.read(documentControllerProvider),
        selectedId: 's1',
      );
      expect(out, isA<ImageTargetAutoSelect>());
      expect((out as ImageTargetAutoSelect).layer.id, 'img1');
    });

    test('no selection + exactly one image -> AutoSelect', () {
      final c = makeContainer();
      add(c, makeImage('img1'));
      final out = resolveImageTarget(
        c.read(documentControllerProvider),
        selectedId: null,
      );
      expect(out, isA<ImageTargetAutoSelect>());
      expect((out as ImageTargetAutoSelect).layer.id, 'img1');
    });

    test('selected shape + multiple images -> Ambiguous', () {
      final c = makeContainer();
      add(c, makeShape('s1'));
      add(c, makeImage('img1'));
      add(c, makeImage('img2'));
      final out = resolveImageTarget(
        c.read(documentControllerProvider),
        selectedId: 's1',
      );
      expect(out, isA<ImageTargetAmbiguous>());
    });

    test('no images at all -> NoneAvailable', () {
      final c = makeContainer();
      add(c, makeShape('s1'));
      final out = resolveImageTarget(
        c.read(documentControllerProvider),
        selectedId: null,
      );
      expect(out, isA<ImageTargetNoneAvailable>());
    });

    test('selectedId points to non-existent layer + one image -> '
        'AutoSelect (stale selection is ignored)', () {
      final c = makeContainer();
      add(c, makeImage('img1'));
      final out = resolveImageTarget(
        c.read(documentControllerProvider),
        selectedId: 'ghost',
      );
      expect(out, isA<ImageTargetAutoSelect>());
    });
  });

  // The screen-level wrapper just adapts an outcome to the same
  // side-effects the toolbar expects: auto-selection of the only
  // image, then opening the matching controller. Re-test the wiring
  // by replicating those side-effects against the real providers.
  group('main-toolbar wiring (one image, no selection)', () {
    test('Crop: auto-selects + opens CropController for the only image', () {
      final c = makeContainer();
      add(c, makeImage('only'));
      final outcome = resolveImageTarget(
        c.read(documentControllerProvider),
        selectedId: c.read(selectionControllerProvider).selectedId,
      );
      expect(outcome, isA<ImageTargetAutoSelect>());
      final layer = (outcome as ImageTargetAutoSelect).layer;
      c.read(selectionControllerProvider.notifier).select(layer.id);
      c.read(cropControllerProvider.notifier).openCrop(layer.id);

      expect(c.read(selectionControllerProvider).selectedId, 'only');
      expect(c.read(cropControllerProvider).active, isTrue);
      expect(c.read(cropControllerProvider).layerId, 'only');
    });

    test('Filters: auto-selects + opens filters slot', () {
      final c = makeContainer();
      add(c, makeImage('only'));
      final outcome = resolveImageTarget(
        c.read(documentControllerProvider),
        selectedId: c.read(selectionControllerProvider).selectedId,
      );
      final layer = (outcome as ImageTargetAutoSelect).layer;
      c.read(selectionControllerProvider.notifier).select(layer.id);
      final ctrl = c.read(imageToolControllerProvider.notifier);
      if (c.read(imageToolControllerProvider).openSlot !=
          ImageToolSlot.filters) {
        ctrl.toggleSlot(ImageToolSlot.filters);
      }
      expect(
        c.read(imageToolControllerProvider).openSlot,
        ImageToolSlot.filters,
      );
      expect(c.read(selectionControllerProvider).selectedId, 'only');
    });

    test('Adjust: auto-selects + opens adjust slot', () {
      final c = makeContainer();
      add(c, makeImage('only'));
      final outcome = resolveImageTarget(
        c.read(documentControllerProvider),
        selectedId: c.read(selectionControllerProvider).selectedId,
      );
      final layer = (outcome as ImageTargetAutoSelect).layer;
      c.read(selectionControllerProvider.notifier).select(layer.id);
      final ctrl = c.read(imageToolControllerProvider.notifier);
      if (c.read(imageToolControllerProvider).openSlot !=
          ImageToolSlot.adjust) {
        ctrl.toggleSlot(ImageToolSlot.adjust);
      }
      expect(
        c.read(imageToolControllerProvider).openSlot,
        ImageToolSlot.adjust,
      );
      expect(c.read(selectionControllerProvider).selectedId, 'only');
    });
  });

  group('main-toolbar wiring (multiple images)', () {
    test('shape selected + 2 images, no base photo: Ambiguous carries '
        'the full candidate list', () {
      final c = makeContainer();
      add(c, makeShape('s1'));
      add(c, makeImage('img1'));
      add(c, makeImage('img2'));
      c.read(selectionControllerProvider.notifier).select('s1');

      final outcome = resolveImageTarget(
        c.read(documentControllerProvider),
        selectedId: 's1',
      );
      expect(outcome, isA<ImageTargetAmbiguous>());
      final candidates = (outcome as ImageTargetAmbiguous).candidates;
      expect(candidates.map((l) => l.id), ['img1', 'img2']);

      // The screen would early-return on Ambiguous; verify nothing
      // was nudged by the resolver itself.
      expect(c.read(selectionControllerProvider).selectedId, 's1');
      expect(c.read(cropControllerProvider).active, isFalse);
      expect(c.read(imageToolControllerProvider).openSlot, isNull);
    });
  });

  group('base photo fallback', () {
    test('shape selected + 2 images + basePhotoLayerId set: AutoSelect '
        'the base photo (not Ambiguous)', () {
      final c = makeContainer();
      add(c, makeImage('photo'));
      c
          .read(documentControllerProvider.notifier)
          .execute(const SetBasePhotoCommand('photo'));
      add(c, makeImage('overlay'));
      add(c, makeShape('s1'));
      c.read(selectionControllerProvider.notifier).select('s1');

      final outcome = resolveImageTarget(
        c.read(documentControllerProvider),
        selectedId: 's1',
      );
      expect(outcome, isA<ImageTargetAutoSelect>());
      expect((outcome as ImageTargetAutoSelect).layer.id, 'photo');
    });

    test('basePhotoLayerId points at a deleted layer: falls through to '
        'Ambiguous', () {
      final c = makeContainer();
      add(c, makeImage('photo'));
      c
          .read(documentControllerProvider.notifier)
          .execute(const SetBasePhotoCommand('photo'));
      add(c, makeImage('a'));
      add(c, makeImage('b'));
      // Removing the photo layer also clears basePhotoLayerId via
      // EditorDocument.removeLayer; verify both happen.
      c
          .read(documentControllerProvider.notifier)
          .execute(const RemoveLayerCommand('photo'));
      expect(c.read(documentControllerProvider).basePhotoLayerId, isNull);
      final outcome = resolveImageTarget(
        c.read(documentControllerProvider),
        selectedId: null,
      );
      expect(outcome, isA<ImageTargetAmbiguous>());
    });

    test('selected ImageLayer beats basePhoto fallback', () {
      final c = makeContainer();
      add(c, makeImage('photo'));
      c
          .read(documentControllerProvider.notifier)
          .execute(const SetBasePhotoCommand('photo'));
      add(c, makeImage('overlay'));
      c.read(selectionControllerProvider.notifier).select('overlay');

      final outcome = resolveImageTarget(
        c.read(documentControllerProvider),
        selectedId: 'overlay',
      );
      expect(outcome, isA<ImageTargetSelected>());
      expect((outcome as ImageTargetSelected).layer.id, 'overlay');
    });
  });
}
