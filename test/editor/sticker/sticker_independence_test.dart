// Regression suite for the "edit one sticker, the other turns black /
// disappears" bug.
//
// The historical failure mode was an Impeller atlas-state corruption
// triggered by `TextStyle.shadows` on color-emoji glyphs: editing
// sticker B caused sticker A to render as a solid black silhouette or
// to vanish for a frame. The renderer was hardened in two places:
//
//   1. [LayerRenderer] now keys its [RepaintBoundary] by `layer.id`
//      so the [RasterCache] can never alias one sticker's cached
//      raster onto another during heavy mutation.
//   2. [TextLayer]'s sticker render path (see `_buildStickerContent`)
//      composes the drop-shadow as a manually stacked, blurred and
//      colour-filtered copy of the same glyph instead of attaching
//      `TextStyle.shadows` to the color-emoji.
//
// These tests cover the model-layer invariants the bug demanded:
// editing one sticker must never mutate another, copyWith must
// preserve every sticker field, JSON round-trip must preserve every
// sticker field, and the rendering tree must expose stable per-layer
// keys (so future regressions cannot silently re-introduce raster
// aliasing).
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/text_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/engine/rendering/layer_renderer.dart';
import 'package:canvas_engine/features/editor/sticker/presentation/sticker_style_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

TextLayer _sticker({
  required String id,
  required String emoji,
  Offset position = Offset.zero,
  Size size = const Size(120, 120),
  TextStyleSpec style = const TextStyleSpec(),
}) {
  return TextLayer(
    id: id,
    transform: LayerTransform(position: position, size: size),
    content: emoji,
    style: style,
    kind: TextLayerKind.emojiSticker,
  );
}

ProviderContainer _container() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  c.read(documentControllerProvider.notifier).newDocument(
        width: 800,
        height: 800,
      );
  return c;
}

