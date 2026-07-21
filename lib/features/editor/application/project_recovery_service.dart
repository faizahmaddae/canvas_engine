import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/core/editor_document.dart';
import '../engine/serialization/document_codec.dart';
import 'autosave_controller.dart';
import 'edit_journal.dart';
import 'imported_image_path_codec.dart';

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
    required String importedImagesDir,
    required bool Function(String path) fileExists,
  }) async {
    try {
      final journal = await EditJournal.open(projectId);
      final doc = await journal.recover();
      if (doc == null) return null;
      // Compare the journal and the persisted save by what they RESOLVE
      // TO on the current install, not by their stored representation.
      // Each document is first run through the runtime rebasing contract
      // (canonical -> current absolute; a missing legacy absolute whose
      // file now lives under the current imported_images dir -> that
      // current file), then re-encoded to canonical form. Two references
      // that point at the same current file therefore compare equal —
      // including after a container relocation — while unresolved or
      // genuinely different documents do not. Read-only: neither the
      // stored project nor the journal is mutated by the comparison.
      final journalCanonical = _resolvedCanonical(
        doc,
        importedImagesDir,
        fileExists,
      );
      final persistedCanonical = _resolvedCanonicalJson(
        persistedJson,
        importedImagesDir,
        fileExists,
      );
      if (journalCanonical == persistedCanonical) {
        await journal.clear();
        return null;
      }
      return journalCanonical;
    } catch (_) {
      // Recovery is strictly best-effort: any failure means "no
      // offer", never a blocked open.
      return null;
    }
  }

  /// Resolve [doc]'s image references against the current install (the
  /// runtime rebasing contract), then encode to canonical storage form so
  /// two documents that resolve to the same current files compare equal.
  /// Pure — no disk mutation.
  String _resolvedCanonical(
    EditorDocument doc,
    String importedImagesDir,
    bool Function(String path) fileExists,
  ) {
    final resolved = ImportedImagePathCodec.runtimeDocument(
      doc,
      importedImagesDir: importedImagesDir,
      fileExists: fileExists,
    );
    return ImportedImagePathCodec.encodeForStorage(
      resolved,
      importedImagesDir: importedImagesDir,
    );
  }

  /// As [_resolvedCanonical] but from a JSON string. Returns the raw
  /// string when it cannot be decoded, so a malformed payload compares
  /// UNEQUAL (fail toward offering — never a silent "nothing to recover").
  String _resolvedCanonicalJson(
    String json,
    String importedImagesDir,
    bool Function(String path) fileExists,
  ) {
    try {
      return _resolvedCanonical(
        DocumentCodec.decode(json),
        importedImagesDir,
        fileExists,
      );
    } catch (_) {
      return json;
    }
  }

  /// Journal JSON for a crashed never-saved session, or null.
  Future<String?> pendingDraftJson() async {
    try {
      final journal = await EditJournal.open(AutosaveController.draftJournalId);
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
    } catch (_) {
      /* best-effort */
    }
  }

  /// Discard the draft journal (user dismissed the resume offer).
  Future<void> clearDraft() async {
    try {
      final journal = await EditJournal.open(AutosaveController.draftJournalId);
      await journal.clear();
    } catch (_) {
      /* best-effort */
    }
  }
}

final projectRecoveryServiceProvider = Provider<ProjectRecoveryService>(
  (ref) => const ProjectRecoveryService(),
);
