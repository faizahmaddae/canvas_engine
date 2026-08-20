// Swapping between drawing and erasing is the most frequent action in
// paint mode, and it used to cost a round trip through the tool
// picker: tap the tool tile, wait for a panel covering most of the
// canvas, find the eraser in a grid, tap it, watch the panel close.
// Twice, to get back — and picking the eraser also collapsed the strip
// from four tiles to two, so the toolbar jumped around underneath you.
//
// The eraser now has a permanent tile that toggles straight to erasing
// and straight back.

import 'package:canvas_engine/features/editor/paint/application/paint_tool_controller.dart';
import 'package:canvas_engine/features/editor/paint/domain/paint_tool_type.dart';
import 'package:canvas_engine/features/editor/paint/domain/paint_bench_slot.dart';
import 'package:canvas_engine/features/editor/paint/presentation/paint_bench.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer harness() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  PaintToolType? active(ProviderContainer c) =>
      c.read(paintToolControllerProvider).activeTool;

  group('eraser toggle', () {
    test('flips to the eraser and back in one call each way', () {
      final c = harness();
      final ctrl = c.read(paintToolControllerProvider.notifier);
      ctrl.selectTool(PaintToolType.freestyle);

      ctrl.toggleEraser();
      expect(active(c), PaintToolType.eraser);

      ctrl.toggleEraser();
      expect(active(c), PaintToolType.freestyle);
    });

    test('returns to whatever was being drawn, not always the pen', () {
      final c = harness();
      final ctrl = c.read(paintToolControllerProvider.notifier);
      ctrl.selectTool(PaintToolType.rectangle);

      ctrl.toggleEraser();
      expect(active(c), PaintToolType.eraser);
      ctrl.toggleEraser();
      expect(
        active(c),
        PaintToolType.rectangle,
        reason: 'erasing is a detour from drawing, not a reset',
      );
    });

    test('the eraser never becomes the tool it returns to', () {
      final c = harness();
      final ctrl = c.read(paintToolControllerProvider.notifier);
      ctrl.selectTool(PaintToolType.line);

      // Toggle several times — a naive implementation that records the
      // eraser as "last tool" would strand the user erasing forever.
      for (var i = 0; i < 3; i++) {
        ctrl.toggleEraser();
        ctrl.toggleEraser();
      }
      expect(active(c), PaintToolType.line);
      expect(ctrl.drawTool, PaintToolType.line);
    });

    test('picking the eraser from the picker still records the draw tool', () {
      final c = harness();
      final ctrl = c.read(paintToolControllerProvider.notifier);
      ctrl.selectTool(PaintToolType.circle);
      ctrl.selectTool(PaintToolType.eraser);

      expect(active(c), PaintToolType.eraser);
      expect(
        ctrl.drawTool,
        PaintToolType.circle,
        reason: 'the strip tile has to keep showing something to go back to',
      );
    });
  });

  group('rack composition', () {
    test('the eraser is a permanent rack slot, one tap from any tool', () {
      // The bench's rack is fixed — no capability matrix can hide it.
      expect(PaintBenchSlot.values, contains(PaintBenchSlot.eraser));
      for (final tool in PaintToolType.values) {
        final c = harness();
        final ctrl = c.read(paintToolControllerProvider.notifier);
        ctrl.selectTool(tool);
        ctrl.armBenchSlot(PaintBenchSlot.eraser);
        expect(
          active(c),
          PaintToolType.eraser,
          reason: '$tool should not need a panel to reach the eraser',
        );
      }
    });

    test('it has no options sheet — tap-again must not open anything', () {
      expect(PaintBench.sheetFor(PaintBenchSlot.eraser), isNull);
    });
  });
}
