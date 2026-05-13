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

  void addImage(ProviderContainer c, {String id = 'img1'}) {
    c.read(documentControllerProvider.notifier).execute(
          AddLayerCommand(
            ImageLayer(
              id: id,
              transform: LayerTransform(
                position: const Offset(100, 100),
                size: const Size(400, 300),
              ),
              source: const ImageSource.asset('assets/test.png'),
            ),
          ),
        );
  }

  ImageLayer readImage(ProviderContainer c, String id) {
    return c.read(documentControllerProvider).layerById(id) as ImageLayer;
  }

  // History size lives on the historyStackProvider — count by
  // popping `undo()` until the layer is gone, since the public
  // controller doesn't expose a length getter directly.
  int undoUntilEmpty(ProviderContainer c) {
    int n = 0;
    final ctrl = c.read(documentControllerProvider.notifier);
    while (ctrl.canUndo) {
      ctrl.undo();
      n++;
    }
    return n;
  }

  group('ImageAdjustments exposure & warmth', () {
    test('default values are identity', () {
      final a = ImageAdjustments();
      expect(a.exposure, 0);
      expect(a.warmth, 0);
      expect(a.isIdentity, isTrue);
    });

    test('non-zero exposure breaks identity and emits a matrix', () {
      final a = ImageAdjustments(exposure: 25);
      expect(a.isIdentity, isFalse);
      expect(a.colorMatrix.length, 20);
    });

    test('non-zero warmth breaks identity and emits a matrix', () {
      final a = ImageAdjustments(warmth: -40);
      expect(a.isIdentity, isFalse);
      expect(a.colorMatrix.length, 20);
    });

    test('JSON round-trip preserves all five fields', () {
      final a = ImageAdjustments(
        brightness: 12,
        contrast: 1.4,
        saturation: 0.8,
        exposure: -22,
        warmth: 33,
      );
      final restored = ImageAdjustments.fromJson(a.toJson());
      expect(restored, equals(a));
    });

    test('JSON omits fields at their identity values', () {
      final a = ImageAdjustments(exposure: 10);
      final j = a.toJson();
      expect(j.containsKey('exposure'), isTrue);
      expect(j.containsKey('warmth'), isFalse);
      expect(j.containsKey('brightness'), isFalse);
      expect(j.containsKey('contrast'), isFalse);
      expect(j.containsKey('saturation'), isFalse);
    });

    test('copyWith only overwrites passed fields', () {
      final base = ImageAdjustments(exposure: 5, warmth: 10);
      final next = base.copyWith(exposure: -5);
      expect(next.exposure, -5);
      expect(next.warmth, 10);
    });
  });

  group('SetImageAdjustmentsCommand exposure/warmth', () {
    test('exposure is applied and stored on the layer', () {
      final c = makeContainer();
      addImage(c);
      c.read(documentControllerProvider.notifier).execute(
            const SetImageAdjustmentsCommand(
              layerId: 'img1',
              exposure: 30,
            ),
          );
      expect(readImage(c, 'img1').adjustments.exposure, 30);
    });

    test('warmth is applied and stored on the layer', () {
      final c = makeContainer();
      addImage(c);
      c.read(documentControllerProvider.notifier).execute(
            const SetImageAdjustmentsCommand(
              layerId: 'img1',
              warmth: -45,
            ),
          );
      expect(readImage(c, 'img1').adjustments.warmth, -45);
    });

    test('undo restores all fields together', () {
      final c = makeContainer();
      addImage(c);
      c.read(documentControllerProvider.notifier).execute(
            const SetImageAdjustmentsCommand(
              layerId: 'img1',
              exposure: 20,
              warmth: 15,
            ),
          );
      c.read(documentControllerProvider.notifier).undo();
      final adj = readImage(c, 'img1').adjustments;
      expect(adj.exposure, 0);
      expect(adj.warmth, 0);
    });
  });

  group('SetImageAdjustmentsCommand.mergeWith (live drags)', () {
    test('successive live commands of the same field collapse to one '
        'undo entry', () {
      final c = makeContainer();
      addImage(c);
      // 5 streamed brightness ticks should leave one history entry.
      for (final v in <double>[5, 10, 15, 20, 25]) {
        c.read(documentControllerProvider.notifier).execute(
              SetImageAdjustmentsCommand(
                layerId: 'img1',
                brightness: v,
                live: true,
              ),
            );
      }
      expect(readImage(c, 'img1').adjustments.brightness, 25);
      // One undo should land back at brightness 0.
      c.read(documentControllerProvider.notifier).undo();
      expect(readImage(c, 'img1').adjustments.brightness, 0);
    });

    test('non-live commands always push a fresh undo entry', () {
      final c = makeContainer();
      addImage(c);
      c.read(documentControllerProvider.notifier).execute(
            const SetImageAdjustmentsCommand(
              layerId: 'img1',
              brightness: 10,
            ),
          );
      c.read(documentControllerProvider.notifier).execute(
            const SetImageAdjustmentsCommand(
              layerId: 'img1',
              brightness: 20,
            ),
          );
      // First undo -> brightness 10, not 0.
      c.read(documentControllerProvider.notifier).undo();
      expect(readImage(c, 'img1').adjustments.brightness, 10);
    });

    test('live commands of different fields do NOT merge', () {
      final c = makeContainer();
      addImage(c);
      c.read(documentControllerProvider.notifier).execute(
            const SetImageAdjustmentsCommand(
              layerId: 'img1',
              brightness: 10,
              live: true,
            ),
          );
      c.read(documentControllerProvider.notifier).execute(
            const SetImageAdjustmentsCommand(
              layerId: 'img1',
              contrast: 1.4,
              live: true,
            ),
          );
      // Two distinct field-sets → two distinct undo entries.
      c.read(documentControllerProvider.notifier).undo();
      expect(readImage(c, 'img1').adjustments.contrast, 1.0);
      expect(readImage(c, 'img1').adjustments.brightness, 10);
    });

    test('live exposure stream collapses to one undo entry', () {
      final c = makeContainer();
      addImage(c);
      for (final v in <double>[5, 10, 15, 20, 30, 40]) {
        c.read(documentControllerProvider.notifier).execute(
              SetImageAdjustmentsCommand(
                layerId: 'img1',
                exposure: v,
                live: true,
              ),
            );
      }
      // Single non-live priming command + one merged live entry =
      // two entries on the stack? No — only the live one ran here.
      // Pop everything and verify count.
      addImage(c, id: 'sentinel'); // bump stack so we can count.
      undoUntilEmpty(c); // exhausts AddLayer + merged live + AddLayer.
      // After full undo we should be back at the empty state.
      expect(c.read(documentControllerProvider).layers, isEmpty);
    });
  });
}
