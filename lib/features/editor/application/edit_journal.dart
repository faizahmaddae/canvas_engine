import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../engine/core/editor_document.dart';
import '../engine/serialization/document_codec.dart';
import 'imported_image_path_codec.dart';

/// Crash-recovery journal — a write-ahead log for the active edit.
///
/// ## What it does
///
/// On every committed document mutation the journal writes the new
/// document JSON to a single, project-scoped file at
/// `<docs>/journal/<projectId>.json`. The write is best-effort and
/// fire-and-forget so it never blocks a slider drag; debounced so a
/// burst of edits writes once.
///
/// On editor launch, [recover] reads any leftover journal entry for
/// [projectId]. If one exists *and* its `lastModified` is newer than
/// the persisted [Project.lastModified], the editor is offered the
/// chance to resume that session — the assumption is that a journal
/// newer than the persisted save means the app crashed before the
/// next autosave landed.
///
/// On normal session end (project closed, app paused with autosave
/// flushed), [clear] removes the journal so the next launch reads a
/// clean slate.
///
/// ## What it deliberately does NOT do
///
/// * Not a redo-log of *commands*. Commands compose, but
///   reconstructing intermediate state from a long command stream
///   is fragile — a single non-deterministic command (loading a
///   network image, current timestamp) breaks replay. The journal
///   stores the *post-state* of every commit, which is always the
///   exact JSON the autosave path would have written.
///
/// * Not a backup. A user who manually deletes a project file is
///   not "recovering" — they wanted it gone. The journal is keyed
///   by `projectId` and gets cleared with the project.
///
/// * Not crypto-secure. Journal contents are the same plaintext
///   JSON that's already on disk for the saved project.
class EditJournal {
  EditJournal._({required this.projectId, required this.directory});

  /// The project this journal belongs to. One file per project so
  /// switching projects mid-session never overwrites an in-flight
  /// journal for a different document.
  final String projectId;

  /// Directory holding journal files. Resolved once on [open].
  final Directory directory;

  /// Open or lazily create the journal directory for [projectId].
  /// Returns a journal handle bound to that project's file.
  static Future<EditJournal> open(String projectId) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/journal');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return EditJournal._(projectId: projectId, directory: dir);
  }

  File get _file => File('${directory.path}/$projectId.json');

  /// Sibling imported-images directory (`<docs>/imported_images`),
  /// derived from this journal's `<docs>/journal` directory. The journal
  /// stores the SAME canonical representation as the persisted project so
  /// the recovery byte-compare (`encode(recover()) == persistedJson`)
  /// stays exact.
  String get _importedImagesDir =>
      '${directory.parent.path}/$importedImagesDirName';

  Timer? _writeTimer;

  /// Debounce window for journal writes. Long enough that a slider
  /// drag emits one write at settle, short enough that a foreground
  /// crash during slow editing loses at most this many ms of work.
  static const Duration writeDebounce = Duration(milliseconds: 750);

  /// Schedule a write of [doc]'s JSON to the journal file. Subsequent
  /// calls within [writeDebounce] coalesce onto the single pending
  /// timer, so a burst of edits produces one write.
  ///
  /// Best-effort: the journal failing to write is far less bad than
  /// the alternative of failing the user's edit, so any I/O error
  /// is intentionally swallowed.
  void scheduleWrite(EditorDocument doc) {
    _writeTimer?.cancel();
    _writeTimer = Timer(writeDebounce, () => _writeNow(doc));
  }

  /// Write [doc]'s JSON to the journal file immediately, bypassing
  /// the debounce. Use for app-lifecycle "going to the background"
  /// flushes where every ms might be the last before the OS kills
  /// the process.
  Future<void> flushNow(EditorDocument doc) async {
    _writeTimer?.cancel();
    _writeTimer = null;
    await _writeNow(doc);
  }

  Future<void> _writeNow(EditorDocument doc) async {
    try {
      final json = ImportedImagePathCodec.encodeForStorage(
        doc,
        importedImagesDir: _importedImagesDir,
      );
      // Write-and-rename so a crash mid-write never leaves a
      // truncated journal — the rename is atomic on POSIX, the only
      // platforms we ship to.
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(_file.path);
    } catch (_) {
      // Swallow. See class doc.
    }
  }

  /// Read and return any pending journal entry, or `null` if none
  /// exists or the file is unreadable. Never throws.
  Future<EditorDocument?> recover() async {
    try {
      if (!await _file.exists()) return null;
      final raw = await _file.readAsString();
      if (raw.isEmpty) return null;
      return DocumentCodec.decode(raw);
    } catch (_) {
      // Corrupt journal — treat as no recovery available. The user
      // loses the journal's content but the persisted save is
      // untouched.
      return null;
    }
  }

  /// Drop the journal file. Call when the session ends cleanly
  /// (autosave flushed, editor closed) so the next launch sees no
  /// stale recovery offer.
  Future<void> clear() async {
    _writeTimer?.cancel();
    _writeTimer = null;
    try {
      if (await _file.exists()) {
        await _file.delete();
      }
    } catch (_) {
      /* swallow */
    }
  }
}
