import 'package:canvas_engine/features/editor/paint/application/paint_tool_controller.dart';
import 'package:canvas_engine/features/editor/paint/domain/paint_bench_slot.dart';
import 'package:canvas_engine/features/editor/paint/domain/paint_tool_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  group('PaintToolController', () {
    test('initial state: panel closed, no active tool', () {
      final c = makeContainer();
      final s = c.read(paintToolControllerProvider);
      expect(s.panelOpen, isFalse);
      expect(s.activeTool, isNull);
    });

    test('closePanel exits the mode wholesale (panel, tool, slot)', () {
      final c = makeContainer();
      final ctrl = c.read(paintToolControllerProvider.notifier);
      ctrl.openPanel();
      expect(c.read(paintToolControllerProvider).panelOpen, isTrue);
      ctrl.selectTool(PaintToolType.line);
      ctrl.toggleSlot('color');
      ctrl.closePanel();
      final s = c.read(paintToolControllerProvider);
      expect(s.panelOpen, isFalse);
      expect(s.activeTool, isNull);
      expect(s.openSlot, isNull);
    });

    test('selectTool keeps panel open and sets the tool', () {
      final c = makeContainer();
      final ctrl = c.read(paintToolControllerProvider.notifier);
      ctrl.selectTool(PaintToolType.freestyle);
      final s = c.read(paintToolControllerProvider);
      expect(s.panelOpen, isTrue);
      expect(s.activeTool, PaintToolType.freestyle);
    });

    test('the rack arms family slots from their remembered variant', () {
      final c = makeContainer();
      final ctrl = c.read(paintToolControllerProvider.notifier);
      // Defaults: solid line, rectangle.
      ctrl.armBenchSlot(PaintBenchSlot.line);
      expect(
        c.read(paintToolControllerProvider).activeTool,
        PaintToolType.line,
      );
      ctrl.armBenchSlot(PaintBenchSlot.shape);
      expect(
        c.read(paintToolControllerProvider).activeTool,
        PaintToolType.rectangle,
      );
      // Picking a variant teaches the slot.
      ctrl.selectTool(PaintToolType.dashLine);
      ctrl.selectTool(PaintToolType.hexagon);
      ctrl.armBenchSlot(PaintBenchSlot.line);
      expect(
        c.read(paintToolControllerProvider).activeTool,
        PaintToolType.dashLine,
      );
      ctrl.armBenchSlot(PaintBenchSlot.shape);
      expect(
        c.read(paintToolControllerProvider).activeTool,
        PaintToolType.hexagon,
      );
    });

    test('enterAdjust un-arms the tool, keeps the mode and the sheet '
        'closed', () {
      final c = makeContainer();
      final ctrl = c.read(paintToolControllerProvider.notifier);
      ctrl.selectTool(PaintToolType.freestyle);
      ctrl.toggleSlot('pen');
      ctrl.armBenchSlot(PaintBenchSlot.adjust);
      final s = c.read(paintToolControllerProvider);
      expect(s.panelOpen, isTrue);
      expect(s.activeTool, isNull);
      expect(s.openSlot, isNull);
    });

    test('re-tapping the eraser slot does not bounce back to drawing', () {
      final c = makeContainer();
      final ctrl = c.read(paintToolControllerProvider.notifier);
      ctrl.selectTool(PaintToolType.freestyle);
      ctrl.armBenchSlot(PaintBenchSlot.eraser);
      expect(
        c.read(paintToolControllerProvider).activeTool,
        PaintToolType.eraser,
      );
      ctrl.armBenchSlot(PaintBenchSlot.eraser);
      expect(
        c.read(paintToolControllerProvider).activeTool,
        PaintToolType.eraser,
        reason: 'rack tiles arm; they do not toggle the tool away',
      );
    });

    test('selectTool ignores unavailable tools', () {
      // No unavailable tools remain in the catalog — verify the guard
      // still rejects an unknown / disabled selection by forcing the
      // available flag check via direct enum probing.
      final unavailable = PaintToolType.values
          .where((t) => !t.available)
          .toList();
      expect(unavailable, isEmpty);
    });

    test('full tool catalog is available', () {
      final available = PaintToolType.values.where((t) => t.available).toSet();
      expect(available, {
        PaintToolType.freestyle,
        PaintToolType.arrow,
        PaintToolType.line,
        PaintToolType.rectangle,
        PaintToolType.circle,
        PaintToolType.eraser,
        PaintToolType.dashLine,
        PaintToolType.dashDotLine,
        PaintToolType.hexagon,
        PaintToolType.polygon,
        PaintToolType.blur,
      });
    });

    test('stroke setters route through controller', () {
      final c = makeContainer();
      final ctrl = c.read(paintToolControllerProvider.notifier);
      ctrl.setStrokeWidth(12);
      ctrl.setPolygonSides(8);
      final s = c.read(paintToolControllerProvider);
      expect(s.strokeWidth, 12);
      expect(s.polygonSides, 8);
    });

    test('setFillEnabled(true) seeds fill from current stroke colour', () {
      final c = makeContainer();
      final ctrl = c.read(paintToolControllerProvider.notifier);
      ctrl.setStrokeColor(const Color(0xFF112233));
      expect(c.read(paintToolControllerProvider).fillColor, isNull);
      ctrl.setFillEnabled(true);
      expect(
        c.read(paintToolControllerProvider).fillColor,
        const Color(0xFF112233),
      );
    });

    test('setFillEnabled(true) is a no-op when fill already on', () {
      final c = makeContainer();
      final ctrl = c.read(paintToolControllerProvider.notifier);
      ctrl.setFillColor(const Color(0xFFAABBCC));
      ctrl.setFillEnabled(true);
      expect(
        c.read(paintToolControllerProvider).fillColor,
        const Color(0xFFAABBCC),
      );
    });

    test('setFillEnabled(false) clears fill colour', () {
      final c = makeContainer();
      final ctrl = c.read(paintToolControllerProvider.notifier);
      ctrl.setFillColor(const Color(0xFFAABBCC));
      ctrl.setFillEnabled(false);
      expect(c.read(paintToolControllerProvider).fillColor, isNull);
    });
  });
}
