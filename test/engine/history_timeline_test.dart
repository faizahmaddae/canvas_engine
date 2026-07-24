// The read-only timeline projection the history browser renders
// (tb5 follow-up). Pure engine — no Flutter, no l10n.

import 'package:canvas_engine/features/editor/engine/commands/editor_command.dart';
import 'package:canvas_engine/features/editor/engine/commands/history_stack.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:flutter_test/flutter_test.dart';

/// A trivial command that appends a tagged marker layer id so each
/// step is a real, distinct document mutation with a stable label.
class _Tag extends EditorCommand {
  const _Tag(this.tag);
  final String tag;

  @override
  String get label => tag;

  @override
  EditorDocument apply(EditorDocument doc) =>
      doc.copyWith(basePhotoLayerId: tag);

  @override
  EditorCommand invert(EditorDocument before) =>
      _Tag(before.basePhotoLayerId ?? 'start');
}

void main() {
  final doc0 = EditorDocument.empty;

  test('empty stack: timeline is empty and current is -1', () {
    final h = HistoryStack();
    expect(h.timeline, isEmpty);
    expect(h.currentIndex, -1);
  });

  test('all-applied: timeline is chronological, current is the last', () {
    final h = HistoryStack();
    var d = doc0;
    d = h.execute(d, const _Tag('a'));
    d = h.execute(d, const _Tag('b'));
    d = h.execute(d, const _Tag('c'));

    expect(h.timeline.map((e) => e.label), ['a', 'b', 'c']);
    expect(h.timeline.map((e) => e.done), [true, true, true]);
    expect(h.currentIndex, 2);
  });

  test('after undo: the undone step stays in the timeline, marked undone '
      'and after the current position', () {
    final h = HistoryStack();
    var d = doc0;
    d = h.execute(d, const _Tag('a'));
    d = h.execute(d, const _Tag('b'));
    d = h.execute(d, const _Tag('c'));
    d = h.undo(d); // undo c

    // Timeline still reads a, b, c chronologically — the browser shows
    // the whole line, not a truncated stack.
    expect(h.timeline.map((e) => e.label), ['a', 'b', 'c']);
    expect(h.timeline.map((e) => e.done), [true, true, false]);
    expect(h.currentIndex, 1, reason: 'current is now b');
  });

  test('multiple undos preserve forward chronological order of undone '
      'steps (redo order)', () {
    final h = HistoryStack();
    var d = doc0;
    for (final t in ['a', 'b', 'c', 'd']) {
      d = h.execute(d, _Tag(t));
    }
    d = h.undo(d); // undo d
    d = h.undo(d); // undo c

    // c and d were undone; they must appear in the order redo would
    // re-apply them (c then d), NOT reversed.
    expect(h.timeline.map((e) => e.label), ['a', 'b', 'c', 'd']);
    expect(h.timeline.map((e) => e.done), [true, true, false, false]);
    expect(h.currentIndex, 1);
  });

  test('redo re-applies and the timeline flags flip back', () {
    final h = HistoryStack();
    var d = doc0;
    d = h.execute(d, const _Tag('a'));
    d = h.execute(d, const _Tag('b'));
    d = h.undo(d);
    d = h.redo(d);

    expect(h.timeline.map((e) => e.label), ['a', 'b']);
    expect(h.timeline.map((e) => e.done), [true, true]);
    expect(h.currentIndex, 1);
  });

  test('a new edit after an undo truncates the redo tail', () {
    final h = HistoryStack();
    var d = doc0;
    d = h.execute(d, const _Tag('a'));
    d = h.execute(d, const _Tag('b'));
    d = h.undo(d); // b undone
    d = h.execute(d, const _Tag('c')); // replaces the redo tail

    expect(h.timeline.map((e) => e.label), ['a', 'c']);
    expect(h.timeline.map((e) => e.done), [true, true]);
    expect(h.currentIndex, 1);
  });

  test('reading the timeline does not perturb the grouped-undo merge '
      'window', () {
    // Two mergeable live commands inside the window collapse to one
    // entry; reading `timeline` between them must not change that.
    final clock = _FrozenClock();
    final h = HistoryStack(clock: clock.now);
    var d = doc0;
    d = h.execute(d, const _MergeTag('x', 1));
    // ignore: unused_local_variable
    final peek = h.timeline; // the browser could be open mid-stream
    d = h.execute(d, const _MergeTag('x', 2));

    expect(h.undoDepth, 1, reason: 'still one merged entry');
    expect(h.timeline.single.label, 'x');
  });
}

class _FrozenClock {
  DateTime now() => DateTime(2026, 1, 1);
}

/// A live, mergeable command (same shape the real steppers use).
class _MergeTag extends EditorCommand {
  const _MergeTag(this.tag, this.v);
  final String tag;
  final int v;

  @override
  String get label => tag;

  @override
  EditorDocument apply(EditorDocument doc) =>
      doc.copyWith(basePhotoLayerId: '$tag$v');

  @override
  EditorCommand invert(EditorDocument before) =>
      _Tag(before.basePhotoLayerId ?? 'start');

  @override
  EditorCommand? mergeWith(EditorCommand previous) =>
      previous is _MergeTag && previous.tag == tag ? this : null;
}
