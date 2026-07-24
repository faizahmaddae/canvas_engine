// Controller-level pins for the merge-gate flip (tb2 6/16,
// interaction contract §3): with UpdateTextCommand /
// UpdatePaintStyleCommand gated on `live`, gesture fencing is
// structural — two discrete interactions are two undo entries no
// matter how close in time, and only sanctioned stepper bursts
// coalesce through the history window.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/paint/application/paint_tool_controller.dart';
import 'package:canvas_engine/features/editor/text/application/text_tool_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    return c;
  }

  group('text merge gate (tb2 6/16)', () {
    void addText(ProviderContainer c) {
      c
          .read(documentControllerProvider.notifier)
          .execute(
            AddLayerCommand(
              const TextLayer(
                id: 't1',
                transform: LayerTransform(
                  position: Offset(50, 50),
                  size: Size(200, 80),
                ),
                content: 'hello',
                style: TextStyleSpec(fontSize: 24),
              ),
            ),
          );
      c.read(selectionControllerProvider.notifier).select('t1');
    }

    test('Bold then Italic taps = TWO entries', () {
      final c = makeContainer();
      addText(c);
      final ctrl = c.read(textToolControllerProvider.notifier);
      final v0 = c.read(documentCommitVersionProvider);

      ctrl.setBold(true);
      ctrl.setItalic(true);
      expect(c.read(documentCommitVersionProvider), v0 + 2);

      c.read(documentControllerProvider.notifier).undo();
      var layer =
          c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(layer.style.italic, isFalse, reason: 'first undo drops italic');
      expect(layer.style.fontWeight, FontWeight.w700, reason: 'bold survives');
      c.read(documentControllerProvider.notifier).undo();
      layer = c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(layer.style.fontWeight, isNot(FontWeight.w700));
    });

    test('two colour swatch cycles back-to-back = TWO entries', () {
      final c = makeContainer();
      addText(c);
      final ctrl = c.read(textToolControllerProvider.notifier);
      final v0 = c.read(documentCommitVersionProvider);

      // Each swatch tap flows begin→set→end within the tap
      // (tb2 4/16 wiring) — well inside the old 1s merge window.
      ctrl.beginStyleDrag();
      ctrl.setColor(const Color(0xFF112233));
      ctrl.endStyleDrag();
      ctrl.beginStyleDrag();
      ctrl.setColor(const Color(0xFF445566));
      ctrl.endStyleDrag();

      expect(
        c.read(documentCommitVersionProvider),
        v0 + 2,
        reason: 'discrete taps must not window-merge (§3)',
      );
    });

    test('A+/A− stepper burst (live) = ONE entry', () {
      final c = makeContainer();
      addText(c);
      final ctrl = c.read(textToolControllerProvider.notifier);
      final v0 = c.read(documentCommitVersionProvider);

      // The size panel's _bump repeat-fire path.
      ctrl.setFontSize(26, live: true);
      ctrl.setFontSize(29, live: true);
      ctrl.setFontSize(32, live: true);

      // Merging replaces the top entry in place — the commit version
      // bumps per write, so count HISTORY entries via undo instead.
      c.read(documentControllerProvider.notifier).undo();
      final layer =
          c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(
        layer.style.fontSize,
        24,
        reason: 'one undo unwinds the whole nudge burst',
      );
      expect(c.read(documentCommitVersionProvider), greaterThan(v0));
    });

    test('two style-drag sessions released back-to-back = TWO entries', () {
      final c = makeContainer();
      addText(c);
      final ctrl = c.read(textToolControllerProvider.notifier);
      double fontSize() =>
          (c.read(documentControllerProvider).layerById('t1') as TextLayer)
              .style
              .fontSize;
      // setFontSize translates requests through the scaleText visual
      // scale, so pin against observed checkpoints, not raw inputs.
      final original = fontSize();

      ctrl.beginStyleDrag();
      ctrl.setFontSize(30);
      ctrl.endStyleDrag();
      final afterFirst = fontSize();
      ctrl.beginStyleDrag();
      ctrl.setFontSize(40);
      ctrl.endStyleDrag();
      expect(fontSize(), isNot(afterFirst));

      c.read(documentControllerProvider.notifier).undo();
      expect(fontSize(), afterFirst, reason: 'undo steps back ONE drag');
      c.read(documentControllerProvider.notifier).undo();
      expect(fontSize(), original);
    });
  });

  group('paint merge gate (tb2 6/16)', () {
    void addStroke(ProviderContainer c) {
      c
          .read(documentControllerProvider.notifier)
          .execute(
            AddLayerCommand(
              PaintLayer(
                id: 'p1',
                transform: const LayerTransform(
                  position: Offset(40, 40),
                  size: Size(200, 100),
                ),
                kind: PaintKind.line,
                normalizedPoints: const [Offset(0, 0.5), Offset(1, 0.5)],
              ),
            ),
          );
      c.read(selectionControllerProvider.notifier).select('p1');
    }

    test('two width drags released back-to-back = TWO entries', () {
      final c = makeContainer();
      addStroke(c);
      final ctrl = c.read(paintToolControllerProvider.notifier);

      ctrl.previewStrokeWidth(20);
      ctrl.commitStrokeWidth();
      ctrl.previewStrokeWidth(40);
      ctrl.commitStrokeWidth();

      c.read(documentControllerProvider.notifier).undo();
      var layer =
          c.read(documentControllerProvider).layerById('p1') as PaintLayer;
      expect(layer.strokeWidth, 20, reason: 'undo steps back ONE drag');
      c.read(documentControllerProvider.notifier).undo();
      layer = c.read(documentControllerProvider).layerById('p1') as PaintLayer;
      expect(layer.strokeWidth, 6.0);
    });

    test('discrete setter mirrors back-to-back = TWO entries', () {
      final c = makeContainer();
      addStroke(c);
      final ctrl = c.read(paintToolControllerProvider.notifier);
      final v0 = c.read(documentCommitVersionProvider);

      ctrl.setStrokeColor(const Color(0xFF111111));
      ctrl.setStrokeColor(const Color(0xFF222222));
      expect(
        c.read(documentCommitVersionProvider),
        v0 + 2,
        reason: 'non-live commands never window-merge (§3)',
      );

      c.read(documentControllerProvider.notifier).undo();
      final layer =
          c.read(documentControllerProvider).layerById('p1') as PaintLayer;
      expect(layer.strokeColor, const Color(0xFF111111));
    });
  });
}
