import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';

void main() {
  group('UnknownEffect forward-compat', () {
    test('decoding an unknown effect type yields an UnknownEffect carrier '
        'instead of throwing', () {
      final json = <String, dynamic>{
        'type': 'someFutureEffect_v9',
        'amount': 0.42,
        'extra': <String, dynamic>{'nested': true},
      };

      final effect = EditorEffect.fromJson(json);

      expect(effect, isA<UnknownEffect>());
      expect(effect.type, 'someFutureEffect_v9');
      // Must contribute nothing to render or matrix composition —
      // an unknown effect must never accidentally affect pixels.
      expect(effect.contributes, isFalse);
      expect(effect.enabled, isFalse);
    });

    test('toJson round-trips the original payload byte-for-byte', () {
      final original = <String, dynamic>{
        'type': 'futureBlur',
        'sigma': 8.0,
        'channels': <String>['r', 'g', 'b'],
      };

      final effect = EditorEffect.fromJson(original);
      final encoded = effect.toJson();

      expect(encoded, equals(original));
    });

    test('an EffectStack containing an unknown effect composes a null '
        'colour matrix (no contribution) and exposes no custom-paint '
        'overlay', () {
      final stack = EffectStack(<EditorEffect>[
        EditorEffect.fromJson(<String, dynamic>{'type': 'futureFx'}),
      ]);

      expect(stack.composedColorMatrix, isNull);
      expect(stack.hasContributingCustomPaint, isFalse);
      expect(stack.customPaintEffects, isEmpty);
    });

    test('unknown effects round-trip inside an EffectStack via toJson / '
        'fromJson without losing their original payload', () {
      final original = <String, dynamic>{
        'type': 'futureGrain',
        'amount': 0.25,
      };

      final stack = EffectStack(<EditorEffect>[
        EditorEffect.fromJson(original),
      ]);

      final encoded = stack.toJson();
      final reread = EffectStack.fromJson(encoded);

      expect(reread.length, 1);
      expect(reread.effects.single, isA<UnknownEffect>());
      expect(reread.effects.single.toJson(), equals(original));
    });
  });
}
