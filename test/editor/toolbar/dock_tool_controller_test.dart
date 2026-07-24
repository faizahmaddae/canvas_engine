import 'package:canvas_engine/features/editor/toolbar/application/dock_tool_controller.dart';
import 'package:canvas_engine/features/editor/toolbar/domain/sibling_swipe_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the GENERIC dock-slot semantics once (tb1 1.10). The
/// image/shape/sticker providers are all instances of
/// [DockToolController], so the open/toggle/close contract is
/// asserted here against a neutral enum instead of being
/// triplicated across the three per-mode test files — those keep
/// only their mode-specific pins (swipe orders, tryByName, opt-out).
enum _TestSlot { a, b, c }

final _withSwipe =
    NotifierProvider<DockToolController<_TestSlot>, DockToolSession<_TestSlot>>(
      () => DockToolController<_TestSlot>(
        swipe: const SiblingSwipeStrategy<_TestSlot>(
          order: [_TestSlot.a, _TestSlot.b, _TestSlot.c],
        ),
      ),
    );

final _noSwipe =
    NotifierProvider<DockToolController<_TestSlot>, DockToolSession<_TestSlot>>(
      DockToolController<_TestSlot>.new,
    );

void main() {
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  group('DockToolController', () {
    test('initial openSlot is null', () {
      final c = makeContainer();
      expect(c.read(_withSwipe).openSlot, isNull);
    });

    test('toggleSlot opens then closes the same slot', () {
      final c = makeContainer();
      final ctrl = c.read(_withSwipe.notifier);
      ctrl.toggleSlot(_TestSlot.a);
      expect(c.read(_withSwipe).openSlot, _TestSlot.a);
      ctrl.toggleSlot(_TestSlot.a);
      expect(c.read(_withSwipe).openSlot, isNull);
    });

    test('toggling a different slot switches it', () {
      final c = makeContainer();
      final ctrl = c.read(_withSwipe.notifier);
      ctrl.toggleSlot(_TestSlot.a);
      ctrl.toggleSlot(_TestSlot.b);
      expect(c.read(_withSwipe).openSlot, _TestSlot.b);
    });

    test('closePanel clears the open slot and is idempotent', () {
      final c = makeContainer();
      final ctrl = c.read(_withSwipe.notifier);
      ctrl.toggleSlot(_TestSlot.a);
      ctrl.closePanel();
      expect(c.read(_withSwipe).openSlot, isNull);
      ctrl.closePanel();
      expect(c.read(_withSwipe).openSlot, isNull);
    });

    test('openNextSlot/openPrevSlot walk the strategy order and wrap', () {
      final c = makeContainer();
      final ctrl = c.read(_withSwipe.notifier);
      ctrl.toggleSlot(_TestSlot.a);
      ctrl.openNextSlot();
      expect(c.read(_withSwipe).openSlot, _TestSlot.b);
      ctrl.openNextSlot();
      expect(c.read(_withSwipe).openSlot, _TestSlot.c);
      ctrl.openNextSlot();
      expect(
        c.read(_withSwipe).openSlot,
        _TestSlot.a,
        reason: 'wraps from last back to first',
      );
      ctrl.openPrevSlot();
      expect(
        c.read(_withSwipe).openSlot,
        _TestSlot.c,
        reason: 'wraps from first back to last',
      );
    });

    test('open{Prev,Next}Slot is a no-op when no panel is open', () {
      final c = makeContainer();
      final ctrl = c.read(_withSwipe.notifier);
      ctrl.openNextSlot();
      ctrl.openPrevSlot();
      expect(c.read(_withSwipe).openSlot, isNull);
    });

    test('open{Prev,Next}Slot is a no-op without a swipe strategy', () {
      final c = makeContainer();
      final ctrl = c.read(_noSwipe.notifier);
      ctrl.toggleSlot(_TestSlot.b);
      ctrl.openNextSlot();
      ctrl.openPrevSlot();
      expect(
        c.read(_noSwipe).openSlot,
        _TestSlot.b,
        reason: 'no-strategy mode (sticker) opts out of swipe',
      );
    });
  });
}
