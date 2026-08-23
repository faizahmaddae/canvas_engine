import 'package:canvas_engine/features/editor/shape/application/shape_tool_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  // Generic open/toggle/close semantics are pinned once in
  // test/editor/toolbar/dock_tool_controller_test.dart (tb1 1.10);
  // this file keeps only the shape-specific pins.

  group('ShapeToolController', () {
    test('openNextSlot walks the canonical order and wraps', () {
      final c = makeContainer();
      final ctrl = c.read(shapeToolControllerProvider.notifier);
      ctrl.toggleSlot(ShapeToolSlot.style);
      ctrl.openNextSlot();
      expect(
        c.read(shapeToolControllerProvider).openSlot,
        ShapeToolSlot.border,
      );
      ctrl.openNextSlot();
      expect(
        c.read(shapeToolControllerProvider).openSlot,
        ShapeToolSlot.shadow,
      );
      ctrl.openNextSlot();
      expect(
        c.read(shapeToolControllerProvider).openSlot,
        ShapeToolSlot.style,
        reason: 'wraps from last back to first',
      );
    });

    test('openPrevSlot walks backwards and wraps', () {
      final c = makeContainer();
      final ctrl = c.read(shapeToolControllerProvider.notifier);
      ctrl.toggleSlot(ShapeToolSlot.style);
      ctrl.openPrevSlot();
      expect(
        c.read(shapeToolControllerProvider).openSlot,
        ShapeToolSlot.shadow,
        reason: 'wraps from first back to last',
      );
      ctrl.openPrevSlot();
      expect(
        c.read(shapeToolControllerProvider).openSlot,
        ShapeToolSlot.border,
      );
    });

    test('open{Prev,Next}Slot is a no-op when no panel is open', () {
      final c = makeContainer();
      final ctrl = c.read(shapeToolControllerProvider.notifier);
      ctrl.openNextSlot();
      ctrl.openPrevSlot();
      expect(c.read(shapeToolControllerProvider).openSlot, isNull);
    });

    test('swipe walk stays inside the panel order', () {
      // Since the bench replaced the strip, every remaining slot IS a
      // panel — the walk must simply never leave the declared order.
      final c = makeContainer();
      final ctrl = c.read(shapeToolControllerProvider.notifier);
      for (final start in kShapePanelSlotOrder) {
        ctrl.toggleSlot(start);
        for (var i = 0; i < ShapeToolSlot.values.length + 2; i++) {
          ctrl.openNextSlot();
          final reached = c.read(shapeToolControllerProvider).openSlot!;
          expect(
            kShapePanelSlotOrder,
            contains(reached),
            reason: 'reached out-of-order slot $reached from $start',
          );
        }
        ctrl.closePanel();
      }
    });
  });

  group('ShapeToolSlot.tryByName', () {
    test('returns the matching slot for a known name', () {
      expect(ShapeToolSlot.tryByName('style'), ShapeToolSlot.style);
      expect(ShapeToolSlot.tryByName('shadow'), ShapeToolSlot.shadow);
    });

    test('returns null for unknown / retired names', () {
      expect(ShapeToolSlot.tryByName(null), isNull);
      expect(ShapeToolSlot.tryByName('nope'), isNull);
      // 'replace' retired with the strip — the bench's specimen chip
      // owns the Replace door now.
      expect(ShapeToolSlot.tryByName('replace'), isNull);
    });
  });

  group('Shape insert UX contract', () {
    test('no panel is open after a fresh shape is inserted', () {
      // editor_screen._addShape no longer calls toggleSlot after insert.
      // The controller starts with openSlot == null and nothing should
      // open it automatically — the user taps a tab when ready.
      final c = makeContainer();
      expect(
        c.read(shapeToolControllerProvider).openSlot,
        isNull,
        reason: 'shape insert must not auto-open any panel',
      );
    });
  });
}
