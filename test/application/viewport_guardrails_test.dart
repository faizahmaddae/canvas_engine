import 'package:canvas_engine/core/constants/engine_constants.dart';
import 'package:canvas_engine/features/editor/application/image_import_service.dart';
import 'package:canvas_engine/features/editor/application/viewport_controller.dart';
import 'package:canvas_engine/features/editor/engine/core/viewport_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Viewport guardrails (tb3 7/7): translation bounds that keep a
/// grabbable sliver of canvas on-screen, a fit-derived zoom-out floor
/// so huge photos actually fit, clamp-on-restore for persisted
/// viewports, and the import dimension cap.

void main() {
  const minEdge = EngineConstants.kViewportMinVisibleEdge;

  ProviderContainer setup() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  group('translation bounds', () {
    test('a wild pan cannot strand the canvas off-screen', () {
      final c = setup();
      final n = c.read(viewportControllerProvider.notifier);
      n.fit(
        screenSize: const Size(800, 800),
        canvasSize: const Size(400, 400),
        padding: 0,
      );
      final scale = c.read(viewportControllerProvider).scale;

      n.panBy(const Offset(1e6, 1e6));
      var v = c.read(viewportControllerProvider);
      expect(
        v.translation.dx,
        lessThanOrEqualTo(800 - minEdge),
        reason: '≥ ${minEdge}px of canvas must stay visible on the left',
      );
      expect(v.translation.dy, lessThanOrEqualTo(800 - minEdge));

      n.panBy(const Offset(-1e6, -1e6));
      v = c.read(viewportControllerProvider);
      expect(
        v.translation.dx,
        greaterThanOrEqualTo(minEdge - 400 * scale),
        reason: '≥ ${minEdge}px of canvas must stay visible on the right',
      );
      expect(v.translation.dy, greaterThanOrEqualTo(minEdge - 400 * scale));
    });

    test('gestureUpdate (pinch/pan path) is clamped the same way', () {
      final c = setup();
      final n = c.read(viewportControllerProvider.notifier);
      n.fit(
        screenSize: const Size(800, 800),
        canvasSize: const Size(400, 400),
        padding: 0,
      );
      final start = c.read(viewportControllerProvider);
      n.gestureUpdate(
        startState: start,
        startFocal: const Offset(400, 400),
        currentFocal: const Offset(400 + 1e6, 400),
        scale: 1.0,
      );
      expect(
        c.read(viewportControllerProvider).translation.dx,
        lessThanOrEqualTo(800 - minEdge),
      );
    });

    test('without fit geometry the clamp is inert (headless contract)', () {
      final c = setup();
      final n = c.read(viewportControllerProvider.notifier);
      n.panBy(const Offset(5000, 5000));
      expect(
        c.read(viewportControllerProvider).translation,
        const Offset(5000, 5000),
        reason: 'no pane known — nothing to clamp against',
      );
    });
  });

  group('clamp-on-restore', () {
    test('an off-screen persisted translation recovers into bounds', () {
      final c = setup();
      final n = c.read(viewportControllerProvider.notifier);
      n.fit(
        screenSize: const Size(800, 800),
        canvasSize: const Size(400, 400),
        padding: 0,
      );
      n.restore(
        const ViewportState(scale: 1.0, translation: Offset(99999, -99999)),
        userAdjusted: true,
      );
      final v = c.read(viewportControllerProvider);
      expect(v.translation.dx, lessThanOrEqualTo(800 - minEdge));
      expect(v.translation.dy, greaterThanOrEqualTo(minEdge - 400 * 1.0));
      expect(v.userAdjusted, isTrue);
    });

    test('a corrupt entry (non-finite / non-positive) is ignored, keeping '
        'the fresh fit', () {
      final c = setup();
      final n = c.read(viewportControllerProvider.notifier);
      n.fit(
        screenSize: const Size(800, 800),
        canvasSize: const Size(400, 400),
        padding: 0,
      );
      final fitState = c.read(viewportControllerProvider);

      n.restore(
        const ViewportState(scale: double.nan, translation: Offset(100, 100)),
        userAdjusted: true,
      );
      expect(c.read(viewportControllerProvider), fitState);

      n.restore(
        const ViewportState(
          scale: 1.0,
          translation: Offset(double.infinity, 0),
        ),
        userAdjusted: true,
      );
      expect(c.read(viewportControllerProvider), fitState);
    });

    test('an out-of-range persisted zoom is clamped into the legal range', () {
      final c = setup();
      final n = c.read(viewportControllerProvider.notifier);
      n.fit(
        screenSize: const Size(800, 800),
        canvasSize: const Size(400, 400),
        padding: 0,
      );
      n.restore(
        const ViewportState(scale: 1e9, translation: Offset(0, 0)),
        userAdjusted: true,
      );
      expect(c.read(viewportControllerProvider).scale, lessThanOrEqualTo(32));
    });
  });

  group('huge-document fit', () {
    test('a 9000px photo fits a small pane (fit scale below the old 0.05 '
        'floor)', () {
      final c = setup();
      final n = c.read(viewportControllerProvider.notifier);
      n.fit(
        screenSize: const Size(400, 400),
        canvasSize: const Size(9000, 9000),
        padding: 0,
      );
      final v = c.read(viewportControllerProvider);
      expect(v.scale, closeTo(400 / 9000, 1e-9));
      expect(
        9000 * v.scale,
        lessThanOrEqualTo(400 + 1e-6),
        reason: 'the whole canvas must fit on-screen',
      );
    });

    test('the zoom-out floor derives from the fit for huge documents', () {
      final c = setup();
      final n = c.read(viewportControllerProvider.notifier);
      n.fit(
        screenSize: const Size(400, 400),
        canvasSize: const Size(9000, 9000),
        padding: 0,
      );
      final fitScale = 400 / 9000;
      n.zoomBy(1e-9, const Offset(200, 200));
      expect(
        c.read(viewportControllerProvider).scale,
        closeTo(fitScale * EngineConstants.kViewportMinZoomOutFactor, 1e-9),
      );
    });

    test('ordinary documents keep the flat 0.05 floor', () {
      final c = setup();
      final n = c.read(viewportControllerProvider.notifier);
      n.fit(
        screenSize: const Size(800, 800),
        canvasSize: const Size(400, 400),
        padding: 0,
      );
      n.zoomBy(1e-9, const Offset(400, 400));
      expect(c.read(viewportControllerProvider).scale, closeTo(0.05, 1e-9));
    });
  });

  group('import dimension cap', () {
    test('sizes at or under the ceiling pass through unchanged', () {
      expect(capImportSize(const Size(4000, 3000)), const Size(4000, 3000));
      expect(capImportSize(const Size(8192, 8192)), const Size(8192, 8192));
    });

    test('oversized landscape picks downscale aspect-preserving to the '
        'longest-side ceiling', () {
      expect(capImportSize(const Size(16384, 8192)), const Size(8192, 4096));
      expect(capImportSize(const Size(10000, 5000)), const Size(8192, 4096));
    });

    test('oversized portrait picks downscale the other axis', () {
      expect(capImportSize(const Size(5000, 10000)), const Size(4096, 8192));
    });

    test('never upscales and never rounds to zero', () {
      expect(capImportSize(const Size(100, 9000)).width, greaterThan(0));
      expect(capImportSize(const Size(1, 1)), const Size(1, 1));
    });
  });
}
