import 'dart:ui';

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/viewport_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/viewport_state.dart';
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
        c.read(viewportControllerProvider).scale,
        greaterThanOrEqualTo(0.05),
      );
    });

    test('fit upscales small canvases to fill the available area', () {
      // A 256x256 canvas on a 1080x1920 screen should auto-zoom in so it
      // becomes the visual focus rather than a tiny postage stamp in the
      // middle of empty space.
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(viewportControllerProvider.notifier)
          .fit(
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
      c
          .read(viewportControllerProvider.notifier)
          .fit(
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
      c
          .read(viewportControllerProvider.notifier)
          .fit(screenSize: const Size(800, 600), canvasSize: Size.zero);
      expect(c.read(viewportControllerProvider), before);
    });

    test('adaptivePaddingFor gives every form factor a floating margin', () {
      // v2 workspace: the canvas floats with a comfortable symmetric
      // margin on every side — no edge-to-edge fits anywhere.
      final phone = ViewportController.adaptivePaddingFor(const Size(360, 800));
      expect(phone.horizontal, 16);
      expect(phone.vertical, 16);

      // Large phone — both axes lerp up from 16.
      final largePhone = ViewportController.adaptivePaddingFor(
        const Size(600, 900),
      );
      expect(largePhone.horizontal, greaterThan(16));
      expect(largePhone.horizontal, lessThan(20));
      expect(largePhone.vertical, greaterThan(16));

      // Tablet — symmetric breathing room.
      final tablet = ViewportController.adaptivePaddingFor(
        const Size(820, 1180),
      );
      expect(tablet.horizontal, greaterThan(20));
      expect(tablet.horizontal, lessThan(28));
      expect(tablet.vertical, tablet.horizontal);

      // Desktop — full symmetric margin.
      final desktop = ViewportController.adaptivePaddingFor(
        const Size(1920, 1080),
      );
      expect(desktop.horizontal, 32);
      expect(desktop.vertical, 32);
    });

    test('fit on phone leaves the floating margin on both sides', () {
      // 360-wide phone with a 1080x1080 canvas: 16px padding per side
      // leaves 328px of workspace width for the canvas.
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(viewportControllerProvider.notifier)
          .fit(
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
      c
          .read(viewportControllerProvider.notifier)
          .fit(
            screenSize: const Size(360, 800),
            canvasSize: const Size(1920, 1080),
          );
      final v = c.read(viewportControllerProvider);
      expect(v.scale, closeTo(328 / 1920, 1e-9));
      expect(v.translation.dx, closeTo(16, 1e-6));
      // Vertical centring: (800 - 1080 * scale) / 2.
      expect(v.translation.dy, closeTo((800 - 1080 * (328 / 1920)) / 2, 1e-6));
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
      expect(
        c.read(viewportControllerProvider).translation,
        fitted.translation,
      );
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
      expect(
        after.translation.dy,
        closeTo(initial.translation.dy, 1e-12),
        reason:
            'Fit-to-screen must not shift the canvas vertically '
            'relative to the initial auto-fit.',
      );
    });

    test('lastFitContext exposes the inputs of the most recent fit', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(viewportControllerProvider.notifier);
      expect(n.lastFitContext, isNull);
      n.fit(screenSize: const Size(500, 800), canvasSize: const Size(400, 400));
      expect(n.lastFitContext?.screenSize, const Size(500, 800));
      expect(n.lastFitContext?.canvasSize, const Size(400, 400));
    });
  });

  // -----------------------------------------------------------------
  // Viewport preservation across a canvas-pane reflow.
  //
  // A tool panel opening / closing / switching resizes the on-screen
  // canvas pane. Before this behaviour a pane change re-fitted and
  // discarded the user's manual zoom/pan; now the controller tracks
  // whether the viewport is a user-owned adjustment and offers a
  // preserve-instead-of-fit path. These assert the resulting viewport
  // transform (user-visible), not internal wiring.
  // -----------------------------------------------------------------
  group('ViewportController — user-adjusted tracking', () {
    test('a fresh viewport and a plain fit are not user-adjusted', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(viewportControllerProvider.notifier);
      expect(n.userAdjusted, isFalse);
      n.fit(
        screenSize: const Size(400, 800),
        canvasSize: const Size(400, 400),
        padding: 0,
      );
      expect(n.userAdjusted, isFalse);
      // The transform was actually applied (centred fit), not left identity.
      final v = c.read(viewportControllerProvider);
      expect(v.scale, 1.0);
      expect(v.translation, const Offset(0, 200));
    });

    test('panBy, zoomBy and gestureUpdate mark the viewport user-adjusted', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(viewportControllerProvider.notifier);

      n.panBy(const Offset(10, 10));
      expect(n.userAdjusted, isTrue);
      expect(
        c.read(viewportControllerProvider).translation,
        const Offset(10, 10),
      );

      // fit() re-enables auto-fit, then each manual op re-marks.
      n.fit(
        screenSize: const Size(400, 800),
        canvasSize: const Size(400, 400),
        padding: 0,
      );
      expect(n.userAdjusted, isFalse);
      n.zoomBy(2.0, const Offset(200, 400));
      expect(n.userAdjusted, isTrue);
      expect(c.read(viewportControllerProvider).scale, 2.0); // 1.0 * 2

      n.fit(
        screenSize: const Size(400, 800),
        canvasSize: const Size(400, 400),
        padding: 0,
      );
      expect(n.userAdjusted, isFalse);
      n.gestureUpdate(
        startState: c.read(viewportControllerProvider),
        startFocal: const Offset(100, 100),
        currentFocal: const Offset(160, 140),
        scale: 1.3,
      );
      expect(n.userAdjusted, isTrue);
      expect(c.read(viewportControllerProvider).scale, closeTo(1.3, 1e-9));
    });

    test('a no-op pan or gesture frame does not mark user-adjusted', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(viewportControllerProvider.notifier);
      n.fit(
        screenSize: const Size(400, 800),
        canvasSize: const Size(400, 400),
        padding: 0,
      );
      n.panBy(Offset.zero);
      expect(n.userAdjusted, isFalse);
      // Finger held still at unit scale: net-zero, must not mark.
      n.gestureUpdate(
        startState: c.read(viewportControllerProvider),
        startFocal: const Offset(150, 150),
        currentFocal: const Offset(150, 150),
        scale: 1.0,
      );
      expect(n.userAdjusted, isFalse);
    });

    test('refit clears user-adjusted and restores the exact fit', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(viewportControllerProvider.notifier);
      n.fit(
        screenSize: const Size(400, 800),
        canvasSize: const Size(400, 400),
        padding: 0,
      );
      final fitted = c.read(viewportControllerProvider);
      n.zoomBy(2.0, const Offset(200, 400));
      expect(n.userAdjusted, isTrue);
      expect(n.refit(), isTrue);
      expect(n.userAdjusted, isFalse);
      expect(c.read(viewportControllerProvider), fitted);
    });

    test('reset clears user-adjusted; restore marks it', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(viewportControllerProvider.notifier);
      n.zoomBy(2.0, const Offset(100, 100));
      expect(n.userAdjusted, isTrue);
      n.reset();
      expect(n.userAdjusted, isFalse);
      expect(c.read(viewportControllerProvider), ViewportState.identity);
      // Restoring a genuine user adjustment applies the transform AND marks
      // it adjusted, so a later reflow preserves it.
      n.restore(
        const ViewportState(scale: 3, translation: Offset(5, 6)),
        userAdjusted: true,
      );
      expect(n.userAdjusted, isTrue);
      expect(c.read(viewportControllerProvider).scale, 3);
      expect(
        c.read(viewportControllerProvider).translation,
        const Offset(5, 6),
      );
      // Restoring an automatic fit applies the transform but stays NOT
      // adjusted, so a later reflow re-fits instead of preserving.
      n.restore(
        const ViewportState(scale: 0.5, translation: Offset(1, 2)),
        userAdjusted: false,
      );
      expect(n.userAdjusted, isFalse);
      expect(c.read(viewportControllerProvider).scale, 0.5);
    });

    test('reflowPreservingZoom keeps scale, holds the focal detail, and '
        'reseeds the fit context so a later Fit targets the new pane', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(viewportControllerProvider.notifier);
      // Fit a 400x400 canvas into an 800-tall pane, then zoom 2x on the
      // pane centre so a specific canvas point is the focus.
      n.fit(
        screenSize: const Size(400, 800),
        canvasSize: const Size(400, 400),
        padding: 0,
      );
      n.zoomBy(2.0, const Offset(200, 400));
      final zoomed = c.read(viewportControllerProvider);
      expect(zoomed.scale, 2.0);
      // The canvas point the user is looking at (under the old pane centre).
      final focusCanvasPoint =
          (const Offset(200, 400) - zoomed.translation) / zoomed.scale;

      // Pane shrinks — a tool panel opened.
      n.reflowPreservingZoom(
        oldScreen: const Size(400, 800),
        newScreen: const Size(400, 600),
        canvasSize: const Size(400, 400),
      );
      final after = c.read(viewportControllerProvider);

      // Scale is preserved — NOT the fit scale for the new pane (which
      // would be 1.0 here), and the user stays adjusted.
      expect(after.scale, closeTo(2.0, 1e-9));
      expect(n.userAdjusted, isTrue);
      // Same canvas detail now sits under the NEW pane centre.
      final nowUnderCentre =
          (const Offset(200, 300) - after.translation) / after.scale;
      expect(nowUnderCentre.dx, closeTo(focusCanvasPoint.dx, 1e-6));
      expect(nowUnderCentre.dy, closeTo(focusCanvasPoint.dy, 1e-6));
      // Translation stays finite / legal.
      expect(after.translation.dx.isFinite, isTrue);
      expect(after.translation.dy.isFinite, isTrue);
      // Fit context now points at the new pane, so "Fit to screen" fits
      // the 600-tall pane, not the stale 800-tall one.
      expect(n.lastFitContext?.screenSize, const Size(400, 600));
      n.refit();
      final refit = c.read(viewportControllerProvider);
      expect(
        refit.scale,
        closeTo(1.0, 1e-9),
      ); // 600-32? padding 0 → 600/400 vs 400/400 → 1.0
      expect(n.userAdjusted, isFalse);
    });

    test(
      'reflowPreservingZoom ignores a degenerate pane (no state change)',
      () {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final n = c.read(viewportControllerProvider.notifier);
        n.zoomBy(2.0, const Offset(100, 100));
        final before = c.read(viewportControllerProvider);
        n.reflowPreservingZoom(
          oldScreen: const Size(400, 800),
          newScreen: Size.zero,
          canvasSize: const Size(400, 400),
        );
        expect(c.read(viewportControllerProvider), before);
      },
    );

    test('an intent-only change (equal transform) is an observable state '
        'transition, and refit clears it', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(viewportControllerProvider.notifier);
      n.fit(
        screenSize: const Size(400, 800),
        canvasSize: const Size(400, 400),
        padding: 0,
      );
      final fitted = c.read(viewportControllerProvider);
      expect(fitted.userAdjusted, isFalse);

      // Restore the SAME transform but as a user adjustment.
      n.restore(fitted, userAdjusted: true);
      final adjusted = c.read(viewportControllerProvider);
      expect(adjusted.userAdjusted, isTrue);
      // Same transform, different intent → NOT equal (so a persistence
      // listener that keys on value equality WILL observe the change).
      expect(adjusted, isNot(fitted));
      expect(adjusted.scale, fitted.scale);
      expect(adjusted.translation, fitted.translation);

      // Explicit Fit recomputes the SAME transform → clears intent as an
      // observable transition, landing back on the fit value.
      expect(n.refit(), isTrue);
      final refitted = c.read(viewportControllerProvider);
      expect(refitted.userAdjusted, isFalse);
      expect(refitted, fitted);
      expect(refitted, isNot(adjusted));
    });

    test('reset() clears intent as an observable transition at identity', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(viewportControllerProvider.notifier);
      // Mark the identity transform as adjusted, then reset — the transform
      // is unchanged but the intent must still flip observably.
      n.restore(ViewportState.identity, userAdjusted: true);
      expect(c.read(viewportControllerProvider).userAdjusted, isTrue);
      n.reset();
      final r = c.read(viewportControllerProvider);
      expect(r.userAdjusted, isFalse);
      expect(r, ViewportState.identity);
    });

    test('manual pan round-trip back to the fit transform, then refit, clears '
        'intent (exact representable deltas)', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(viewportControllerProvider.notifier);
      n.fit(
        screenSize: const Size(400, 800),
        canvasSize: const Size(400, 400),
        padding: 0,
      );
      final fitted = c.read(viewportControllerProvider);
      // Pan out and exactly back — integer offsets round-trip exactly.
      n.panBy(const Offset(30, -20));
      n.panBy(const Offset(-30, 20));
      final roundTripped = c.read(viewportControllerProvider);
      expect(roundTripped.translation, fitted.translation);
      expect(roundTripped.scale, fitted.scale);
      expect(roundTripped.userAdjusted, isTrue); // still adjusted
      expect(roundTripped, isNot(fitted)); // differ only by intent
      // Fit on the equal transform must still clear + be observable.
      n.refit();
      final refitted = c.read(viewportControllerProvider);
      expect(refitted.userAdjusted, isFalse);
      expect(refitted, fitted);
    });
  });

  group('Logical canvas independence', () {
    test('newDocument resets layers, history, and stores logical size', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(documentControllerProvider.notifier);
      n.execute(
        AddLayerCommand(
          ShapeLayer(
            id: 'a',
            transform: const LayerTransform(
              position: Offset.zero,
              size: Size(100, 100),
            ),
            kind: ShapeKind.rectangle,
          ),
        ),
      );
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
      c
          .read(documentControllerProvider.notifier)
          .execute(
            AddLayerCommand(
              ShapeLayer(
                id: 'l',
                transform: const LayerTransform(
                  position: Offset(123, 456),
                  size: Size(50, 50),
                ),
                kind: ShapeKind.rectangle,
              ),
            ),
          );
      c
          .read(viewportControllerProvider.notifier)
          .fit(
            screenSize: const Size(400, 400),
            canvasSize: const Size(2000, 2000),
          );
      final layer = c.read(documentControllerProvider).layerById('l')!;
      expect(layer.transform.position, const Offset(123, 456));
    });
  });
}
