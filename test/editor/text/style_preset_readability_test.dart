// Picking a style preset must not make the text invisible.
//
// Several presets are authored light-on-dark — `outline`, `neon`,
// `pop_3d`, `shadow_soft` all declare white with no background plate.
// `addCenteredText` has always run new text through
// [TextColorResolver]; applying a preset skipped it, so the one path
// where the USER does not choose the colour was the one path with no
// guard, and on the default white canvas those four presets applied
// white text to white paper.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/text/application/text_tool_controller.dart';
import 'package:canvas_engine/features/editor/text/application/text_color_resolver.dart';
import 'package:canvas_engine/features/editor/text/domain/text_style_presets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

TextLayer _text(String id) => TextLayer(
  id: id,
  transform: LayerTransform(
    position: const Offset(100, 100),
    size: const Size(400, 120),
  ),
  content: 'Hello',
  style: const TextStyleSpec(color: Color(0xFF111111)),
);

/// A document with one selected text layer.
///
/// [canvasFill] puts an opaque shape UNDER the text so the resolver
/// samples that instead of the default white paper — the only way to
/// exercise a backdrop other than white, which is what let a mid-grey
/// regression hide from the earlier white-only sweep.
ProviderContainer _withSelectedText({Color? canvasFill}) {
  final c = ProviderContainer();
  final ctrl = c.read(documentControllerProvider.notifier);
  ctrl.newDocument(width: 1080, height: 1080);
  if (canvasFill != null) {
    ctrl.execute(
      AddLayerCommand(
        ShapeLayer(
          id: 'bg',
          transform: LayerTransform(
            position: Offset.zero,
            size: const Size(1080, 1080),
          ),
          kind: ShapeKind.rectangle,
          fillColor: canvasFill,
        ),
      ),
    );
  }
  ctrl.execute(AddLayerCommand(_text('t')));
  c.read(selectionControllerProvider.notifier).select('t');
  return c;
}

