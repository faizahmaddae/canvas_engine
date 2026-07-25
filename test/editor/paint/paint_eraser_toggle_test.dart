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
import 'package:canvas_engine/features/editor/paint/presentation/paint_mode_toolbar.dart';
import 'package:canvas_engine/features/editor/paint/presentation/paint_tool_specs.dart';
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

  group('strip composition', () {
    test('the eraser is reachable from every drawing tool', () {
      for (final tool in PaintToolType.values) {
        final allowed = allowedPaintSlotsFor(tool);
        if (tool == PaintToolType.blur) continue; // its own mode
        expect(
          allowed,
          contains('eraser'),
          reason: '$tool should not need a panel to reach the eraser',
        );
      }
    });

    test('but it is NOT in the sibling-swipe order', () {
      // It has no sheet. Paging onto it would open nothing and swap
      // the user's tool mid-swipe.
      for (final tool in PaintToolType.values) {
        expect(PaintModeToolbar.toolIdsFor(tool), isNot(contains('eraser')));
      }
    });
  });
}
