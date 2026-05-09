// Visual selection chrome must be suppressed for the protected
// base photo of a photo project. Tested at the resolver/state
// layer (a real widget test would require pumping the entire
// editor); the production code wires these signals through
// `EditorDocument.isProtectedBasePhoto(id)`.

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
  ProviderContainer makePhotoProject({String id = 'photo'}) {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final ctrl = c.read(documentControllerProvider.notifier);
    ctrl.newDocument(width: 800, height: 600, kind: ProjectKind.photo);
    ctrl.execute(
      CompositeCommand(
        [
          AddLayerCommand(ImageLayer(
            id: id,
            transform: LayerTransform(
              position: Offset.zero,
              size: const Size(800, 600),
            ),
            source: const ImageSource.asset('a.png'),
            locked: true,
          )),
          SetBasePhotoCommand(id),
        ],
        labelOverride: 'Import photo',
      ),
    );
    ctrl.clearHistory();
    // Mirror the home Import flow: NO auto-select.
    return c;
  }

  ProviderContainer makeDesignProject() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c
        .read(documentControllerProvider.notifier)
        .newDocument(width: 1080, height: 1080);
    return c;
  }

  group('protected base photo', () {
    test('photo import leaves selection EMPTY (no object chrome)', () {
      final c = makePhotoProject();
      // Imported state mirrors what the home flow seeds.
      expect(c.read(selectionControllerProvider).selectedId, isNull);
      expect(c.read(documentControllerProvider).basePhotoLayerId, 'photo');
    });

    test('isProtectedBasePhoto identifies the photo-project base layer',
        () {
      final c = makePhotoProject();
      final doc = c.read(documentControllerProvider);
      expect(doc.isProtectedBasePhoto('photo'), isTrue);
      expect(doc.isProtectedBasePhoto('does-not-exist'), isFalse);
    });

    test('design-project image layer is NEVER protected', () {
      final c = makeDesignProject();
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(ImageLayer(
            id: 'i',
            transform: LayerTransform(
              position: Offset.zero,
              size: const Size(400, 300),
            ),
            source: const ImageSource.asset('a.png'),
          )));
      final doc = c.read(documentControllerProvider);
      expect(doc.projectKind, ProjectKind.design);
      expect(doc.isProtectedBasePhoto('i'), isFalse);
    });

    test('Crop/Filters/Adjust resolve base photo with NO selection', () {
      final c = makePhotoProject();
      final doc = c.read(documentControllerProvider);
      final outcome = resolveImageTarget(doc, selectedId: null);
      // Single image present -> auto-select to the base photo.
      expect(outcome, isA<ImageTargetAutoSelect>());
      expect(
        (outcome as ImageTargetAutoSelect).layer.id,
        'photo',
      );
    });

    test('Crop resolves base photo even when an overlay is selected '
        '(via basePhotoLayerId fallback when overlay is non-image)', () {
      final c = makePhotoProject();
      // Add a shape overlay and select it: resolver should still
      // fall through to the base photo because the selection is
      // not an ImageLayer.
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(ShapeLayer(
            id: 's',
            transform: LayerTransform(
              position: Offset.zero,
              size: const Size(50, 50),
            ),
            kind: ShapeKind.rectangle,
            fillColor: const Color(0xFFFFFFFF),
          )));
      c.read(selectionControllerProvider.notifier).select('s');
      final doc = c.read(documentControllerProvider);
      final outcome =
          resolveImageTarget(doc, selectedId: 's');
      // Only one image (the photo) -> auto-select to it.
      expect(outcome, isA<ImageTargetAutoSelect>());
      expect((outcome as ImageTargetAutoSelect).layer.id, 'photo');
    });

    test('selecting an overlay layer is NOT protected (normal chrome)',
        () {
      final c = makePhotoProject();
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(ShapeLayer(
            id: 's',
            transform: LayerTransform(
              position: Offset.zero,
              size: const Size(50, 50),
            ),
            kind: ShapeKind.rectangle,
            fillColor: const Color(0xFFFFFFFF),
          )));
      c.read(selectionControllerProvider.notifier).select('s');
      final doc = c.read(documentControllerProvider);
      expect(doc.isProtectedBasePhoto('s'), isFalse);
    });
  });
}
