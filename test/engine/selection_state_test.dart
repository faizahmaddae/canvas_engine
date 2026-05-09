import 'package:canvas_engine/features/editor/engine/core/selection_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Foundation tests for multi-layer selection.
///
/// The data model now supports an insertion-ordered set of layer ids
/// with a *primary* (most-recently-added). The previous single-
/// selection API surface is preserved for backwards compatibility:
/// every existing call site that reads `selectedId` keeps working
/// because it returns the primary id.
void main() {
  group('SelectionState — single-selection back-compat', () {
    test('empty has no selection', () {
      expect(SelectionState.empty.hasSelection, isFalse);
      expect(SelectionState.empty.selectedId, isNull);
      expect(SelectionState.empty.count, 0);
    });

    test('select(id) replaces the entire selection with one id', () {
      final s = SelectionState.empty.select('a').select('b');
      expect(s.selectedId, 'b');
      expect(s.count, 1);
      expect(s.contains('a'), isFalse);
      expect(s.contains('b'), isTrue);
    });

    test('clear() removes the selection', () {
      final s = SelectionState.empty.select('a').clear();
      expect(s.hasSelection, isFalse);
      expect(s, SelectionState.empty);
    });

    test('legacy SelectionState(selectedId: id) constructor still works', () {
      final s = SelectionState(selectedId: 'x');
      expect(s.selectedId, 'x');
      expect(s.count, 1);
    });
  });

  group('SelectionState — multi-selection foundation', () {
    test('add(id) adds and makes id primary', () {
      final s = SelectionState.empty.add('a').add('b');
      expect(s.selectedIds, ['a', 'b']);
      expect(s.selectedId, 'b', reason: 'primary = most-recently-added');
      expect(s.count, 2);
    });

    test('add(existing) promotes to primary without duplicating', () {
      final s = SelectionState.empty.add('a').add('b').add('a');
      expect(s.selectedIds, ['b', 'a']);
      expect(s.selectedId, 'a');
      expect(s.count, 2);
    });

    test('remove(id) preserves remaining order; primary falls back', () {
      final s = SelectionState.empty.add('a').add('b').add('c').remove('c');
      expect(s.selectedIds, ['a', 'b']);
      expect(s.selectedId, 'b',
          reason: 'after removing primary, previous id becomes primary');
    });

    test('remove(missing) is a no-op (returns same state)', () {
      final s = SelectionState.empty.add('a');
      expect(identical(s.remove('z'), s), isTrue);
    });

    test('toggle adds when missing, removes when present', () {
      final s = SelectionState.empty.toggle('a').toggle('b').toggle('a');
      expect(s.selectedIds, ['b']);
      expect(s.selectedId, 'b');
    });

    test('replaceWith deduplicates and preserves order', () {
      final s = SelectionState.empty.replaceWith(['a', 'b', 'a', 'c', 'b']);
      expect(s.selectedIds, ['a', 'b', 'c']);
      expect(s.selectedId, 'c');
    });

    test('selectedIds is unmodifiable', () {
      final s = SelectionState.empty.add('a').add('b');
      expect(() => s.selectedIds.add('c'), throwsUnsupportedError);
    });

    test('equality is order-sensitive', () {
      final ab = SelectionState.empty.add('a').add('b');
      final ba = SelectionState.empty.add('b').add('a');
      expect(ab, isNot(equals(ba)),
          reason: 'order encodes the primary, so [a,b] != [b,a]');
      final ab2 = SelectionState.empty.add('a').add('b');
      expect(ab, equals(ab2));
      expect(ab.hashCode, ab2.hashCode);
    });
  });
}
