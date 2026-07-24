import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';

/// Validates that [EffectStack.composedColorMatrix] is memoised by
/// stack identity: repeated calls on the same instance return the
/// same `List<double>` reference (cache hit), while a freshly built
/// stack with the same effect values produces an equal-but-distinct
/// matrix (cache miss — each instance has its own entry).
///
/// The cache is the difference between O(stack-length) matrix work
/// per render frame and O(1) reuse during slider drags.
void main() {
  group('EffectStack.composedColorMatrix memoisation', () {
    test('returns the same List instance on repeated calls', () {
      final stack = EffectStack(<EditorEffect>[
        const BrightnessEffect(amount: 12),
        const ContrastEffect(amount: 1.4),
      ]);
      final first = stack.composedColorMatrix;
      final second = stack.composedColorMatrix;
      expect(first, isNotNull);
      expect(
        identical(first, second),
        isTrue,
        reason:
            'composedColorMatrix should hit the per-instance '
            'Expando cache on the second call',
      );
    });

    test('returns null without throwing on a stack with no '
        'contributing effects, and the null answer is cached', () {
      final stack = EffectStack(<EditorEffect>[
        const BrightnessEffect(amount: 0), // identity
        const ContrastEffect(amount: ContrastEffect.identityAmount),
      ]);
      expect(stack.composedColorMatrix, isNull);
      // Second call must also return null, exercising the sentinel
      // cache path.
      expect(stack.composedColorMatrix, isNull);
    });

    test('two equal-by-value but distinct stack instances each '
        'compute their own matrix (identity cache, not value cache)', () {
      final a = EffectStack(<EditorEffect>[const BrightnessEffect(amount: 5)]);
      final b = EffectStack(<EditorEffect>[const BrightnessEffect(amount: 5)]);
      expect(a.composedColorMatrix, equals(b.composedColorMatrix));
      expect(
        identical(a.composedColorMatrix, b.composedColorMatrix),
        isFalse,
        reason: 'identity cache should not bridge across instances',
      );
    });

    test('an empty stack returns null and does not crash on cache '
        'lookups', () {
      const empty = EffectStack.empty;
      expect(empty.composedColorMatrix, isNull);
      expect(empty.composedColorMatrix, isNull);
    });
  });
}
