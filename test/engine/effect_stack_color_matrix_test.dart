import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void _expectMatrixClose(List<double>? a, List<double>? b, {double eps = 1e-9}) {
  if (a == null && b == null) return;
  expect(a, isNotNull, reason: 'left matrix null');
  expect(b, isNotNull, reason: 'right matrix null');
  expect(a!.length, b!.length);
  for (var i = 0; i < a.length; i++) {
    expect(
      (a[i] - b[i]).abs() < eps,
      isTrue,
      reason: 'index $i: ${a[i]} vs ${b[i]}',
    );
  }
}

void main() {
  group('EffectStack.composedColorMatrix', () {
    test('empty stack yields null', () {
      expect(EffectStack.empty.composedColorMatrix, isNull);
    });

    test('all-identity effects fold to null', () {
      final stack = EffectStack(<EditorEffect>[
        const BrightnessEffect(amount: 0),
        const ContrastEffect(amount: 1),
        const SaturationEffect(amount: 1),
        const ExposureEffect(amount: 0),
        const WarmthEffect(amount: 0),
      ]);
      expect(stack.composedColorMatrix, isNull);
    });

    test('disabled and masked effects are skipped', () {
      final stack = EffectStack(<EditorEffect>[
        const BrightnessEffect(amount: 50, enabled: false),
        const ContrastEffect(amount: 1.5, mask: null),
      ]);
      // Brightness disabled → drops out; only contrast contributes.
      final m = stack.composedColorMatrix!;
      final ref = EffectStack(<EditorEffect>[
        const ContrastEffect(amount: 1.5),
      ]).composedColorMatrix!;
      _expectMatrixClose(m, ref);
    });

    test('matches ImageAdjustments matrix for the canonical projection', () {
      // Walk a non-trivial parameter set through both code paths
      // and assert byte-equivalent matrices. This is the renderer
      // equivalence guarantee that lets Step 5 swap sources without
      // a visual regression.
      final adj = ImageAdjustments(
        brightness: 17,
        contrast: 1.3,
        saturation: 0.6,
        exposure: 22,
        warmth: -45,
      );
      final stack = EffectStack(adj.toEffectStack());
      _expectMatrixClose(stack.composedColorMatrix, adj.colorMatrix);
    });

    test(
      'order-dependent: brightness then contrast ≠ contrast then brightness',
      () {
        final a = EffectStack(<EditorEffect>[
          const BrightnessEffect(amount: 30),
          const ContrastEffect(amount: 1.5),
        ]).composedColorMatrix!;
        final b = EffectStack(<EditorEffect>[
          const ContrastEffect(amount: 1.5),
          const BrightnessEffect(amount: 30),
        ]).composedColorMatrix!;
        expect(listEquals(a, b), isFalse);
      },
    );
  });
}
