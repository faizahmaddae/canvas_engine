import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/text/application/text_tool_controller.dart';
import 'package:canvas_engine/features/editor/text/domain/text_style_presets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    c
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    addTearDown(c.dispose);
    return c;
  }

  TextLayer addText(
    ProviderContainer c, {
    String id = 't1',
    TextStyleSpec style = const TextStyleSpec(),
    String content = 'hello',
    Size size = const Size(200, 80),
    Offset position = const Offset(50, 50),
  }) {
    final layer = TextLayer(
      id: id,
      transform: LayerTransform(position: position, size: size),
      content: content,
      style: style,
    );
    c.read(documentControllerProvider.notifier).execute(AddLayerCommand(layer));
    return layer;
  }

  group('TextStylePresets (visual-only)', () {
    test('catalog: every preset has a unique id and a non-empty name', () {
      final ids = <String>{};
      for (final p in kTextStylePresets) {
        expect(ids.add(p.id), isTrue, reason: 'duplicate id: ${p.id}');
        expect(p.name, isNotEmpty);
      }
    });

    test('no preset specifies font/size/metric fields — visual-only', () {
      for (final p in kTextStylePresets) {
        expect(
          p.spec.fontFamily,
          isNull,
          reason: '${p.id} must not carry a fontFamily',
        );
        // Spec defaults: fontSize 16, letterSpacing/lineHeight unset.
        // Re-deriving the default and expecting equality on these
        // four fields guarantees presets only differ by visual props.
        const defaults = TextStyleSpec();
        expect(
          p.spec.fontSize,
          defaults.fontSize,
          reason: '${p.id} must not carry a fontSize',
        );
        expect(
          p.spec.letterSpacing,
          defaults.letterSpacing,
          reason: '${p.id} must not carry letterSpacing',
        );
        expect(
          p.spec.lineHeight,
          defaults.lineHeight,
          reason: '${p.id} must not carry lineHeight',
        );
        expect(
          p.spec.alignment,
          defaults.alignment,
          reason: '${p.id} must not carry alignment',
        );
      }
    });

    test('lookup helpers', () {
      expect(
        textStylePresetById(kTextStylePresets.first.id),
        kTextStylePresets.first,
      );
      expect(textStylePresetById('does_not_exist'), isNull);
      expect(kAllTextStylePresets, kTextStylePresets);
    });

    // -----------------------------------------------------------------
    // Curated catalog quality bar.
    // -----------------------------------------------------------------
    test('catalog covers every category with at least one preset', () {
      final byCategory = <TextStylePresetCategory, int>{};
      for (final p in kTextStylePresets) {
        byCategory.update(p.category, (v) => v + 1, ifAbsent: () => 1);
      }
      for (final cat in TextStylePresetCategory.values) {
        expect(
          byCategory[cat] ?? 0,
          greaterThanOrEqualTo(1),
          reason: 'category ${cat.name} must have at least one preset',
        );
      }
      // Curated kit — quality over quantity. Keep the floor at
      // 12 (every category covered, but no shelf clutter) and a
      // hard ceiling so future PRs don't drift back into the
      // 30+ "more is more" anti-pattern.
      expect(kTextStylePresets.length, greaterThanOrEqualTo(12));
      expect(
        kTextStylePresets.length,
        lessThanOrEqualTo(20),
        reason: 'curated kit — add a preset only after removing one',
      );
    });

    test('every preset id is referenceable + matches the slug rule', () {
      // ids are used by tests + selected-state highlight, so they
      // must be machine-friendly (lowercase + underscores).
      final slug = RegExp(r'^[a-z0-9_]+$');
      for (final p in kTextStylePresets) {
        expect(
          slug.hasMatch(p.id),
          isTrue,
          reason: '${p.id} is not a valid slug',
        );
        expect(textStylePresetById(p.id), same(p));
      }
    });

    test('curated kit ships the workhorse presets', () {
      // The senior-design audit cut the catalogue from 31 to ~16.
      // These ids are the workhorses that survived — deleting any
      // of them would leave a real gap in the kit.
      const keepIds = <String>[
        // Minimal
        'classic',
        'quote',
        // Emphasis
        'highlight',
        // Readability (photo-friendly)
        'shadow_soft',
        'contrast',
        'glass',
        'caption',
        'subtitle_band',
        // Social
        'cta',
        'badge_red',
        'hashtag',
        // Decorative
        'outline',
        'neon',
        'poster',
        'sticker',
        'pop_3d',
      ];
      for (final id in keepIds) {
        expect(
          textStylePresetById(id),
          isNotNull,
          reason: '$id is a workhorse preset — do not delete',
        );
      }
    });

    test('weak / redundant presets stay deleted', () {
      // The audit cut these because each was either redundant
      // (mark_pink ≈ highlight, mention ≈ hashtag, chip_blue ≈
      // badge, glow_pink ≈ neon, chrome ≈ sticker) or trivially
      // available via another tool (strong/underline = font tool;
      // link = colored underline; tag/handle = badge variants;
      // subtle/whisper = just gray text; border_light = outline
      // variant; lede = quote+bold; retro = gimmicky).
      const removed = <String>[
        'mark_pink',
        'strong',
        'underline',
        'link',
        'tag',
        'mention',
        'handle_dark',
        'chip_blue',
        'glow_pink',
        'retro',
        'chrome',
        'subtle',
        'whisper',
        'border_light',
        'lede',
      ];
      for (final id in removed) {
        expect(
          textStylePresetById(id),
          isNull,
          reason: '$id was cut for being weak/redundant — do not re-add',
        );
      }
    });

    test('every preset name is short + display-ready (<= 12 chars)', () {
      for (final p in kTextStylePresets) {
        expect(
          p.name.length,
          lessThanOrEqualTo(12),
          reason: '${p.id} name "${p.name}" too long for a chip',
        );
        expect(
          p.name.trim(),
          p.name,
          reason: '${p.id} name has leading/trailing whitespace',
        );
      }
    });

    // -----------------------------------------------------------------
    // Quality bar on individual preset values. These tests pin the
    // refinements made when we did the senior-design audit so a
    // future tweak doesn't silently regress them back to the old
    // squished / invisible / oversized values.
    // -----------------------------------------------------------------
    test('Highlight has breathing-room padding (padY >= 4)', () {
      final p = textStylePresetById('highlight')!;
      expect(
        p.spec.backgroundPaddingY,
        greaterThanOrEqualTo(4),
        reason: 'highlight padY too tight — looks unfinished at large sizes',
      );
    });

    test('Sticker outline width is bounded so glyphs stay readable', () {
      // Flutter strokes are centre-aligned, so half the outline
      // width eats into the glyph's interior. >4 px starts to make
      // counter-spaces (the inside of "o", "e") collapse at typical
      // body sizes.
      final p = textStylePresetById('sticker')!;
      expect(
        p.spec.outlineWidth,
        lessThanOrEqualTo(4),
        reason: 'Sticker outline too thick — eats glyph interior',
      );
    });

    test('Pop preset: hard offset shadow with zero blur (dimensional)', () {
      final p = textStylePresetById('pop_3d')!;
      expect(p.spec.shadowColor, isNotNull);
      expect(
        p.spec.shadowBlur,
        0.0,
        reason: 'pop_3d must be a HARD shadow (no blur) for 3D feel',
      );
      expect(
        p.spec.shadowOffset,
        isNot(Offset.zero),
        reason: 'pop_3d must offset the shadow to read as dimensional',
      );
    });

    test('layered presets stack at least two visual effects', () {
      // These presets get their photo-readability from layered
      // effects — losing any one of the layers breaks the look.
      void requireLayers(String id, int min) {
        final s = textStylePresetById(id)!.spec;
        var n = 0;
        if (s.backgroundColor != null) n++;
        if (s.outlineColor != null) n++;
        if (s.shadowColor != null) n++;
        expect(
          n,
          greaterThanOrEqualTo(min),
          reason: '$id needs $min layered effects, found $n',
        );
      }

      requireLayers('caption', 2); // plate + shadow
      requireLayers('sticker', 2); // outline + shadow
    });

    // -----------------------------------------------------------------
    // Panel data source: `orderedTextStylePresets` is the *single*
    // ordered list the Styles panel renders. No "More styles" split.
    // -----------------------------------------------------------------
    test('orderedTextStylePresets returns every preset exactly once', () {
      final ordered = orderedTextStylePresets(
        layerStyle: const TextStyleSpec(),
      );
      expect(
        ordered.length,
        kTextStylePresets.length,
        reason: 'panel must show every preset \u2014 no hidden tail',
      );
      final ids = <String>{};
      for (final p in ordered) {
        expect(
          ids.add(p.id),
          isTrue,
          reason: '${p.id} appears twice in the panel order',
        );
      }
    });

    test('orderedTextStylePresets sorts recommended chips to the front', () {
      // Fresh layer \u2192 the safe trio (Classic, Highlight, Badge / CTA)
      // should appear in the first 4 chips so the user sees them
      // without scrolling.
      final ordered = orderedTextStylePresets(
        layerStyle: const TextStyleSpec(),
      );
      final headIds = ordered.take(4).map((p) => p.id).toSet();
      // At least Classic + Highlight should be in the head \u2014 those
      // are the universally-safe picks for any fresh layer.
      expect(headIds, containsAll(<String>['classic', 'highlight']));
    });
  });

  group('default font for new text', () {
    test('textIsArabicScript detects Persian content; otherwise Latin', () {
      expect(textIsArabicScript('سلام دنیا'), isTrue);
      expect(textIsArabicScript('Hello world'), isFalse);
      expect(textIsArabicScript('  ۱۲۳ سلام'), isTrue);
      expect(textIsArabicScript('Hi سلام'), isFalse);
      expect(textIsArabicScript(''), isFalse);
      expect(textIsArabicScript('!!! 1234'), isFalse);
    });

    test(
      'defaultFontFamilyForContent: Vazir for every script (Persian-first)',
      () {
        expect(defaultFontFamilyForContent('سلام'), 'Vazir_Regular');
        expect(defaultFontFamilyForContent('Hello'), 'Vazir_Regular');
        expect(defaultFontFamilyForContent(''), 'Vazir_Regular');
      },
    );

    test('textDirectionForContent: auto uses the first strong script', () {
      expect(textDirectionForContent('سلام جهان'), TextDirection.rtl);
      expect(textDirectionForContent('Hello world'), TextDirection.ltr);
      expect(textDirectionForContent(''), TextDirection.ltr);
      expect(textDirectionForContent('!!! ۱۲۳ سلام'), TextDirection.rtl);
      expect(textDirectionForContent('سلام Hi'), TextDirection.rtl);
      expect(textDirectionForContent('Hi سلام Hello world'), TextDirection.ltr);
    });

    test('textDirectionForContent can force RTL or LTR', () {
      expect(
        textDirectionForContent('Hello سلام', mode: TextDirectionMode.rtl),
        TextDirection.rtl,
      );
      expect(
        textDirectionForContent('سلام Hello', mode: TextDirectionMode.ltr),
        TextDirection.ltr,
      );
    });

    test('isAutoDefaultFontFamily flags only the two auto-defaults', () {
      expect(isAutoDefaultFontFamily('Roboto'), isTrue);
      expect(isAutoDefaultFontFamily('Vazir_Regular'), isTrue);
      expect(isAutoDefaultFontFamily('Lobster'), isFalse);
      expect(isAutoDefaultFontFamily(null), isFalse);
    });
  });

  group('mergePresetVisual (projection)', () {
    test('preserves all metric-affecting fields from `current`', () {
      const current = TextStyleSpec(
        fontFamily: 'Lobster',
        fontSize: 99,
        letterSpacing: 2.5,
        lineHeight: 1.7,
        alignment: TextAlign.right,
      );
      final preset = kTextStylePresets.firstWhere((p) => p.id == 'badge_red');
      final out = mergePresetVisual(current: current, preset: preset.spec);
      expect(out.fontFamily, 'Lobster');
      expect(out.fontSize, 99);
      expect(out.letterSpacing, 2.5);
      expect(out.lineHeight, 1.7);
      expect(out.alignment, TextAlign.right);
      // Visual subset from preset.
      expect(out.color, preset.spec.color);
      expect(out.backgroundColor, preset.spec.backgroundColor);
      expect(out.backgroundRadius, preset.spec.backgroundRadius);
      expect(out.fontWeight, preset.spec.fontWeight);
    });

    test('clears background/outline/shadow when preset omits them', () {
      const current = TextStyleSpec(
        backgroundColor: Color(0xFFFF0000),
        outlineColor: Color(0xFF00FF00),
        shadowColor: Color(0xFF0000FF),
      );
      final classic = kTextStylePresets.firstWhere((p) => p.id == 'classic');
      final out = mergePresetVisual(current: current, preset: classic.spec);
      expect(out.backgroundColor, isNull);
      expect(out.outlineColor, isNull);
      expect(out.shadowColor, isNull);
    });
  });

  group('TextToolController.applyStylePreset (visual-only)', () {
    test('preserves fontFamily and fontSize exactly', () {
      final c = makeContainer();
      addText(
        c,
        style: const TextStyleSpec(fontFamily: 'Vazir_Regular', fontSize: 42),
      );
      c.read(selectionControllerProvider.notifier).select('t1');
      final ctrl = c.read(textToolControllerProvider.notifier);
      ctrl.applyStylePreset(
        kTextStylePresets.firstWhere((p) => p.id == 'badge_red').spec,
      );
      final layer =
          c.read(documentControllerProvider).layerById('t1') as TextLayer;
      // Both font and size are unchanged.
      expect(layer.style.fontFamily, 'Vazir_Regular');
      expect(layer.style.fontSize, 42);
      // Visual subset still applied.
      expect(layer.style.backgroundColor, isNotNull);
      expect(layer.style.color, const Color(0xFFFFFFFF));
    });

    test('preserves the layer bounding box exactly (no auto-resize)', () {
      final c = makeContainer();
      addText(c, size: const Size(321, 123), position: const Offset(77, 88));
      c.read(selectionControllerProvider.notifier).select('t1');
      // Pick a preset that toggles fontWeight (would normally widen
      // glyphs) — the box must still stay put.
      final preset = kTextStylePresets.firstWhere((p) => p.id == 'badge_red');
      c.read(textToolControllerProvider.notifier).applyStylePreset(preset.spec);
      final layer =
          c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(layer.transform.position, const Offset(77, 88));
      expect(layer.transform.size, const Size(321, 123));
    });

    test('does not change content', () {
      final c = makeContainer();
      addText(c, content: 'keep me');
      c.read(selectionControllerProvider.notifier).select('t1');
      c
          .read(textToolControllerProvider.notifier)
          .applyStylePreset(kTextStylePresets.first.spec);
      final layer =
          c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(layer.content, 'keep me');
    });

    test('one undoable step rewinds the whole change', () {
      final c = makeContainer();
      addText(c);
      c.read(selectionControllerProvider.notifier).select('t1');
      c
          .read(textToolControllerProvider.notifier)
          .applyStylePreset(
            kTextStylePresets.firstWhere((p) => p.id == 'badge_red').spec,
          );
      c.read(documentControllerProvider.notifier).undo();
      final reverted =
          c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(reverted.style, const TextStyleSpec());
    });

    test('with no selected layer, mutates defaultStyle (next-add seed)', () {
      final c = makeContainer();
      final preset = kTextStylePresets.firstWhere((p) => p.id == 'badge_red');
      c.read(textToolControllerProvider.notifier).applyStylePreset(preset.spec);
      final ds = c.read(textToolControllerProvider).defaultStyle;
      expect(ds.color, preset.spec.color);
      expect(ds.backgroundColor, preset.spec.backgroundColor);
      // Font + size still inherited from the prior default.
      expect(ds.fontFamily, isNull);
      expect(ds.fontSize, const TextStyleSpec().fontSize);
    });

    test('clears the sticky size-preset pin', () {
      final c = makeContainer();
      addText(c);
      c.read(selectionControllerProvider.notifier).select('t1');
      final ctrl = c.read(textToolControllerProvider.notifier);
      ctrl.setFontSizeFromPreset(size: 24, presetLabel: 'S', layerId: 't1');
      expect(c.read(textToolControllerProvider).selectedSizePreset, isNotNull);
      ctrl.applyStylePreset(kTextStylePresets.first.spec);
      expect(c.read(textToolControllerProvider).selectedSizePreset, isNull);
    });

    test('does not leak preset onto defaultStyle when applied to a layer', () {
      final c = makeContainer();
      addText(c);
      c.read(selectionControllerProvider.notifier).select('t1');
      c
          .read(textToolControllerProvider.notifier)
          .applyStylePreset(kTextStylePresets.first.spec);
      expect(
        c.read(textToolControllerProvider).defaultStyle,
        const TextStyleSpec(),
      );
    });
  });

  group('default font on new text creation', () {
    test('English content commits with Vazir when no font was picked '
        '(Persian-first default)', () {
      final c = makeContainer();
      final ctrl = c.read(textToolControllerProvider.notifier);
      final id = ctrl.beginAddText();
      ctrl.previewContent('Hello world');
      ctrl.commitLiveEdit('Hello world');
      final layer =
          c.read(documentControllerProvider).layerById(id) as TextLayer;
      expect(layer.style.fontFamily, 'Vazir_Regular');
    });

    test('Persian content commits with Vazir when no font was picked', () {
      final c = makeContainer();
      final ctrl = c.read(textToolControllerProvider.notifier);
      final id = ctrl.beginAddText();
      ctrl.previewContent('سلام دنیا');
      ctrl.commitLiveEdit('سلام دنیا');
      final layer =
          c.read(documentControllerProvider).layerById(id) as TextLayer;
      expect(layer.style.fontFamily, 'Vazir_Regular');
    });

    test(
      'respects an explicit defaultStyle.fontFamily set by the Font tool',
      () {
        final c = makeContainer();
        final ctrl = c.read(textToolControllerProvider.notifier);
        ctrl.setFontFamily('Lobster');
        final id = ctrl.beginAddText();
        ctrl.previewContent('Hello');
        ctrl.commitLiveEdit('Hello');
        final layer =
            c.read(documentControllerProvider).layerById(id) as TextLayer;
        expect(layer.style.fontFamily, 'Lobster');
      },
    );
  });

  group('background roundness (percent of box)', () {
    test('0% percent → square (0px) at any size', () {
      expect(textBackgroundRadiusPx(const Size(40, 24), 0), 0);
      expect(textBackgroundRadiusPx(const Size(800, 400), 0), 0);
    });

    test(
      '100% percent → true pill (radius == min(side)/2) small AND large',
      () {
        // Small text box.
        expect(textBackgroundRadiusPx(const Size(60, 28), 1), 14);
        // Large text box — still a perfect pill, not a tiny corner.
        expect(textBackgroundRadiusPx(const Size(800, 200), 1), 100);
      },
    );

    test('50% percent → visibly rounded (quarter of shorter side)', () {
      expect(textBackgroundRadiusPx(const Size(120, 60), 0.5), 15);
    });

    test('controller clamps backgroundRadius to [0, 1]', () {
      final c = makeContainer();
      addText(c);
      c.read(selectionControllerProvider.notifier).select('t1');
      final ctrl = c.read(textToolControllerProvider.notifier);
      ctrl.setBackgroundRadius(2.5);
      var layer =
          c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(layer.style.backgroundRadius, 1.0);
      ctrl.setBackgroundRadius(-0.4);
      layer = c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(layer.style.backgroundRadius, 0.0);
    });

    test('legacy px-radius JSON migrates into the percent space', () {
      // Pre-migration docs stored radius in pixels (e.g. 24 for a
      // chip). They should land safely inside [0, 1] after read.
      final restored = TextStyleSpec.fromJson(<String, dynamic>{
        'fontSize': 48,
        'color': 0xFFFFFFFF,
        'fontWeight': 700,
        'letterSpacing': 0,
        'lineHeight': 1.2,
        'alignment': 'center',
        'backgroundColor': 0xFFEF4444,
        'backgroundRadius': 24,
        'backgroundPaddingX': 18,
        'backgroundPaddingY': 10,
      });
      expect(restored.backgroundRadius, 0.6);
    });

    test('pill-style presets (Badge / CTA / Hashtag) ship at 100%', () {
      for (final id in ['badge_red', 'cta', 'hashtag']) {
        final p = textStylePresetById(id)!;
        expect(
          p.spec.backgroundRadius,
          1.0,
          reason: '$id should be a true pill at any size',
        );
      }
    });
  });
}