void main() {
  group('sticker layer model independence', () {
    test(
      'TextLayer.copyWith preserves transform / visibility / locked / '
      'opacity / kind',
      () {
        final original = TextLayer(
          id: 'a',
          transform: const LayerTransform(
            position: Offset(40, 50),
            size: Size(120, 130),
            rotation: 0.7,
          ),
          content: '\u{1F600}',
          style: const TextStyleSpec(
            shadowColor: Color(0x4D000000),
            shadowBlur: 12,
            shadowOffset: Offset(0, 6),
          ),
          kind: TextLayerKind.emojiSticker,
          name: 'happy',
          visible: false,
          locked: true,
          opacity: 0.42,
        );

        final copy = original.copyWith(content: '\u{1F602}');

        expect(copy.id, original.id);
        expect(copy.transform, original.transform);
        expect(copy.style, original.style);
        expect(copy.kind, TextLayerKind.emojiSticker);
        expect(copy.isSticker, isTrue);
        expect(copy.name, original.name);
        expect(copy.visible, isFalse);
        expect(copy.locked, isTrue);
        expect(copy.opacity, closeTo(0.42, 1e-9));
        expect(copy.content, '\u{1F602}');
      },
    );

    test('TextLayer.toJson \u2194 fromJson preserves every sticker field', () {
      final original = TextLayer(
        id: 'sticker-1',
        transform: const LayerTransform(
          position: Offset(10, 20),
          size: Size(110, 120),
          rotation: -0.3,
        ),
        content: '\u{1F525}',
        style: const TextStyleSpec(
          shadowColor: Color(0xFF000000),
          shadowBlur: 2,
          shadowOffset: Offset.zero,
        ),
        kind: TextLayerKind.emojiSticker,
        name: 'fire',
        visible: true,
        locked: false,
        opacity: 0.81,
      );
      final restored = TextLayer.fromJson(original.toJson());
      expect(restored, equals(original));
      expect(restored.kind, TextLayerKind.emojiSticker);
      expect(restored.style.shadowColor, original.style.shadowColor);
      expect(restored.style.shadowBlur, original.style.shadowBlur);
      expect(restored.style.shadowOffset, original.style.shadowOffset);
      expect(restored.opacity, closeTo(original.opacity, 1e-9));
    });

    test(
      'editing sticker B\u2019s style does not mutate sticker A\u2019s style or '
      'transform',
      () {
        final c = _container();
        final a = _sticker(
          id: 'A',
          emoji: '\u{1F600}',
          position: const Offset(50, 50),
        );
        final b = _sticker(
          id: 'B',
          emoji: '\u{1F525}',
          position: const Offset(300, 300),
        );
        c.read(documentControllerProvider.notifier).execute(AddLayerCommand(a));
        c.read(documentControllerProvider.notifier).execute(AddLayerCommand(b));

        // Apply the "Pop" preset to sticker B only.
        final bAfter = c.read(documentControllerProvider).layerById('B')!
            as TextLayer;
        final preset = StickerStylePreset.pop;
        c.read(documentControllerProvider.notifier).execute(
              UpdateTextCommand(
                layerId: 'B',
                content: bAfter.content,
                style: preset.apply(bAfter.style),
              ),
            );

        final aFinal = c.read(documentControllerProvider).layerById('A')!
            as TextLayer;
        final bFinal = c.read(documentControllerProvider).layerById('B')!
            as TextLayer;

        // Sticker A is byte-identical to its original.
        expect(aFinal, equals(a),
            reason: 'sticker A must be untouched by edits to sticker B');
        expect(aFinal.style.shadowColor, isNull);
        expect(aFinal.transform, a.transform);

        // Sticker B picked up the preset.
        expect(bFinal.style.shadowColor, isNotNull);
        expect(bFinal.transform, b.transform,
            reason: 'style edit must not move sticker B either');
        expect(bFinal.id, 'B');
        expect(bFinal.content, '\u{1F525}');
      },
    );

    test(
      'resizing sticker B does not move or resize sticker A',
      () {
        final c = _container();
        final a = _sticker(
          id: 'A',
          emoji: '\u{1F600}',
          position: const Offset(50, 50),
          size: const Size(120, 120),
        );
        final b = _sticker(
          id: 'B',
          emoji: '\u{1F525}',
          position: const Offset(300, 300),
          size: const Size(120, 120),
        );
        c.read(documentControllerProvider.notifier).execute(AddLayerCommand(a));
        c.read(documentControllerProvider.notifier).execute(AddLayerCommand(b));

        c.read(documentControllerProvider.notifier).execute(
              ResizeLayerCommand(
                layerId: 'B',
                transform: b.transform.copyWith(size: const Size(240, 240)),
              ),
            );

        final aFinal =
            c.read(documentControllerProvider).layerById('A')! as TextLayer;
        final bFinal =
            c.read(documentControllerProvider).layerById('B')! as TextLayer;
        expect(aFinal.transform, a.transform,
            reason: 'sticker A must not move when sticker B is resized');
        expect(bFinal.transform.size, const Size(240, 240));
      },
    );

    test('every StickerStylePreset round-trips through JSON', () {
      for (final preset in StickerStylePreset.values) {
        final styled = preset.apply(const TextStyleSpec());
        final layer = _sticker(id: preset.name, emoji: '\u{1F600}',
            style: styled);
        final restored = TextLayer.fromJson(layer.toJson());
        expect(restored.style, styled,
            reason: 'preset ${preset.name} must serialise losslessly');
        expect(restored.kind, TextLayerKind.emojiSticker);
      }
    });
  });

  group('sticker layer rendering keys', () {
    testWidgets(
      'LayerRenderer wraps each sticker in a RepaintBoundary keyed by '
      'layer.id (no raster aliasing across siblings)',
      (tester) async {
        final a = _sticker(id: 'A', emoji: '\u{1F600}');
        final b = _sticker(id: 'B', emoji: '\u{1F525}');

        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.ltr,
              child: Stack(
                children: [
                  LayerRenderer(layer: a, transform: a.transform),
                  LayerRenderer(layer: b, transform: b.transform),
                ],
              ),
            ),
          ),
        );

        final boundaries = find
            .byWidgetPredicate((w) => w is RepaintBoundary && w.key != null)
            .evaluate()
            .map((e) => (e.widget as RepaintBoundary).key)
            .whereType<ValueKey<String>>()
            .toList();
        expect(boundaries, contains(const ValueKey<String>('layer-rb-A')));
        expect(boundaries, contains(const ValueKey<String>('layer-rb-B')));
      },
    );

    testWidgets(
      'sticker render path does NOT paint via Text widgets at all '
      '(Impeller color-glyph atlas-corruption guard)',
      (tester) async {
        // The sticker render path was hardened a second time after a
        // regression where scaling one sticker made siblings disappear:
        // even without `TextStyle.shadows`, painting a color emoji as
        // a `Text` widget under an `ImageFiltered` saveLayer (or just
        // re-recording it every gesture frame) could still corrupt the
        // color-glyph atlas and erase sibling stickers' draws. The
        // fix pre-rasterises every glyph to a `ui.Image` and renders
        // it via [RawImage], bypassing the color-glyph atlas at paint
        // time. This test enforces the invariant that the sticker
        // subtree contains zero `Text` widgets so the broken path
        // cannot silently sneak back in.
        final styled = StickerStylePreset.pop.apply(const TextStyleSpec());
        final s = _sticker(id: 'X', emoji: '\u{1F525}', style: styled);

        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.ltr,
              child: SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  children: [
                    LayerRenderer(layer: s, transform: s.transform),
                  ],
                ),
              ),
            ),
          ),
        );

        // The sticker subtree must paint via RawImage, not Text. We
        // scope the search to the LayerRenderer subtree so unrelated
        // chrome elsewhere in a future MaterialApp doesn't false-pass
        // this assertion.
        final layerFinder = find.byType(LayerRenderer);
        expect(layerFinder, findsOneWidget);
        expect(
          find.descendant(of: layerFinder, matching: find.byType(Text)),
          findsNothing,
          reason: 'sticker glyphs must be pre-rasterised to a ui.Image '
              'and painted via RawImage \u2014 painting them as Text would '
              're-introduce the color-glyph atlas corruption that makes '
              'sibling stickers vanish during a scale gesture.',
        );
        expect(
          find.descendant(of: layerFinder, matching: find.byType(RawImage)),
          findsWidgets,
          reason: 'sticker body must be rendered through RawImage so it '
              'goes through the regular image atlas, not the color-glyph '
              'atlas.',
        );
      },
    );
  });
}
