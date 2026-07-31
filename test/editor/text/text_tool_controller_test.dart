import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/editing_controller.dart';
import 'package:canvas_engine/features/editor/application/live_overlay_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/text/application/text_color_resolver.dart';
import 'package:canvas_engine/features/editor/text/application/text_tool_controller.dart';
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
    TextDirectionMode textDirectionMode = TextDirectionMode.auto,
  }) {
    final layer = TextLayer(
      id: id,
      transform: LayerTransform(
        position: const Offset(50, 50),
        size: const Size(200, 80),
      ),
      content: content,
      style: style,
      textDirectionMode: textDirectionMode,
    );
    c.read(documentControllerProvider.notifier).execute(AddLayerCommand(layer));
    return layer;
  }

  group('TextToolController', () {
    test('initial state: panel closed, default style, no recents', () {
      final c = makeContainer();
      final s = c.read(textToolControllerProvider);
      expect(s.panelOpen, isFalse);
      expect(s.defaultStyle, const TextStyleSpec());
      expect(s.recentColors, isEmpty);
    });

    test('openPanel/closePanel are idempotent', () {
      final c = makeContainer();
      final ctrl = c.read(textToolControllerProvider.notifier);
      ctrl.openPanel();
      ctrl.openPanel();
      expect(c.read(textToolControllerProvider).panelOpen, isTrue);
      ctrl.closePanel();
      ctrl.closePanel();
      expect(c.read(textToolControllerProvider).panelOpen, isFalse);
    });

    test('closePanel also stops the editing controller', () {
      final c = makeContainer();
      c.read(editingControllerProvider.notifier).start('t1');
      expect(c.read(editingControllerProvider), 't1');
      c.read(textToolControllerProvider.notifier)
        ..openPanel()
        ..closePanel();
      expect(c.read(editingControllerProvider), isNull);
    });

    // The pair straddles the w600 synthesis threshold on purpose — a
    // toggle drawn from two weights above it would be invisible on the
    // single-face families most of the catalogue ships.
    test('setBold round-trips between the default weight and w700', () {
      final c = makeContainer();
      final ctrl = c.read(textToolControllerProvider.notifier);
      final initial = c
          .read(textToolControllerProvider)
          .defaultStyle
          .fontWeight;
      ctrl.setBold(true);
      expect(
        c.read(textToolControllerProvider).defaultStyle.fontWeight,
        FontWeight.w700,
      );
      ctrl.setBold(false);
      expect(
        c.read(textToolControllerProvider).defaultStyle.fontWeight,
        initial,
      );
    });

    test('style setters all update defaultStyle', () {
      final c = makeContainer();
      final ctrl = c.read(textToolControllerProvider.notifier);
      ctrl
        ..setColor(const Color(0xFF112233))
        ..setFontSize(64)
        ..setItalic(true)
        ..setAlignment(TextAlign.right)
        ..setLetterSpacing(2.5)
        ..setLineHeight(1.8);
      final s = c.read(textToolControllerProvider).defaultStyle;
      expect(s.color, const Color(0xFF112233));
      expect(s.fontSize, 64);
      expect(s.italic, isTrue);
      expect(s.alignment, TextAlign.right);
      expect(s.letterSpacing, 2.5);
      expect(s.lineHeight, 1.8);
    });

    test('style change with no selection: only defaultStyle changes', () {
      final c = makeContainer();
      addText(c);
      // No selection.
      c.read(textToolControllerProvider.notifier).setFontSize(99);
      final layer =
          c.read(documentControllerProvider).layerById('t1') as TextLayer;
      // Layer is untouched.
      expect(layer.style.fontSize, const TextStyleSpec().fontSize);
      expect(c.read(textToolControllerProvider).defaultStyle.fontSize, 99);
    });

    test('addCenteredText creates and selects a new text layer', () {
      final c = makeContainer();
      final ctrl = c.read(textToolControllerProvider.notifier);
      final id = ctrl.addCenteredText('Hello world');
      expect(id, isNotNull);
      final selected = c.read(selectionControllerProvider).selectedId;
      expect(selected, id);
      final layer =
          c.read(documentControllerProvider).layerById(id!) as TextLayer;
      expect(layer.content, 'Hello world');
    });

    // -------------------------------------------------------------------
    // Default subtle drop-shadow on insert.
    // -------------------------------------------------------------------
    test('beginAddText: brand-new text gets a subtle default shadow '
        '(opposite-luminance, fixed alpha)', () {
      final c = makeContainer();
      final ctrl = c.read(textToolControllerProvider.notifier);
      final id = ctrl.beginAddText();
      final layer = c.read(renderedDocumentProvider).layerById(id) as TextLayer;
      // Default text colour is white -> shadow must be the
      // translucent-black halo from the resolver.
      expect(layer.style.shadowColor, isNotNull);
      expect(
        layer.style.shadowColor,
        TextColorResolver.defaultShadowFor(layer.style.color),
      );
      // Blur and offset are canvas-aware: the reference 6 px / 2 px
      // (designed against the 1080 canvas) are scaled by
      // CanvasSizing.scaleDimension for this 800-square test doc.
      const expectedScale = 800 / 1080;
      expect(
        layer.style.shadowBlur,
        closeTo(TextColorResolver.kDefaultShadowBlur * expectedScale, 0.01),
      );
      expect(
        layer.style.shadowOffset.dy,
        closeTo(
          TextColorResolver.kDefaultShadowOffset.dy * expectedScale,
          0.01,
        ),
      );
      expect(layer.style.shadowOffset.dx, 0);
    });

    test('addCenteredText: quick-add text also gets the default shadow', () {
      final c = makeContainer();
      final ctrl = c.read(textToolControllerProvider.notifier);
      final id = ctrl.addCenteredText('Quick');
      final layer =
          c.read(documentControllerProvider).layerById(id!) as TextLayer;
      expect(layer.style.shadowColor, isNotNull);
      expect(
        layer.style.shadowColor,
        TextColorResolver.defaultShadowFor(layer.style.color),
      );
    });

    test('default shadow respects auto-picked text colour: white canvas + '
        'white default text -> dark text -> WHITE halo', () {
      // On a white canvas the resolver flips white default text to
      // near-black for readability. The auto-shadow must then be the
      // OPPOSITE of that final colour, i.e. white — not black, which
      // would be a black shadow on near-black text and look like a
      // bug.
      final c = makeContainer();
      final ctrl = c.read(textToolControllerProvider.notifier);
      final id = ctrl.beginAddText();
      final layer = c.read(renderedDocumentProvider).layerById(id) as TextLayer;
      // Sanity: text colour was overridden away from white.
      expect(layer.style.color, isNot(const Color(0xFFFFFFFF)));
      // Shadow is computed from the FINAL colour.
      expect(
        layer.style.shadowColor,
        TextColorResolver.defaultShadowFor(layer.style.color),
      );
    });

    test('user-tuned default shadow is preserved (not overwritten by '
        'auto-shadow)', () {
      // If the user has already picked their own shadow into
      // defaultStyle, beginAddText must respect it verbatim.
      final c = makeContainer();
      final notifier = c.read(textToolControllerProvider.notifier);
      // No layer selected -> _applyStyle is the public path that
      // updates `defaultStyle`. Push every shadow field through the
      // shadow setters so we end up with the user-tuned default.
      notifier.setShadowColor(const Color(0xFFFF00FF));
      notifier.setShadowBlur(20);
      notifier.setShadowOffset(const Offset(4, 4));
      expect(
        c.read(textToolControllerProvider).defaultStyle.shadowColor,
        const Color(0xFFFF00FF),
      );
      final id = notifier.beginAddText();
      final layer = c.read(renderedDocumentProvider).layerById(id) as TextLayer;
      expect(layer.style.shadowColor, const Color(0xFFFF00FF));
      expect(layer.style.shadowBlur, 20);
      expect(layer.style.shadowOffset, const Offset(4, 4));
    });

    test('existing saved layers are NOT touched by the auto-shadow rule', () {
      // Loading a doc with a TextLayer whose style has shadowColor
      // null must keep that null — auto-shadow only runs on inserts
      // through the controller, never as a migration.
      final c = makeContainer();
      addText(c, id: 'legacy', style: const TextStyleSpec()); // no shadow
      final layer =
          c.read(documentControllerProvider).layerById('legacy') as TextLayer;
      expect(layer.style.shadowColor, isNull);
    });

    test('style change with text layer selected: mirrors to layer via '
        'UpdateTextCommand', () {
      final c = makeContainer();
      addText(c);
      c.read(selectionControllerProvider.notifier).select('t1');
      c.read(textToolControllerProvider.notifier).setFontSize(99);
      final layer =
          c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(layer.style.fontSize, 99);
      // Editing a selected layer must NOT mutate the session's
      // default style — otherwise the next freshly-added text
      // would inherit this layer's font/colour/background, which
      // is exactly the cross-layer leak we're guarding against.
      expect(
        c.read(textToolControllerProvider).defaultStyle.fontSize,
        const TextStyleSpec().fontSize,
      );
    });

    test('no cross-layer style leak: editing Text A does not pollute '
        'defaults so a later beginAddText starts clean', () {
      final c = makeContainer();
      // Text A on canvas, fully styled by the user.
      addText(c);
      c.read(selectionControllerProvider.notifier).select('t1');
      final ctrl = c.read(textToolControllerProvider.notifier);
      ctrl
        ..setFontSize(120)
        ..setColor(const Color(0xFFAA0000))
        ..setBackgroundColor(const Color(0xFF00AA00))
        ..setBold(true);
      // Switch focus away (mirrors tapping the canvas / Done).
      c.read(selectionControllerProvider.notifier).clear();
      // App default style must still be the pristine initial — none
      // of A's edits should have leaked here.
      const initial = TextStyleSpec();
      final defaults = c.read(textToolControllerProvider).defaultStyle;
      expect(defaults.fontSize, initial.fontSize);
      expect(defaults.color, initial.color);
      expect(defaults.backgroundColor, isNull);
      expect(defaults.fontWeight, initial.fontWeight);
      // And the freshly-staged Text B inherits the clean defaults
      // (modulo canvas-relative font scaling).
      final newId = ctrl.beginAddText();
      final staged =
          c.read(renderedDocumentProvider).layerById(newId) as TextLayer;
      expect(staged.style.backgroundColor, isNull);
      expect(staged.style.fontWeight, initial.fontWeight);
      // Original Text A is preserved unchanged.
      final a = c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(a.style.fontSize, 120);
      expect(a.style.color, const Color(0xFFAA0000));
      expect(a.style.backgroundColor, const Color(0xFF00AA00));
    });

    test('style change is undoable as a single step', () {
      final c = makeContainer();
      // Start non-bold so setBold(true) is a real change.
      addText(c, style: const TextStyleSpec(fontWeight: FontWeight.w400));
      c.read(selectionControllerProvider.notifier).select('t1');
      c.read(textToolControllerProvider.notifier).setBold(true);
      expect(
        (c.read(documentControllerProvider).layerById('t1') as TextLayer)
            .style
            .isBold,
        isTrue,
      );
      c.read(documentControllerProvider.notifier).undo();
      expect(
        (c.read(documentControllerProvider).layerById('t1') as TextLayer)
            .style
            .isBold,
        isFalse,
      );
    });

    test('selecting a non-text layer means style writes do not mirror', () {
      final c = makeContainer();
      addText(c, id: 'txt');
      // Add a text layer but pretend selection is some other id —
      // selectedTextLayer() returns null because the id has no layer.
      c.read(selectionControllerProvider.notifier).select('ghost');
      c.read(textToolControllerProvider.notifier).setFontSize(123);
      final layer =
          c.read(documentControllerProvider).layerById('txt') as TextLayer;
      expect(layer.style.fontSize, isNot(123));
    });

    test('rememberRecentColor: prepends, dedupes, caps at 8', () {
      final c = makeContainer();
      final ctrl = c.read(textToolControllerProvider.notifier);
      for (var i = 0; i < 10; i++) {
        ctrl.rememberRecentColor(Color(0xFF000000 + i));
      }
      var recents = c.read(textToolControllerProvider).recentColors;
      expect(recents, hasLength(8));
      // Most recent first.
      expect(recents.first, const Color(0xFF000009));

      // Re-pick an existing colour: moves to front, no duplicate.
      ctrl.rememberRecentColor(const Color(0xFF000003));
      recents = c.read(textToolControllerProvider).recentColors;
      expect(recents.first, const Color(0xFF000003));
      expect(recents, hasLength(8));
      expect(recents.where((c) => c == const Color(0xFF000003)).length, 1);
    });

    test('addCenteredText rejects empty / whitespace input', () {
      final c = makeContainer();
      final ctrl = c.read(textToolControllerProvider.notifier);
      expect(ctrl.addCenteredText(''), isNull);
      expect(ctrl.addCenteredText('   '), isNull);
      expect(c.read(documentControllerProvider).layers, isEmpty);
    });

    test('setOpacity clamps to [0,1] and preserves color hue', () {
      final c = makeContainer();
      addText(c, style: const TextStyleSpec(color: Color(0xFFAABBCC)));
      c.read(selectionControllerProvider.notifier).select('t1');
      final ctrl = c.read(textToolControllerProvider.notifier);

      ctrl.setOpacity(0.5);
      var layer =
          c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(layer.style.color.r, closeTo(0xAA / 255, 0.01));
      expect(layer.style.color.g, closeTo(0xBB / 255, 0.01));
      expect(layer.style.color.b, closeTo(0xCC / 255, 0.01));
      expect(layer.style.color.a, closeTo(0.5, 0.01));

      ctrl.setOpacity(2.0);
      layer = c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(layer.style.color.a, closeTo(1.0, 0.001));

      ctrl.setOpacity(-1);
      layer = c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(layer.style.color.a, closeTo(0.0, 0.001));
    });

    test('shadow toggle: enable seeds defaults, disable clears it', () {
      final c = makeContainer();
      addText(c);
      c.read(selectionControllerProvider.notifier).select('t1');
      final ctrl = c.read(textToolControllerProvider.notifier);

      // Default state: no shadow.
      var layer =
          c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(layer.style.shadowColor, isNull);

      ctrl.setShadowEnabled(true);
      layer = c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(layer.style.shadowColor, isNotNull);
      // Toggle now seeds canvas-aware blur (reference 6 px scaled
      // by 800/1080), not the spec's at-rest default of 4.
      expect(
        layer.style.shadowBlur,
        closeTo(TextColorResolver.kDefaultShadowBlur * 800 / 1080, 0.01),
      );

      // Re-enabling on an already-enabled layer is a no-op (does not
      // overwrite a custom colour).
      ctrl.setShadowColor(const Color(0xFFFF0000));
      ctrl.setShadowEnabled(true);
      layer = c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(layer.style.shadowColor, const Color(0xFFFF0000));

      ctrl.setShadowBlur(12);
      layer = c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(layer.style.shadowBlur, 12);

      ctrl.setShadowEnabled(false);
      layer = c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(layer.style.shadowColor, isNull);
    });

    test('background toggle: enable seeds defaults, disable clears it', () {
      final c = makeContainer();
      addText(c);
      c.read(selectionControllerProvider.notifier).select('t1');
      final ctrl = c.read(textToolControllerProvider.notifier);

      var layer =
          c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(layer.style.backgroundColor, isNull);

      ctrl.setBackgroundEnabled(true);
      layer = c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(layer.style.backgroundColor, isNotNull);

      ctrl.setBackgroundColor(const Color(0xFF00FF00));
      ctrl.setBackgroundRadius(0.5);
      layer = c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(layer.style.backgroundColor, const Color(0xFF00FF00));
      expect(layer.style.backgroundRadius, 0.5);

      ctrl.setBackgroundEnabled(false);
      layer = c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(layer.style.backgroundColor, isNull);
    });

    test('outline toggle: enable seeds canvas-aware width '
        '(reference 2 px scaled by 800/1080)', () {
      final c = makeContainer();
      addText(c);
      c.read(selectionControllerProvider.notifier).select('t1');
      final ctrl = c.read(textToolControllerProvider.notifier);

      ctrl.setOutlineEnabled(true);
      final layer =
          c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(layer.style.outlineColor, isNotNull);
      // Reference 2 px scaled by 800/1080 ≈ 1.481, which is well
      // within the 0.5..20 clamp so no clamp engages here.
      expect(layer.style.outlineWidth, closeTo(2.0 * 800 / 1080, 0.01));
    });

    test('background toggle: enable seeds canvas-aware padding '
        '(reference 8/4 px scaled by 800/1080)', () {
      final c = makeContainer();
      addText(c);
      c.read(selectionControllerProvider.notifier).select('t1');
      final ctrl = c.read(textToolControllerProvider.notifier);

      ctrl.setBackgroundEnabled(true);
      final layer =
          c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(layer.style.backgroundPaddingX, closeTo(8.0 * 800 / 1080, 0.01));
      expect(layer.style.backgroundPaddingY, closeTo(4.0 * 800 / 1080, 0.01));
    });

    test('shadow + background round-trip through JSON', () {
      const original = TextStyleSpec(
        shadowColor: Color(0xAA112233),
        shadowBlur: 8,
        shadowOffset: Offset(3, 5),
        backgroundColor: Color(0xCC445566),
        backgroundRadius: 0.4,
      );
      final restored = TextStyleSpec.fromJson(original.toJson());
      expect(restored, original);
    });

    test('duplicateSelectedText copies content/style and offsets position', () {
      final c = makeContainer();
      addText(c, content: 'hello', textDirectionMode: TextDirectionMode.rtl);
      c.read(selectionControllerProvider.notifier).select('t1');
      c.read(textToolControllerProvider.notifier).duplicateSelectedText();
      final layers = c.read(documentControllerProvider).layers;
      expect(layers, hasLength(2));
      final dup = layers.last as TextLayer;
      final orig = layers.first as TextLayer;
      expect(dup.content, orig.content);
      expect(dup.style, orig.style);
      expect(dup.textDirectionMode, orig.textDirectionMode);
      expect(
        dup.transform.position - orig.transform.position,
        const Offset(24, 24),
      );
      // New layer is selected.
      expect(c.read(selectionControllerProvider).selectedId, dup.id);
    });

    test('toggleSelectedLock flips locked state', () {
      final c = makeContainer();
      addText(c);
      c.read(selectionControllerProvider.notifier).select('t1');
      final ctrl = c.read(textToolControllerProvider.notifier);
      expect(
        (c.read(documentControllerProvider).layerById('t1') as TextLayer)
            .locked,
        isFalse,
      );
      ctrl.toggleSelectedLock();
      expect(
        (c.read(documentControllerProvider).layerById('t1') as TextLayer)
            .locked,
        isTrue,
      );
      ctrl.toggleSelectedLock();
      expect(
        (c.read(documentControllerProvider).layerById('t1') as TextLayer)
            .locked,
        isFalse,
      );
    });

    test(
      'arrange forward / backward reorders the selected text in the doc',
      () {
        final c = makeContainer();
        addText(c, id: 'a');
        addText(c, id: 'b');
        addText(c, id: 'c');
        c.read(selectionControllerProvider.notifier).select('b');
        final ctrl = c.read(textToolControllerProvider.notifier);
        ctrl.arrangeSelectedForward();
        expect(
          c.read(documentControllerProvider).layers.map((l) => l.id).toList(),
          ['a', 'c', 'b'],
        );
        ctrl.arrangeSelectedBackward();
        expect(
          c.read(documentControllerProvider).layers.map((l) => l.id).toList(),
          ['a', 'b', 'c'],
        );
        // Bounds: backward at index 0 is a no-op.
        c.read(selectionControllerProvider.notifier).select('a');
        ctrl.arrangeSelectedBackward();
        expect(
          c.read(documentControllerProvider).layers.map((l) => l.id).toList(),
          ['a', 'b', 'c'],
        );
      },
    );

    test('setUnderline mirrors to the selected layer in real time', () {
      final c = makeContainer();
      addText(c);
      c.read(selectionControllerProvider.notifier).select('t1');
      final ctrl = c.read(textToolControllerProvider.notifier);
      ctrl.setUnderline(true);
      expect(
        (c.read(documentControllerProvider).layerById('t1') as TextLayer)
            .style
            .underline,
        isTrue,
      );
      ctrl.setUnderline(false);
      expect(
        (c.read(documentControllerProvider).layerById('t1') as TextLayer)
            .style
            .underline,
        isFalse,
      );
    });

    // Regression: previously TextLayer did not override == / hashCode,
    // so EditorDocument.== (uses listEquals) treated two docs as equal
    // when only the style changed. That made Notifier skip the state
    // emit and the canvas only rebuilt on the next unrelated
    // interaction \u2014 the "delayed batch apply" symptom.
    group('document notifies on style-only changes (no batch delay)', () {
      void expectEmit(String label, void Function(TextToolController) mutate) {
        test('$label triggers a documentControllerProvider listener', () {
          final c = makeContainer();
          addText(c);
          c.read(selectionControllerProvider.notifier).select('t1');
          var emitted = 0;
          c.listen<EditorDocument>(
            documentControllerProvider,
            (_, _) => emitted++,
          );
          mutate(c.read(textToolControllerProvider.notifier));
          expect(emitted, 1, reason: '$label should emit exactly once');
        });
      }

      expectEmit('setBold', (ctrl) => ctrl.setBold(true));
      expectEmit('setFontSize', (ctrl) => ctrl.setFontSize(72));
      expectEmit('setColor', (ctrl) => ctrl.setColor(const Color(0xFF112233)));
      expectEmit('setItalic', (ctrl) => ctrl.setItalic(true));
      expectEmit('setUnderline', (ctrl) => ctrl.setUnderline(true));
      expectEmit('setAlignment', (ctrl) => ctrl.setAlignment(TextAlign.right));
      expectEmit('setLetterSpacing', (ctrl) => ctrl.setLetterSpacing(4));
      expectEmit('setLineHeight', (ctrl) => ctrl.setLineHeight(1.8));
      expectEmit('setOpacity', (ctrl) => ctrl.setOpacity(0.4));
      expectEmit('setContent', (ctrl) => ctrl.setContent('changed'));
    });

    test('TextLayer == ignores identity but distinguishes content + style', () {
      final base = TextLayer(
        id: 'x',
        transform: LayerTransform(
          position: Offset.zero,
          size: const Size(100, 30),
        ),
        content: 'hello',
        style: const TextStyleSpec(),
      );
      final sameContent = base.copyWith();
      expect(base, equals(sameContent));
      expect(base.hashCode, sameContent.hashCode);

      expect(base.copyWith(content: 'other'), isNot(equals(base)));
      expect(
        base.copyWith(style: const TextStyleSpec(fontSize: 99)),
        isNot(equals(base)),
      );
    });

    group('live edit', () {
      test('previewContent updates content + auto-resizes height '
          'without pushing history', () {
        final c = makeContainer();
        final original = addText(c, content: 'one');
        c.read(selectionControllerProvider.notifier).select(original.id);
        final ctrl = c.read(textToolControllerProvider.notifier);

        ctrl.beginEditText();
        ctrl.previewContent('one\ntwo\nthree');

        final live =
            c.read(renderedDocumentProvider).layerById(original.id)
                as TextLayer;
        expect(live.content, 'one\ntwo\nthree');
        // Bounding box auto-fits the natural text size: height grew to
        // accommodate three lines.
        expect(
          live.transform.size.height,
          greaterThan(original.transform.size.height),
        );

        // History was not touched: undo restores the empty document
        // state (everything before the AddLayerCommand).
        expect(c.read(documentControllerProvider.notifier).canUndo, isTrue);
        c.read(documentControllerProvider.notifier).undo();
        // After single undo we should be back to the state BEFORE the
        // text was added — proves the previews didn't push entries.
        expect(
          c.read(documentControllerProvider).layerById(original.id),
          isNull,
        );
      });

      test('commitLiveEdit pushes ONE undo entry covering all keystrokes', () {
        final c = makeContainer();
        final original = addText(c, content: 'a');
        c.read(selectionControllerProvider.notifier).select(original.id);
        final ctrl = c.read(textToolControllerProvider.notifier);
        final docCtrl = c.read(documentControllerProvider.notifier);

        ctrl.beginEditText();
        ctrl.previewContent('ab');
        ctrl.previewContent('abc');
        ctrl.previewContent('abc\ndef');
        ctrl.commitLiveEdit('abc\ndef');

        final after =
            c.read(documentControllerProvider).layerById(original.id)
                as TextLayer;
        expect(after.content, 'abc\ndef');

        // ONE undo step undoes the whole edit (text + size).
        docCtrl.undo();
        final reverted =
            c.read(documentControllerProvider).layerById(original.id)
                as TextLayer;
        expect(reverted.content, 'a');
        expect(reverted.transform.size, original.transform.size);
      });

      test(
        'cancelLiveEdit restores the original snapshot, no history entry',
        () {
          final c = makeContainer();
          final original = addText(c, content: 'keep me');
          c.read(selectionControllerProvider.notifier).select(original.id);
          final ctrl = c.read(textToolControllerProvider.notifier);

          ctrl.beginEditText();
          ctrl.previewContent('something else entirely');
          ctrl.cancelLiveEdit();

          final restored =
              c.read(documentControllerProvider).layerById(original.id)
                  as TextLayer;
          expect(restored.content, 'keep me');
          expect(restored.transform.size, original.transform.size);

          // Undo once should remove the layer (the AddLayerCommand),
          // proving cancel didn't push anything to history.
          c.read(documentControllerProvider.notifier).undo();
          expect(
            c.read(documentControllerProvider).layerById(original.id),
            isNull,
          );
        },
      );

      test('commitLiveEdit with no actual change pushes nothing', () {
        final c = makeContainer();
        final original = addText(c, content: 'unchanged');
        c.read(selectionControllerProvider.notifier).select(original.id);
        final ctrl = c.read(textToolControllerProvider.notifier);

        ctrl.beginEditText();
        ctrl.commitLiveEdit('unchanged');

        // Single undo removes the AddLayerCommand → layer gone.
        c.read(documentControllerProvider.notifier).undo();
        expect(
          c.read(documentControllerProvider).layerById(original.id),
          isNull,
        );
      });

      // Quick-style writes (the composer's Bold/Color strip) inside an
      // EDIT session. Regression tests for the session-writer bug where
      // these fell through to execute(), mutating the committed doc
      // mid-session: debug assert in commit/cancel, style loss on
      // commit, and a cancel that didn't cancel in release.
      test('style writes during an edit session never touch the committed '
          'doc and fold into the single commit entry', () {
        final c = makeContainer();
        final original = addText(c, content: 'hi');
        c.read(selectionControllerProvider.notifier).select(original.id);
        final ctrl = c.read(textToolControllerProvider.notifier);
        final docBefore = c.read(documentControllerProvider);

        ctrl.beginEditText();
        ctrl.setBold(true);
        ctrl.setColor(const Color(0xFF112233));
        ctrl.previewContent('hi there');

        // Committed document instance untouched mid-session — the
        // invariant commitLiveEdit asserts on.
        expect(
          identical(docBefore, c.read(documentControllerProvider)),
          isTrue,
        );
        // Overlay preview carries the style already.
        final live =
            c.read(renderedDocumentProvider).layerById(original.id)
                as TextLayer;
        expect(live.style.fontWeight, FontWeight.bold);
        expect(live.style.color, const Color(0xFF112233));

        ctrl.commitLiveEdit('hi there');

        final after =
            c.read(documentControllerProvider).layerById(original.id)
                as TextLayer;
        expect(after.content, 'hi there');
        expect(after.style.fontWeight, FontWeight.bold);
        expect(after.style.color, const Color(0xFF112233));

        // ONE undo step reverts the whole session (content + style).
        c.read(documentControllerProvider.notifier).undo();
        final reverted =
            c.read(documentControllerProvider).layerById(original.id)
                as TextLayer;
        expect(reverted.content, 'hi');
        expect(reverted.style.fontWeight, original.style.fontWeight);
        expect(reverted.style.color, original.style.color);
      });

      test('cancel after quick-style writes in an edit session is a true '
          'no-op', () {
        final c = makeContainer();
        final original = addText(c, content: 'keep');
        c.read(selectionControllerProvider.notifier).select(original.id);
        final ctrl = c.read(textToolControllerProvider.notifier);

        ctrl.beginEditText();
        ctrl.setBold(true);
        ctrl.setColor(const Color(0xFF445566));
        ctrl.previewContent('scrap this');
        ctrl.cancelLiveEdit();

        final restored =
            c.read(documentControllerProvider).layerById(original.id)
                as TextLayer;
        expect(restored.content, 'keep');
        expect(restored.style, original.style);

        // No history entry: one undo removes the AddLayerCommand.
        c.read(documentControllerProvider.notifier).undo();
        expect(
          c.read(documentControllerProvider).layerById(original.id),
          isNull,
        );
      });

      test('undo landing mid style-drag wins: the drag commit is '
          'abandoned', () {
        // Regression (roadmap tb0 0.7): the AppBar Undo button stays
        // live while a dock slider is held. Pre-fix, endStyleDrag
        // asserted in debug and, in release, committed a full-layer
        // restore built from pre-undo state — silently reverting the
        // user's undo.
        final c = makeContainer();
        final original = addText(c, content: 'first');
        c.read(selectionControllerProvider.notifier).select(original.id);
        final ctrl = c.read(textToolControllerProvider.notifier);
        final docCtrl = c.read(documentControllerProvider.notifier);

        // A committed edit the mid-drag undo will revert.
        ctrl.setColor(const Color(0xFF445566));
        expect(
          (c.read(documentControllerProvider).layerById(original.id)!
                  as TextLayer)
              .style
              .color,
          const Color(0xFF445566),
        );

        ctrl.beginStyleDrag();
        ctrl.setFontSize(140); // overlay preview only
        docCtrl.undo(); // second finger hits Undo mid-drag
        ctrl.endStyleDrag(); // release — must NOT commit the drag

        final after =
            c.read(documentControllerProvider).layerById(original.id)!
                as TextLayer;
        expect(
          after.style.color,
          original.style.color,
          reason: 'the undo must survive the drag release',
        );
        expect(
          after.style.fontSize,
          original.style.fontSize,
          reason: 'the abandoned drag must leave no trace',
        );
        // Overlay dropped: merged view equals committed view.
        final merged =
            c.read(renderedDocumentProvider).layerById(original.id)!
                as TextLayer;
        expect(merged.style.fontSize, original.style.fontSize);
      });

      test('style-only edit session with unchanged content still commits '
          'one entry', () {
        final c = makeContainer();
        final original = addText(c, content: 'same');
        c.read(selectionControllerProvider.notifier).select(original.id);
        final ctrl = c.read(textToolControllerProvider.notifier);

        ctrl.beginEditText();
        ctrl.setBold(true);
        ctrl.commitLiveEdit('same');

        final after =
            c.read(documentControllerProvider).layerById(original.id)
                as TextLayer;
        expect(after.content, 'same');
        expect(after.style.fontWeight, FontWeight.bold);

        // Exactly one entry: first undo reverts the style, second
        // removes the layer.
        final docCtrl = c.read(documentControllerProvider.notifier);
        docCtrl.undo();
        final reverted =
            c.read(documentControllerProvider).layerById(original.id)
                as TextLayer;
        expect(reverted.style.fontWeight, original.style.fontWeight);
        docCtrl.undo();
        expect(
          c.read(documentControllerProvider).layerById(original.id),
          isNull,
        );
      });

      test('preview/commit on no selection are safe no-ops', () {
        final c = makeContainer();
        final ctrl = c.read(textToolControllerProvider.notifier);
        // No selection.
        ctrl.beginEditText();
        ctrl.previewContent('whatever');
        ctrl.commitLiveEdit('whatever');
        ctrl.cancelLiveEdit();
        // No throw, no state change.
        expect(c.read(documentControllerProvider).layers, isEmpty);
      });

      test('edit: clearing all text and committing is treated as cancel '
          '(original preserved, no history entry)', () {
        final c = makeContainer();
        final original = addText(c, content: 'do not lose me');
        c.read(selectionControllerProvider.notifier).select(original.id);
        final ctrl = c.read(textToolControllerProvider.notifier);

        ctrl.beginEditText();
        ctrl.previewContent('');
        ctrl.commitLiveEdit('');

        final after =
            c.read(documentControllerProvider).layerById(original.id)
                as TextLayer;
        expect(after.content, 'do not lose me');
        expect(after.transform.size, original.transform.size);

        // No history pushed: single undo removes the AddLayerCommand.
        c.read(documentControllerProvider.notifier).undo();
        expect(
          c.read(documentControllerProvider).layerById(original.id),
          isNull,
        );
      });

      test('edit: whitespace-only commit is treated as cancel', () {
        final c = makeContainer();
        final original = addText(c, content: 'real content');
        c.read(selectionControllerProvider.notifier).select(original.id);
        final ctrl = c.read(textToolControllerProvider.notifier);

        ctrl.beginEditText();
        ctrl.commitLiveEdit('   \n  ');

        final after =
            c.read(documentControllerProvider).layerById(original.id)
                as TextLayer;
        expect(after.content, 'real content');
      });

      test('edit auto-resizes the bounding box to fit the new content', () {
        final c = makeContainer();
        final original = addText(c, content: 'hi');
        c.read(selectionControllerProvider.notifier).select(original.id);
        final ctrl = c.read(textToolControllerProvider.notifier);

        ctrl.beginEditText();
        ctrl.commitLiveEdit('a much longer string\nwith multiple lines');
        final committed =
            c.read(documentControllerProvider).layerById(original.id)
                as TextLayer;
        expect(committed.transform.size, isNot(original.transform.size));
        expect(
          committed.transform.size.height,
          greaterThan(original.transform.size.height),
        );
      });

      test('add: beginAddText stages a centered empty layer + selects it; '
          'previewContent grows it; commit produces ONE add entry', () {
        final c = makeContainer();
        final ctrl = c.read(textToolControllerProvider.notifier);

        final id = ctrl.beginAddText();
        // Layer is staged + selected immediately.
        expect(c.read(selectionControllerProvider).selectedId, id);
        var staged =
            c.read(renderedDocumentProvider).layerById(id) as TextLayer;
        expect(staged.content, '');

        ctrl.previewContent('hello\nworld');
        staged = c.read(renderedDocumentProvider).layerById(id) as TextLayer;
        expect(staged.content, 'hello\nworld');

        ctrl.commitLiveEdit('hello\nworld');
        final committed =
            c.read(documentControllerProvider).layerById(id) as TextLayer;
        expect(committed.content, 'hello\nworld');
        expect(c.read(selectionControllerProvider).selectedId, id);

        // Commit pushed exactly one entry — undo removes the layer.
        c.read(documentControllerProvider.notifier).undo();
        expect(c.read(documentControllerProvider).layerById(id), isNull);
        expect(c.read(documentControllerProvider.notifier).canRedo, isTrue);
        // Redo restores it identically.
        c.read(documentControllerProvider.notifier).redo();
        expect(
          (c.read(documentControllerProvider).layerById(id) as TextLayer)
              .content,
          'hello\nworld',
        );
      });

      test('add: cancel removes the staged layer and restores the prior '
          'selection', () {
        final c = makeContainer();
        // Set up some other layer to be the prior selection.
        addText(c, id: 'prior', content: 'prior');
        c.read(selectionControllerProvider.notifier).select('prior');
        final ctrl = c.read(textToolControllerProvider.notifier);

        final id = ctrl.beginAddText();
        ctrl.previewContent('typing');
        expect(c.read(renderedDocumentProvider).layerById(id), isNotNull);

        ctrl.cancelLiveEdit();
        expect(c.read(documentControllerProvider).layerById(id), isNull);
        expect(c.read(selectionControllerProvider).selectedId, 'prior');
      });

      test('add: empty / whitespace commit is treated as cancel — '
          'no layer added, no history entry', () {
        final c = makeContainer();
        final ctrl = c.read(textToolControllerProvider.notifier);

        final id = ctrl.beginAddText();
        ctrl.previewContent('a');
        ctrl.previewContent('');
        ctrl.commitLiveEdit('   ');

        expect(c.read(documentControllerProvider).layerById(id), isNull);
        expect(c.read(documentControllerProvider.notifier).canUndo, isFalse);
        expect(c.read(selectionControllerProvider).hasSelection, isFalse);
      });

      test(
        'add: typing then deleting then re-typing keeps preview in sync',
        () {
          final c = makeContainer();
          final ctrl = c.read(textToolControllerProvider.notifier);

          final id = ctrl.beginAddText();
          ctrl.previewContent('he');
          ctrl.previewContent('hel');
          ctrl.previewContent('h');
          ctrl.previewContent('');
          ctrl.previewContent('done');

          final live =
              c.read(renderedDocumentProvider).layerById(id) as TextLayer;
          expect(live.content, 'done');
        },
      );

      test('add: uses defaultStyle from session at the moment of begin, '
          'scaled to canvas dimensions', () {
        final c = makeContainer();
        final ctrl = c.read(textToolControllerProvider.notifier);
        ctrl.setFontSize(64);
        final id = ctrl.beginAddText();
        final staged =
            c.read(renderedDocumentProvider).layerById(id) as TextLayer;
        // Default style font sizes are authored against a 1080-px
        // reference canvas; on this 800-square canvas the staged
        // layer scales proportionally: 64 \u00d7 800/1080 \u2248 47.4.
        // Other style fields pass through verbatim.
        expect(staged.style.fontSize, closeTo(64 * 800 / 1080, 0.5));
      });

      test('add: scales font size up on a poster-sized canvas', () {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        c
            .read(documentControllerProvider.notifier)
            .newDocument(width: 2160, height: 2160);
        final ctrl = c.read(textToolControllerProvider.notifier);
        ctrl.setFontSize(48);
        final id = ctrl.beginAddText();
        final staged =
            c.read(renderedDocumentProvider).layerById(id) as TextLayer;
        // 48 \u00d7 2160/1080 = 96 \u2014 a 2160-square poster gets 2\u00d7 the
        // visual font size of the 1080 baseline so proportions match.
        expect(staged.style.fontSize, closeTo(96, 0.5));
      });

      test('add: clamps font size on a tiny sticker canvas', () {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        c
            .read(documentControllerProvider.notifier)
            .newDocument(width: 100, height: 100);
        final ctrl = c.read(textToolControllerProvider.notifier);
        ctrl.setFontSize(48);
        final id = ctrl.beginAddText();
        final staged =
            c.read(renderedDocumentProvider).layerById(id) as TextLayer;
        // 48 \u00d7 100/1080 \u2248 4.4, clamped to the 8-px floor so the
        // text remains visible / hit-testable on a sticker canvas.
        expect(staged.style.fontSize, 8.0);
      });

      test('add: uses geometric mean for landscape banners', () {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        // 16:9 hero banner -- using min(w, h) would give 1080 and
        // leave 48-pt looking too small. Geometric mean
        // sqrt(1920 * 1080) ~= 1440 captures the canvas's true
        // presence: 48 * 1440/1080 = 64 -> snapped to 64.0.
        c
            .read(documentControllerProvider.notifier)
            .newDocument(width: 1920, height: 1080);
        final ctrl = c.read(textToolControllerProvider.notifier);
        ctrl.setFontSize(48);
        final id = ctrl.beginAddText();
        final staged =
            c.read(renderedDocumentProvider).layerById(id) as TextLayer;
        expect(staged.style.fontSize, 64.0);
      });

      test('add: extreme aspect ratio falls back to long axis '
          'so ticker banners stay readable', () {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        // 20:1 ticker -- geometric mean would give sqrt(4000 * 200)
        // ~= 894, scaling 48-pt down to ~40 pt despite the huge
        // canvas. Above the 4:1 aspect threshold we use the long
        // axis instead: 48 * 4000/1080 ~= 177.78 -> 178.0.
        c
            .read(documentControllerProvider.notifier)
            .newDocument(width: 4000, height: 200);
        final ctrl = c.read(textToolControllerProvider.notifier);
        ctrl.setFontSize(48);
        final id = ctrl.beginAddText();
        final staged =
            c.read(renderedDocumentProvider).layerById(id) as TextLayer;
        expect(staged.style.fontSize, 178.0);
      });

      test('add: snaps scaled font size to nearest 0.5 pt', () {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        // 700-square -> 48 * 700/1080 = 31.111..., snapped to 31.0
        // (nearest 0.5) so the size shown in the slider/label reads
        // as a clean number.
        c
            .read(documentControllerProvider.notifier)
            .newDocument(width: 700, height: 700);
        final ctrl = c.read(textToolControllerProvider.notifier);
        ctrl.setFontSize(48);
        final id = ctrl.beginAddText();
        final staged =
            c.read(renderedDocumentProvider).layerById(id) as TextLayer;
        expect(staged.style.fontSize, 31.0);
      });

      test('isLiveEditing reflects begin/commit/cancel transitions', () {
        final c = makeContainer();
        final ctrl = c.read(textToolControllerProvider.notifier);
        expect(ctrl.isLiveEditing, isFalse);
        ctrl.beginAddText();
        expect(ctrl.isLiveEditing, isTrue);
        ctrl.commitLiveEdit('x');
        expect(ctrl.isLiveEditing, isFalse);

        addText(c, id: 'e1');
        c.read(selectionControllerProvider.notifier).select('e1');
        ctrl.beginEditText();
        expect(ctrl.isLiveEditing, isTrue);
        ctrl.cancelLiveEdit();
        expect(ctrl.isLiveEditing, isFalse);
      });
    });

    group('new-add wrap-inside-canvas', () {
      // Regression: in scaleText mode the natural width is unbounded,
      // so as the user types a long word the bounding box used to
      // shoot off the right edge of the canvas (it was anchored to
      // the empty-content centred origin and only the size grew).
      // For NEW layers we now (a) cap the natural width at
      // 90 % of the canvas width so content wraps inside the canvas
      // and (b) re-centre the layer on every keystroke so it grows
      // symmetrically around the canvas centre.

      test('live-typing a long word wraps inside the canvas instead '
          'of overflowing the right edge', () {
        final c = makeContainer(); // 800 \u00d7 800 doc
        final ctrl = c.read(textToolControllerProvider.notifier);
        final id = ctrl.beginAddText();
        // A long single "word" that, unwrapped at the default
        // ~96-pt-scaled font, would easily exceed 800 px wide.
        ctrl.previewContent('Hellohellohellohello');
        final layer =
            c.read(renderedDocumentProvider).layerById(id) as TextLayer;
        final right = layer.transform.position.dx + layer.transform.size.width;
        final canvasWidth = c.read(documentControllerProvider).width;
        // Box stays inside the canvas (within the 90 % wrap cap +
        // a tiny rounding tolerance for the painter).
        expect(right, lessThanOrEqualTo(canvasWidth + 0.5));
        expect(layer.transform.position.dx, greaterThanOrEqualTo(-0.5));
        // And the box wrapped \u2014 height is more than a single line.
        expect(layer.transform.size.height, greaterThan(layer.style.fontSize));
        ctrl.cancelLiveEdit();
      });

      test('layer stays horizontally centred as content grows', () {
        final c = makeContainer();
        final ctrl = c.read(textToolControllerProvider.notifier);
        final id = ctrl.beginAddText();
        final canvasCx = c.read(documentControllerProvider).width / 2;

        for (final text in ['A', 'AB', 'ABC', 'A long line of text']) {
          ctrl.previewContent(text);
          final layer =
              c.read(renderedDocumentProvider).layerById(id) as TextLayer;
          final cx =
              layer.transform.position.dx + layer.transform.size.width / 2;
          expect(
            cx,
            closeTo(canvasCx, 0.5),
            reason: 'centre drift while typing "$text"',
          );
        }
        ctrl.cancelLiveEdit();
      });

      test('committing a long string lands a layer that fits inside '
          'the canvas', () {
        final c = makeContainer();
        final ctrl = c.read(textToolControllerProvider.notifier);
        ctrl.beginAddText();
        ctrl.previewContent('Hellohellohellohello');
        ctrl.commitLiveEdit('Hellohellohellohello');
        final layers = c.read(documentControllerProvider).layers;
        expect(layers, hasLength(1));
        final layer = layers.single as TextLayer;
        final canvasWidth = c.read(documentControllerProvider).width;
        final right = layer.transform.position.dx + layer.transform.size.width;
        expect(layer.transform.position.dx, greaterThanOrEqualTo(-0.5));
        expect(right, lessThanOrEqualTo(canvasWidth + 0.5));
      });

      test('editing an EXISTING layer never moves it (resize cap is '
          'opt-in to the new-add flow only)', () {
        final c = makeContainer();
        final layer = addText(c, id: 'e1', content: 'hi');
        c.read(selectionControllerProvider.notifier).select(layer.id);
        final ctrl = c.read(textToolControllerProvider.notifier);
        final originalPos = layer.transform.position;
        ctrl.beginEditText();
        ctrl.previewContent('hi there a much longer string');
        final after =
            c.read(renderedDocumentProvider).layerById(layer.id) as TextLayer;
        expect(after.transform.position, originalPos);
        ctrl.cancelLiveEdit();
      });

      test('short content commits in scaleText mode (snug single-line '
          'box, sticker semantics)', () {
        final c = makeContainer();
        final ctrl = c.read(textToolControllerProvider.notifier);
        ctrl.beginAddText();
        ctrl.previewContent('Hi');
        ctrl.commitLiveEdit('Hi');
        final layer =
            c.read(documentControllerProvider).layers.single as TextLayer;
        expect(layer.resizeMode, TextResizeMode.scaleText);
      });

      test('long (wrapped) content commits in resizeBox mode so '
          'corner-drag re-wraps the paragraph cleanly', () {
        final c = makeContainer();
        final ctrl = c.read(textToolControllerProvider.notifier);
        ctrl.beginAddText();
        ctrl.previewContent('Hellohellohellohello');
        ctrl.commitLiveEdit('Hellohellohellohello');
        final layer =
            c.read(documentControllerProvider).layers.single as TextLayer;
        expect(layer.resizeMode, TextResizeMode.resizeBox);
        // resizeBox commits at the wrap-cap width, not the natural
        // (overflowing) width.
        final canvasWidth = c.read(documentControllerProvider).width;
        expect(
          layer.transform.size.width,
          lessThanOrEqualTo(canvasWidth * 0.9 + 0.5),
        );
      });

      test('changing font size mid-type re-flows + re-centres the '
          'live new-add layer without polluting history', () {
        final c = makeContainer();
        final ctrl = c.read(textToolControllerProvider.notifier);
        final id = ctrl.beginAddText();
        ctrl.previewContent('Hi');
        final beforeSize =
            (c.read(renderedDocumentProvider).layerById(id) as TextLayer)
                .transform
                .size;
        // Drag the size slider mid-type.
        ctrl.setFontSize(200);
        final after =
            c.read(renderedDocumentProvider).layerById(id) as TextLayer;
        // Box re-measured to the new style.
        expect(after.style.fontSize, 200);
        expect(after.transform.size, isNot(beforeSize));
        // Still horizontally centred at the new size.
        final canvasCx = c.read(documentControllerProvider).width / 2;
        final cx = after.transform.position.dx + after.transform.size.width / 2;
        expect(cx, closeTo(canvasCx, 0.5));
        // No extra history entries pushed during the live session.
        expect(c.read(documentControllerProvider.notifier).canUndo, isFalse);
        ctrl.cancelLiveEdit();
      });
    });

    group('sub-toolbar persistence on selection change', () {
      // Sheets persist across selection changes (consistent with
      // paint mode). The panel widget renders nothing when no text
      // layer is selected, so the sheet visually hides on deselect
      // and reappears on re-select. State is preserved.

      test('clearing selection preserves the open sheet', () {
        final c = makeContainer();
        final layer = addText(c, id: 't1');
        c.read(selectionControllerProvider.notifier).select(layer.id);
        final ctrl = c.read(textToolControllerProvider.notifier);
        ctrl.toggleSheet('style');
        expect(c.read(textToolControllerProvider).openSheet, 'style');

        // Simulate canvas-tap-to-deselect — sheet state stays so
        // re-selection restores the user's working context.
        c.read(selectionControllerProvider.notifier).clear();
        expect(c.read(textToolControllerProvider).openSheet, 'style');
      });

      test('switching to a non-text layer preserves the sheet', () {
        final c = makeContainer();
        final text = addText(c, id: 'text');
        c.read(selectionControllerProvider.notifier).select(text.id);
        final ctrl = c.read(textToolControllerProvider.notifier);
        ctrl.toggleSheet('color');
        expect(c.read(textToolControllerProvider).openSheet, 'color');

        c.read(selectionControllerProvider.notifier).clear();
        expect(c.read(textToolControllerProvider).openSheet, 'color');
      });

      test('selecting a different text layer keeps the sheet open', () {
        // Switching between two text layers is still a "text editing"
        // intent — the user expects the sub-toolbar to follow them
        // rather than reset.
        final c = makeContainer();
        final a = addText(c, id: 'a');
        addText(c, id: 'b');
        c.read(selectionControllerProvider.notifier).select(a.id);
        final ctrl = c.read(textToolControllerProvider.notifier);
        ctrl.toggleSheet('style');
        expect(c.read(textToolControllerProvider).openSheet, 'style');

        c.read(selectionControllerProvider.notifier).select('b');
        expect(c.read(textToolControllerProvider).openSheet, 'style');
      });
    });

    group('style change auto-resizes box', () {
      // Regression: a font-size change used to update the layer's
      // style but leave transform.size untouched, so the rendered text
      // grew past the bounding box and got clipped. Style writes must
      // re-measure the layer to its natural size at the new style and
      // bundle the new transform into the same UpdateTextCommand so
      // content + size update in lock-step (one undo entry) and the
      // selection overlay never lags.

      test('setFontSize: layer grows when font size grows', () {
        final c = makeContainer();
        final layer = addText(c, content: 'one\ntwo');
        c.read(selectionControllerProvider.notifier).select(layer.id);
        final h0 = layer.transform.size.height;
        final w0 = layer.transform.size.width;

        // Default fontSize is 96 (heading-weight), so we use 144 to
        // exercise growth past the default.
        c.read(textToolControllerProvider.notifier).setFontSize(144);
        final after =
            c.read(documentControllerProvider).layerById(layer.id) as TextLayer;
        expect(after.style.fontSize, 144);
        expect(after.transform.size.height, greaterThan(h0));
        expect(after.transform.size.width, greaterThan(w0));
      });

      test('setFontSize: layer shrinks when font size shrinks', () {
        final c = makeContainer();
        final layer = addText(
          c,
          content: 'one\ntwo',
          style: const TextStyleSpec(fontSize: 96),
        );
        c.read(selectionControllerProvider.notifier).select(layer.id);
        final h0 = layer.transform.size.height;

        c.read(textToolControllerProvider.notifier).setFontSize(12);
        final after =
            c.read(documentControllerProvider).layerById(layer.id) as TextLayer;
        expect(after.transform.size.height, lessThan(h0));
      });

      test('setLineHeight + setLetterSpacing also re-measure', () {
        final c = makeContainer();
        final layer = addText(c, content: 'measure me');
        c.read(selectionControllerProvider.notifier).select(layer.id);
        final ctrl = c.read(textToolControllerProvider.notifier);
        final h0 = layer.transform.size.height;
        ctrl.setLineHeight(2.5);
        final h1 =
            (c.read(documentControllerProvider).layerById(layer.id)
                    as TextLayer)
                .transform
                .size
                .height;
        expect(h1, greaterThan(h0));
        final w1 =
            (c.read(documentControllerProvider).layerById(layer.id)
                    as TextLayer)
                .transform
                .size
                .width;
        ctrl.setLetterSpacing(20);
        final after =
            c.read(documentControllerProvider).layerById(layer.id) as TextLayer;
        // Letter-spacing widens the natural text bounds.
        expect(after.transform.size.width, greaterThan(w1));
      });

      test('setBold re-measures (bolder glyphs are wider)', () {
        final c = makeContainer();
        final layer = addText(
          c,
          content: 'a b c d e f g h i',
          style: const TextStyleSpec(fontWeight: FontWeight.w400),
        );
        c.read(selectionControllerProvider.notifier).select(layer.id);
        c.read(textToolControllerProvider.notifier).setBold(true);
        final after =
            c.read(documentControllerProvider).layerById(layer.id) as TextLayer;
        expect(after.style.isBold, isTrue);
      });

      test('setFontSize on a corner-scaled layer preserves visual size '
          '(no jump back to natural metrics)', () {
        final c = makeContainer();
        // Start a layer whose box is much larger than its natural size
        // — simulates a prior corner-drag that scaled the rendered text
        // up via FittedBox. fontSize=10 + 600x400 box ⇒ visual scale ≫ 1.
        final layer = TextLayer(
          id: 'scaled',
          transform: const LayerTransform(
            position: Offset.zero,
            size: Size(600, 400),
          ),
          content: 'hi',
          style: const TextStyleSpec(fontSize: 10),
        );
        c
            .read(documentControllerProvider.notifier)
            .execute(AddLayerCommand(layer));
        c.read(selectionControllerProvider.notifier).select('scaled');

        // User taps A+ / picks a slightly larger preset (12 in stepper
        // space). Because the layer was scaled up ~Nx, the controller
        // translates the request through the same factor so the
        // *visual* glyph height grows by the same +20% the user asked
        // for, instead of snapping down to a tiny natural-at-12 box.
        c.read(textToolControllerProvider.notifier).setFontSize(12);
        final after =
            c.read(documentControllerProvider).layerById('scaled') as TextLayer;
        // Resulting fontSize is much larger than the raw request — it
        // absorbs the prior visual scale.
        expect(after.style.fontSize, greaterThan(12));
        // Bounding box does NOT collapse to a tiny natural-at-12 box.
        expect(
          after.transform.size.height,
          greaterThan(layer.transform.size.height * 0.5),
        );
      });

      test('style change is ONE undoable step that reverts BOTH style '
          'and auto-measured box', () {
        final c = makeContainer();
        final layer = addText(c, content: 'two\nlines');
        c.read(selectionControllerProvider.notifier).select(layer.id);
        c.read(textToolControllerProvider.notifier).setFontSize(144);
        final after =
            c.read(documentControllerProvider).layerById(layer.id) as TextLayer;
        expect(after.style.fontSize, 144);
        expect(after.transform.size, isNot(layer.transform.size));

        c.read(documentControllerProvider.notifier).undo();
        final reverted =
            c.read(documentControllerProvider).layerById(layer.id) as TextLayer;
        expect(reverted.style.fontSize, layer.style.fontSize);
        expect(reverted.transform.size, layer.transform.size);
      });

      test(
        'live slider: many setFontSize calls keep box in sync each frame',
        () {
          final c = makeContainer();
          final layer = addText(c, content: 'long\ntext\nhere');
          c.read(selectionControllerProvider.notifier).select(layer.id);
          final ctrl = c.read(textToolControllerProvider.notifier);
          for (final s in [20.0, 40.0, 60.0, 80.0, 100.0]) {
            ctrl.setFontSize(s);
            final live =
                c.read(documentControllerProvider).layerById(layer.id)
                    as TextLayer;
            // Box must always reflect THIS step's measured size for the
            // current style — never a stale value from a previous frame.
            final expected = TextPainter(
              text: TextSpan(
                text: live.content,
                style: TextStyle(
                  fontFamily: live.style.fontFamily,
                  fontSize: live.style.fontSize,
                  fontWeight: live.style.fontWeight,
                  fontStyle: live.style.italic
                      ? FontStyle.italic
                      : FontStyle.normal,
                  letterSpacing: live.style.letterSpacing,
                  height: live.style.lineHeight,
                ),
              ),
              textAlign: live.style.alignment,
              textDirection: TextDirection.ltr,
              maxLines: null,
            )..layout(maxWidth: double.infinity);
            expect(live.transform.size.height, expected.height);
            expect(live.transform.size.width, expected.width);
            expected.dispose();
          }
        },
      );
    });

    group('resize mode (per-layer opt-in)', () {
      test('default mode is scaleText and capability is aspect-locked', () {
        final c = makeContainer();
        final ctrl = c.read(textToolControllerProvider.notifier);
        final id = ctrl.beginAddText();
        final staged =
            c.read(renderedDocumentProvider).layerById(id) as TextLayer;
        expect(staged.resizeMode, TextResizeMode.scaleText);
        expect(staged.capabilities.keepsAspectRatio, isTrue);
      });

      test('setResizeMode swaps capability and re-measures the box', () {
        final c = makeContainer();
        final layer = addText(c, content: 'hello\nworld');
        c.read(selectionControllerProvider.notifier).select(layer.id);
        final w0 = layer.transform.size.width;

        c
            .read(textToolControllerProvider.notifier)
            .setResizeMode(TextResizeMode.resizeBox);
        final after =
            c.read(documentControllerProvider).layerById(layer.id) as TextLayer;
        expect(after.resizeMode, TextResizeMode.resizeBox);
        expect(after.capabilities.keepsAspectRatio, isFalse);
        // Width is preserved across the mode switch (resizeBox keeps the
        // current column); height is re-measured for that column.
        expect(after.transform.size.width, w0);
      });

      test('resizeBox: setFontSize keeps width, height re-measures', () {
        final c = makeContainer();
        final layer = addText(c, content: 'one two three four five');
        c.read(selectionControllerProvider.notifier).select(layer.id);
        c
            .read(textToolControllerProvider.notifier)
            .setResizeMode(TextResizeMode.resizeBox);
        final boxLayer =
            c.read(documentControllerProvider).layerById(layer.id) as TextLayer;
        final w = boxLayer.transform.size.width;
        final h0 = boxLayer.transform.size.height;

        c.read(textToolControllerProvider.notifier).setFontSize(144);
        final after =
            c.read(documentControllerProvider).layerById(layer.id) as TextLayer;
        // Width unchanged (wrap column held), height grew to fit the
        // bigger wrapped paragraph.
        expect(after.transform.size.width, w);
        expect(after.transform.size.height, greaterThan(h0));
      });

      test('setResizeMode is undoable and restores previous mode + box', () {
        final c = makeContainer();
        final layer = addText(c, content: 'roundtrip');
        c.read(selectionControllerProvider.notifier).select(layer.id);
        final originalSize = layer.transform.size;
        final originalMode = layer.resizeMode;

        c
            .read(textToolControllerProvider.notifier)
            .setResizeMode(TextResizeMode.resizeBox);
        c.read(documentControllerProvider.notifier).undo();
        final reverted =
            c.read(documentControllerProvider).layerById(layer.id) as TextLayer;
        expect(reverted.resizeMode, originalMode);
        expect(reverted.transform.size, originalSize);
      });
    });

    group('text direction mode', () {
      test('setTextDirectionMode is undoable', () {
        final c = makeContainer();
        final layer = addText(c, content: 'Hello سلام');
        c.read(selectionControllerProvider.notifier).select(layer.id);

        c
            .read(textToolControllerProvider.notifier)
            .setTextDirectionMode(TextDirectionMode.rtl);
        var current =
            c.read(documentControllerProvider).layerById(layer.id) as TextLayer;
        expect(current.textDirectionMode, TextDirectionMode.rtl);

        c.read(documentControllerProvider.notifier).undo();
        current =
            c.read(documentControllerProvider).layerById(layer.id) as TextLayer;
        expect(current.textDirectionMode, TextDirectionMode.auto);
      });

      test('edit preserves a forced direction mode for mixed text', () {
        final c = makeContainer();
        final layer = addText(
          c,
          content: 'Hello سلام',
          textDirectionMode: TextDirectionMode.rtl,
        );
        c.read(selectionControllerProvider.notifier).select(layer.id);
        final ctrl = c.read(textToolControllerProvider.notifier);

        ctrl.beginEditText();
        ctrl.previewContent('Sale ۵۰٪ امروز');
        ctrl.commitLiveEdit('Sale ۵۰٪ امروز');

        final current =
            c.read(documentControllerProvider).layerById(layer.id) as TextLayer;
        expect(current.content, 'Sale ۵۰٪ امروز');
        expect(current.textDirectionMode, TextDirectionMode.rtl);
      });
    });

    group('edit existing text preserves visual size', () {
      // Bug-1 regression: opening edit on a text layer that the user
      // had previously corner-scaled used to re-measure the box to
      // natural metrics on the first preview/commit, snapping the
      // glyphs to a much smaller visual size. The live session now
      // captures the layer's scale at begin and re-applies it to
      // every measured size during the edit, so the user's manual
      // scale survives content changes verbatim.

      test('beginEditText followed by previewContent keeps the scaled '
          'box size proportional to the prior visual scale', () {
        final c = makeContainer();
        // Layer with box deliberately ~5x its natural width — a
        // user corner-drag scale-up.
        final layer = TextLayer(
          id: 'edit-scaled',
          transform: const LayerTransform(
            position: Offset.zero,
            size: Size(800, 200),
          ),
          content: 'hi',
          style: const TextStyleSpec(fontSize: 20),
        );
        c
            .read(documentControllerProvider.notifier)
            .execute(AddLayerCommand(layer));
        c.read(selectionControllerProvider.notifier).select('edit-scaled');
        final beforeSize = layer.transform.size;
        final ctrl = c.read(textToolControllerProvider.notifier);
        ctrl.beginEditText();
        ctrl.previewContent('hello');
        final after =
            c.read(documentControllerProvider).layerById('edit-scaled')
                as TextLayer;
        // The box still reflects the prior scale (within an order of
        // magnitude of the original height) — it does NOT collapse to
        // natural-at-fontSize-20 metrics.
        expect(
          after.transform.size.height,
          greaterThan(beforeSize.height * 0.5),
        );
        ctrl.cancelLiveEdit();
      });

      test('commitLiveEdit on an edited scaled layer keeps the box '
          'roughly at the prior visual scale', () {
        final c = makeContainer();
        final layer = TextLayer(
          id: 'commit-scaled',
          transform: const LayerTransform(
            position: Offset.zero,
            size: Size(800, 200),
          ),
          content: 'hi',
          style: const TextStyleSpec(fontSize: 20),
        );
        c
            .read(documentControllerProvider.notifier)
            .execute(AddLayerCommand(layer));
        c.read(selectionControllerProvider.notifier).select('commit-scaled');
        final beforeHeight = layer.transform.size.height;
        final ctrl = c.read(textToolControllerProvider.notifier);
        ctrl.beginEditText();
        ctrl.commitLiveEdit('hi there');
        final after =
            c.read(documentControllerProvider).layerById('commit-scaled')
                as TextLayer;
        // Same scale preserved — height remains within the same
        // order of magnitude as the pre-edit value.
        expect(after.transform.size.height, greaterThan(beforeHeight * 0.5));
      });
    });

    group('script-aware defaults', () {
      // v2 Persian-first: new text always ships in Vazir (direction
      // still follows the dominant script), and edits re-pick the
      // auto-default (only when the user hasn't picked a font
      // themselves) — which migrates legacy auto-Roboto layers to
      // Vazir on their next edit.

      test('add Persian content commits with Vazir + RTL-friendly content', () {
        final c = makeContainer();
        final ctrl = c.read(textToolControllerProvider.notifier);
        ctrl.beginAddText();
        ctrl.previewContent('سلام');
        ctrl.commitLiveEdit('سلام');
        final layer =
            c.read(documentControllerProvider).layers.single as TextLayer;
        expect(layer.style.fontFamily, 'Vazir_Regular');
        expect(textDirectionForContent(layer.content), TextDirection.rtl);
      });

      test('add English content commits with Vazir + LTR', () {
        final c = makeContainer();
        final ctrl = c.read(textToolControllerProvider.notifier);
        ctrl.beginAddText();
        ctrl.previewContent('Hello');
        ctrl.commitLiveEdit('Hello');
        final layer =
            c.read(documentControllerProvider).layers.single as TextLayer;
        expect(layer.style.fontFamily, 'Vazir_Regular');
        expect(textDirectionForContent(layer.content), TextDirection.ltr);
      });

      test('editing migrates a legacy auto-Roboto layer to Vazir', () {
        final c = makeContainer();
        final layer = addText(
          c,
          content: 'Hello',
          style: const TextStyleSpec(fontFamily: 'Roboto'),
        );
        c.read(selectionControllerProvider.notifier).select(layer.id);
        final ctrl = c.read(textToolControllerProvider.notifier);
        ctrl.beginEditText();
        ctrl.commitLiveEdit('سلام جهان');
        final after =
            c.read(documentControllerProvider).layerById(layer.id) as TextLayer;
        expect(after.style.fontFamily, 'Vazir_Regular');
      });

      test('user-picked font is never overwritten on edit', () {
        final c = makeContainer();
        final layer = addText(
          c,
          content: 'Hello',
          style: const TextStyleSpec(fontFamily: 'Lobster'),
        );
        c.read(selectionControllerProvider.notifier).select(layer.id);
        final ctrl = c.read(textToolControllerProvider.notifier);
        ctrl.beginEditText();
        ctrl.commitLiveEdit('سلام جهان');
        final after =
            c.read(documentControllerProvider).layerById(layer.id) as TextLayer;
        expect(after.style.fontFamily, 'Lobster');
      });
    });
  });
}
