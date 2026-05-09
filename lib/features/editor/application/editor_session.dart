import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lightweight context the editor carries about *what* it's editing.
///
/// Set by the home screen before pushing the editor; consumed by the
/// editor's "Save project" action to decide between insert vs update.
/// Cleared on navigation back to home.
class EditorSession {
  const EditorSession({
    required this.name,
    this.projectId,
  });

  /// Display name shown in the editor app bar / used as the saved
  /// project name.
  final String name;

  /// `null` when the editor is operating on a fresh, never-persisted
  /// document; non-null when the user is continuing an existing
  /// project (so save updates rather than inserts).
  final String? projectId;

  EditorSession copyWith({String? name, String? projectId}) => EditorSession(
        name: name ?? this.name,
        projectId: projectId ?? this.projectId,
      );
}

/// Holds the active [EditorSession]. Null when no editor is open.
class EditorSessionController extends Notifier<EditorSession?> {
  @override
  EditorSession? build() => null;

  // ignore: use_setters_to_change_properties
  @override
  set state(EditorSession? value) => super.state = value;
}

final editorSessionProvider =
    NotifierProvider<EditorSessionController, EditorSession?>(
  EditorSessionController.new,
);
