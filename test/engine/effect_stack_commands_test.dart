import 'package:canvas_engine/features/editor/engine/commands/image_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

ImageLayer _img({EffectStack effects = EffectStack.empty}) => ImageLayer(
  id: 'img',
  transform: const LayerTransform(position: Offset.zero, size: Size(100, 100)),
  source: const ImageSource.asset('assets/test.png'),
  effects: effects,
);

EditorDocument _doc(ImageLayer layer) =>
    EditorDocument(layers: [layer], width: 200, height: 200);

EditorDocument _seed() => _doc(
  _img(
    effects: const EffectStack(<EditorEffect>[
      BrightnessEffect(amount: 20),
      ContrastEffect(amount: 1.4),
      VignetteEffect(intensity: 0.5),
    ]),
  ),
);

void main() {
  group('ReorderEffectCommand', () {
    test('moves an effect from oldIndex to newIndex', () {
      final after = const ReorderEffectCommand(
        layerId: 'img',
        oldIndex: 0,
        newIndex: 2,
      ).apply(_seed());
      final next = (after.layers.single as ImageLayer).effects.effects;
      expect(next[0], const ContrastEffect(amount: 1.4));
      expect(next[1], const VignetteEffect(intensity: 0.5));
      expect(next[2], const BrightnessEffect(amount: 20));
    });

    test('noop when oldIndex == newIndex', () {
      final start = _seed();
      final after = const ReorderEffectCommand(
        layerId: 'img',
        oldIndex: 1,
        newIndex: 1,
      ).apply(start);
      expect(identical(after, start), isTrue);
    });

    test('noop on out-of-range indices', () {
      final start = _seed();
      expect(
        identical(
          const ReorderEffectCommand(
            layerId: 'img',
            oldIndex: 99,
            newIndex: 0,
          ).apply(start),
          start,
        ),
        isTrue,
      );
      expect(
        identical(
          const ReorderEffectCommand(
            layerId: 'img',
            oldIndex: 0,
            newIndex: -1,
          ).apply(start),
          start,
        ),
        isTrue,
      );
    });

    test('round-trip via invert restores byte-identical document', () {
      final start = _seed();
      final raw = DocumentCodec.encode(start);
      const fwd = ReorderEffectCommand(
        layerId: 'img',
        oldIndex: 0,
        newIndex: 2,
      );
      final restored = fwd.invert(start).apply(fwd.apply(start));
      expect(DocumentCodec.encode(restored), raw);
    });

    test('does not merge', () {
      const a = ReorderEffectCommand(layerId: 'img', oldIndex: 0, newIndex: 1);
      const b = ReorderEffectCommand(layerId: 'img', oldIndex: 1, newIndex: 2);
      expect(b.mergeWith(a), isNull);
    });
  });

  group('ToggleEffectEnabledCommand', () {
    test('flips enabled on the addressed effect', () {
      final after = const ToggleEffectEnabledCommand(
        layerId: 'img',
        index: 0,
      ).apply(_seed());
      final eff = (after.layers.single as ImageLayer).effects.effects[0];
      expect(eff.enabled, isFalse);
      expect(eff, isA<BrightnessEffect>());
    });

    test('toggle twice is the identity', () {
      final start = _seed();
      final raw = DocumentCodec.encode(start);
      final once = const ToggleEffectEnabledCommand(
        layerId: 'img',
        index: 1,
      ).apply(start);
      final twice = const ToggleEffectEnabledCommand(
        layerId: 'img',
        index: 1,
      ).apply(once);
      expect(DocumentCodec.encode(twice), raw);
    });

    test('invert undoes a toggle', () {
      final start = _seed();
      const fwd = ToggleEffectEnabledCommand(layerId: 'img', index: 2);
      final restored = fwd.invert(start).apply(fwd.apply(start));
      expect(DocumentCodec.encode(restored), DocumentCodec.encode(start));
    });

    test('noop on out-of-range index', () {
      final start = _seed();
      final after = const ToggleEffectEnabledCommand(
        layerId: 'img',
        index: 99,
      ).apply(start);
      expect(identical(after, start), isTrue);
    });

    test('does not merge', () {
      const a = ToggleEffectEnabledCommand(layerId: 'img', index: 0);
      const b = ToggleEffectEnabledCommand(layerId: 'img', index: 0);
      expect(b.mergeWith(a), isNull);
    });
  });

  group('DeleteEffectCommand', () {
    test('removes the effect at index', () {
      final after = const DeleteEffectCommand(
        layerId: 'img',
        index: 1,
      ).apply(_seed());
      final next = (after.layers.single as ImageLayer).effects.effects;
      expect(next.length, 2);
      expect(next[0], const BrightnessEffect(amount: 20));
      expect(next[1], const VignetteEffect(intensity: 0.5));
    });

    test('noop on out-of-range index', () {
      final start = _seed();
      final after = const DeleteEffectCommand(
        layerId: 'img',
        index: 99,
      ).apply(start);
      expect(identical(after, start), isTrue);
    });

    test('invert re-inserts at the original index byte-identically', () {
      final start = _seed();
      final raw = DocumentCodec.encode(start);
      const fwd = DeleteEffectCommand(layerId: 'img', index: 1);
      final restored = fwd.invert(start).apply(fwd.apply(start));
      expect(DocumentCodec.encode(restored), raw);
    });

    test('deleting the last effect leaves an empty stack', () {
      final start = _doc(
        _img(
          effects: const EffectStack(<EditorEffect>[
            BrightnessEffect(amount: 10),
          ]),
        ),
      );
      final after = const DeleteEffectCommand(
        layerId: 'img',
        index: 0,
      ).apply(start);
      final layer = after.layers.single as ImageLayer;
      expect(layer.effects.isEmpty, isTrue);
      // And restoring should be a clean round-trip.
      const fwd = DeleteEffectCommand(layerId: 'img', index: 0);
      final restored = fwd.invert(start).apply(after);
      expect(DocumentCodec.encode(restored), DocumentCodec.encode(start));
    });

    test('does not merge', () {
      const a = DeleteEffectCommand(layerId: 'img', index: 0);
      const b = DeleteEffectCommand(layerId: 'img', index: 0);
      expect(b.mergeWith(a), isNull);
    });
  });

  group('Codec stability after reorder', () {
    test('reorder + serialise + deserialise preserves new order', () {
      final start = _seed();
      final after = const ReorderEffectCommand(
        layerId: 'img',
        oldIndex: 2,
        newIndex: 0,
      ).apply(start);
      final raw = DocumentCodec.encode(after);
      final back = DocumentCodec.decode(raw).layers.single as ImageLayer;
      expect(back.effects.effects[0], const VignetteEffect(intensity: 0.5));
      expect(back.effects.effects[1], const BrightnessEffect(amount: 20));
      expect(back.effects.effects[2], const ContrastEffect(amount: 1.4));
      expect(DocumentCodec.encode(_doc(back)), raw);
    });
  });

  group('EditorEffect.withEnabled', () {
    test('preserves all subclass fields on every concrete', () {
      const effects = <EditorEffect>[
        BrightnessEffect(amount: 17),
        ContrastEffect(amount: 1.6),
        SaturationEffect(amount: 0.7),
        ExposureEffect(amount: -22),
        WarmthEffect(amount: 33),
        VignetteEffect(intensity: 0.6, feather: 0.3, color: Color(0xFF112233)),
      ];
      for (final eff in effects) {
        final off = eff.withEnabled(false);
        expect(
          off.enabled,
          isFalse,
          reason: 'enabled flip on ${eff.runtimeType}',
        );
        expect(off.runtimeType, eff.runtimeType);
        // Toggling back to true restores the original instance.
        expect(
          off.withEnabled(true),
          eff,
          reason: 'round-trip on ${eff.runtimeType}',
        );
      }
    });
  });
}
