import 'package:canvas_engine/features/editor/image/application/image_tool_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  group('ImageToolController', () {
    test('initial openSlot is null', () {
      final c = makeContainer();
      expect(c.read(imageToolControllerProvider).openSlot, isNull);
    });

    test('toggleSlot opens then closes the same slot', () {
      final c = makeContainer();
      final ctrl = c.read(imageToolControllerProvider.notifier);
      ctrl.toggleSlot(ImageToolSlot.style);
      expect(c.read(imageToolControllerProvider).openSlot,
          ImageToolSlot.style);
      ctrl.toggleSlot(ImageToolSlot.style);
      expect(c.read(imageToolControllerProvider).openSlot, isNull);
    });

    test('toggling a different slot switches it', () {
      final c = makeContainer();
      final ctrl = c.read(imageToolControllerProvider.notifier);
      ctrl.toggleSlot(ImageToolSlot.style);
      ctrl.toggleSlot(ImageToolSlot.border);
      expect(c.read(imageToolControllerProvider).openSlot,
          ImageToolSlot.border);
    });

    test('closePanel clears the open slot', () {
      final c = makeContainer();
      final ctrl = c.read(imageToolControllerProvider.notifier);
      ctrl.toggleSlot(ImageToolSlot.style);
      ctrl.closePanel();
      expect(c.read(imageToolControllerProvider).openSlot, isNull);
    });
  });

  group('ImageToolController sibling navigation', () {
    test('openNextSlot walks the panel order and wraps', () {
      final c = makeContainer();
      final ctrl = c.read(imageToolControllerProvider.notifier);
      ctrl.toggleSlot(kImagePanelSlotOrder.first);
      for (var i = 1; i < kImagePanelSlotOrder.length; i++) {
        ctrl.openNextSlot();
        expect(c.read(imageToolControllerProvider).openSlot,
            kImagePanelSlotOrder[i]);
      }
      ctrl.openNextSlot();
      expect(c.read(imageToolControllerProvider).openSlot,
          kImagePanelSlotOrder.first,
          reason: 'wraps from last back to first');
    });

    test('openPrevSlot wraps from first back to last', () {
      final c = makeContainer();
      final ctrl = c.read(imageToolControllerProvider.notifier);
      ctrl.toggleSlot(kImagePanelSlotOrder.first);
      ctrl.openPrevSlot();
      expect(c.read(imageToolControllerProvider).openSlot,
          kImagePanelSlotOrder.last);
    });

    test('open{Prev,Next}Slot is a no-op when no panel is open', () {
      final c = makeContainer();
      final ctrl = c.read(imageToolControllerProvider.notifier);
      ctrl.openNextSlot();
      ctrl.openPrevSlot();
      expect(c.read(imageToolControllerProvider).openSlot, isNull);
    });

    test('non-panel slots (crop, replace) are unreachable by swipe', () {
      // Open every panel slot in turn and assert that walking next
      // never lands on a non-panel slot. This is the typed
      // counterpart of the old drift test against string ids.
      final c = makeContainer();
      final ctrl = c.read(imageToolControllerProvider.notifier);
      for (final start in kImagePanelSlotOrder) {
        ctrl.toggleSlot(start);
        for (var i = 0; i < ImageToolSlot.values.length + 2; i++) {
          ctrl.openNextSlot();
          final reached = c.read(imageToolControllerProvider).openSlot!;
          expect(reached.isPanel, isTrue,
              reason: 'reached non-panel slot $reached from $start');
        }
        ctrl.closePanel();
      }
    });
  });

  group('ImageToolSlot.tryByName', () {
    test('returns the matching slot for a known name', () {
      expect(ImageToolSlot.tryByName('style'), ImageToolSlot.style);
      expect(ImageToolSlot.tryByName('crop'), ImageToolSlot.crop);
    });

    test('returns null for unknown / null', () {
      expect(ImageToolSlot.tryByName(null), isNull);
      expect(ImageToolSlot.tryByName('totally-unknown'), isNull);
      expect(ImageToolSlot.tryByName(''), isNull);
    });
  });
}
