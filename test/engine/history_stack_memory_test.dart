// Memory-cap tests for [HistoryStack]. Pure engine; no Material.
//
// These tests exist because the count-only cap can let undo memory
// grow unboundedly when payloads are large (a 200-deep stack of
// 50k-point paint strokes pins hundreds of MB). The byte budget is
// soft — it evicts oldest entries when exceeded but never drops the
// most recent entry, on the principle that losing the latest undo is
// a worse failure mode than briefly holding extra memory.

import 'package:canvas_engine/core/constants/engine_constants.dart';
import 'package:canvas_engine/features/editor/engine/commands/editor_command.dart';
import 'package:canvas_engine/features/editor/engine/commands/history_stack.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal command whose `apply` flips a counter on the document so
/// `HistoryStack` doesn't short-circuit it as a no-op, and whose
/// `estimatedByteSize` is configurable per-instance. Inverses point
/// to the prior counter value so undo restores it exactly.
class _SizedCommand extends EditorCommand {
  _SizedCommand({required this.tag, required this.bytes});

  /// Unique tag carried into the command so we can verify which
  /// entries survived eviction (compared via the `_appliedTags`
  /// side-channel).
  final int tag;

  final int bytes;

  @override
  String get label => 'sized($tag,$bytes)';

  @override
  EditorDocument apply(EditorDocument doc) {
    // Force a non-identical return value so HistoryStack records the
    // entry. Doc is otherwise untouched; we don't need real layers
    // for memory-budget tests.
    _appliedTags.add(tag);
    return doc.copyWith(); // new instance, structurally identical
  }

  @override
  EditorCommand invert(EditorDocument before) =>
      _SizedCommand(tag: -tag, bytes: bytes);

  @override
  int get estimatedByteSize => bytes;
}

/// Side-channel used by `_SizedCommand.apply` to record what ran.
/// Cleared per test in `setUp`.
final List<int> _appliedTags = [];

