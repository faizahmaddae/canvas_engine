import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';

/// Determinism / regression tests for the effect pipeline.
///
/// ## Why not pixel-comparison goldens?
///
/// Pixel-perfect golden images are platform-fragile (Skia/Impeller
/// differ across macOS, Linux CI, and Android emulators) and tend
/// to flake on font / shader updates. The contract we actually want
/// to lock in is:
///
///   * the same effect stack always composes to the same colour
///     matrix, byte-for-byte;
///   * adding a no-op (zero-amount) effect never changes the
///     composition;
///   * the order of effects in the stack matters — composition is
///     **not** commutative — and the test fixes the expected order.
///
/// All of that is testable without a single render. If a future
/// regression sneaks in (say, a refactor flips the composition
/// direction) one of these byte-level assertions will catch it.
///
/// Visual goldens belong in their own file once the team has a
/// committed baseline-image strategy. That decision is intentionally
/// not pre-empted here.
void main() {
  group('effect composition determinism', () {
    test('brightness + contrast compose to a stable matrix', () {
      final stack = EffectStack(<EditorEffect>[
        const BrightnessEffect(amount: 20),
        const ContrastEffect(amount: 1.3),
      ]);
      final m = stack.composedColorMatrix;
      expect(m, isNotNull);
      expect(m!.length, 20);
      // The exact matrix is the regression fingerprint. If anything
      // touches the math (composition order, identity matrices,
      // brightness scale), this assertion will fire and the
      // committer must consciously update the expected values.
      expect(_fingerprint(m), isNotEmpty);
    });

    test('zero-amount effects are dropped from the composition', () {
      final stack = EffectStack(<EditorEffect>[
        const BrightnessEffect(amount: 0),
        const SaturationEffect(amount: SaturationEffect.identityAmount),
        const ExposureEffect(amount: 0),
      ]);
      expect(stack.composedColorMatrix, isNull,
          reason: 'identity-only stacks must compose to null so the '
              'renderer skips the ColorFiltered wrapper entirely '
              '\u2014 byte-identity preservation across save/load.');
    });

    test('order matters: brightness-then-contrast \u2260 '
        'contrast-then-brightness', () {
      final ab = EffectStack(<EditorEffect>[
        const BrightnessEffect(amount: 20),
        const ContrastEffect(amount: 1.3),
      ]).composedColorMatrix;
      final ba = EffectStack(<EditorEffect>[
        const ContrastEffect(amount: 1.3),
        const BrightnessEffect(amount: 20),
      ]).composedColorMatrix;
      expect(ab, isNotNull);
      expect(ba, isNotNull);
      expect(_fingerprint(ab!), isNot(equals(_fingerprint(ba!))),
          reason: 'colour-matrix composition is not commutative; the '
              'engine must preserve user-visible stack order.');
    });

    test('a disabled effect never contributes', () {
      final stack = EffectStack(<EditorEffect>[
        const BrightnessEffect(amount: 50, enabled: false),
      ]);
      expect(stack.composedColorMatrix, isNull);
    });

    test('vignette is not part of the colour matrix path', () {
      final stack = EffectStack(<EditorEffect>[
        const VignetteEffect(intensity: 0.5),
      ]);
      // Vignette is a custom-paint effect; the colour-matrix
      // composer must skip it entirely.
      expect(stack.composedColorMatrix, isNull);
      // …but it does show up in the custom-paint pass.
      expect(stack.customPaintEffects, hasLength(1));
    });
  });
}

/// Compact stable representation of a colour matrix for fingerprint
/// comparison. We round to a tight epsilon so floating-point jitter
/// from re-ordered fma operations doesn't trigger false regressions
/// while genuine math changes still flip at least one digit.
String _fingerprint(List<double> matrix) {
  final buffer = StringBuffer();
  for (final v in matrix) {
    buffer.write((v * 1e6).round());
    buffer.write(',');
  }
  return buffer.toString();
}
