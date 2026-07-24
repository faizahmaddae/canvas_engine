import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/live_overlay_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for [LiveOverlay] + [LiveOverlayController] +
/// [renderedDocumentProvider]. Together they replace the historical
/// `DocumentController.liveReplace` pathway: in-flight gesture state
/// stages on the overlay, the canvas reads the merged view, and the
/// committed [documentControllerProvider] only ticks on real commits.
void main() {
  TextLayer textLayer({required String id, String content = 'hi'}) {
    return TextLayer(
      id: id,
      transform: LayerTransform(
        position: const Offset(10, 10),
        size: const Size(100, 40),
      ),
      content: content,
      style: const TextStyleSpec(),
    );
  }

  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    return c;
  }

  group('LiveOverlay.applyTo', () {
    test('returns the same doc instance when overlay is empty', () {
      final c = makeContainer();
      final doc = c.read(documentControllerProvider);
      // Identity equality matters for Riverpod listeners — an empty
      // overlay must not trigger spurious rebuilds.
      expect(identical(LiveOverlay.empty.applyTo(doc), doc), isTrue);
    });

    test('replacements substitute layers by id', () {
      final c = makeContainer();
      final original = textLayer(id: 'a', content: 'original');
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(original));
      final doc = c.read(documentControllerProvider);

      final preview = textLayer(id: 'a', content: 'preview');
      final overlay = LiveOverlay(replacements: {'a': preview});
      final merged = overlay.applyTo(doc);

      expect((merged.layerById('a')! as TextLayer).content, 'preview');
      // Committed doc untouched.
      expect((doc.layerById('a')! as TextLayer).content, 'original');
    });

    test('replacement against an unknown id is silently ignored', () {
      // Drag-handler fire-and-forget contract: a stale frame against
      // a just-removed layer must not resurrect a phantom.
      final c = makeContainer();
      final overlay = LiveOverlay(
        replacements: {'ghost': textLayer(id: 'ghost')},
      );
      final merged = overlay.applyTo(c.read(documentControllerProvider));
      expect(merged.layerById('ghost'), isNull);
    });

    test('additions append on top of committed layers in order', () {
      final c = makeContainer();
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(textLayer(id: 'committed')));
      final overlay = LiveOverlay(
        additions: [
          textLayer(id: 'add1'),
          textLayer(id: 'add2'),
        ],
      );
      final merged = overlay.applyTo(c.read(documentControllerProvider));
      expect(merged.layers.map((l) => l.id), ['committed', 'add1', 'add2']);
    });

    test('removals hide committed layers from the merged view', () {
      final c = makeContainer();
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(textLayer(id: 'a')));
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(textLayer(id: 'b')));
      final overlay = LiveOverlay(removals: {'a'});
      final merged = overlay.applyTo(c.read(documentControllerProvider));
      expect(merged.layers.map((l) => l.id), ['b']);
    });

    test('removal trumps a stale replacement of the same id', () {
      final c = makeContainer();
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(textLayer(id: 'a')));
      final overlay = LiveOverlay(
        replacements: {'a': textLayer(id: 'a', content: 'preview')},
        removals: {'a'},
      );
      final merged = overlay.applyTo(c.read(documentControllerProvider));
      expect(merged.layerById('a'), isNull);
    });
  });

  group('LiveOverlayController', () {
    test('replaceLayer publishes a new overlay identity', () {
      final c = makeContainer();
      final before = c.read(liveOverlayProvider);
      c.read(liveOverlayProvider.notifier).replaceLayer(textLayer(id: 'a'));
      final after = c.read(liveOverlayProvider);
      expect(identical(before, after), isFalse);
      expect(after.replacements, contains('a'));
    });

    test('addLayer appends to additions', () {
      final c = makeContainer();
      final ctrl = c.read(liveOverlayProvider.notifier);
      ctrl.addLayer(textLayer(id: 'a'));
      ctrl.addLayer(textLayer(id: 'b'));
      expect(c.read(liveOverlayProvider).additions.map((l) => l.id), [
        'a',
        'b',
      ]);
    });

    test('updateAddedLayer mutates an existing addition by id', () {
      final c = makeContainer();
      final ctrl = c.read(liveOverlayProvider.notifier);
      ctrl.addLayer(textLayer(id: 'a', content: 'first'));
      ctrl.updateAddedLayer(textLayer(id: 'a', content: 'second'));
      final additions = c.read(liveOverlayProvider).additions;
      expect(additions, hasLength(1));
      expect((additions.single as TextLayer).content, 'second');
    });

    test('updateAddedLayer is a no-op when the id is not staged', () {
      final c = makeContainer();
      c
          .read(liveOverlayProvider.notifier)
          .updateAddedLayer(textLayer(id: 'unknown'));
      expect(c.read(liveOverlayProvider).additions, isEmpty);
    });

    test('removeLayer adds the id to removals', () {
      final c = makeContainer();
      c.read(liveOverlayProvider.notifier).removeLayer('a');
      expect(c.read(liveOverlayProvider).removals, contains('a'));
    });

    test('clear returns to LiveOverlay.empty (identity equal when '
        'already empty)', () {
      final c = makeContainer();
      // Already-empty clear must not allocate a fresh instance, or
      // listeners would rebuild for nothing.
      final first = c.read(liveOverlayProvider);
      c.read(liveOverlayProvider.notifier).clear();
      expect(identical(first, c.read(liveOverlayProvider)), isTrue);

      // After a real mutation, clear publishes empty.
      c.read(liveOverlayProvider.notifier).addLayer(textLayer(id: 'a'));
      c.read(liveOverlayProvider.notifier).clear();
      expect(c.read(liveOverlayProvider).isEmpty, isTrue);
    });
  });

  group('renderedDocumentProvider', () {
    test('mirrors documentControllerProvider when overlay is empty', () {
      final c = makeContainer();
      expect(
        identical(
          c.read(documentControllerProvider),
          c.read(renderedDocumentProvider),
        ),
        isTrue,
      );
    });

    test('reflects an in-flight replacement WITHOUT mutating the '
        'committed doc', () {
      final c = makeContainer();
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(textLayer(id: 'a', content: 'committed')));
      final docBefore = c.read(documentControllerProvider);

      c
          .read(liveOverlayProvider.notifier)
          .replaceLayer(textLayer(id: 'a', content: 'preview'));

      // Committed instance is byte-for-byte unchanged.
      expect(identical(c.read(documentControllerProvider), docBefore), isTrue);
      // Merged view reflects the in-flight preview.
      expect(
        (c.read(renderedDocumentProvider).layerById('a')! as TextLayer).content,
        'preview',
      );
    });

    test('reflects a staged addition WITHOUT mutating the committed doc', () {
      final c = makeContainer();
      final docBefore = c.read(documentControllerProvider);
      c.read(liveOverlayProvider.notifier).addLayer(textLayer(id: 'staged'));
      expect(identical(c.read(documentControllerProvider), docBefore), isTrue);
      expect(c.read(renderedDocumentProvider).layerById('staged'), isNotNull);
    });

    test('clear() returns the merged view to the committed doc identity', () {
      final c = makeContainer();
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(textLayer(id: 'a')));
      final docCommitted = c.read(documentControllerProvider);

      c
          .read(liveOverlayProvider.notifier)
          .replaceLayer(textLayer(id: 'a', content: 'preview'));
      expect(
        identical(c.read(renderedDocumentProvider), docCommitted),
        isFalse,
      );

      c.read(liveOverlayProvider.notifier).clear();
      expect(identical(c.read(renderedDocumentProvider), docCommitted), isTrue);
    });
  });
}
