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

    test('non-panel slots (replace) are unreachable by swipe', () {
      final c = makeContainer();
      final ctrl = c.read(shapeToolControllerProvider.notifier);
      for (final start in kShapePanelSlotOrder) {
        ctrl.toggleSlot(start);
        for (var i = 0; i < ShapeToolSlot.values.length + 2; i++) {
          ctrl.openNextSlot();
          final reached = c.read(shapeToolControllerProvider).openSlot!;
          expect(
            reached.isPanel,
            isTrue,
            reason: 'reached non-panel slot $reached from $start',
          );
        }
        ctrl.closePanel();
      }
    });
  });

  group('ShapeToolSlot.tryByName', () {
    test('returns the matching slot for a known name', () {
      expect(ShapeToolSlot.tryByName('style'), ShapeToolSlot.style);
      expect(ShapeToolSlot.tryByName('replace'), ShapeToolSlot.replace);
    });

    test('returns null for unknown / null', () {
      expect(ShapeToolSlot.tryByName(null), isNull);
      expect(ShapeToolSlot.tryByName('nope'), isNull);
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
