import 'package:canvas_engine/features/editor/engine/commands/history_stack.dart';
import 'package:canvas_engine/features/editor/engine/commands/image_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_mask.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

ImageLayer _makeImage({
  EffectStack effects = EffectStack.empty,
}) =>
    ImageLayer(
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
  group('Color adjustment effects — serialization', () {
    test('every concrete round-trips through the codec', () {
      final stack = EffectStack(<EditorEffect>[
        const ExposureEffect(amount: 25),
        const WarmthEffect(amount: -40),
        const SaturationEffect(amount: 1.5),
        const ContrastEffect(amount: 1.2),
        const BrightnessEffect(amount: 30),
      ]);
      final layer = _makeImage(effects: stack);
      final raw = DocumentCodec.encode(_doc(layer));
      final back = DocumentCodec.decode(raw).layers.single as ImageLayer;
      expect(back.effects, stack);
      expect(DocumentCodec.encode(_doc(back)), raw);
    });

    test('disabled flag and mask survive round-trip', () {
      const mask = RectMask(
        rect: Rect.fromLTWH(0.1, 0.25, 0.5, 0.5),
      );
      final stack = EffectStack(<EditorEffect>[
        const BrightnessEffect(amount: 50, enabled: false, mask: mask),
      ]);
      final layer = _makeImage(effects: stack);
      final raw = DocumentCodec.encode(_doc(layer));
      final back = DocumentCodec.decode(raw).layers.single as ImageLayer;
      final eff = back.effects.effects.single as BrightnessEffect;
      expect(eff.amount, 50);
      expect(eff.enabled, false);
      expect(eff.mask, mask);
    });

    test('identity-valued adjustments project to an empty effect list',
        () {
      final adj = ImageAdjustments();
      expect(adj.toEffectStack(), isEmpty);
    });

    test('non-identity adjustments project preserving fixed order', () {
      final adj = ImageAdjustments(
        brightness: 10,
        contrast: 1.4,
        saturation: 0.8,
        exposure: 5,
        warmth: -10,
      );
      final effects = adj.toEffectStack();
      expect(effects.map((e) => e.type).toList(), <String>[
        'exposure',
        'warmth',
        'saturation',
        'contrast',
        'brightness',
      ]);
    });
  });

  group('SetImageAdjustmentsCommand — dual-write', () {
    test('mirrors adjustments into the layer effect stack', () {
      final start = _doc(_makeImage());
      final next = const SetImageAdjustmentsCommand(
        layerId: 'img',
        brightness: 20,
        contrast: 1.3,
      ).apply(start);
      final layer = next.layers.single as ImageLayer;
      expect(layer.adjustments.brightness, 20);
      expect(layer.adjustments.contrast, 1.3);
      // Stack should contain exactly the two non-identity effects in
      // canonical order (contrast then brightness).
      expect(
        layer.effects.effects.map((e) => e.type).toList(),
        <String>['contrast', 'brightness'],
      );
    });

    test('preserves a masked derived effect the sliders cannot see', () {
      // A masked brightness is invisible to fromEffectStack (and so
      // to the Adjust sliders) — a contrast drag must leave it
      // untouched, not strip it as a stale derived entry.
      const preserved = BrightnessEffect(
        amount: 5,
        mask: RectMask(rect: Rect.fromLTRB(0, 0, 0.5, 0.5)),
      );
      final start = _doc(
        _makeImage(effects: EffectStack(<EditorEffect>[preserved])),
      );
      final after = const SetImageAdjustmentsCommand(
        layerId: 'img',
        contrast: 1.2,
      ).apply(start);
      final stack = (after.layers.single as ImageLayer).effects.effects;
      expect(stack.map((e) => e.type).toList(), <String>[
        'contrast',
        'brightness',
      ]);
      final survivor = stack[1] as BrightnessEffect;
      expect(survivor.amount, 5);
      expect(survivor.mask, preserved.mask);
    });

    test('preserves a disabled derived effect (Effects-panel eyeball)', () {
      // The headline bug: toggle brightness off in the Effects
      // panel, drag any Adjust slider — the old strip-and-regenerate
      // rebuild deleted the disabled effect and its amount.
      final start = _doc(_makeImage(
        effects: EffectStack(<EditorEffect>[
          const BrightnessEffect(amount: 20, enabled: false),
        ]),
      ));
      final after = const SetImageAdjustmentsCommand(
        layerId: 'img',
        contrast: 1.2,
      ).apply(start);
      final layer = after.layers.single as ImageLayer;
      expect(layer.adjustments.contrast, 1.2);
      expect(layer.adjustments.brightness, 0,
          reason: 'disabled effects stay invisible to the sliders');
      final disabled = layer.effects.effects
          .whereType<BrightnessEffect>()
          .single;
      expect(disabled.enabled, isFalse);
      expect(disabled.amount, 20,
          reason: 'the disabled effect and its amount must survive '
              'unrelated slider drags');
    });

    test('edits the live effect in place, preserving user reorder', () {
      // User reordered brightness *below* saturation in the Effects
      // panel; dragging the brightness slider must edit it where it
      // sits, not regenerate the canonical order.
      final start = _doc(_makeImage(
        effects: EffectStack(<EditorEffect>[
          const BrightnessEffect(amount: 12),
          const SaturationEffect(amount: 0.8),
        ]),
      ));
      final after = const SetImageAdjustmentsCommand(
        layerId: 'img',
        brightness: 20,
      ).apply(start);
      final stack = (after.layers.single as ImageLayer).effects.effects;
      expect(stack.map((e) => e.type).toList(), <String>[
        'brightness',
        'saturation',
      ]);
      expect((stack.first as BrightnessEffect).amount, 20);
    });

    test('identity drag removes only the live instance, in place', () {
      final start = _doc(_makeImage(
        effects: EffectStack(<EditorEffect>[
          const SaturationEffect(amount: 0.8),
          const ContrastEffect(amount: 1.2),
          const BrightnessEffect(amount: 12),
        ]),
      ));
      final after = const SetImageAdjustmentsCommand(
        layerId: 'img',
        contrast: 1,
      ).apply(start);
      final stack = (after.layers.single as ImageLayer).effects.effects;
      expect(stack.map((e) => e.type).toList(), <String>[
        'saturation',
        'brightness',
      ]);
    });

    test('undo restores the exact stack: order, disabled entries', () {
      // Worst case for a value-replay inverse: a reordered stack
      // (contrast above... below? — contrast first, saturation
      // second is NON-canonical) plus a disabled entry, then a drag
      // to identity which *removes* the contrast. Only a verbatim
      // stack restore brings back the original arrangement.
      final seed = EffectStack(<EditorEffect>[
        const ContrastEffect(amount: 1.2),
        const SaturationEffect(amount: 0.8),
        const BrightnessEffect(amount: 20, enabled: false),
      ]);
      var doc = _doc(_makeImage(effects: seed));
      final history = HistoryStack();
      doc = history.execute(
        doc,
        const SetImageAdjustmentsCommand(layerId: 'img', contrast: 1),
      );
      expect(
        (doc.layers.single as ImageLayer)
            .effects
            .effects
            .map((e) => e.type)
            .toList(),
        <String>['saturation', 'brightness'],
      );

      doc = history.undo(doc);
      expect((doc.layers.single as ImageLayer).effects, equals(seed),
          reason: 'invert(before).apply(after) must reproduce the '
              'pre-drag stack verbatim');
    });

    test('clearing adjustments empties the derived effect stack', () {
      final start = _doc(_makeImage(
        effects: EffectStack(<EditorEffect>[
          const BrightnessEffect(amount: 30),
        ]),
      ));
      final cleared = const SetImageAdjustmentsCommand(
        layerId: 'img',
        brightness: 0,
      ).apply(start);
      final layer = cleared.layers.single as ImageLayer;
      expect(layer.adjustments.brightness, 0);
      expect(layer.effects.effects, isEmpty);
      expect(identical(layer.effects, EffectStack.empty), isTrue);
    });
  });
}
