import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/image_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
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

  ImageLayer addImage(ProviderContainer c, {String id = 'img1'}) {
    final layer = ImageLayer(
      id: id,
      transform: LayerTransform(
        position: const Offset(100, 100),
        size: const Size(400, 300),
      ),
      source: const ImageSource.asset('assets/test.png'),
    );
    c.read(documentControllerProvider.notifier).execute(AddLayerCommand(layer));
    return layer;
  }

  ImageLayer readImage(ProviderContainer c, String id) {
    return c.read(documentControllerProvider).layerById(id) as ImageLayer;
  }

  group('SetImageFilterCommand', () {
    test('new image defaults to ImageFilterPreset.none', () {
      final c = makeContainer();
      addImage(c);
      expect(readImage(c, 'img1').filterPreset, ImageFilterPreset.none);
    });

    test('execute swaps the filter preset on the layer', () {
      final c = makeContainer();
      addImage(c);
      c
          .read(documentControllerProvider.notifier)
          .execute(
            const SetImageFilterCommand(
              layerId: 'img1',
              filterPreset: ImageFilterPreset.vintage,
            ),
          );
      expect(readImage(c, 'img1').filterPreset, ImageFilterPreset.vintage);
    });

    test('undo restores the previous filter preset', () {
      final c = makeContainer();
      addImage(c);
      c
          .read(documentControllerProvider.notifier)
          .execute(
            const SetImageFilterCommand(
              layerId: 'img1',
              filterPreset: ImageFilterPreset.warm,
            ),
          );
      c
          .read(documentControllerProvider.notifier)
          .execute(
            const SetImageFilterCommand(
              layerId: 'img1',
              filterPreset: ImageFilterPreset.mono,
            ),
          );
      c.read(documentControllerProvider.notifier).undo();
      expect(readImage(c, 'img1').filterPreset, ImageFilterPreset.warm);
      c.read(documentControllerProvider.notifier).undo();
      expect(readImage(c, 'img1').filterPreset, ImageFilterPreset.none);
    });

    test('no-op when filter is unchanged (does not consume undo)', () {
      final c = makeContainer();
      addImage(c);
      c
          .read(documentControllerProvider.notifier)
          .execute(
            const SetImageFilterCommand(
              layerId: 'img1',
              filterPreset: ImageFilterPreset.cool,
            ),
          );
      // Re-applying same filter should be a no-op (apply returns
      // the same doc → command framework drops the entry).
      c
          .read(documentControllerProvider.notifier)
          .execute(
            const SetImageFilterCommand(
              layerId: 'img1',
              filterPreset: ImageFilterPreset.cool,
            ),
          );
      c.read(documentControllerProvider.notifier).undo();
      // Single undo should restore none, not still be on cool.
      expect(readImage(c, 'img1').filterPreset, ImageFilterPreset.none);
    });

    test('filter preserved across other image commands', () {
      final c = makeContainer();
      addImage(c);
      c
          .read(documentControllerProvider.notifier)
          .execute(
            const SetImageFilterCommand(
              layerId: 'img1',
              filterPreset: ImageFilterPreset.dramatic,
            ),
          );
      // Mutating an unrelated field must not clobber the filter.
      c
          .read(documentControllerProvider.notifier)
          .execute(
            const SetImageMaskCommand(layerId: 'img1', mask: ImageMask.circle),
          );
      c
          .read(documentControllerProvider.notifier)
          .execute(const SetImageBorderCommand(layerId: 'img1', width: 4));
      c
          .read(documentControllerProvider.notifier)
          .execute(
            const SetImageAdjustmentsCommand(layerId: 'img1', brightness: 12),
          );
      expect(readImage(c, 'img1').filterPreset, ImageFilterPreset.dramatic);
    });

    test('JSON round-trip preserves the filter preset', () {
      final layer = ImageLayer(
        id: 'x',
        transform: LayerTransform(
          position: const Offset(0, 0),
          size: const Size(100, 100),
        ),
        source: const ImageSource.asset('a.png'),
        filterPreset: ImageFilterPreset.fade,
      );
      final json = layer.toJson();
      expect(json['filterPreset'], 'fade');
      final restored = ImageLayer.fromJson(json);
      expect(restored.filterPreset, ImageFilterPreset.fade);
    });

    test('JSON omits filterPreset when default (back-compat)', () {
      final layer = ImageLayer(
        id: 'x',
        transform: LayerTransform(
          position: const Offset(0, 0),
          size: const Size(100, 100),
        ),
        source: const ImageSource.asset('a.png'),
      );
      expect(layer.toJson().containsKey('filterPreset'), isFalse);
    });

    test('imageFilterMatrix returns null for none, non-null otherwise', () {
      expect(imageFilterMatrix(ImageFilterPreset.none), isNull);
      for (final p in ImageFilterPreset.values.where(
        (p) => p != ImageFilterPreset.none,
      )) {
        final m = imageFilterMatrix(p);
        expect(m, isNotNull, reason: 'matrix for $p');
        expect(m!.length, 20, reason: '4x5 matrix for $p');
      }
    });
  });
}
