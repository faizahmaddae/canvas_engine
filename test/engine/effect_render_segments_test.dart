import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/core/layer_mask.dart';
import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';

/// Step 6 segmentation (docs/effects-step6-per-effect-masks-2026-07.md
/// §3-§4): maximal unmasked colour-matrix runs compose into one
/// segment (associative — exact), masked effects are their own
/// boundaries (composing across a per-pixel blend is not).
void main() {
  const mask = RectMask(rect: Rect.fromLTWH(0, 0, 100, 50));

  EffectStack stack(List<EditorEffect> effects) =>
      EffectStack(List<EditorEffect>.unmodifiable(effects));

  group('hasEnabledMaskedEffect', () {
    test('false for unmasked, disabled-masked, and identity-masked', () {
      expect(stack([BrightnessEffect(amount: 10)]).hasEnabledMaskedEffect,
          isFalse);
      expect(
        stack([BrightnessEffect(amount: 10, enabled: false, mask: mask)])
            .hasEnabledMaskedEffect,
        isFalse,
        reason: 'disabled effects render on neither path',
      );
      expect(
        stack([BrightnessEffect(amount: 0, mask: mask)])
            .hasEnabledMaskedEffect,
        isFalse,
        reason: 'identity amounts contribute nothing to mask',
      );
      expect(EffectStack.empty.hasEnabledMaskedEffect, isFalse);
    });

    test('true for an enabled, contributing, masked effect', () {
      expect(
        stack([BrightnessEffect(amount: 10, mask: mask)])
            .hasEnabledMaskedEffect,
        isTrue,
      );
    });
  });

  group('renderSegments', () {
    test('all-unmasked stack folds to ONE segment equal to the memoised '
        'matrix', () {
      final s = stack([
        const SaturationEffect(amount: 0.8),
        BrightnessEffect(amount: 10),
        const ContrastEffect(amount: 1.2),
      ]);
      final segments = s.renderSegments;
      expect(segments, hasLength(1));
      final seg = segments.single as MatrixSegment;
      expect(listEquals(seg.matrix, s.composedColorMatrix), isTrue,
          reason: 'the fast path and the fold must agree exactly');
    });

    test('empty / identity-only stacks fold to zero segments', () {
      expect(EffectStack.empty.renderSegments, isEmpty);
      expect(stack([BrightnessEffect(amount: 0)]).renderSegments, isEmpty);
    });

    test('a masked effect splits the fold into three segments', () {
      final s = stack([
        const SaturationEffect(amount: 0.8),
        ContrastEffect(amount: 1.5, mask: mask),
        BrightnessEffect(amount: 10),
      ]);
      final segments = s.renderSegments;
      expect(segments, hasLength(3));
      expect(segments[0], isA<MatrixSegment>());
      final masked = segments[1] as MaskedEffectSegment;
      expect(masked.effect, isA<ContrastEffect>());
      expect(masked.effect.mask, mask);
      expect(segments[2], isA<MatrixSegment>());

      // The boundary is load-bearing: merging saturation and
      // brightness across the masked contrast would change pixels
      // inside the mask. Prove the outer segments are the individual
      // effects, not a merged pair.
      final satOnly =
          stack([const SaturationEffect(amount: 0.8)]).composedColorMatrix!;
      final brightOnly =
          stack([BrightnessEffect(amount: 10)]).composedColorMatrix!;
      expect(
        listEquals((segments[0] as MatrixSegment).matrix, satOnly),
        isTrue,
      );
      expect(
        listEquals((segments[2] as MatrixSegment).matrix, brightOnly),
        isTrue,
      );
    });

    test('disabled masked effect does not split the run', () {
      final s = stack([
        const SaturationEffect(amount: 0.8),
        ContrastEffect(amount: 1.5, enabled: false, mask: mask),
        BrightnessEffect(amount: 10),
      ]);
      final segments = s.renderSegments;
      expect(segments, hasLength(1),
          reason: 'a disabled effect is invisible to the fold, so the '
              'run stays maximal');
      final merged = stack([
        const SaturationEffect(amount: 0.8),
        BrightnessEffect(amount: 10),
      ]).composedColorMatrix!;
      expect(
        listEquals((segments.single as MatrixSegment).matrix, merged),
        isTrue,
      );
    });

    test('custom-paint effects never enter the fold', () {
      final s = stack([
        BrightnessEffect(amount: 10),
        const VignetteEffect(intensity: 0.5),
      ]);
      expect(s.renderSegments, hasLength(1));
    });

    test('consecutive masked effects are consecutive boundaries', () {
      const mask2 =
          RectMask(rect: Rect.fromLTWH(0, 50, 100, 50), inverted: true);
      final s = stack([
        BrightnessEffect(amount: 10, mask: mask),
        ContrastEffect(amount: 1.5, mask: mask2),
      ]);
      final segments = s.renderSegments;
      expect(segments, hasLength(2));
      expect((segments[0] as MaskedEffectSegment).effect.mask, mask);
      expect((segments[1] as MaskedEffectSegment).effect.mask, mask2);
    });
  });

  group('maskedCustomPaintEffects', () {
    test('selects only enabled, contributing, masked custom-paint', () {
      final s = stack([
        const VignetteEffect(intensity: 0.5, mask: mask),
        const VignetteEffect(intensity: 0.5),
        const VignetteEffect(intensity: 0, mask: mask),
        BrightnessEffect(amount: 10, mask: mask),
      ]);
      final masked = s.maskedCustomPaintEffects.toList();
      expect(masked, hasLength(1));
      expect((masked.single as VignetteEffect).intensity, 0.5);
    });
  });
}
