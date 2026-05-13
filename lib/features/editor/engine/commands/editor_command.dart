import '../core/editor_document.dart';

/// A command mutates an [EditorDocument] and can be undone.
///
/// Commands MUST be pure functions of `(document) -> document`. They never
/// reach into providers or UI. The undo stack stores commands, not diffs,
/// which keeps history self-describing and serializable later.
abstract class EditorCommand {
  const EditorCommand();

  /// Human-readable label, useful for debugging / future history UI.
  String get label;

  EditorDocument apply(EditorDocument document);

  EditorCommand invert(EditorDocument documentBeforeApply);

  /// Optionally fold this command's effect into [previous] so a stream
  /// of fast successive edits (e.g. dragging a slider) collapses into
  /// a single undo entry whose inverse still restores the pre-stream
  /// state.
  ///
  /// Return `null` (the default) to opt out — the new command becomes
  /// its own history entry. Return a replacement command to use as the
  /// merged "forward" of the existing top-of-stack entry; its inverse
  /// is left untouched, so undo jumps back to the state from before
  /// [previous] was first executed.
  ///
  /// Implementations should only merge with the IMMEDIATELY-previous
  /// entry and only when it targets the same layer + the same set of
  /// fields, to avoid silently swallowing unrelated edits.
  EditorCommand? mergeWith(EditorCommand previous) => null;

  /// Approximate retained-memory cost of this command, in bytes. Read
  /// by [HistoryStack] to enforce a soft byte budget on top of the
  /// count cap; an overestimate is fine, an underestimate risks the
  /// silent-OOM scenario the budget exists to prevent.
  ///
  /// Default `0`. Override on commands that hold a full layer copy, a
  /// pixel buffer, a long stroke-point list, or any other payload
  /// that scales with user content. Scalar/enum-only commands can
  /// keep the default — the per-entry structural overhead is added
  /// once by `HistoryStack` itself.
  ///
  /// Must be O(1) (or close to it) — read on every push and on every
  /// undo/redo to keep the running total honest. Layer-bearing
  /// commands typically delegate to [EditorLayer.estimatedByteSize].
  int get estimatedByteSize => 0;
}
