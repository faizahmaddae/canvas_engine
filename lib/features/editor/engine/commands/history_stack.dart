import '../../../../core/constants/engine_constants.dart';
import '../core/editor_document.dart';
import 'editor_command.dart';

/// Undo/redo stack. Pure data + pure functions – no Flutter dependencies.
class HistoryStack {
  HistoryStack({
    this.limit = 200,
    this.byteBudget = EngineConstants.kHistoryByteBudget,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Injectable time source so the merge-window gate is testable
  /// without real sleeps. Production uses the wall clock.
  final DateTime Function() _clock;

  /// Hard count cap on each stack. Predates the byte cap and continues
  /// to apply — eviction triggers as soon as either the count OR the
  /// byte budget is exceeded.
  final int limit;

  /// Soft byte cap on each stack. The most-recent entry is never
  /// evicted, even if it alone exceeds the budget — losing the latest
  /// undo would be worse than holding onto an oversized command.
  final int byteBudget;

  final List<_HistoryEntry> _undo = [];
  final List<_HistoryEntry> _redo = [];

  // Running totals kept in lock-step with the lists. Every code path
  // that mutates [_undo] or [_redo] must also adjust the matching
  // counter; otherwise the byte cap drifts and eviction either
  // over- or under-fires. The memory tests verify this invariant.
  int _undoBytes = 0;
  int _redoBytes = 0;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get undoDepth => _undo.length;
  int get redoDepth => _redo.length;

  /// Read-only timeline for the history browser, oldest → newest.
  ///
  /// The applied (undo-side) entries first, then the undone (redo-side)
  /// entries in the order redo would re-apply them, so the list reads as
  /// one continuous timeline the current position sits inside rather
  /// than two stacks. Pure projection — building it neither mutates nor
  /// depends on execute/undo/redo, so it cannot perturb the grouped-undo
  /// merge window.
  ///
  /// `_redo` is a stack (its last element is the next redo), so the
  /// forward chronological order of undone steps is `_redo.reversed`.
  List<HistoryEntryView> get timeline => <HistoryEntryView>[
    for (final e in _undo) HistoryEntryView(label: e.forward.label, done: true),
    for (final e in _redo.reversed)
      HistoryEntryView(label: e.forward.label, done: false),
  ];

  /// Index into [timeline] of the current document position — the
  /// newest applied entry. `-1` when nothing has been applied (the
  /// document is at its initial state), which the browser renders as an
  /// explicit "start" row rather than an empty selection.
  int get currentIndex => _undo.length - 1;

  /// Sum of `forward.estimatedByteSize + inverse.estimatedByteSize +
  /// kHistoryEntryOverheadBytes` across every entry currently on the
  /// undo stack. Exposed for diagnostics + tests; do not surface in UI.
  int get undoBytes => _undoBytes;

  /// Same idea, for the redo stack.
  int get redoBytes => _redoBytes;

  /// Apply [command] to [document] and push an inverse entry onto the undo
  /// stack. Clears the redo stack.
  ///
  /// If [command] is mergeable with the top-of-stack entry's forward
  /// command (see [EditorCommand.mergeWith]), the existing entry's
  /// forward is replaced with the merged command instead of pushing a
  /// new entry. The original inverse is preserved so undo still jumps
  /// back to the state from before the merge stream began. Since the
  /// tb2 6/16 merge-gate flip every mergeable command opts in per
  /// instance via a `live` flag, so this window coalesces ONLY the
  /// sanctioned burst streams (steppers/nudges, the canvas-background
  /// exemption) — slider drags commit once structurally through the
  /// overlay preview channels and never rely on it.
  EditorDocument execute(EditorDocument document, EditorCommand command) {
    final inverse = command.invert(document);
    final next = command.apply(document);
    if (identical(next, document)) return document; // no-op
    final now = _clock();
    if (_undo.isNotEmpty) {
      final top = _undo.last;
      // Merge-window gate: a stream only extends an entry that was
      // touched within kLiveMergeWindow. Without it, two drags of the
      // same slider minutes apart collapsed into one undo entry —
      // sliders emit no drag-end settle, and a same-value settle
      // would be swallowed by the no-op guard above anyway.
      // Strictly-less-than so an entry backdated by exactly one
      // window (see [redo]) can never be absorbed.
      final withinWindow =
          now.difference(top.touchedAt) < EngineConstants.kLiveMergeWindow;
      final merged = withinWindow ? command.mergeWith(top.forward) : null;
      if (merged != null) {
        // Merge replaces the forward command in place; the inverse
        // is preserved so undo still rewinds to the pre-stream state.
        // Adjust the running total by the delta between the old and
        // new forward sizes (inverse is unchanged).
        _undoBytes += merged.estimatedByteSize - top.forward.estimatedByteSize;
        _undo[_undo.length - 1] = _HistoryEntry(
          inverse: top.inverse,
          forward: merged,
          touchedAt: now,
        );
        _clearRedoInternal();
        // A merge can grow the entry (e.g. a future composite-merge
        // bundling more children); enforce the budget afterwards.
        _enforceUndoBudget();
        return next;
      }
    }
    final entry = _HistoryEntry(
      inverse: inverse,
      forward: command,
      touchedAt: now,
    );
    _undo.add(entry);
    _undoBytes += _entryBytes(entry);
    _clearRedoInternal();
    _enforceUndoBudget();
    return next;
  }

  EditorDocument undo(EditorDocument document) {
    if (_undo.isEmpty) return document;
    final entry = _undo.removeLast();
    _undoBytes -= _entryBytes(entry);
    final next = entry.inverse.apply(document);
    final redoEntry = _HistoryEntry(
      inverse: entry.inverse.invert(document),
      forward: entry.forward,
      touchedAt: _clock(),
    );
    _redo.add(redoEntry);
    _redoBytes += _entryBytes(redoEntry);
    _enforceRedoBudget();
    return next;
  }

  EditorDocument redo(EditorDocument document) {
    if (_redo.isEmpty) return document;
    final entry = _redo.removeLast();
    _redoBytes -= _entryBytes(entry);
    final next = entry.forward.apply(document);
    // Stamped with the current time, but a redone entry should not
    // silently absorb the next live drag — it represents completed
    // work, not an in-flight stream. Backdating it beyond the merge
    // window closes that hole.
    final undoEntry = _HistoryEntry(
      inverse: entry.forward.invert(document),
      forward: entry.forward,
      touchedAt: _clock().subtract(EngineConstants.kLiveMergeWindow),
    );
    _undo.add(undoEntry);
    _undoBytes += _entryBytes(undoEntry);
    _enforceUndoBudget();
    return next;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
    _undoBytes = 0;
    _redoBytes = 0;
  }

  /// Internal: clear redo and reset its byte counter. Called on every
  /// new push (a forward edit invalidates any pending redo).
  void _clearRedoInternal() {
    _redo.clear();
    _redoBytes = 0;
  }

  /// Evict oldest undo entries until both the count limit and the
  /// byte budget are honoured. Always preserves at least the most
  /// recent entry — a single oversized command is held even if it
  /// alone exceeds [byteBudget], because losing the latest undo would
  /// be a worse failure mode than holding onto extra memory.
  void _enforceUndoBudget() {
    while ((_undo.length > limit || _undoBytes > byteBudget) &&
        _undo.length > 1) {
      final removed = _undo.removeAt(0);
      _undoBytes -= _entryBytes(removed);
    }
  }

  /// Same eviction policy, applied to the redo stack. The redo stack
  /// has no count limit today (the historical implementation never
  /// capped it either), but the byte budget does apply.
  void _enforceRedoBudget() {
    while (_redoBytes > byteBudget && _redo.length > 1) {
      final removed = _redo.removeAt(0);
      _redoBytes -= _entryBytes(removed);
    }
  }

  /// Per-entry retained-bytes estimate: forward + inverse payload
  /// plus a fixed structural overhead so a stream of "no payload"
  /// commands still counts toward the budget.
  static int _entryBytes(_HistoryEntry e) =>
      e.forward.estimatedByteSize +
      e.inverse.estimatedByteSize +
      EngineConstants.kHistoryEntryOverheadBytes;
}

/// One row in the history browser's timeline (see [HistoryStack.timeline]).
///
/// Deliberately carries only what the browser renders — the command's
/// human label and whether it is currently applied — never the command
/// objects themselves, so the UI layer cannot reach in and re-apply or
/// mutate history out of band.
class HistoryEntryView {
  const HistoryEntryView({required this.label, required this.done});

  /// The command's [EditorCommand.label].
  final String label;

  /// `true` for an applied step (at or before the current position),
  /// `false` for an undone step reachable by redo.
  final bool done;
}

class _HistoryEntry {
  _HistoryEntry({
    required this.inverse,
    required this.forward,
    required this.touchedAt,
  });
  final EditorCommand inverse;
  final EditorCommand forward;

  /// When this entry was pushed or last absorbed a merge. Gates the
  /// live-merge window in [HistoryStack.execute].
  final DateTime touchedAt;
}
