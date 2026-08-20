import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/commands/editor_command.dart';
import '../engine/commands/history_stack.dart';
import '../engine/core/editor_document.dart';
import '../engine/serialization/document_codec.dart';

/// Owns the [EditorDocument] and its undo/redo history.
///
/// Single-responsibility: mutates the document through commands. It knows
/// nothing about selection or gestures – those live in their own
/// controllers to avoid a god provider.
class DocumentController extends Notifier<EditorDocument> {
  final HistoryStack _history = HistoryStack();

  @override
  EditorDocument build() => EditorDocument.empty;

  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;

  /// Read-only history timeline for the browser (oldest → newest).
  /// Pure projection of the stack — reading it never mutates history.
  List<HistoryEntryView> get historyTimeline => _history.timeline;

  /// Index of the current position in [historyTimeline] (`-1` at the
  /// initial state).
  int get historyCurrentIndex => _history.currentIndex;

  void execute(EditorCommand command) {
    final next = _history.execute(state, command);
    if (!identical(next, state)) {
      state = next;
      _bumpCommitVersion();
    }
  }

  void undo() {
    final next = _history.undo(state);
    if (!identical(next, state)) {
      state = next;
      _bumpCommitVersion();
    }
  }

  void redo() {
    final next = _history.redo(state);
    if (!identical(next, state)) {
      state = next;
      _bumpCommitVersion();
    }
  }

  /// Jump the document to position [targetIndex] in [historyTimeline]:
  /// after the call the entry at [targetIndex] is the newest applied
  /// step (`historyCurrentIndex == targetIndex`). `-1` rewinds to the
  /// initial document state. Jumping to an undone entry redoes it
  /// INCLUSIVELY; jumping to an applied entry undoes everything after
  /// it; jumping to the current position does nothing. Never
  /// destructive — a jump is only a replayed run of undo/redo, so the
  /// user can jump straight back.
  ///
  /// Deliberately a loop over the single-step [undo]/[redo] rather
  /// than a new [HistoryStack] operation: each step traverses one
  /// whole history entry, so grouped-undo entries stay grouped, and
  /// redo's merge-window backdating applies to every replayed step
  /// exactly as it would to manual taps.
  ///
  /// The loop trusts the stack, not the requested index: each
  /// iteration must move [historyCurrentIndex] one step toward the
  /// target, and the loop stops the moment a step reports no progress
  /// (empty stack, or byte-budget eviction shifting indices under
  /// us). A jump can therefore stop short, but can never spin or
  /// drift out of sync with the stack.
  void jumpToHistoryIndex(int targetIndex) {
    while (historyCurrentIndex > targetIndex) {
      final before = historyCurrentIndex;
      undo();
      if (historyCurrentIndex >= before) return; // no-op → stop
    }
    while (historyCurrentIndex < targetIndex) {
      final before = historyCurrentIndex;
      redo();
      if (historyCurrentIndex <= before) return; // no-op → stop
    }
  }

  /// Bumps [documentCommitVersionProvider] so listeners (autosave,
  /// dirty-state indicators) can react only to *committed* document
  /// changes — not 60fps previews staged on `liveOverlayProvider`.
  void _bumpCommitVersion() {
    ref.read(documentCommitVersionProvider.notifier).bump();
  }

  /// Discard all undo/redo history while keeping the current document
  /// state. Used by import flows that want the imported asset to be
  /// the project's *initial* state -- pressing Undo immediately
  /// after opening an imported photo must not remove the photo and
  /// leave a blank canvas. The home Import flow calls this after
  /// dispatching the AddLayer + SetBasePhoto composite, effectively
  /// promoting the imported document to a fresh origin.
  void clearHistory() {
    _history.clear();
  }

  /// Replace the current document with a fresh blank one of the given
  /// logical canvas size and discard undo/redo history. Document creation
  /// is not itself undoable -- the user has explicitly chosen "new".
  ///
  /// [kind] selects the project archetype. [ProjectKind.design] (the
  /// default) preserves the historical "blank canvas" UX. Passing
  /// [ProjectKind.photo] is reserved for the gallery-import flow on
  /// the home screen, where the freshly-created document is about to
  /// be seeded with the imported photo as its base photo.
  void newDocument({
    required double width,
    required double height,
    ProjectKind kind = ProjectKind.design,
  }) {
    _history.clear();
    state = EditorDocument(
      layers: const [],
      width: width,
      height: height,
      projectKind: kind,
    );
  }

  /// Serialize the current document to a JSON string. Pure delegation to
  /// [DocumentCodec.encode]; lives here so UI code never needs to import
  /// the engine directly.
  String exportJson() => DocumentCodec.encode(state);

  /// Replace the current document with one decoded from [jsonSource] and
  /// discard undo/redo history. A loaded document is a fresh origin —
  /// the previous editing session's history would no longer make sense.
  /// Throws [DocumentDecodeException] on invalid input; on success,
  /// state updates atomically.
  void importJson(String jsonSource) {
    final next = DocumentCodec.decode(jsonSource);
    _history.clear();
    state = next;
  }

  /// Install an already-decoded [document] as the current editing origin
  /// and discard undo/redo history. Used by load paths that decode a
  /// persisted document through the application-layer path codec (which
  /// resolves imported-image references to absolute runtime paths) before
  /// handing the finished document here — the engine never sees the
  /// persistence transform, and history resets exactly like [importJson].
  void loadDocument(EditorDocument document) {
    _history.clear();
    state = document;
  }
}

final documentControllerProvider =
    NotifierProvider<DocumentController, EditorDocument>(
      DocumentController.new,
    );

/// Monotonically-increasing counter bumped by [DocumentController]
/// after every undoable commit (`execute` / `undo` / `redo`).
///
/// Listeners (autosave, "Saved · Just now" badges, future dirty-state
/// dialogs) should subscribe here instead of [documentControllerProvider]
/// so they ignore mid-gesture live previews routed through
/// [DocumentController.liveReplace].
class DocumentCommitVersionController extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

final documentCommitVersionProvider =
    NotifierProvider<DocumentCommitVersionController, int>(
      DocumentCommitVersionController.new,
    );
