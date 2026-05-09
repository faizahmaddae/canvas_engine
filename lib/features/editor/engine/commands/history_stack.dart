import '../core/editor_document.dart';
import 'editor_command.dart';

/// Undo/redo stack. Pure data + pure functions – no Flutter dependencies.
class HistoryStack {
  HistoryStack({this.limit = 200});

  final int limit;
  final List<_HistoryEntry> _undo = [];
  final List<_HistoryEntry> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get undoDepth => _undo.length;
  int get redoDepth => _redo.length;

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
        _undo[_undo.length - 1] =
            _HistoryEntry(inverse: top.inverse, forward: merged);
        _redo.clear();
        return next;
      }
    }
    _undo.add(_HistoryEntry(inverse: inverse, forward: command));
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
    return next;
  }

  EditorDocument undo(EditorDocument document) {
    if (_undo.isEmpty) return document;
    final entry = _undo.removeLast();
    final next = entry.inverse.apply(document);
    _redo.add(_HistoryEntry(
      inverse: entry.inverse.invert(document),
      forward: entry.forward,
    ));
    return next;
  }

  EditorDocument redo(EditorDocument document) {
    if (_redo.isEmpty) return document;
    final entry = _redo.removeLast();
    final next = entry.forward.apply(document);
    _undo.add(_HistoryEntry(
      inverse: entry.forward.invert(document),
      forward: entry.forward,
    ));
    return next;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}

class _HistoryEntry {
  _HistoryEntry({required this.inverse, required this.forward});
  final EditorCommand inverse;
  final EditorCommand forward;
}
