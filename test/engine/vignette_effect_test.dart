import 'package:canvas_engine/features/editor/engine/commands/image_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_mask.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

ImageLayer _makeImage({EffectStack effects = EffectStack.empty}) => ImageLayer(
      id: 'img',
      transform: const LayerTransform(
        position: Offset.zero,
        size: Size(100, 100),
      ),
      source: const ImageSource.asset('assets/test.png'),
      effects: effects,
    );

EditorDocument _doc(ImageLayer layer) =>
    EditorDocument(layers: [layer], width: 200, height: 200);

void main() {
  group('VignetteEffect — classification', () {
    test('declares the custom-paint render kind', () {
      const eff = VignetteEffect(intensity: 0.4);
      expect(eff.kind, EffectKind.customPaint);
    });

    test('contributes is false at intensity 0, true otherwise', () {
      expect(const VignetteEffect().contributes, isFalse);
      expect(const VignetteEffect(intensity: 0.01).contributes, isTrue);
    });

    test('color-matrix concretes still declare colorMatrix kind', () {
      expect(const BrightnessEffect(amount: 5).kind, EffectKind.colorMatrix);
      expect(const ContrastEffect(amount: 1.2).kind, EffectKind.colorMatrix);
      expect(const SaturationEffect(amount: 0.8).kind, EffectKind.colorMatrix);
      expect(const ExposureEffect(amount: 5).kind, EffectKind.colorMatrix);
      expect(const WarmthEffect(amount: 5).kind, EffectKind.colorMatrix);
    });
  });

  group('VignetteEffect — serialization', () {
    test('round-trips through the codec', () {
      const v = VignetteEffect(
        intensity: 0.4,
        feather: 0.3,
        color: Color(0xFF112233),
      );
      final layer = _makeImage(effects: const EffectStack(<EditorEffect>[v]));
      final raw = DocumentCodec.encode(_doc(layer));
      final back = DocumentCodec.decode(raw).layers.single as ImageLayer;
      expect(back.effects.effects.single, v);
      expect(DocumentCodec.encode(_doc(back)), raw);
    });

    test('default values are omitted from the JSON payload', () {
      const v = VignetteEffect();
      final json = v.toJson();
      expect(json['type'], 'vignette');
      expect(json.containsKey('intensity'), isFalse);
      expect(json.containsKey('feather'), isFalse);
      expect(json.containsKey('color'), isFalse);
    });

    test('disabled flag and mask survive round-trip', () {
      const mask = RectMask(rect: Rect.fromLTWH(0, 0, 0.5, 0.5));
      const v = VignetteEffect(
        intensity: 0.5,
        enabled: false,
        mask: mask,
      );
      final layer = _makeImage(effects: const EffectStack(<EditorEffect>[v]));
      final raw = DocumentCodec.encode(_doc(layer));
      final back = DocumentCodec.decode(raw).layers.single as ImageLayer;
      final eff = back.effects.effects.single as VignetteEffect;
      expect(eff.intensity, 0.5);
      expect(eff.enabled, isFalse);
      expect(eff.mask, mask);
    });
  });

  group('SetImageVignetteCommand', () {
    test('inserts a vignette when none exists and intensity > 0', () {
      final layer = _makeImage();
      final doc = _doc(layer);
      final after = const SetImageVignetteCommand(
        layerId: 'img',
        intensity: 0.4,
      ).apply(doc);
      final next = after.layers.single as ImageLayer;
      final v = next.effects.effects.single as VignetteEffect;
      expect(v.intensity, 0.4);
      expect(v.feather, VignetteEffect.defaultFeather);
    });

    test('removes the vignette when intensity goes back to 0', () {
      final start = _doc(_makeImage(
        effects: const EffectStack(<EditorEffect>[
          VignetteEffect(intensity: 0.6),
        ]),
      ));
      final after = const SetImageVignetteCommand(
        layerId: 'img',
        intensity: 0,
      ).apply(start);
      final next = after.layers.single as ImageLayer;
      expect(next.effects.isEmpty, isTrue);
    });

    test('round-trip "set then clear" is byte-identical to never set', () {
      final clean = _doc(_makeImage());
      final cleanRaw = DocumentCodec.encode(clean);
      final touched = const SetImageVignetteCommand(
        layerId: 'img',
        intensity: 0.5,
      ).apply(clean);
      final cleared = const SetImageVignetteCommand(
        layerId: 'img',
        intensity: 0,
      ).apply(touched);
      expect(DocumentCodec.encode(cleared), cleanRaw);
    });

    test('preserves other effects on the stack when toggling vignette', () {
      final start = _doc(_makeImage(
        effects: const EffectStack(<EditorEffect>[
          BrightnessEffect(amount: 20),
          ContrastEffect(amount: 1.2),
        ]),
      ));
      final after = const SetImageVignetteCommand(
        layerId: 'img',
        intensity: 0.3,
      ).apply(start);
      final next = after.layers.single as ImageLayer;
      expect(next.effects.length, 3);
      expect(next.effects.effects.last, isA<VignetteEffect>());
      expect(next.effects.effects[0], const BrightnessEffect(amount: 20));
      expect(next.effects.effects[1], const ContrastEffect(amount: 1.2));
    });

    test('is a noop when no change would result', () {
      final clean = _doc(_makeImage());
      final after = const SetImageVignetteCommand(
        layerId: 'img',
        intensity: 0,
      ).apply(clean);
      expect(identical(after, clean), isTrue);
    });

    test('invert restores all three knobs atomically', () {
      final before = _doc(_makeImage(
        effects: const EffectStack(<EditorEffect>[
          VignetteEffect(
            intensity: 0.6,
            feather: 0.2,
            color: Color(0xFF222244),
          ),
        ]),
      ));
      const fwd = SetImageVignetteCommand(
        layerId: 'img',
        intensity: 0.1,
      );
      final inverse = fwd.invert(before);
      final restored = inverse.apply(fwd.apply(before));
      final v = (restored.layers.single as ImageLayer)
          .effects
          .effects
          .single as VignetteEffect;
      expect(v.intensity, 0.6);
      expect(v.feather, 0.2);
      expect(v.color, const Color(0xFF222244));
    });

    test('mergeWith collapses live drags of the same field-set', () {
      const a = SetImageVignetteCommand(
        layerId: 'img',
        intensity: 0.3,
        live: true,
      );
      const b = SetImageVignetteCommand(
        layerId: 'img',
        intensity: 0.4,
        live: true,
      );
      final merged = b.mergeWith(a);
      expect(merged, same(b));
    });

    test('mergeWith refuses across different field-sets', () {
      const a = SetImageVignetteCommand(
        layerId: 'img',
        intensity: 0.3,
        live: true,
      );
      const b = SetImageVignetteCommand(
        layerId: 'img',
        feather: 0.4,
        live: true,
      );
      expect(b.mergeWith(a), isNull);
    });

    test('mergeWith refuses non-live commands', () {
      const a = SetImageVignetteCommand(
        layerId: 'img',
        intensity: 0.3,
      );
      const b = SetImageVignetteCommand(
        layerId: 'img',
        intensity: 0.4,
        live: true,
      );
      expect(b.mergeWith(a), isNull);
    });
  });

  group('Renderer dual-path equivalence', () {
    test('intensity-0 vignette stack does not contribute custom-paint', () {
      const stack = EffectStack(<EditorEffect>[
        VignetteEffect(intensity: 0),
      ]);
      expect(stack.hasContributingCustomPaint, isFalse);
      expect(stack.customPaintEffects, isEmpty);
    });

    test('disabled vignette is excluded from custom-paint pass', () {
      const stack = EffectStack(<EditorEffect>[
        VignetteEffect(intensity: 0.5, enabled: false),
      ]);
      expect(stack.hasContributingCustomPaint, isFalse);
    });

    test('masked vignette is excluded (per-effect mask not yet wired)', () {
      const stack = EffectStack(<EditorEffect>[
        VignetteEffect(
          intensity: 0.5,
          mask: RectMask(rect: Rect.fromLTWH(0, 0, 1, 1)),
        ),
      ]);
      expect(stack.hasContributingCustomPaint, isFalse);
    });

    test('vignette does NOT poison composedColorMatrix', () {
      const stack = EffectStack(<EditorEffect>[
        BrightnessEffect(amount: 20),
        VignetteEffect(intensity: 0.5),
      ]);
      final m = stack.composedColorMatrix;
      expect(m, isNotNull);
      expect(m![4], closeTo(20 * 2.55, 1e-9));
      expect(stack.customPaintEffects.length, 1);
    });
  });

  group('v3 byte-identity guarantee', () {
    test('encoding a vignette doc twice is stable', () {
      final layer = _makeImage(
        effects: const EffectStack(<EditorEffect>[
          VignetteEffect(intensity: 0.5, feather: 0.3),
        ]),
      );
      final once = DocumentCodec.encode(_doc(layer));
      final twice = DocumentCodec.encode(DocumentCodec.decode(once));
      expect(twice, once);
    });

    test('vignette presence triggers schema v3', () {
      final layer = _makeImage(
        effects: const EffectStack(<EditorEffect>[
          VignetteEffect(intensity: 0.4),
        ]),
      );
      final raw = DocumentCodec.encode(_doc(layer));
      expect(raw, contains('"version": 3'));
    });
  });
}
