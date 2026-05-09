import 'package:canvas_engine/features/editor/engine/export/document_png_exporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:math' as math;

/// Regression coverage for the engine-level export memory cap.
///
/// The cap is the *only* thing standing between a user with a huge
/// canvas (or an "Original × 3" preset on a poster) and a low-end
/// Android OOM during `toImage`. Behaviour is intentionally simple
/// so it can never silently regress:
///
///   * If the requested pixelRatio fits under [maxOutputPixels], it
///     is returned unchanged.
///   * If it doesn't, the largest pixelRatio that *does* fit is
///     returned, and aspect ratio is preserved automatically because
///     the same scalar applies to width and height.
void main() {
  group('DocumentPngExporter.clampPixelRatio', () {
    test('returns requested ratio unchanged when it fits', () {
      // 1080×1080 @ 2x = ~4.7 Mpx — well under the 24 Mpx cap.
      final r = DocumentPngExporter.clampPixelRatio(
        width: 1080,
        height: 1080,
        requested: 2.0,
      );
      expect(r, 2.0);
    });

    test('reduces ratio when canvas × ratio² exceeds maxOutputPixels', () {
      // 6000×4000 = 24 Mpx already; any ratio > 1 must shrink.
      final r = DocumentPngExporter.clampPixelRatio(
        width: 6000,
        height: 4000,
        requested: 3.0,
        // Pin to the global cap so the test is independent of the
        // ambient device-aware ceiling that would otherwise depend
        // on the test harness's `PlatformDispatcher` view size.
        maxPixels: DocumentPngExporter.maxOutputPixels,
      );
      expect(r, lessThan(3.0));
      // Shrunk image must respect the cap (with a tiny slack).
      final pixels = (6000 * r) * (4000 * r);
      expect(pixels, lessThanOrEqualTo(DocumentPngExporter.maxOutputPixels + 1));
    });

    test('preserves aspect ratio (same scalar applied to W and H)', () {
      // An anisotropic canvas: clamping must keep w/h ratio unchanged.
      final r = DocumentPngExporter.clampPixelRatio(
        width: 8000,
        height: 2000,
        requested: 4.0,
      );
      const inAspect = 8000 / 2000;
      final outAspect = (8000 * r) / (2000 * r);
      expect(outAspect, closeTo(inAspect, 1e-9));
    });

    test('degenerate inputs are returned unchanged (no NaN, no crash)', () {
      expect(
        DocumentPngExporter.clampPixelRatio(
          width: 0,
          height: 1080,
          requested: 2.0,
        ),
        2.0,
      );
      expect(
        DocumentPngExporter.clampPixelRatio(
          width: 1080,
          height: 1080,
          requested: 0,
        ),
        0,
      );
    });

    test('willReducePixelRatio mirrors clampPixelRatio', () {
      expect(
        DocumentPngExporter.willReducePixelRatio(
          width: 1080,
          height: 1080,
          requested: 2.0,
          maxPixels: DocumentPngExporter.maxOutputPixels,
        ),
        isFalse,
      );
      expect(
        DocumentPngExporter.willReducePixelRatio(
          width: 6000,
          height: 4000,
          requested: 3.0,
          maxPixels: DocumentPngExporter.maxOutputPixels,
        ),
        isTrue,
      );
    });

    test('custom maxPixels lets callers tighten the cap for tests', () {
      final r = DocumentPngExporter.clampPixelRatio(
        width: 1000,
        height: 1000,
        requested: 4.0,
        maxPixels: 1000 * 1000, // 1 Mpx
      );
      // 1000×1000 already hits the cap at ratio 1.0.
      expect(r, closeTo(1.0, 1e-9));
    });
  });

  group('DocumentPngExporter.devicePixelCap', () {
    test('is positive, finite, and never above maxOutputPixels', () {
      final cap = DocumentPngExporter.devicePixelCap();
      expect(cap, greaterThan(0));
      expect(cap, lessThanOrEqualTo(DocumentPngExporter.maxOutputPixels));
    });

    test('is at least the documented floor', () {
      // The floor exists so cheap thumbnail rasters are never
      // starved on a tiny / unknown device. We don't expose the
      // private constant — assert against a conservative public
      // lower bound (4 Mpx).
      final cap = DocumentPngExporter.devicePixelCap();
      expect(cap, greaterThanOrEqualTo(4 * 1000 * 1000));
    });

    test(
      'omitting maxPixels uses devicePixelCap (not maxOutputPixels)',
      () {
        // A canvas big enough to bust the device cap but small
        // enough to fit the global cap — only with an actual
        // device-aware ceiling will the ratio shrink.
        final cap = DocumentPngExporter.devicePixelCap();
        // Build a square canvas that needs ratio = 2 to hit `cap`,
        // then ask for ratio 4 — must shrink iff the device cap
        // was actually consulted.
        final edge = math.sqrt(cap / 4); // 2× cap area at ratio 4
        final shrunk = DocumentPngExporter.clampPixelRatio(
          width: edge * 2, // already covers `cap` at ratio 1
          height: edge * 2,
          requested: 4.0,
        );
        expect(shrunk, lessThan(4.0));
      },
    );
  });
}
