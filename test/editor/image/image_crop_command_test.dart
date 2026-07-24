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

  ImageLayer? readImage(ProviderContainer c, String id) {
    final l = c
        .read(documentControllerProvider)
        .layers
        .where((l) => l.id == id)
        .toList();
    return l.isEmpty ? null : l.first as ImageLayer;
  }

  group('SetImageCropCommand', () {
    test('default cropRect is fullCrop', () {
      final c = makeContainer();
      addImage(c);
      expect(readImage(c, 'img1')!.cropRect, ImageLayer.fullCrop);
      expect(readImage(c, 'img1')!.isFullCrop, isTrue);
    });

    test('execute swaps cropRect on the layer', () {
      final c = makeContainer();
      addImage(c);
      final next = const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
      c
          .read(documentControllerProvider.notifier)
          .execute(SetImageCropCommand(layerId: 'img1', cropRect: next));
      expect(readImage(c, 'img1')!.cropRect, next);
      expect(readImage(c, 'img1')!.isFullCrop, isFalse);
    });

    test('clamps out-of-range edges into [0..1]', () {
      final c = makeContainer();
      addImage(c);
      c
          .read(documentControllerProvider.notifier)
          .execute(
            SetImageCropCommand(
              layerId: 'img1',
              cropRect: const Rect.fromLTRB(-0.5, -0.2, 1.4, 1.2),
            ),
          );
      expect(readImage(c, 'img1')!.cropRect, ImageLayer.fullCrop);
    });

    test('zero-area input snaps back to fullCrop', () {
      final c = makeContainer();
      addImage(c);
      c
          .read(documentControllerProvider.notifier)
          .execute(
            SetImageCropCommand(
              layerId: 'img1',
              cropRect: const Rect.fromLTRB(0.5, 0.5, 0.5, 0.5),
            ),
          );
      expect(readImage(c, 'img1')!.cropRect, ImageLayer.fullCrop);
    });

    test('undo restores the previous cropRect', () {
      final c = makeContainer();
      addImage(c);
      final r1 = const Rect.fromLTRB(0.0, 0.0, 0.6, 0.6);
      final r2 = const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8);
      c
          .read(documentControllerProvider.notifier)
          .execute(SetImageCropCommand(layerId: 'img1', cropRect: r1));
      c
          .read(documentControllerProvider.notifier)
          .execute(SetImageCropCommand(layerId: 'img1', cropRect: r2));
      expect(readImage(c, 'img1')!.cropRect, r2);
      c.read(documentControllerProvider.notifier).undo();
      expect(readImage(c, 'img1')!.cropRect, r1);
      c.read(documentControllerProvider.notifier).undo();
      expect(readImage(c, 'img1')!.cropRect, ImageLayer.fullCrop);
    });

    test(
      'preserves transform / fit / mask / border / shadow / adjustments',
      () {
        final c = makeContainer();
        addImage(c);
        final original = readImage(c, 'img1')!;
        c
            .read(documentControllerProvider.notifier)
            .execute(
              SetImageCropCommand(
                layerId: 'img1',
                cropRect: const Rect.fromLTRB(0.1, 0.2, 0.7, 0.8),
              ),
            );
        final next = readImage(c, 'img1')!;
        expect(next.transform.position, original.transform.position);
        expect(next.transform.size, original.transform.size);
        expect(next.fit, original.fit);
        expect(next.mask, original.mask);
        expect(next.borderColor, original.borderColor);
        expect(next.borderWidth, original.borderWidth);
        expect(next.shadowOpacity, original.shadowOpacity);
        expect(next.adjustments, original.adjustments);
      },
    );

    test('JSON round-trip preserves non-default cropRect', () {
      final c = makeContainer();
      addImage(c);
      const next = Rect.fromLTRB(0.15, 0.25, 0.85, 0.75);
      c
          .read(documentControllerProvider.notifier)
          .execute(SetImageCropCommand(layerId: 'img1', cropRect: next));
      final json = readImage(c, 'img1')!.toJson();
      final restored = ImageLayer.fromJson(json);
      expect(restored.cropRect, next);
      expect(restored.isFullCrop, isFalse);
    });

    test('Replace source resets cropRect to fullCrop', () {
      final c = makeContainer();
      addImage(c);
      c
          .read(documentControllerProvider.notifier)
          .execute(
            SetImageCropCommand(
              layerId: 'img1',
              cropRect: const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9),
            ),
          );
      expect(readImage(c, 'img1')!.isFullCrop, isFalse);
      c
          .read(documentControllerProvider.notifier)
          .execute(
            const ReplaceImageSourceCommand(
              layerId: 'img1',
              source: ImageSource.asset('assets/other.png'),
            ),
          );
      expect(readImage(c, 'img1')!.isFullCrop, isTrue);
    });
  });
}