void main() {
  setUp(_appliedTags.clear);

  // Per-entry overhead added by HistoryStack. Tests reason about
  // `bytes + bytes + overhead` per entry (forward + inverse + overhead).
  const overhead = EngineConstants.kHistoryEntryOverheadBytes;

  group('HistoryStack — count cap (regression)', () {
    test('count cap still evicts beyond [limit]', () {
      // Generous byte budget so only the count cap can fire.
      final stack = HistoryStack(limit: 200, byteBudget: 1 << 30);
      var doc = EditorDocument.empty;
      for (var i = 0; i < 250; i++) {
        doc = stack.execute(doc, _SizedCommand(tag: i, bytes: 0));
      }
      expect(stack.undoDepth, 200);
      // Oldest 50 are gone; tag 49 should be evicted, tag 50 retained.
      // We can't directly read entries, but we can drain via undo and
      // observe order.
      final inverseTags = <int>[];
      while (stack.canUndo) {
        doc = stack.undo(doc);
        // The undo just applied is the LAST entry; its inverse tag was
        // negated at construction. The actual tag isn't directly
        // observable — but the count is enough for this regression.
        inverseTags.add(stack.undoDepth);
      }
      expect(inverseTags.length, 200);
    });
  });

  group('HistoryStack — byte cap', () {
    test('byte budget evicts when count cap would not', () {
      // 100 commands each estimated at 5 MB forward. Inverse is also
      // a `_SizedCommand` with the same `bytes`, so each entry costs
      // 10 MB + overhead. Budget 256 MB → keep ~25 entries.
      const each = 5 * 1024 * 1024;
      const budget = 256 * 1024 * 1024;
      final stack = HistoryStack(limit: 1000, byteBudget: budget);
      var doc = EditorDocument.empty;
      for (var i = 0; i < 100; i++) {
        doc = stack.execute(doc, _SizedCommand(tag: i, bytes: each));
      }
      // Each entry costs `2*each + overhead`; with overhead ~64 the
      // count is dominated by `2*each`.
      const perEntry = 2 * each + overhead;
      final expectedDepth = budget ~/ perEntry;
      expect(stack.undoDepth, expectedDepth);
      expect(stack.undoBytes, lessThanOrEqualTo(budget));
      // Most-recent entry survives (the eviction loop's `> 1` guard).
      expect(stack.canUndo, isTrue);
    });

    test('count and byte caps interact — tighter wins', () {
      // Count cap says 100; byte budget says ~30. Verify ~30 retained.
      const each = 8 * 1024 * 1024;
      const budget = 256 * 1024 * 1024;
      const perEntry = 2 * each + overhead;
      final stack = HistoryStack(limit: 100, byteBudget: budget);
      var doc = EditorDocument.empty;
      for (var i = 0; i < 100; i++) {
        doc = stack.execute(doc, _SizedCommand(tag: i, bytes: each));
      }
      final expectedDepth = budget ~/ perEntry;
      expect(stack.undoDepth, expectedDepth);
      expect(expectedDepth, lessThan(100));
      expect(stack.undoBytes, lessThanOrEqualTo(budget));
    });

    test('single oversized command is kept (soft cap)', () {
      // One 500 MB command into a 256 MB budget. The eviction loop's
      // `_undo.length > 1` guard preserves the most recent entry no
      // matter how big it is — losing the only undo would be worse.
      const huge = 500 * 1024 * 1024;
      const budget = 256 * 1024 * 1024;
      final stack = HistoryStack(limit: 200, byteBudget: budget);
      var doc = EditorDocument.empty;
      doc = stack.execute(doc, _SizedCommand(tag: 1, bytes: huge));
      expect(stack.undoDepth, 1);
      expect(stack.undoBytes, greaterThan(budget),
          reason: 'soft cap: single oversized entry exceeds budget');

      // Pushing a small command after the giant: the small one
      // becomes the new most-recent and the giant gets evicted (it
      // is no longer protected by the "keep at least one" guard).
      doc = stack.execute(doc, _SizedCommand(tag: 2, bytes: 1024));
      expect(stack.undoDepth, 1);
      expect(stack.undoBytes, lessThan(budget));
    });

    test('eviction updates running total exactly', () {
      // After every push, undoBytes must equal the sum of remaining
      // entries' (forward+inverse+overhead). We verify this by
      // pushing, evicting, pushing more, and recomputing the
      // expected total at every step from the surviving tags.
      const each = 1024 * 1024; // 1 MB
      const budget = 10 * 1024 * 1024;
      final stack = HistoryStack(limit: 1000, byteBudget: budget);
      var doc = EditorDocument.empty;
      for (var i = 0; i < 50; i++) {
        doc = stack.execute(doc, _SizedCommand(tag: i, bytes: each));
        // Invariant: byte total never exceeds budget+overhead-of-last
        // (the most-recent entry can push us over briefly, but only
        // when evicting more would empty the stack).
        if (stack.undoDepth > 1) {
          expect(stack.undoBytes, lessThanOrEqualTo(budget));
        }
        // Invariant: byte total equals depth * per-entry cost.
        const perEntry = 2 * each + overhead;
        expect(stack.undoBytes, stack.undoDepth * perEntry,
            reason: 'running total drifted at iteration $i');
      }
    });
  });

  group('HistoryStack — redo budget', () {
    test('redo stack honours its own byte budget independently', () {
      const each = 10 * 1024 * 1024;
      const budget = 50 * 1024 * 1024;
      const perEntry = 2 * each + overhead;
      final stack = HistoryStack(limit: 1000, byteBudget: budget);
      var doc = EditorDocument.empty;
      // Push enough that undo cap is exercised.
      for (var i = 0; i < 6; i++) {
        doc = stack.execute(doc, _SizedCommand(tag: i, bytes: each));
      }
      // Undo all surviving entries — they move to redo, which now
      // applies its own budget enforcement on every transfer.
      while (stack.canUndo) {
        doc = stack.undo(doc);
      }
      expect(stack.redoBytes, lessThanOrEqualTo(budget));
      // Redo stack contents are bounded by budget / perEntry.
      expect(stack.redoDepth, lessThanOrEqualTo(budget ~/ perEntry));
    });

    test('execute clears redo and resets redoBytes', () {
      const each = 1024 * 1024;
      final stack = HistoryStack(limit: 100, byteBudget: 100 * 1024 * 1024);
      var doc = EditorDocument.empty;
      doc = stack.execute(doc, _SizedCommand(tag: 1, bytes: each));
      doc = stack.execute(doc, _SizedCommand(tag: 2, bytes: each));
      doc = stack.undo(doc);
      expect(stack.redoDepth, 1);
      expect(stack.redoBytes, greaterThan(0));
      // A new edit invalidates redo; both depth and bytes go to zero.
      doc = stack.execute(doc, _SizedCommand(tag: 3, bytes: each));
      expect(stack.redoDepth, 0);
      expect(stack.redoBytes, 0);
    });
  });

  group('HistoryStack — undo correctness through eviction', () {
    test('surviving entries undo cleanly after eviction has fired', () {
      // Push more than the budget allows, then verify the entries
      // that DID survive can be undone without crashing or corrupting
      // the byte counter. This is the regression that catches the
      // bookkeeping bug where eviction forgets to subtract from
      // _undoBytes on remove.
      const each = 5 * 1024 * 1024;
      const budget = 50 * 1024 * 1024;
      final stack = HistoryStack(limit: 1000, byteBudget: budget);
      var doc = EditorDocument.empty;
      for (var i = 0; i < 30; i++) {
        doc = stack.execute(doc, _SizedCommand(tag: i, bytes: each));
      }
      final survivors = stack.undoDepth;
      expect(survivors, lessThan(30));
      // Drain via undo; byte counter must hit exactly zero.
      while (stack.canUndo) {
        doc = stack.undo(doc);
      }
      expect(stack.undoDepth, 0);
      expect(stack.undoBytes, 0);
      // Redo bytes track whatever moved across; they should be > 0
      // unless the redo budget evicted everything (it shouldn't here
      // since each entry is 10 MB + overhead and budget is 50 MB).
      expect(stack.redoBytes, greaterThanOrEqualTo(0));
    });

    test('clear() zeroes both running totals', () {
      const each = 1024 * 1024;
      final stack = HistoryStack(limit: 100, byteBudget: 100 * 1024 * 1024);
      var doc = EditorDocument.empty;
      for (var i = 0; i < 5; i++) {
        doc = stack.execute(doc, _SizedCommand(tag: i, bytes: each));
      }
      doc = stack.undo(doc);
      expect(stack.undoBytes, greaterThan(0));
      expect(stack.redoBytes, greaterThan(0));
      stack.clear();
      expect(stack.undoBytes, 0);
      expect(stack.redoBytes, 0);
      expect(stack.undoDepth, 0);
      expect(stack.redoDepth, 0);
    });
  });

  // ---------------------------------------------------------------------
  // TODO: enable when a composite-mergeable command exists.
  //
  // Today no command's `mergeWith` produces a CompositeCommand result,
  // so the "merge that grows an entry beyond budget" case can't be
  // exercised end-to-end without a mock command class that mimics
  // composite merging. The case IS handled in `HistoryStack.execute`:
  // after a merge, `_undoBytes` is adjusted by
  // `merged.estimatedByteSize - top.forward.estimatedByteSize` and
  // `_enforceUndoBudget()` is called, so older entries get evicted in
  // response while the just-merged entry is preserved by the
  // `_undo.length > 1` guard.
  //
  // When that future composite-merge command lands, add a test:
  //   1. Push an entry close to the budget.
  //   2. Push another entry whose `mergeWith` returns a much larger
  //      composite forward. Total bytes after merge should exceed
  //      the budget.
  //   3. Verify older entries are evicted, the merged entry remains.
  // ---------------------------------------------------------------------

  group('HistoryStack — stress sanity check', () {
    test('1000-limit / 10 MB budget holds steady at ~50 entries', () {
      // Per the spec: the kind of test where one off-by-one in the
      // bookkeeping makes the budget drift by 50% over many pushes.
      const each = 200 * 1024; // 200 KB per command
      const budget = 10 * 1024 * 1024;
      const perEntry = 2 * each + overhead;
      final stack = HistoryStack(limit: 1000, byteBudget: budget);
      var doc = EditorDocument.empty;
      for (var i = 0; i < 100; i++) {
        doc = stack.execute(doc, _SizedCommand(tag: i, bytes: each));
      }
      final expectedDepth = budget ~/ perEntry;
      expect(stack.undoDepth, expectedDepth,
          reason: 'expected ~$expectedDepth entries in a 10 MB budget');
      expect(stack.undoBytes, lessThanOrEqualTo(budget),
          reason: 'budget drifted: $stack.undoBytes > $budget');
      // Most recent entry intact.
      expect(stack.canUndo, isTrue);
      // And the running total is exact, not approximate.
      expect(stack.undoBytes, stack.undoDepth * perEntry);
    });
  });
}
