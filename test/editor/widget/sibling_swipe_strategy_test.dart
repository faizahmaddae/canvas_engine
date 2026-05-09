import 'package:canvas_engine/features/editor/toolbar/domain/sibling_swipe_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SiblingSwipeStrategy.next/prev', () {
    test('walks forward and wraps around', () {
      const s = SiblingSwipeStrategy<String>(order: ['a', 'b', 'c']);
      expect(s.next('a'), 'b');
      expect(s.next('b'), 'c');
      expect(s.next('c'), 'a');
    });

    test('walks backward and wraps around', () {
      const s = SiblingSwipeStrategy<String>(order: ['a', 'b', 'c']);
      expect(s.prev('a'), 'c');
      expect(s.prev('b'), 'a');
      expect(s.prev('c'), 'b');
    });

    test('returns null when current is null', () {
      const s = SiblingSwipeStrategy<String>(order: ['a', 'b']);
      expect(s.next(null), isNull);
      expect(s.prev(null), isNull);
    });

    test('returns null when current is not in order (legacy id)', () {
      const s = SiblingSwipeStrategy<String>(order: ['a', 'b']);
      expect(s.next('z'), isNull);
      expect(s.prev('z'), isNull);
    });

    test('returns null when order is empty', () {
      const s = SiblingSwipeStrategy<String>(order: <String>[]);
      expect(s.next('a'), isNull);
    });

    test('single-slot list: swipe is a no-op (no fake same-slot jump)',
        () {
      const s = SiblingSwipeStrategy<String>(order: ['only']);
      expect(s.next('only'), isNull);
      expect(s.prev('only'), isNull);
    });

    test('skips excluded slots when walking', () {
      const s = SiblingSwipeStrategy<String>(
        order: ['a', 'b', 'c', 'd'],
        excluded: {'b', 'c'},
      );
      expect(s.next('a'), 'd');
      expect(s.prev('a'), 'd');
      expect(s.next('d'), 'a');
    });
  });
}
