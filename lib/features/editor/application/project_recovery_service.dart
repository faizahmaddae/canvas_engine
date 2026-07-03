import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/serialization/document_codec.dart';
import 'autosave_controller.dart';
import 'edit_journal.dart';

/// Read side of the crash-recovery journal ([EditJournal] is the
/// write side). Two recovery shapes:
///
///   * **Saved project** — a leftover journal for a `projectId`
///     means the app died between the last journal write and the
///     next autosave flush. If the journal's content differs from
///     the persisted document, the open-project flow offers to
///     resume it.
///   * **Draft** — a leftover journal in the reserved
///     [AutosaveController.draftJournalId] slot means a never-saved
///     session crashed. Home offers to resume it on launch.
///
/// All results are JSON strings, not [EditorDocument]s, so the home
/// feature can consume them without importing the engine.
class ProjectRecoveryService {
  const ProjectRecoveryService();

  /// Journal JSON for [projectId] when it differs from
  /// [persistedJson]; null when there is nothing worth offering. A
  /// journal that matches the persisted save byte-for-byte is
  /// redundant (the autosave landed before the crash) and is cleared
  /// here so it cannot re-prompt on every open.
  Future<String?> pendingJsonForProject({
    required String projectId,
    required String persistedJson,
  }) async {
    try {
      final journal = await EditJournal.open(projectId);
      final doc = await journal.recover();
      if (doc == null) return null;
      final json = DocumentCodec.encode(doc);
      if (json == persistedJson) {
        await journal.clear();
        return null;
      }
      return json;
    } catch (_) {
      // Recovery is strictly best-effort: any failure means "no
      // offer", never a blocked open.
      return null;
    }
  }

  /// Journal JSON for a crashed never-saved session, or null.
  Future<String?> pendingDraftJson() async {
    try {
      final journal =
          await EditJournal.open(AutosaveController.draftJournalId);
      final doc = await journal.recover();
      if (doc == null) return null;
      return DocumentCodec.encode(doc);
    } catch (_) {
      return null;
    }
  }

  /// Discard a saved project's pending journal (user chose the
  /// persisted version).
  Future<void> clearForProject(String projectId) async {
    try {
      final journal = await EditJournal.open(projectId);
      await journal.clear();
    } catch (_) {/* best-effort */}
  }

  /// Discard the draft journal (user dismissed the resume offer).
  Future<void> clearDraft() async {
    try {
      final journal =
          await EditJournal.open(AutosaveController.draftJournalId);
      await journal.clear();
    } catch (_) {/* best-effort */}
  }
}

final projectRecoveryServiceProvider = Provider<ProjectRecoveryService>(
  (ref) => const ProjectRecoveryService(),
);
