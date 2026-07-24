import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/crop/application/crop_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/image_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the centralised [CropController] / [CropSession].
///
/// Covers:
///   * open/cancel/commit lifecycle
///   * draft-only mutation (document untouched until commit)
///   * setAspectRatio shrinks centred inside the current draft
///   * resetCrop returns the draft to fullCrop without committing
///   * sanitise clamps to [0..1] and enforces minNorm
///   * commit dispatches a single SetImageCropCommand and is undoable
///   * commit on a non-image / missing layer is a safe no-op
void main() {
  late ProviderContainer container;
  late ImageLayer layer;

  setUp(() {
    container = ProviderContainer();
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 1000, height: 1000);
    layer = ImageLayer(
      id: 'img1',
      transform: LayerTransform(
        position: const Offset(0, 0),
        size: const Size(800, 400), // wide image, aspect 2.0
      ),
      source: const ImageSource.asset('assets/test.png'),
    );
    container
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(layer));
  });

  tearDown(() => container.dispose());

  ImageLayer readLayer() {
    final l = container
        .read(documentControllerProvider)
        .layers
        .firstWhere((l) => l.id == 'img1');
    return l as ImageLayer;
  }

  group('lifecycle', () {
    test('initial state is inactive', () {
      final s = container.read(cropControllerProvider);
      expect(s.active, isFalse);
      expect(s.layerId, isNull);
      expect(s.draftCrop, ImageLayer.fullCrop);
    });

    test('openCrop seeds draft from current layer cropRect', () {
      container
          .read(documentControllerProvider.notifier)
          .execute(
            const SetImageCropCommand(
              layerId: 'img1',
              cropRect: Rect.fromLTRB(0.1, 0.2, 0.9, 0.8),
            ),
          );
      container.read(cropControllerProvider.notifier).openCrop('img1');
      final s = container.read(cropControllerProvider);
      expect(s.active, isTrue);
      expect(s.layerId, 'img1');
      expect(s.draftCrop, const Rect.fromLTRB(0.1, 0.2, 0.9, 0.8));
      expect(s.aspectRatio, isNull);
      expect(s.originalAspect, closeTo(2.0, 1e-6));
    });

    test('cancelCrop closes session without committing', () {
      container.read(cropControllerProvider.notifier).openCrop('img1');
      container
          .read(cropControllerProvider.notifier)
          .updateDraft(const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8));
      container.read(cropControllerProvider.notifier).cancelCrop();
      expect(container.read(cropControllerProvider).active, isFalse);
      expect(readLayer().cropRect, ImageLayer.fullCrop);
    });

    test('cancelCrop restores the previous image crop state', () {
      const original = Rect.fromLTRB(0.1, 0.2, 0.9, 0.8);
      container
          .read(documentControllerProvider.notifier)
          .execute(
            const SetImageCropCommand(layerId: 'img1', cropRect: original),
          );

      container.read(cropControllerProvider.notifier).openCrop('img1');
      container
          .read(cropControllerProvider.notifier)
          .updateDraft(const Rect.fromLTRB(0.2, 0.2, 0.7, 0.7));
      container.read(cropControllerProvider.notifier).cancelCrop();

      expect(container.read(cropControllerProvider).active, isFalse);
      expect(readLayer().cropRect, original);
      expect(readLayer().transform.size, const Size(800, 400));
    });

    test('openCrop on non-image layer leaves session inactive', () {
      container
          .read(cropControllerProvider.notifier)
          .openCrop('does-not-exist');
      expect(container.read(cropControllerProvider).active, isFalse);
    });
  });

  group('aspect ratio', () {
    // Layer is 800×400 → layerAspect = 2.0.
    // Aspect presets are interpreted in **image-pixel space** so a
    // pixel-square (1:1) on this wide layer = 0.5 wide × 1.0 tall in
    // normalised space, centred on (0.5, 0.5).
    Rect expected(double aspect, {double layerAspect = 2.0}) {
      return CropController.fitAspect(
        bounds: ImageLayer.fullCrop,
        aspect: aspect,
        layerAspect: layerAspect,
      );
    }

    test('Original (= layerAspect) returns fullCrop on a wide layer', () {
      container.read(cropControllerProvider.notifier).openCrop('img1');
      container.read(cropControllerProvider.notifier).setAspectRatio(2.0);
      expect(
        container.read(cropControllerProvider).draftCrop,
        ImageLayer.fullCrop,
      );
    });

    test('1:1 on a 2:1 layer = centred 0.5×1.0 normalised rect', () {
      container.read(cropControllerProvider.notifier).openCrop('img1');
      container.read(cropControllerProvider.notifier).setAspectRatio(1.0);
      final r = container.read(cropControllerProvider).draftCrop;
      expect(r.width, closeTo(0.5, 1e-6));
      expect(r.height, closeTo(1.0, 1e-6));
      expect(r.center.dx, closeTo(0.5, 1e-6));
      expect(r.center.dy, closeTo(0.5, 1e-6));
    });

    test('aspect presets are deterministic & idempotent (×10)', () {
      container.read(cropControllerProvider.notifier).openCrop('img1');
      for (final aspect in <double>[2.0, 1.0, 4 / 5, 5 / 4, 16 / 9, 9 / 16]) {
        Rect? prev;
        for (var i = 0; i < 10; i++) {
          container
              .read(cropControllerProvider.notifier)
              .setAspectRatio(aspect);
          final r = container.read(cropControllerProvider).draftCrop;
          if (prev != null) expect(r, prev);
          prev = r;
        }
        // And matches the pure helper output.
        expect(prev, expected(aspect));
      }
    });

    test('cycling Original → 1:1 → Original → 4:5 … never shrinks', () {
      container.read(cropControllerProvider.notifier).openCrop('img1');
      const cycle = <double>[2.0, 1.0, 2.0, 4 / 5, 2.0, 16 / 9, 2.0];
      Rect? lastOriginal;
      for (final a in cycle) {
        container.read(cropControllerProvider.notifier).setAspectRatio(a);
        final r = container.read(cropControllerProvider).draftCrop;
        if (a == 2.0) {
          // Every Original must land back on fullCrop.
          expect(r, ImageLayer.fullCrop);
          lastOriginal = r;
        }
      }
      expect(lastOriginal, ImageLayer.fullCrop);
    });

    test('cycling all presets 20× lands on deterministic values', () {
      container.read(cropControllerProvider.notifier).openCrop('img1');
      const presets = <double>[2.0, 1.0, 4 / 5, 5 / 4, 16 / 9, 9 / 16];
      for (var iter = 0; iter < 20; iter++) {
        for (final a in presets) {
          container.read(cropControllerProvider.notifier).setAspectRatio(a);
          expect(container.read(cropControllerProvider).draftCrop, expected(a));
        }
      }
    });

    test('manual crop then 1:1 returns deterministic centred 1:1', () {
      container.read(cropControllerProvider.notifier).openCrop('img1');
      container
          .read(cropControllerProvider.notifier)
          .updateDraft(const Rect.fromLTRB(0.05, 0.05, 0.4, 0.4));
      container.read(cropControllerProvider.notifier).setAspectRatio(1.0);
      expect(container.read(cropControllerProvider).draftCrop, expected(1.0));
    });

    test('manual crop then 4:5 returns deterministic centred 4:5', () {
      container.read(cropControllerProvider.notifier).openCrop('img1');
      container
          .read(cropControllerProvider.notifier)
          .updateDraft(const Rect.fromLTRB(0.1, 0.6, 0.3, 0.8));
      container.read(cropControllerProvider.notifier).setAspectRatio(4 / 5);
      expect(container.read(cropControllerProvider).draftCrop, expected(4 / 5));
    });

    test('Free preserves current cropRect and clears lock only', () {
      container.read(cropControllerProvider.notifier).openCrop('img1');
      const manual = Rect.fromLTRB(0.2, 0.2, 0.8, 0.6);
      container.read(cropControllerProvider.notifier).updateDraft(manual);
      container.read(cropControllerProvider.notifier).setAspectRatio(1.0);
      container.read(cropControllerProvider.notifier).updateDraft(manual);
      container.read(cropControllerProvider.notifier).setAspectRatio(null);
      final s = container.read(cropControllerProvider);
      expect(s.aspectRatio, isNull);
      expect(s.draftCrop, manual);
    });

    test('setAspectRatio does NOT mutate the document', () {
      container.read(cropControllerProvider.notifier).openCrop('img1');
      container.read(cropControllerProvider.notifier).setAspectRatio(1.0);
      container.read(cropControllerProvider.notifier).setAspectRatio(16 / 9);
      expect(readLayer().cropRect, ImageLayer.fullCrop);
    });
  });

  group('reset', () {
    test('resetCrop sets draft to fullCrop and clears aspect', () {
      container.read(cropControllerProvider.notifier).openCrop('img1');
      container.read(cropControllerProvider.notifier).setAspectRatio(1.0);
      container
          .read(cropControllerProvider.notifier)
          .updateDraft(const Rect.fromLTRB(0.3, 0.3, 0.7, 0.7));
      container.read(cropControllerProvider.notifier).resetCrop();
      final s = container.read(cropControllerProvider);
      expect(s.draftCrop, ImageLayer.fullCrop);
      expect(s.aspectRatio, isNull);
      // Document untouched.
      expect(readLayer().cropRect, ImageLayer.fullCrop);
    });

    test('reset after every preset returns fullCrop', () {
      container.read(cropControllerProvider.notifier).openCrop('img1');
      for (final a in <double>[1.0, 4 / 5, 5 / 4, 16 / 9, 9 / 16, 2.0]) {
        container.read(cropControllerProvider.notifier).setAspectRatio(a);
        container.read(cropControllerProvider.notifier).resetCrop();
        final s = container.read(cropControllerProvider);
        expect(s.draftCrop, ImageLayer.fullCrop);
        expect(s.aspectRatio, isNull);
      }
    });

    test('reset after manual drag returns fullCrop', () {
      container.read(cropControllerProvider.notifier).openCrop('img1');
      container
          .read(cropControllerProvider.notifier)
          .updateDraft(const Rect.fromLTRB(0.1, 0.1, 0.4, 0.4));
      container.read(cropControllerProvider.notifier).resetCrop();
      expect(
        container.read(cropControllerProvider).draftCrop,
        ImageLayer.fullCrop,
      );
    });
  });

  group('sanitise', () {
    test('clamps out-of-range edges into [0..1]', () {
      final r = CropController.sanitise(
        const Rect.fromLTRB(-0.2, -0.5, 1.5, 2.0),
      );
      expect(r.left, 0.0);
      expect(r.top, 0.0);
      expect(r.right, 1.0);
      expect(r.bottom, 1.0);
    });

    test('enforces minNorm on degenerate rects', () {
      final r = CropController.sanitise(
        const Rect.fromLTRB(0.5, 0.5, 0.5, 0.5),
      );
      expect(r.width, greaterThanOrEqualTo(CropController.minNorm - 1e-9));
      expect(r.height, greaterThanOrEqualTo(CropController.minNorm - 1e-9));
    });
  });

  group('commit', () {
    test('reshapes layer to cropped pixel rect and resets cropRect', () {
      // Layer 800x400 → committing a (0.1, 0.2, 0.9, 0.8) draft
      // bakes the crop into transform.size (640 x 240) and resets
      // cropRect to full so the renderer no longer scales pixels
      // anisotropically.
      container.read(cropControllerProvider.notifier).openCrop('img1');
      container
          .read(cropControllerProvider.notifier)
          .updateDraft(const Rect.fromLTRB(0.1, 0.2, 0.9, 0.8));
      container.read(cropControllerProvider.notifier).commitCrop();
      expect(container.read(cropControllerProvider).active, isFalse);
      final l = readLayer();
      expect(l.cropRect, ImageLayer.fullCrop);
      expect(l.transform.size.width, closeTo(640, 1e-6));
      expect(l.transform.size.height, closeTo(240, 1e-6));
      // Design project: layer position shifts to keep the cropped
      // region anchored where the user saw it.
      expect(l.transform.position.dx, closeTo(80, 1e-6));
      expect(l.transform.position.dy, closeTo(80, 1e-6));
    });

    test('no-op commit (draft == current) skips the command', () {
      container.read(cropControllerProvider.notifier).openCrop('img1');
      container.read(cropControllerProvider.notifier).commitCrop();
      // Undo stack should still be empty (only AddLayerCommand from setUp).
      final doc = container.read(documentControllerProvider.notifier);
      doc.undo(); // pops AddLayerCommand
      // After undoing AddLayerCommand the layer is gone.
      expect(
        container
            .read(documentControllerProvider)
            .layers
            .where((l) => l.id == 'img1'),
        isEmpty,
      );
    });

    test('committed crop is undoable in one step', () {
      final originalSize = readLayer().transform.size;
      container.read(cropControllerProvider.notifier).openCrop('img1');
      container
          .read(cropControllerProvider.notifier)
          .updateDraft(const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8));
      container.read(cropControllerProvider.notifier).commitCrop();
      expect(readLayer().cropRect, ImageLayer.fullCrop);
      expect(readLayer().transform.size, isNot(originalSize));
      container.read(documentControllerProvider.notifier).undo();
      expect(readLayer().cropRect, ImageLayer.fullCrop);
      expect(readLayer().transform.size, originalSize);
    });

    test('re-opening Crop on a previously-cropped layer + Done with no '
        'changes does NOT push a redundant history entry', () {
      // First, real crop -> bakes into transform.size & resets cropRect.
      container.read(cropControllerProvider.notifier).openCrop('img1');
      container
          .read(cropControllerProvider.notifier)
          .updateDraft(const Rect.fromLTRB(0.1, 0.2, 0.9, 0.8));
      container.read(cropControllerProvider.notifier).commitCrop();
      final sizeAfter = readLayer().transform.size;
      // Now re-open + Done with no drag. cropRect was reset to full
      // post-commit so the no-op short-circuit must fire.
      container.read(cropControllerProvider.notifier).openCrop('img1');
      container.read(cropControllerProvider.notifier).commitCrop();
      // Single undo restores the pre-crop state; the redundant
      // re-open/Done must NOT add a second history entry.
      container.read(documentControllerProvider.notifier).undo();
      expect(readLayer().transform.size, isNot(sizeAfter));
      expect(readLayer().transform.size, const Size(800, 400));
    });
  });

  group('commit (source-window path)', () {
    // With the source aspect known (reported by the overlay), commit
    // converts the display-space draft into a persistent SOURCE
    // window: fit flips to fill and cropRect carries the window, so
    // the renderer reproduces exactly the chosen pixels at the new
    // box aspect. Regression tests for the old behavior that reset
    // cropRect to full and re-derived pixels through a cover fit —
    // recentring off-centre crops and zooming inset crops back out.
    //
    // Geometry used throughout: layer box 800x400 (aspect 2), SQUARE
    // source (aspect 1) → the cover display shows the source's
    // centred vertical strip LTWH(0, 0.25, 1, 0.5).

    CropController ctrl() => container.read(cropControllerProvider.notifier);

    test('off-centre draft commits the drafted region, left-anchored', () {
      ctrl().openCrop('img1');
      ctrl().setSourceAspect(1.0);
      // Left half of the display — the case cover recentres.
      ctrl().updateDraft(const Rect.fromLTRB(0, 0, 0.5, 1));
      ctrl().commitCrop();

      final l = readLayer();
      expect(l.fit, BoxFit.fill);
      expect(l.cropRect.left, closeTo(0, 1e-6));
      expect(l.cropRect.top, closeTo(0.25, 1e-6));
      expect(l.cropRect.width, closeTo(0.5, 1e-6));
      expect(l.cropRect.height, closeTo(0.5, 1e-6));
      expect(l.transform.size.width, closeTo(400, 1e-6));
      expect(l.transform.size.height, closeTo(400, 1e-6));
      expect(l.transform.position.dx, closeTo(0, 1e-6));
      expect(l.transform.position.dy, closeTo(0, 1e-6));
    });

    test('inset draft maps into the cover strip; box math matches the '
        'display', () {
      ctrl().openCrop('img1');
      ctrl().setSourceAspect(1.0);
      ctrl().updateDraft(const Rect.fromLTRB(0.1, 0.2, 0.9, 0.8));
      ctrl().commitCrop();

      final l = readLayer();
      expect(l.fit, BoxFit.fill);
      // Strip LTWH(0,0.25,1,0.5) ∘ draft LTWH(0.1,0.2,0.8,0.6).
      expect(l.cropRect.left, closeTo(0.1, 1e-6));
      expect(l.cropRect.top, closeTo(0.35, 1e-6));
      expect(l.cropRect.width, closeTo(0.8, 1e-6));
      expect(l.cropRect.height, closeTo(0.3, 1e-6));
      // On-canvas box identical to the legacy math (display-space).
      expect(l.transform.size.width, closeTo(640, 1e-6));
      expect(l.transform.size.height, closeTo(240, 1e-6));
      expect(l.transform.position.dx, closeTo(80, 1e-6));
      expect(l.transform.position.dy, closeTo(80, 1e-6));
    });

    test('single undo restores fit, cropRect and transform', () {
      ctrl().openCrop('img1');
      ctrl().setSourceAspect(1.0);
      ctrl().updateDraft(const Rect.fromLTRB(0, 0, 0.5, 1));
      ctrl().commitCrop();
      container.read(documentControllerProvider.notifier).undo();

      final l = readLayer();
      expect(l.fit, BoxFit.cover);
      expect(l.cropRect, ImageLayer.fullCrop);
      expect(l.transform.size, const Size(800, 400));
      expect(l.transform.position, Offset.zero);
    });

    test('re-crop of a fill layer: Done without dragging is a no-op; '
        'a narrowed draft re-windows the source directly', () {
      // First crop → fill layer with window LTWH(0.1,0.35,0.8,0.3).
      ctrl().openCrop('img1');
      ctrl().setSourceAspect(1.0);
      ctrl().updateDraft(const Rect.fromLTRB(0.1, 0.2, 0.9, 0.8));
      ctrl().commitCrop();

      // Done-with-no-drag: seeded draft == cropRect → no history entry.
      ctrl().openCrop('img1');
      ctrl().setSourceAspect(1.0);
      ctrl().commitCrop();
      final afterNoop = readLayer();
      expect(afterNoop.transform.size.width, closeTo(640, 1e-6));
      // One undo jumps past the (absent) no-op straight to pre-crop.
      container.read(documentControllerProvider.notifier).undo();
      expect(readLayer().transform.size, const Size(800, 400));
      container.read(documentControllerProvider.notifier).redo();

      // Narrow to the left half of the current window. The draft's
      // basis for a fill layer is the FULL source.
      ctrl().openCrop('img1');
      ctrl().setSourceAspect(1.0);
      ctrl().updateDraft(const Rect.fromLTRB(0.1, 0.35, 0.5, 0.65));
      ctrl().commitCrop();
      final l = readLayer();
      expect(l.fit, BoxFit.fill);
      expect(l.cropRect.left, closeTo(0.1, 1e-6));
      expect(l.cropRect.top, closeTo(0.35, 1e-6));
      expect(l.cropRect.width, closeTo(0.4, 1e-6));
      expect(l.cropRect.height, closeTo(0.3, 1e-6));
      // Scale reference is the previous window: 0.4/0.8 × 640 = 320.
      expect(l.transform.size.width, closeTo(320, 1e-6));
      expect(l.transform.size.height, closeTo(240, 1e-6));
      expect(l.transform.position.dx, closeTo(80, 1e-6));
      expect(l.transform.position.dy, closeTo(80, 1e-6));
    });

    test('without a resolved source aspect commit falls back to the '
        'legacy reshape', () {
      ctrl().openCrop('img1');
      ctrl().updateDraft(const Rect.fromLTRB(0, 0, 0.5, 1));
      ctrl().commitCrop();
      final l = readLayer();
      expect(l.fit, BoxFit.cover);
      expect(l.cropRect, ImageLayer.fullCrop);
      expect(l.transform.size.width, closeTo(400, 1e-6));
    });
  });

  group('handles', () {
    // Pure resize math. Driven directly by gesture deltas; the
    // overlay just maps its private handle enum onto these.

    test('top edge drag (no aspect) shrinks height only, keeps width', () {
      const start = Rect.fromLTRB(0.1, 0.2, 0.9, 0.8);
      final next = CropController.resize(
        start,
        handle: CropHandle.t,
        dx: 0.0,
        dy: 0.1,
      );
      expect(next.left, closeTo(0.1, 1e-9));
      expect(next.right, closeTo(0.9, 1e-9));
      expect(next.bottom, closeTo(0.8, 1e-9));
      expect(next.top, closeTo(0.3, 1e-9));
    });

    test('right edge drag (no aspect) extends width only', () {
      const start = Rect.fromLTRB(0.1, 0.2, 0.7, 0.8);
      final next = CropController.resize(
        start,
        handle: CropHandle.r,
        dx: 0.2,
        dy: 0.0,
      );
      expect(next.left, closeTo(0.1, 1e-9));
      expect(next.right, closeTo(0.9, 1e-9));
      expect(next.top, closeTo(0.2, 1e-9));
      expect(next.bottom, closeTo(0.8, 1e-9));
    });

    test('top edge drag with 1:1 aspect lock grows symmetrically '
        'around the bottom-edge midpoint', () {
      // Start with a centred 0.4×0.4 rect at the layer middle.
      const start = Rect.fromLTRB(0.3, 0.3, 0.7, 0.7);
      final next = CropController.resize(
        start,
        handle: CropHandle.t,
        dx: 0.0,
        dy: -0.1, // grow up by 0.1 -> new height = 0.5
        aspect: 1.0,
      );
      // Aspect locked: width must equal height.
      expect(next.height, closeTo(0.5, 1e-9));
      expect(next.width, closeTo(0.5, 1e-9));
      // Anchored on bottom-edge midpoint (0.5, 0.7) so it stays
      // centred horizontally around x=0.5.
      expect(next.center.dx, closeTo(0.5, 1e-9));
      expect(next.bottom, closeTo(0.7, 1e-9));
    });

    test('left edge drag with 16:9 aspect lock keeps right edge fixed '
        'and adjusts height symmetrically', () {
      const start = Rect.fromLTRB(0.2, 0.3, 0.8, 0.7);
      final next = CropController.resize(
        start,
        handle: CropHandle.l,
        dx: 0.1, // shrink width to 0.5
        dy: 0.0,
        aspect: 16 / 9,
      );
      expect(next.right, closeTo(0.8, 1e-9));
      expect(next.width, closeTo(0.5, 1e-9));
      expect(next.height, closeTo(0.5 / (16 / 9), 1e-9));
      // Anchored on right-edge midpoint (0.8, 0.5) so symmetric
      // about y=0.5.
      expect(next.center.dy, closeTo(0.5, 1e-9));
    });

    test('corner drag without aspect changes both axes', () {
      const start = Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
      final next = CropController.resize(
        start,
        handle: CropHandle.br,
        dx: -0.2,
        dy: -0.2,
      );
      expect(next.right, closeTo(0.7, 1e-9));
      expect(next.bottom, closeTo(0.7, 1e-9));
      expect(next.left, closeTo(0.1, 1e-9));
      expect(next.top, closeTo(0.1, 1e-9));
    });

    test('corner drag with aspect locks ratio', () {
      const start = Rect.fromLTRB(0.0, 0.0, 1.0, 1.0);
      final next = CropController.resize(
        start,
        handle: CropHandle.br,
        dx: -0.4,
        dy: -0.1,
        aspect: 1.0,
      );
      // Anchored on top-left (0, 0). Driving axis = larger gap;
      // here width-gap (0.6) > height-gap (0.9) so width drives ->
      // h = w. Result is a 0.6 x 0.6 square at (0,0).
      expect(next.width, closeTo(next.height, 1e-9));
    });

    test('translate body drag clamps inside [0..1]', () {
      const start = Rect.fromLTRB(0.7, 0.7, 0.95, 0.95);
      final next = CropController.translate(start, 0.5, 0.5);
      // Width=0.25 height=0.25 -> max left/top = 0.75.
      expect(next.left, closeTo(0.75, 1e-9));
      expect(next.top, closeTo(0.75, 1e-9));
      expect(next.width, closeTo(0.25, 1e-9));
      expect(next.height, closeTo(0.25, 1e-9));
    });

    test('all 8 handles + aspect lock 1:1 produce a square', () {
      const start = Rect.fromLTRB(0.3, 0.3, 0.7, 0.7);
      for (final h in CropHandle.values) {
        final next = CropController.resize(
          start,
          handle: h,
          dx: 0.05,
          dy: 0.05,
          aspect: 1.0,
        );
        expect(
          next.width,
          closeTo(next.height, 1e-9),
          reason: 'handle $h should preserve 1:1 aspect',
        );
      }
    });
  });
}
