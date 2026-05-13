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

  /// Bumps [documentCommitVersionProvider] so listeners (autosave,
  /// dirty-state indicators) can react only to *committed* document
  /// changes — not 60fps live drag previews routed through
  /// [liveReplace].
  void _bumpCommitVersion() {
    ref.read(documentCommitVersionProvider.notifier).bump();
  }

  /// Replace the current document state without pushing onto the undo
  /// stack. Used historically for transient previews (live drag, live
  /// text editing) where the final committed state was pushed via
  /// [execute] on commit.
  ///
  /// **Deprecated.** Replaced by `liveOverlayProvider` — every
  /// in-flight UI change now stages onto an in-memory overlay and the
  /// canvas reads the merged view via `renderedDocumentProvider`.
  /// That keeps the committed document instance stable during
  /// gestures, so non-canvas widgets (layers panel, undo rail,
  /// autosave) stop rebuilding at 60 fps. See
  /// `live_overlay_controller.dart` for migration patterns.
  @Deprecated('Use liveOverlayProvider instead — see live_overlay_controller.dart')
  void liveReplace(EditorDocument document) {
    state = document;
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