void main() {
  group('applyStylePreset readability guard', () {
    test('white-on-nothing is re-resolved against a white canvas', () {
      final c = _withSelectedText();
      addTearDown(c.dispose);
      final ctrl = c.read(textToolControllerProvider.notifier);

      const whiteNoPlate = TextStyleSpec(color: Color(0xFFFFFFFF));
      final resolved = ctrl.readableOnCanvas(whiteNoPlate);

      expect(
        resolved.color,
        isNot(const Color(0xFFFFFFFF)),
        reason: 'white text on white paper is not a style, it is a bug',
      );
    });

    test('a preset with its own plate is left exactly as authored', () {
      final c = _withSelectedText();
      addTearDown(c.dispose);
      final ctrl = c.read(textToolControllerProvider.notifier);

      // The plate guarantees contrast, and the resolver samples the
      // DOCUMENT behind the layer — not what such a preset sits on.
      const plated = TextStyleSpec(
        color: Color(0xFFFFFFFF),
        backgroundColor: Color(0xFF111111),
      );
      expect(ctrl.readableOnCanvas(plated), same(plated));
    });

    // The guard's first version exempted only `backgroundColor`, so it
    // "fixed" white-on-white by turning `outline` — white fill inside a
    // 3dp BLACK stroke, legible on white by construction — into
    // near-black glyphs inside a near-black outline.
    test('a stroked preset is left alone even with no plate', () {
      final c = _withSelectedText();
      addTearDown(c.dispose);
      final ctrl = c.read(textToolControllerProvider.notifier);

      const stroked = TextStyleSpec(
        color: Color(0xFFFFFFFF),
        outlineColor: Color(0xFF000000),
        outlineWidth: 3,
      );
      expect(
        ctrl.readableOnCanvas(stroked),
        same(stroked),
        reason: 'the outline is what makes it legible; do not repaint it',
      );
    });

    test('a zero-width outline does NOT count as protection', () {
      final c = _withSelectedText();
      addTearDown(c.dispose);
      final ctrl = c.read(textToolControllerProvider.notifier);

      const bogus = TextStyleSpec(
        color: Color(0xFFFFFFFF),
        outlineColor: Color(0xFF000000),
        outlineWidth: 0,
      );
      expect(
        ctrl.readableOnCanvas(bogus).color,
        isNot(const Color(0xFFFFFFFF)),
      );
    });

    test('a legible colour is preserved, not normalised', () {
      final c = _withSelectedText();
      addTearDown(c.dispose);
      final ctrl = c.read(textToolControllerProvider.notifier);

      const legible = TextStyleSpec(color: Color(0xFF7A1F1F));
      expect(ctrl.readableOnCanvas(legible).color, const Color(0xFF7A1F1F));
    });

    // «نئون» is NOT in this set, and that is the point. An earlier
    // version of this test listed it as protected — the file's own
    // header names it as one of the four broken presets, and the test
    // then pinned the bug. Its glow is opaque cyan behind a near-white
    // fill: 1.79:1 fill-vs-glow, 1.01:1 fill-vs-white-paper. It has a
    // shadow; it has no contrast.
    const protectedIds = {
      'highlight',
      'shadow_soft',
      'contrast',
      // «glass» is deliberately NOT here. Its plate is 40% black, so
      // painted over the default paper it is a mid grey and its white
      // glyphs land at 2.85:1 — the guard repaints it, correctly. It
      // sat in this list while the plate arm measured the authored
      // colour and ignored alpha.
      'caption',
      'subtitle_band',
      'cta',
      'badge_red',
      'hashtag',
      'outline',
      'poster',
      'sticker',
      'pop_3d',
    };

    test('protected presets are never repainted', () {
      final c = _withSelectedText();
      addTearDown(c.dispose);
      final ctrl = c.read(textToolControllerProvider.notifier);
      for (final preset in kTextStylePresets) {
        if (!protectedIds.contains(preset.id)) continue;
        expect(
          identical(ctrl.readableOnCanvas(preset.spec), preset.spec),
          isTrue,
          reason:
              '«${preset.id}» carries its own contrast and must '
              'survive verbatim',
        );
      }
    });

    // The previous form of this test re-implemented the guard's own
    // predicate and `continue`d on a match, so it skipped all 14
    // protected presets and could not fail. This measures instead:
    // every preset must end up legible, and a preset that claims
    // self-protection must prove its protective paint contrasts with
    // its own fill.
    test('no preset can end up illegible on the default canvas', () {
      final c = _withSelectedText();
      addTearDown(c.dispose);
      final ctrl = c.read(textToolControllerProvider.notifier);
      const white = Color(0xFFFFFFFF);

      for (final preset in kTextStylePresets) {
        final r = ctrl.readableOnCanvas(preset.spec);
        final plate = r.backgroundColor;
        if (plate != null) {
          // Composited over the paper, not measured raw: a translucent
          // plate is not the colour it declares. `glass` is 40% black,
          // which is 21:1 on paper and 2.85:1 once painted.
          final painted = Color.alphaBlend(
            plate,
            TextColorResolver.kCanvasFill,
          );
          expect(
            TextColorResolver.contrastRatio(r.color, painted),
            greaterThanOrEqualTo(3.0),
            reason: '«${preset.id}» glyphs on its own plate, as painted',
          );
          continue;
        }
        final outline = r.outlineColor;
        final shadow = r.shadowColor;
        final protection = (outline != null && r.outlineWidth > 0)
            ? outline
            : (shadow != null && shadow.a > 0.25 ? shadow : null);
        // Either the paint behind it delineates it, or the fill itself
        // survives on white paper. One of the two, measured.
        final against = protection ?? white;
        expect(
          TextColorResolver.contrastRatio(r.color, against),
          greaterThanOrEqualTo(3.0),
          reason: protection == null
              ? '«${preset.id}» has no plate, stroke or shadow, so its '
                    'colour alone has to survive on white paper'
              : '«${preset.id}» relies on its stroke/shadow to be '
                    'readable, so that paint has to contrast with the fill',
        );
      }
    });

    // The white-canvas sweep above cannot catch this: it was a MID-GREY
    // band (#959595..#9F9F9F) where the guard resolved the fill against
    // the DOCUMENT while the glyphs actually land on the preset's own
    // 40%-black plate. It repainted white->near-black, the near-black
    // met the plate's #5C5C5C, and the result was ~4x worse than doing
    // nothing. Resolving against the plate-as-painted is the fix.
    test('a translucent plate is resolved against the plate, not the doc', () {
      for (final grey in [0x95, 0x99, 0x9F]) {
        final backdrop = Color.fromARGB(0xFF, grey, grey, grey);
        final c = _withSelectedText(canvasFill: backdrop);
        addTearDown(c.dispose);
        final ctrl = c.read(textToolControllerProvider.notifier);

        const glass = TextStyleSpec(
          color: Color(0xFFFFFFFF),
          backgroundColor: Color(0x66000000),
        );
        final r = ctrl.readableOnCanvas(glass);
        final painted = Color.alphaBlend(glass.backgroundColor!, backdrop);
        expect(
          TextColorResolver.contrastRatio(r.color, painted),
          greaterThanOrEqualTo(3.0),
          reason:
              'on #${grey.toRadixString(16)} the glyphs sit on the plate '
              '(${painted.toARGB32().toRadixString(16)}), not on the canvas',
        );
      }
    });

    test('with nothing selected the preset passes through untouched', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(documentControllerProvider.notifier)
          .newDocument(width: 1080, height: 1080);
      final ctrl = c.read(textToolControllerProvider.notifier);
      const spec = TextStyleSpec(color: Color(0xFFFFFFFF));
      expect(ctrl.readableOnCanvas(spec), same(spec));
    });
  });
}
