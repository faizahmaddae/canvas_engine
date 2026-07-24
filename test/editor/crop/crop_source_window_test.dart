// Crop v2 (roadmap 4.10): the crop frame is a NON-DESTRUCTIVE window
// into the source bitmap.
//
// The pre-v2 frame was confined to whatever the layer was displaying
// at the time, so a cover fit's clipped strip — and, after a commit,
// anything the committed window excluded — was unreachable without
// undoing. These tests pin the two halves of the fix:
//
//   * [CropSession.draftBounds] opens the frame onto the WHOLE source
//     (still expressed in the display-space draft coordinates the
//     commit math and the existing crop suites are written in), and
//   * a crop can therefore be widened back out on re-entry until the
//     layer shows the entire bitmap again.
//
// Geometry used throughout: layer box 800x400 (aspect 2) over a
// SQUARE source (aspect 1). A cover fit shows the source's centred
// vertical strip LTWH(0, 0.25, 1, 0.5); the top and bottom quarters
// of the bitmap are hidden.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/crop/application/crop_controller.dart';
import 'package:canvas_engine/features/editor/crop/presentation/crop_mode_overlay.dart';
import 'package:canvas_engine/features/editor/engine/commands/image_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;

  ImageLayer readLayer() =>
      container.read(documentControllerProvider).layerById('img1')!
          as ImageLayer;

  CropController ctrl() => container.read(cropControllerProvider.notifier);
  CropSession session() => container.read(cropControllerProvider);

  setUp(() {
    container = ProviderContainer();
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 1000, height: 1000);
    container
        .read(documentControllerProvider.notifier)
        .execute(
          AddLayerCommand(
            ImageLayer(
              id: 'img1',
              transform: LayerTransform(
                position: Offset.zero,
                size: const Size(800, 400),
              ),
              source: const ImageSource.asset('assets/test.png'),
            ),
          ),
        );
  });

  tearDown(() => container.dispose());

  group('displayBasisFor', () {
    test('cover reports the strip the box actually shows', () {
      final basis = CropController.displayBasisFor(
        fit: BoxFit.cover,
        boxSize: const Size(800, 400),
        sourceAspect: 1.0,
      );
      expect(basis.left, closeTo(0, 1e-9));
      expect(basis.top, closeTo(0.25, 1e-9));
      expect(basis.width, closeTo(1, 1e-9));
      expect(basis.height, closeTo(0.5, 1e-9));
    });

    test('fill maps the whole source onto the box', () {
      expect(
        CropController.displayBasisFor(
          fit: BoxFit.fill,
          boxSize: const Size(800, 400),
          sourceAspect: 1.0,
        ),
        ImageLayer.fullCrop,
      );
    });

    test('an unresolved source aspect collapses onto display space', () {
      // The legacy commit path's precondition — draft space and
      // source space coincide, so nothing about the old behaviour
      // changes for a layer whose bytes never resolve.
      expect(
        CropController.displayBasisFor(
          fit: BoxFit.cover,
          boxSize: const Size(800, 400),
          sourceAspect: null,
        ),
        ImageLayer.fullCrop,
      );
    });
  });

  group('draftBounds', () {
    test('is the unit box until the source aspect resolves', () {
      ctrl().openCrop('img1');
      expect(session().draftBounds, ImageLayer.fullCrop);
    });

    test('opens onto the pixels a cover fit is hiding', () {
      ctrl().openCrop('img1');
      ctrl().setSourceAspect(1.0);
      final b = session().draftBounds;
      // The strip is half the source tall, centred: one strip-height
      // of slack above and below.
      expect(b.left, closeTo(0, 1e-9));
      expect(b.right, closeTo(1, 1e-9));
      expect(b.top, closeTo(-0.5, 1e-9));
      expect(b.bottom, closeTo(1.5, 1e-9));
    });

    test('a frame dragged past the strip survives the clamp and commits '
        'source pixels the layer never displayed', () {
      ctrl().openCrop('img1');
      ctrl().setSourceAspect(1.0);
      // The source's TOP half — entirely outside the cover strip.
      ctrl().updateDraft(const Rect.fromLTRB(0, -0.5, 1, 0.5));
      expect(session().draftCrop.top, closeTo(-0.5, 1e-9));
      ctrl().commitCrop();

      final l = readLayer();
      expect(l.fit, BoxFit.fill);
      expect(l.cropRect.left, closeTo(0, 1e-6));
      expect(l.cropRect.top, closeTo(0, 1e-6));
      expect(l.cropRect.width, closeTo(1, 1e-6));
      expect(l.cropRect.height, closeTo(0.5, 1e-6));
      // A 1.0 x 0.5 window of a square source is 2:1 in pixels — the
      // box must match it or the commit would deform the image.
      expect(l.transform.size.width, closeTo(800, 1e-6));
      expect(l.transform.size.height, closeTo(400, 1e-6));
    });
  });

  group('non-destructive round trip', () {
    test('a committed crop can be widened back to the whole source', () {
      // 1. Crop to the left half of what the layer displays.
      ctrl().openCrop('img1');
      ctrl().setSourceAspect(1.0);
      ctrl().updateDraft(const Rect.fromLTRB(0, 0, 0.5, 1));
      ctrl().commitCrop();
      final cropped = readLayer();
      expect(cropped.fit, BoxFit.fill);
      expect(cropped.transform.size, const Size(400, 400));

      // 2. Re-enter: the draft is seeded to the committed window and
      //    its basis is now the full source, so the frame can reach
      //    every pixel — including the strip's discarded right half
      //    AND the quarters the original cover fit clipped.
      ctrl().openCrop('img1');
      ctrl().setSourceAspect(1.0);
      expect(session().draftCrop.left, closeTo(0, 1e-6));
      expect(session().draftCrop.top, closeTo(0.25, 1e-6));
      expect(session().draftCrop.right, closeTo(0.5, 1e-6));
      expect(session().draftCrop.bottom, closeTo(0.75, 1e-6));
      expect(session().draftBounds, ImageLayer.fullCrop);

      // 3. Widen to everything and commit.
      ctrl().resetCrop();
      ctrl().commitCrop();
      final restored = readLayer();
      expect(restored.cropRect, ImageLayer.fullCrop);
      // Square source, square box: every pixel back, undistorted.
      expect(restored.transform.size.width, closeTo(800, 1e-6));
      expect(restored.transform.size.height, closeTo(800, 1e-6));
    });

    test('Restore image reaches the whole source, not just the window', () {
      ctrl().openCrop('img1');
      ctrl().setSourceAspect(1.0);
      ctrl().updateDraft(const Rect.fromLTRB(0.2, 0.2, 0.6, 0.6));
      ctrl().resetCrop();
      expect(session().draftCrop, session().draftBounds);
      expect(session().draftCrop.top, closeTo(-0.5, 1e-9));
    });

    test('aspect presets may claim hidden pixels', () {
      ctrl().openCrop('img1');
      ctrl().setSourceAspect(1.0);
      // 1:1 in image pixels is 0.5 x 1.0 in the strip's own units, so
      // it fits inside the strip; 9:16 is taller than the strip and
      // must be allowed to grow past it rather than shrink to fit.
      ctrl().setAspectRatio(9 / 16);
      final r = session().draftCrop;
      expect(r.top, lessThan(0));
      expect(r.bottom, greaterThan(1));
    });
  });

  group('preview Look', () {
    test('lookMatrixOf is null only when the layer has no Look', () {
      final plain = readLayer();
      expect(lookMatrixOf(plain), isNull);

      final filtered = plain.copyAll(filterPreset: ImageFilterPreset.vintage);
      expect(lookMatrixOf(filtered), isNotNull);

      final adjusted = plain.copyAll(
        effects: EffectStack(const [BrightnessEffect(amount: 0.4)]),
      );
      expect(lookMatrixOf(adjusted), isNotNull);

      // Both present: one composed matrix, not two passes.
      final both = adjusted.copyAll(filterPreset: ImageFilterPreset.vintage);
      expect(lookMatrixOf(both), hasLength(20));
    });

    testWidgets('the crop preview renders the source through that Look', (
      tester,
    ) async {
      container
          .read(documentControllerProvider.notifier)
          .execute(
            const SetImageFilterCommand(
              layerId: 'img1',
              filterPreset: ImageFilterPreset.dramatic,
            ),
          );
      ctrl().openCrop('img1');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CropModeOverlay()),
        ),
      );
      await tester.pump();
      expect(find.byType(ColorFiltered), findsOneWidget);
    });

    testWidgets('and skips the filter entirely when there is no Look', (
      tester,
    ) async {
      ctrl().openCrop('img1');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CropModeOverlay()),
        ),
      );
      await tester.pump();
      expect(find.byType(ColorFiltered), findsNothing);
    });
  });
}
