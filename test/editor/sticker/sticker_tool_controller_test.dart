import 'package:canvas_engine/features/editor/sticker/application/sticker_tool_controller.dart';
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
  // this file keeps only the sticker-specific pins.

  group('StickerToolController', () {
    test('sticker opts out of sibling-swipe: prev/next are no-ops', () {
      final c = makeContainer();
      final ctrl = c.read(stickerToolControllerProvider.notifier);
      ctrl.toggleSlot(StickerToolSlot.style);
      ctrl.openNextSlot();
      ctrl.openPrevSlot();
      expect(
        c.read(stickerToolControllerProvider).openSlot,
        StickerToolSlot.style,
        reason: 'no swipe strategy is wired for the sticker dock',
      );
    });
  });

  group('StickerToolSlot.tryByName', () {
    test('returns the matching slot for a known name', () {
      expect(StickerToolSlot.tryByName('style'), StickerToolSlot.style);
      expect(StickerToolSlot.tryByName('size'), StickerToolSlot.size);
      expect(StickerToolSlot.tryByName('replace'), StickerToolSlot.replace);
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
