import 'package:canvas_engine/features/editor/sticker/application/sticker_tool_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  group('StickerToolController', () {
    test('initial openSlot is null', () {
      final c = makeContainer();
      expect(c.read(stickerToolControllerProvider).openSlot, isNull);
    });

    test('toggleSlot opens then closes the same slot', () {
      final c = makeContainer();
      final ctrl = c.read(stickerToolControllerProvider.notifier);
      ctrl.toggleSlot(StickerToolSlot.size);
      expect(c.read(stickerToolControllerProvider).openSlot,
          StickerToolSlot.size);
      ctrl.toggleSlot(StickerToolSlot.size);
      expect(c.read(stickerToolControllerProvider).openSlot, isNull);
    });

    test('toggling a different slot switches it', () {
      final c = makeContainer();
      final ctrl = c.read(stickerToolControllerProvider.notifier);
      ctrl.toggleSlot(StickerToolSlot.style);
      ctrl.toggleSlot(StickerToolSlot.replace);
      expect(c.read(stickerToolControllerProvider).openSlot,
          StickerToolSlot.replace);
    });

    test('closePanel clears the open slot', () {
      final c = makeContainer();
      final ctrl = c.read(stickerToolControllerProvider.notifier);
      ctrl.toggleSlot(StickerToolSlot.style);
      ctrl.closePanel();
      expect(c.read(stickerToolControllerProvider).openSlot, isNull);
    });

    test('closePanel is a no-op when nothing is open', () {
      final c = makeContainer();
      final ctrl = c.read(stickerToolControllerProvider.notifier);
      ctrl.closePanel();
      expect(c.read(stickerToolControllerProvider).openSlot, isNull);
    });
  });

  group('StickerToolSlot.tryByName', () {
    test('returns the matching slot for a known name', () {
      expect(StickerToolSlot.tryByName('style'), StickerToolSlot.style);
      expect(StickerToolSlot.tryByName('size'), StickerToolSlot.size);
      expect(StickerToolSlot.tryByName('replace'),
          StickerToolSlot.replace);
    });

    test('returns null for unknown / null', () {
      expect(StickerToolSlot.tryByName(null), isNull);
      expect(StickerToolSlot.tryByName('nope'), isNull);
      expect(StickerToolSlot.tryByName(''), isNull);
    });
  });

  test('strip slot order is the full enum', () {
    expect(kStickerStripSlotOrder, StickerToolSlot.values);
  });
}
