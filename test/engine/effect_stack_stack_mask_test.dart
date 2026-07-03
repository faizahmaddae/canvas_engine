import 'dart:convert';
import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/core/layer_mask.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:flutter_test/flutter_test.dart';

/// A3 Step 1 — `EffectStack.stackMask` model + serialization.
///
/// The load-bearing invariant (plan §6, trap #1): the `effects` JSON
/// key is gated on the raw effects LIST, never on a composite
/// emptiness. A stackMask-only stack must write NO `effects` key —
/// writing `'effects': []` would change the bytes of every legacy
/// document on disk.
void main() {
  const mask = RectMask(
    rect: Rect.fromLTWH(0, 0, 800, 400),
    feather: 12,
    inverted: true,
  );

  ImageLayer makeImage({EffectStack effects = EffectStack.empty}) =>
      ImageLayer(
        id: 'img-1',
        transform: const LayerTransform(
          position: Offset(100, 100),
          size: Size(200, 200),
        ),
        source: const ImageSource.asset('stub.png'),
        effects: effects,
      );

  group('EffectStack.stackMask — value semantics', () {
    test('== and hashCode include stackMask', () {
      final effects = List<EditorEffect>.unmodifiable(
        <EditorEffect>[BrightnessEffect(amount: 20)],
      );
      final without = EffectStack(effects);
      final withMask = EffectStack(effects, stackMask: mask);
      final withEqualMask = EffectStack(
        effects,
        stackMask: const RectMask(
          rect: Rect.fromLTWH(0, 0, 800, 400),
          feather: 12,
          inverted: true,
        ),
      );

      expect(withMask, equals(withEqualMask));
      expect(withMask.hashCode, equals(withEqualMask.hashCode));
      expect(withMask, isNot(equals(without)));
      expect(withMask.hashCode, isNot(equals(without.hashCode)));
    });

    test('isEmpty reflects the effects list only, never the mask', () {
      const maskOnly = EffectStack(<EditorEffect>[], stackMask: mask);
      expect(maskOnly.isEmpty, isTrue,
          reason: 'isEmpty gates the effects JSON key; folding the '
              'mask in would emit "effects": [] and break legacy bytes');
      expect(maskOnly.isNotEmpty, isFalse);
      expect(maskOnly.stackMask, equals(mask));
    });
  });

  group('EffectStack.stackMask — layer serialization', () {
    test('effects + stackMask round-trip through layer JSON', () {
      final layer = makeImage(
        effects: EffectStack(
          List<EditorEffect>.unmodifiable(
            <EditorEffect>[BrightnessEffect(amount: 20)],
          ),
          stackMask: mask,
        ),
      );

      final json = layer.toJson();
      expect(json['effects'], isNotNull);
      expect(json['stackMask'], isNotNull);

      final decoded = ImageLayer.fromJson(json);
      expect(decoded.effects, equals(layer.effects));
      expect(decoded.effects.stackMask, equals(mask));

      // Re-encode stability: encode → decode → encode is identical.
      expect(jsonEncode(decoded.toJson()), equals(jsonEncode(json)));
    });

    test('stackMask-only stack writes NO effects key (trap #1)', () {
      final layer = makeImage(
        effects: const EffectStack(<EditorEffect>[], stackMask: mask),
      );

      final json = layer.toJson();
      expect(json.containsKey('effects'), isFalse,
          reason: 'a stackMask-only stack must omit the effects key '
              'entirely — "effects": [] changes every legacy doc\'s bytes');
      expect(json['stackMask'], isNotNull);

      final decoded = ImageLayer.fromJson(json);
      expect(decoded.effects.isEmpty, isTrue);
      expect(decoded.effects.stackMask, equals(mask));
      expect(jsonEncode(decoded.toJson()), equals(jsonEncode(json)));
    });

    test('no stackMask writes no stackMask key', () {
      final layer = makeImage(
        effects: EffectStack(
          List<EditorEffect>.unmodifiable(
            <EditorEffect>[BrightnessEffect(amount: 20)],
          ),
        ),
      );

      final json = layer.toJson();
      expect(json.containsKey('stackMask'), isFalse);

      final decoded = ImageLayer.fromJson(json);
      expect(decoded.effects.stackMask, isNull);
      expect(jsonEncode(decoded.toJson()), equals(jsonEncode(json)));
    });

    test('empty stack stays byte-identical to pre-stackMask encoding', () {
      final layer = makeImage();
      final json = layer.toJson();
      expect(json.containsKey('effects'), isFalse);
      expect(json.containsKey('stackMask'), isFalse);
    });

    test('legacy adjustments lift preserves a decoded stackMask', () {
      // Hybrid shape: v3 stackMask alongside a leftover v2
      // `adjustments` map. Never produced by our writers, but decode
      // must not silently drop the mask on the lift path.
      final layer = makeImage();
      final json = layer.toJson();
      json['adjustments'] = <String, dynamic>{'brightness': 20.0};
      json['stackMask'] = mask.toJson();

      final decoded = ImageLayer.fromJson(json);
      expect(decoded.effects.effects, hasLength(1));
      expect(decoded.effects.effects.single, isA<BrightnessEffect>());
      expect(decoded.effects.stackMask, equals(mask));
    });
  });
}
