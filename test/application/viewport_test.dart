import 'dart:ui';

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/viewport_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ViewportController', () {
    test('identity is the build default', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final v = c.read(viewportControllerProvider);
      expect(v.scale, 1.0);
      expect(v.translation, Offset.zero);
    });

    test('fit centres the canvas with a uniform scale', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      // Square canvas, wide screen \u2192 scale fits height (the smaller axis
      // after subtracting padding) and centres horizontally.
      c
          .read(viewportControllerProvider.notifier)
          .fit(
            screenSize: const Size(800, 400),
            canvasSize: const Size(1000, 1000),
            padding: 0,
          );
      final v = c.read(viewportControllerProvider);
      expect(v.scale, 0.4); // 400 / 1000
      expect(v.translation.dx, (800 - 1000 * 0.4) / 2);
      expect(v.translation.dy, 0.0);
    });

    test('zoomBy keeps the focal point fixed in screen space', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(viewportControllerProvider.notifier);
      n.fit(
        screenSize: const Size(1000, 1000),
        canvasSize: const Size(500, 500),
        padding: 0,
      );
      // After fit: scale 2, translation (0,0). Focal at (200,200) on screen
      // \u21d2 canvas point (100,100). Zoom by 2 \u21d2 scale 4. The same canvas
      // point must still appear at (200,200).
      n.zoomBy(2.0, const Offset(200, 200));
      final v = c.read(viewportControllerProvider);
      expect(v.scale, 4.0);
      // canvasPoint (100,100) * 4 + translation == (200,200) \u21d2 t = (-200,-200)
      expect(v.translation, const Offset(-200, -200));
    });

    test('clamps scale to the configured min/max', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(viewportControllerProvider.notifier);
      n.zoomBy(1000, Offset.zero);
      expect(c.read(viewportControllerProvider).scale, lessThanOrEqualTo(32));
      n.zoomBy(0.0001, Offset.zero);
      expect(
          c.read(viewportControllerProvider).scale, greaterThanOrEqualTo(0.05));
    });

    test('fit upscales small canvases to fill the available area', () {
      // A 256x256 canvas on a 1080x1920 screen should auto-zoom in so it
      // becomes the visual focus rather than a tiny postage stamp in the
      // middle of empty space.
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(viewportControllerProvider.notifier).fit(
            screenSize: const Size(1080, 1920),
            canvasSize: const Size(256, 256),
            padding: 32,
          );
      final v = c.read(viewportControllerProvider);
      // 1080 - 64 = 1016 available width; (1016 / 256) ≈ 3.97
      expect(v.scale, closeTo(1016 / 256, 1e-9));
      // Centred horizontally and vertically.
      final fitted = 256 * v.scale;
      expect(v.translation.dx, closeTo((1080 - fitted) / 2, 1e-6));
      expect(v.translation.dy, closeTo((1920 - fitted) / 2, 1e-6));
    });

    test('fit honours the padding margin so canvas never touches edges', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(viewportControllerProvider.notifier).fit(
            screenSize: const Size(500, 500),
            canvasSize: const Size(500, 500),
            padding: 24,
          );
      final v = c.read(viewportControllerProvider);
      // 500 - 48 = 452 available; scale = 452/500 = 0.904
      expect(v.scale, closeTo(0.904, 1e-9));
      final fitted = 500 * v.scale;
      expect(v.translation.dx, closeTo((500 - fitted) / 2, 1e-6));
      expect(v.translation.dy, closeTo((500 - fitted) / 2, 1e-6));
    });

    test('fit ignores degenerate canvas sizes (no state change)', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final before = c.read(viewportControllerProvider);
      c.read(viewportControllerProvider.notifier).fit(
            screenSize: const Size(800, 600),
            canvasSize: Size.zero,
          );
      expect(c.read(viewportControllerProvider), before);
    });

    test('adaptivePaddingFor gives every form factor a floating margin', () {
      // v2 workspace: the canvas floats with a comfortable symmetric
      // margin on every side — no edge-to-edge fits anywhere.
      final phone =
          ViewportController.adaptivePaddingFor(const Size(360, 800));
      expect(phone.horizontal, 16);
      expect(phone.vertical, 16);

      // Large phone — both axes lerp up from 16.
      final largePhone =
          ViewportController.adaptivePaddingFor(const Size(600, 900));
      expect(largePhone.horizontal, greaterThan(16));
      expect(largePhone.horizontal, lessThan(20));
      expect(largePhone.vertical, greaterThan(16));

      // Tablet — symmetric breathing room.
      final tablet =
          ViewportController.adaptivePaddingFor(const Size(820, 1180));
      expect(tablet.horizontal, greaterThan(20));
      expect(tablet.horizontal, lessThan(28));
      expect(tablet.vertical, tablet.horizontal);

      // Desktop — full symmetric margin.
      final desktop =
          ViewportController.adaptivePaddingFor(const Size(1920, 1080));
      expect(desktop.horizontal, 32);
      expect(desktop.vertical, 32);
    });

    test('fit on phone leaves the floating margin on both sides', () {
      // 360-wide phone with a 1080x1080 canvas: 16px padding per side
      // leaves 328px of workspace width for the canvas.
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(viewportControllerProvider.notifier).fit(
            screenSize: const Size(360, 800),
            canvasSize: const Size(1080, 1080),
          );
      final v = c.read(viewportControllerProvider);
      expect(v.scale, closeTo(328 / 1080, 1e-9));
      // Square canvas at padded width ⇒ side gap is exactly the margin.
      expect(v.translation.dx, closeTo(16, 1e-6));
    });

    test('fit on phone still centres a landscape canvas horizontally', () {
      // Canvas wider than tall, rendered at padded screen width ⇒
      // leftover height gets split top/bottom; horizontal translation
      // is the floating margin.
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(viewportControllerProvider.notifier).fit(
            screenSize: const Size(360, 800),
            canvasSize: const Size(1920, 1080),
          );
      final v = c.read(viewportControllerProvider);
      expect(v.scale, closeTo(328 / 1920, 1e-9));
      expect(v.translation.dx, closeTo(16, 1e-6));
      // Vertical centring: (800 - 1080 * scale) / 2.
      expect(
        v.translation.dy,
        closeTo((800 - 1080 * (328 / 1920)) / 2, 1e-6),
      );
    });

    // -----------------------------------------------------------------
    // refit(): single source of truth for "Fit to screen"
    // -----------------------------------------------------------------
    //
    // Regression cover for the centring bug where the More -> Fit to
    // screen menu re-derived the screen rect from MediaQuery instead of
    // the actual canvas pane the EditorCanvas LayoutBuilder produced.
    // That route silently disagreed with the layout's real pane (the
    // bottom dock height was unaccounted for) and shifted the canvas
    // visibly downward. refit() solves it by replaying the cached
    // (screenSize, canvasSize) the auto-fit was computed against.

    test('refit replays the most recent fit exactly', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(viewportControllerProvider.notifier);
      n.fit(
        screenSize: const Size(800, 600),
        canvasSize: const Size(400, 400),
        padding: 0,
      );
      final fitted = c.read(viewportControllerProvider);
      // Pan + zoom away from the fitted state.
      n.panBy(const Offset(50, 70));
      n.zoomBy(2.0, const Offset(100, 100));
      expect(c.read(viewportControllerProvider), isNot(fitted));
      // Refit must restore the EXACT pre-pan/zoom state.
      final ok = n.refit();
      expect(ok, isTrue);
      expect(c.read(viewportControllerProvider).scale, fitted.scale);
      expect(c.read(viewportControllerProvider).translation, fitted.translation);
    });

    test('refit returns false when no fit has been recorded yet', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(viewportControllerProvider.notifier).refit(), isFalse);
    });

    test('refit uses the LAST fit (caches subsequent fits)', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(viewportControllerProvider.notifier);
      n.fit(
        screenSize: const Size(800, 600),
        canvasSize: const Size(400, 400),
        padding: 0,
      );
      // Simulate a layout / orientation change.
      n.fit(
        screenSize: const Size(1200, 900),
        canvasSize: const Size(400, 400),
        padding: 0,
      );
      final secondFit = c.read(viewportControllerProvider);
      n.panBy(const Offset(33, 44));
      n.refit();
      expect(c.read(viewportControllerProvider), secondFit);
    });

    test('refit and the original fit produce identical translation '
        '— Fit-to-screen must centre exactly like the auto-fit', () {
      // The bug surfaced as a vertical offset only after the user
      // panned and then tapped "Fit to screen". We assert that an
      // auto-fit followed by an arbitrary pan/zoom and then a refit
      // lands EXACTLY on the auto-fit translation, with no drift.
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(viewportControllerProvider.notifier);
      // Realistic phone pane: 360 wide, 700 tall after chrome.
      const pane = Size(360, 700);
      const canvas = Size(1080, 1350);
      n.fit(screenSize: pane, canvasSize: canvas);
      final initial = c.read(viewportControllerProvider);
      // User pans the canvas down + zooms in.
      n.panBy(const Offset(0, 200));
      n.zoomBy(1.5, const Offset(180, 350));
      // Tap More -> Fit to screen.
      final ok = n.refit();
      expect(ok, isTrue);
      final after = c.read(viewportControllerProvider);
      expect(after.scale, closeTo(initial.scale, 1e-12));
      expect(after.translation.dx, closeTo(initial.translation.dx, 1e-12));
      expect(after.translation.dy, closeTo(initial.translation.dy, 1e-12),
          reason: 'Fit-to-screen must not shift the canvas vertically '
              'relative to the initial auto-fit.');
    });

    test('lastFitContext exposes the inputs of the most recent fit', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(viewportControllerProvider.notifier);
      expect(n.lastFitContext, isNull);
      n.fit(
        screenSize: const Size(500, 800),
        canvasSize: const Size(400, 400),
      );
      expect(n.lastFitContext?.screenSize, const Size(500, 800));
      expect(n.lastFitContext?.canvasSize, const Size(400, 400));
    });
  });

  group('Logical canvas independence', () {
    test('newDocument resets layers, history, and stores logical size', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(documentControllerProvider.notifier);
      n.execute(AddLayerCommand(ShapeLayer(
        id: 'a',
        transform: const LayerTransform(
          position: Offset.zero,
          size: Size(100, 100),
        ),
        kind: ShapeKind.rectangle,
      )));
      expect(c.read(documentControllerProvider).layers, hasLength(1));
      expect(n.canUndo, isTrue);

      n.newDocument(width: 800, height: 1200);
      final doc = c.read(documentControllerProvider);
      expect(doc.layers, isEmpty);
      expect(doc.width, 800);
      expect(doc.height, 1200);
      expect(n.canUndo, isFalse);
      expect(n.canRedo, isFalse);
    });

    test('layer positions are independent of any "screen size"', () {
      // Sanity: a layer placed at logical (123, 456) on a 2000\u00d72000 doc
      // keeps that exact position regardless of viewport scale/translation.
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(documentControllerProvider.notifier)
          .newDocument(width: 2000, height: 2000);
      c.read(documentControllerProvider.notifier).execute(AddLayerCommand(
            ShapeLayer(
              id: 'l',
              transform: const LayerTransform(
                position: Offset(123, 456),
                size: Size(50, 50),
              ),
              kind: ShapeKind.rectangle,
            ),
          ));
      c
          .read(viewportControllerProvider.notifier)
          .fit(screenSize: const Size(400, 400), canvasSize: const Size(2000, 2000));
      final layer = c.read(documentControllerProvider).layerById('l')!;
      expect(layer.transform.position, const Offset(123, 456));
    });
  });
}
