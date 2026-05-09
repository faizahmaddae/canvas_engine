// Behavior spec for `CanvasSizing` — the single source of truth for
// "how big should a freshly-inserted object be on this canvas?".

import 'dart:math' as math;
import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/core/canvas_sizing.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:flutter_test/flutter_test.dart';

EditorDocument _doc(double w, double h) => EditorDocument(
      layers: const [],
      width: w,
      height: h,
    );

void main() {
  group('effectiveDim', () {
    test('returns the geometric mean for square / near-square canvases',
        () {
      expect(CanvasSizing.effectiveDim(_doc(1080, 1080)), 1080);
      expect(
        CanvasSizing.effectiveDim(_doc(1920, 1080)),
        closeTo(math.sqrt(1920 * 1080), 0.001),
      );
    });

    test('falls back to the long axis at the 4:1 aspect threshold', () {
      expect(CanvasSizing.effectiveDim(_doc(4096, 1024)), 4096);
      expect(CanvasSizing.effectiveDim(_doc(1024, 4096)), 4096);
    });

    test('uses geometric mean just below the threshold', () {
      expect(
        CanvasSizing.effectiveDim(_doc(3900, 1000)),
        closeTo(math.sqrt(3900 * 1000), 0.001),
      );
    });

    test('returns 0 for degenerate documents', () {
      expect(CanvasSizing.effectiveDim(_doc(0, 600)), 0);
      expect(CanvasSizing.effectiveDim(_doc(800, 0)), 0);
    });
  });

  group('scaleFactor', () {
    test('is 1.0 on the reference canvas', () {
      expect(CanvasSizing.scaleFactor(_doc(1080, 1080)), 1.0);
    });

    test('is 1.0 for empty / degenerate documents', () {
      expect(CanvasSizing.scaleFactor(_doc(0, 0)), 1.0);
    });

    test('scales up on huge canvases (6720x4480 photo case)', () {
      final f = CanvasSizing.scaleFactor(_doc(6720, 4480));
      expect(f, greaterThan(4.5));
      expect(f, lessThan(6.0));
    });

    test('scales down on tiny canvases', () {
      final f = CanvasSizing.scaleFactor(_doc(512, 512));
      expect(f, lessThan(0.5));
      expect(f, greaterThan(0.4));
    });
  });

  group('scaleSize: insertion-default rescaling', () {
    const reference = Size(220, 220);

    test('returns the input verbatim on the reference canvas', () {
      final out = CanvasSizing.scaleSize(reference, _doc(1080, 1080));
      expect(out.width, closeTo(220, 0.01));
      expect(out.height, closeTo(220, 0.01));
    });

    test('grows proportionally on a 6720x4480 photo canvas', () {
      // Bug case: 220x220 default felt invisible on a 6720x4480 photo.
      final out = CanvasSizing.scaleSize(reference, _doc(6720, 4480));
      expect(out.width, greaterThan(900),
          reason: 'must be visibly large on huge canvas');
      expect(out.width, lessThanOrEqualTo(6720 * 0.9 + 0.01));
      expect(out.height, lessThanOrEqualTo(4480 * 0.9 + 0.01));
    });

    test(
        'shrinks proportionally on a tiny 512x512 canvas (no overflow)',
        () {
      final out = CanvasSizing.scaleSize(reference, _doc(512, 512));
      expect(out.width, lessThan(220));
      expect(out.width, lessThanOrEqualTo(512 * 0.9 + 0.01));
    });

    test('clamps to 90% of canvas when reference is bigger than canvas',
        () {
      final out = CanvasSizing.scaleSize(const Size(2000, 2000), _doc(400, 300));
      expect(out.width, lessThanOrEqualTo(400 * 0.9 + 0.01));
      expect(out.height, lessThanOrEqualTo(300 * 0.9 + 0.01));
    });

    test('preserves aspect ratio of the reference', () {
      const stroked = Size(280, 80);
      final out = CanvasSizing.scaleSize(stroked, _doc(2160, 2160));
      expect(out.width / out.height, closeTo(280 / 80, 0.01));
    });

    test('returns reference verbatim for empty doc (identity scale)', () {
      final out = CanvasSizing.scaleSize(reference, _doc(0, 0));
      expect(out.width, 220);
      expect(out.height, 220);
    });
  });

  group('scaleDimension', () {
    test('matches the width scale factor of scaleSize', () {
      final doc = _doc(2160, 1440);
      final scaledSize = CanvasSizing.scaleSize(const Size(100, 100), doc);
      final scaledDim = CanvasSizing.scaleDimension(100, doc);
      expect(scaledDim, closeTo(scaledSize.width, 0.01));
    });
  });

  group('proportionalStroke: canvas-aware preset thickness', () {
    // Use the production fractions/clamps so the test doubles as a
    // regression net on the Shape + Image border preset grammar.
    const thinF = 0.001, thinMin = 1.0, thinMax = 12.0;
    const medF = 0.004, medMin = 3.0, medMax = 48.0;
    const boldF = 0.010, boldMin = 8.0, boldMax = 120.0;

    double thin(EditorDocument d) => CanvasSizing.proportionalStroke(d,
        fraction: thinF, minPx: thinMin, maxPx: thinMax);
    double med(EditorDocument d) => CanvasSizing.proportionalStroke(d,
        fraction: medF, minPx: medMin, maxPx: medMax);
    double bold(EditorDocument d) => CanvasSizing.proportionalStroke(d,
        fraction: boldF, minPx: boldMin, maxPx: boldMax);

    test('reference 1080 canvas yields the historical good values', () {
      // The numbers that already "felt right" — preserves visual
      // continuity with documents authored on 1080-square.
      final d = _doc(1080, 1080);
      expect(thin(d), closeTo(1.08, 0.001));
      expect(med(d), closeTo(4.32, 0.001));
      expect(bold(d), closeTo(10.8, 0.001));
    });

    test('tiny 100x100 canvas hits the minPx floor on every preset', () {
      // Without minPx, Bold would be 1 px on a sticker — invisible.
      final d = _doc(100, 100);
      expect(thin(d), thinMin);
      expect(med(d), medMin);
      expect(bold(d), boldMin);
    });

    test('huge 12000x12000 canvas hits the maxPx ceiling on every preset',
        () {
      // Without maxPx, Bold would be 120+ px and read as a bezel.
      final d = _doc(12000, 12000);
      expect(thin(d), thinMax);
      expect(med(d), medMax);
      expect(bold(d), boldMax);
    });

    test('huge 6720x4480 photo canvas scales up smoothly (no clamps yet)',
        () {
      // Geometric mean ≈ 5486.85; raw values stay well inside clamps.
      final d = _doc(6720, 4480);
      expect(thin(d), closeTo(5.487, 0.01));
      expect(med(d), closeTo(21.947, 0.01));
      expect(bold(d), closeTo(54.868, 0.01));
    });

    test('extreme aspect 4096x400 ticker uses the long axis', () {
      // effectiveDim falls back to 4096 (≥4:1 trigger) so strokes
      // don't hairline based on the short axis.
      final d = _doc(4096, 400);
      expect(thin(d), closeTo(4.096, 0.01));
      expect(med(d), closeTo(16.384, 0.01));
      expect(bold(d), closeTo(40.96, 0.01));
    });

    test('degenerate / empty document returns minPx', () {
      final d = _doc(0, 0);
      expect(thin(d), thinMin);
      expect(med(d), medMin);
      expect(bold(d), boldMin);
    });

    test('Bold ≥ Medium ≥ Thin holds across every canvas size', () {
      // Monotonicity invariant — preset ordering must never invert,
      // even at the clamp boundaries.
      for (final size in const [
        [100.0, 100.0],
        [512.0, 512.0],
        [1080.0, 1080.0],
        [1920.0, 1080.0],
        [4096.0, 4096.0],
        [6720.0, 4480.0],
        [12000.0, 12000.0],
        [4096.0, 400.0],
      ]) {
        final d = _doc(size[0], size[1]);
        expect(bold(d), greaterThanOrEqualTo(med(d)),
            reason: 'bold < medium at ${size[0]}x${size[1]}');
        expect(med(d), greaterThanOrEqualTo(thin(d)),
            reason: 'medium < thin at ${size[0]}x${size[1]}');
      }
    });

    test('asserts on invalid fraction / clamp arguments', () {
      final d = _doc(1080, 1080);
      expect(
        () => CanvasSizing.proportionalStroke(d,
            fraction: 0, minPx: 1, maxPx: 10),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => CanvasSizing.proportionalStroke(d,
            fraction: 0.01, minPx: 10, maxPx: 5),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
