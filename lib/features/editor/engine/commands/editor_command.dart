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
}
