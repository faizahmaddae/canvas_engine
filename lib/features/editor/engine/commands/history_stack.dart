import '../../../../core/constants/engine_constants.dart';
import '../core/editor_document.dart';
import 'editor_command.dart';

/// Undo/redo stack. Pure data + pure functions – no Flutter dependencies.
class HistoryStack {
  HistoryStack({
    this.limit = 200,
    this.byteBudget = EngineConstants.kHistoryByteBudget,
  });

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
  /// back to the state from before the merge stream began. This makes
  /// slider drags and other rapid streams of micro-edits collapse to
  /// a single undo step without callers having to coordinate.
  EditorDocument execute(EditorDocument document, EditorCommand command) {
    final inverse = command.invert(document);
    final next = command.apply(document);
    if (identical(next, document)) return document; // no-op
    if (_undo.isNotEmpty) {
      final top = _undo.last;
      final merged = command.mergeWith(top.forward);
      if (merged != null) {
        // Merge replaces the forward command in place; the inverse
        // is preserved so undo still rewinds to the pre-stream state.
        // Adjust the running total by the delta between the old and
        // new forward sizes (inverse is unchanged).
        _undoBytes += merged.estimatedByteSize - top.forward.estimatedByteSize;
        _undo[_undo.length - 1] =
            _HistoryEntry(inverse: top.inverse, forward: merged);
        _clearRedoInternal();
        // A merge can grow the entry (e.g. a future composite-merge
        // bundling more children); enforce the budget afterwards.
        _enforceUndoBudget();
        return next;
      }
    }
    final entry = _HistoryEntry(inverse: inverse, forward: command);
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
    final undoEntry = _HistoryEntry(
      inverse: entry.forward.invert(document),
      forward: entry.forward,
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

class _HistoryEntry {
  _HistoryEntry({required this.inverse, required this.forward});
  final EditorCommand inverse;
  final EditorCommand forward;
}
