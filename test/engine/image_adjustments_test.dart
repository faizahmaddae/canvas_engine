// Engine-level tests for [ImageAdjustments.colorMatrix]. Pure engine,
// no Material — lives under test/engine/ per tests.instructions.md.
//
// The point of this file: prove the cache is *semantically correct*,
// not just performant. The cache must:
//   1. Match the previous per-call composition byte-for-byte
//      (no behaviour change — gate for the rename + cache).
//   2. Return the same `List<double>` instance on repeated reads
//      (the cache is actually caching).
//   3. Never share a cache slot across instances — `copyWith` must
//      produce a fresh slot, since it returns a new instance.
//   4. Different field values produce different matrices (no aliasing
//      bug where every instance ends up returning the same list).

import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:flutter_test/flutter_test.dart';

// Reference implementation: literally the body of the previous
// `toMatrix()` method. If [ImageAdjustments.colorMatrix] ever drifts
// from this, the equivalence test catches it.
List<double> _referenceMatrix(ImageAdjustments a) {
  final ex = 1 + a.exposure / 100;
  final expM = <double>[
    ex,
    0,
    0,
    0,
    0,
    0,
    ex,
    0,
    0,
    0,
    0,
    0,
    ex,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  final wOff = a.warmth * 0.2 * 2.55;
  final warmM = <double>[
    1,
    0,
    0,
    0,
    wOff,
    0,
    1,
    0,
    0,
    wOff * 0.4,
    0,
    0,
    1,
    0,
    -wOff,
    0,
    0,
    0,
    1,
    0,
  ];

  final s = a.saturation;
  const lr = 0.299;
  const lg = 0.587;
  const lb = 0.114;
  final sr0 = (1 - s) * lr;
  final sg0 = (1 - s) * lg;
  final sb0 = (1 - s) * lb;
  final sat = <double>[
    sr0 + s,
    sg0,
    sb0,
    0,
    0,
    sr0,
    sg0 + s,
    sb0,
    0,
    0,
    sr0,
    sg0,
    sb0 + s,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  final c = a.contrast;
  final cTrans = 128 * (1 - c);
  final con = <double>[
    c,
    0,
    0,
    0,
    cTrans,
    0,
    c,
    0,
    0,
    cTrans,
    0,
    0,
    c,
    0,
    cTrans,
    0,
    0,
    0,
    1,
    0,
  ];

  final bTrans = a.brightness * 2.55;
  final bri = <double>[
    1,
    0,
    0,
    0,
    bTrans,
    0,
    1,
    0,
    0,
    bTrans,
    0,
    0,
    1,
    0,
    bTrans,
    0,
    0,
    0,
    1,
    0,
  ];

  return composeColorMatrices(
    bri,
    composeColorMatrices(
      con,
      composeColorMatrices(sat, composeColorMatrices(warmM, expM)),
    ),
  );
}

void main() {
  group(
    'ImageAdjustments.colorMatrix — equivalence with prior composition',
    () {
      // Ten representative parameter sets covering the corners and the
      // middle of the configurable space. Each must produce a matrix
      // byte-identical to the reference inline composition.
      final cases = <ImageAdjustments>[
        ImageAdjustments(),
        ImageAdjustments(brightness: 50),
        ImageAdjustments(brightness: -75),
        ImageAdjustments(contrast: 1.4),
        ImageAdjustments(contrast: 0.6),
        ImageAdjustments(saturation: 0),
        ImageAdjustments(saturation: 1.8),
        ImageAdjustments(exposure: 30),
        ImageAdjustments(warmth: -60),
        ImageAdjustments(
          brightness: 12,
          contrast: 1.1,
          saturation: 0.9,
          exposure: -5,
          warmth: 7,
        ),
      ];

      for (var i = 0; i < cases.length; i++) {
        final a = cases[i];
        test('case #$i matches reference composition', () {
          final got = a.colorMatrix;
          final want = _referenceMatrix(a);
          expect(got.length, 20);
          expect(want.length, 20);
          for (var j = 0; j < 20; j++) {
            // Byte-identical: same operations in the same order on the
            // same inputs must produce bit-equal IEEE-754 doubles.
            expect(
              got[j],
              want[j],
              reason: 'matrix element $j differs for case $i',
            );
          }
        });
      }
    },
  );

  group('ImageAdjustments.colorMatrix — cache identity', () {
    test('repeated reads return the same List instance', () {
      final a = ImageAdjustments(brightness: 10, contrast: 1.2);
      final first = a.colorMatrix;
      final second = a.colorMatrix;
      // The whole point of `late final` here: one allocation per
      // instance, then every subsequent read hands back the same list.
      expect(identical(first, second), isTrue);
    });

    test('identity singleton caches its own matrix', () {
      final m1 = ImageAdjustments.identity.colorMatrix;
      final m2 = ImageAdjustments.identity.colorMatrix;
      expect(identical(m1, m2), isTrue);
      expect(m1.length, 20);
    });
  });

  group('ImageAdjustments.colorMatrix — cache independence', () {
    test('different instances do not share a cache slot', () {
      final a = ImageAdjustments(brightness: 10);
      final b = ImageAdjustments(brightness: 20);
      final ma = a.colorMatrix;
      final mb = b.colorMatrix;
      expect(identical(ma, mb), isFalse);
      expect(ma, isNot(equals(mb)));
    });

    test(
      'copyWith produces a fresh cache slot, leaving the source untouched',
      () {
        // The semantic-correctness gate. If `copyWith` ever started
        // sharing a cache list with `this`, mutating one would bleed
        // into the other — and worse, the wrong matrix would render.
        // Immutability of the fields makes this unreachable in practice,
        // but we wedge it closed anyway.
        final a = ImageAdjustments(brightness: 0.5);
        final b = a.copyWith(contrast: 0.3);
        final ma = a.colorMatrix; // realize a's cache
        final mb = b.colorMatrix; // realize b's cache
        expect(identical(ma, mb), isFalse);
        expect(ma, isNot(equals(mb)));
        // a's cache is unchanged after b realizes its own cache.
        expect(identical(a.colorMatrix, ma), isTrue);
      },
    );

    test(
      'two instances with equal field values still compute independent caches',
      () {
        // == is value-equality, but the cache lives on the instance —
        // two equal-value `ImageAdjustments` are still two objects with
        // two cache slots. Equal values, distinct lists, equal contents.
        final a = ImageAdjustments(exposure: 5);
        final b = ImageAdjustments(exposure: 5);
        expect(a, equals(b));
        final ma = a.colorMatrix;
        final mb = b.colorMatrix;
        expect(identical(ma, mb), isFalse);
        expect(ma, equals(mb));
      },
    );
  });
}
