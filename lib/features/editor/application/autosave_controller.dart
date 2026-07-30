import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/user_error.dart';
import '../../home/application/project_store.dart';
import 'document_controller.dart';
import 'edit_journal.dart';
import 'editor_session.dart';
import 'imported_image_path_codec.dart';

/// Listens to [documentCommitVersionProvider] and persists the
/// current document into the [projectStoreProvider] on a debounced
/// schedule.
///
/// Design rules:
///
/// 1. **Only autosaves projects that already exist on disk.** If
///    [EditorSession.projectId] is null the document has never been
///    saved by the user — auto-creating a "Untitled" record on the
///    first edit would clutter the home grid with throwaway projects.
///    The user can opt in with a single explicit Save; from then on
///    autosave keeps it warm.
///
/// 2. **Debounced.** A fast burst of edits collapses into a single
///    write so we don't churn `SharedPreferences` while the user is
///    actively dragging chips, typing text, or stepping a slider.
///
/// 3. **Skips thumbnail rendering.** Manual save (via the overflow
///    menu) re-renders the PNG thumbnail because it's a deliberate
///    user action; autosave keeps the previous thumbnail to stay
///    cheap and off the UI thread. The home grid still updates the
///    `lastModified` ordering immediately.
///
/// 4. **Pure side-effect notifier.** The notifier exposes no state;
///    presentation just needs to keep it alive (e.g. via `ref.watch`)
///    while the editor is on screen.
class AutosaveController extends Notifier<void> {
  /// Window in which consecutive commits collapse into one write.
  /// Long enough to absorb a burst of slider ticks; short enough that
  /// a backgrounding user doesn't lose more than ~1.5 s of work.
  static const Duration debounce = Duration(milliseconds: 1500);

  /// Journal slot for the never-saved document. Rule 1 keeps unsaved
  /// docs out of the project store, but a crash mid-first-session was
  /// total loss — so the journal covers them under this single
  /// reserved id (one editor session at a time → one draft slot, no
  /// per-draft bookkeeping). Cleared when the user deliberately
  /// leaves the editor without saving (leaving an unsaved doc IS the
  /// discard gesture) and when a first save rebinds the session to a
  /// real project id.
  static const String draftJournalId = 'draft';

  Timer? _timer;

  /// Per-project journal handle. Lazily opened on the first write
  /// for a given session — cheap (one mkdir-if-needed + a struct
  /// allocation), but wasteful to do on every flush.
  EditJournal? _journal;
  String? _journalProjectId;

  /// Name last recorded in the journal's identity sidecar. The
  /// journal handle is keyed on project id, and every never-saved
  /// session shares the reserved 'draft' id — so binding alone is not
  /// a reliable moment to write identity: a second unsaved session
  /// reuses the same handle and would inherit the first one's name.
  /// Tracking the value written lets the sidecar follow the session
  /// without paying a file write on every commit.
  String? _journalName;

  @override
  void build() {
    // Subscribe once; the listener fires on every commit.
    ref.listen<int>(documentCommitVersionProvider, (_, _) {
      _schedule();
      _scheduleJournal();
    });
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
  }

  /// Raise the flag the editor watches. Once per session is enough:
  /// a full disk does not un-fill itself between two debounced
  /// writes, and repeating the warning every 1.5s would be noise on
  /// top of a problem the user already knows about.
  void _reportJournalFailure(Object error) {
    if (!ref.mounted) return;
    if (ref.read(journalWriteFailedProvider)) return;
    debugLogError('editor/journal-write', error, StackTrace.current);
    ref.read(journalWriteFailedProvider.notifier).raise();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(debounce, _flush);
  }

  /// Schedule a journal write. Independent of the autosave timer
  /// because the journal is meant to capture in-flight state at a
  /// finer cadence than the autosave write — a crash between the
  /// last journal write and the next autosave must still be
  /// recoverable.
  void _scheduleJournal() {
    final session = ref.read(editorSessionProvider);
    if (session == null) return;
    // Unsaved docs journal under the reserved draft slot so a crash
    // in a first session is recoverable even though rule 1 keeps the
    // doc out of the project store.
    final journalId = session.projectId ?? draftJournalId;
    if (_journalProjectId != journalId) {
      // First save mid-session moves journaling from the draft slot
      // to the real project id — drop the stale draft file so it
      // can't produce a false "resume draft?" offer later.
      if (_journalProjectId == draftJournalId) {
        unawaited(_journal?.clear());
      }
      _journal = null;
      _journalProjectId = journalId;
      _journalName = null;
      EditJournal.open(journalId)
          .then((j) {
            if (!ref.mounted) return;
            if (_journalProjectId != journalId) return;
            _journal = j;
            j.onWriteFailure = _reportJournalFailure;
            _syncJournalName(j, session.name);
            _journal!.scheduleWrite(ref.read(documentControllerProvider));
          })
          .catchError((_) {
            /* swallow */
          });
      return;
    }
    final journal = _journal;
    if (journal == null) return;
    _syncJournalName(journal, session.name);
    journal.scheduleWrite(ref.read(documentControllerProvider));
  }

  /// Write the identity sidecar when — and only when — the name it
  /// holds is out of date.
  void _syncJournalName(EditJournal journal, String name) {
    if (_journalName == name) return;
    _journalName = name;
    unawaited(journal.writeMeta(name: name));
  }

  /// Force any pending autosave to run immediately. Intended for
  /// "navigating away from the editor" hooks where the debounce
  /// timer might otherwise drop the latest edits on the floor.
  ///
  /// [sessionEnding] distinguishes a deliberate exit (PopScope /
  /// editor dispose) from an app-lifecycle pause. Exiting a
  /// never-saved session with real content KEEPS (and fresh-flushes)
  /// the draft journal — the journal is the only copy of that work,
  /// the exit may be an accidental back-swipe, and Home's resume
  /// banner is the recovery path. This deliberately reverses the
  /// earlier "walking away is the discard gesture" rule (roadmap
  /// tb0 0.4): silent, unconfirmed total loss is worse than an
  /// occasional stale resume offer, which one tap dismisses. Only an
  /// UNTOUCHED never-saved document (no layers, nothing to undo)
  /// still clears the slot, so blank round-trips through the editor
  /// never spawn bogus offers. On a pause the journal is always
  /// kept: the OS may kill the process, and that is exactly the
  /// crash case the draft slot exists to recover.
  Future<void> flushNow({bool sessionEnding = false}) async {
    _timer?.cancel();
    _timer = null;
    if (!ref.mounted) return;
    final neverSaved =
        sessionEnding && ref.read(editorSessionProvider)?.projectId == null;
    final discardingDraft =
        neverSaved &&
        ref.read(documentControllerProvider).layers.isEmpty &&
        !ref.read(documentControllerProvider.notifier).canUndo;
    if (discardingDraft) {
      if (_journalProjectId == draftJournalId) {
        await _journal?.clear();
      } else {
        // Journal handle may not have opened yet (no commit landed);
        // clear the slot directly so the file cannot linger.
        try {
          final j = await EditJournal.open(draftJournalId);
          await j.clear();
        } catch (_) {
          /* swallow — best-effort, same as journal writes */
        }
      }
    } else {
      // Force the crash-recovery journal to disk NOW instead of waiting
      // out its 750 ms debounce. This is the going-to-background path:
      // the OS can suspend then kill the process before the pending
      // debounce Timer ever fires, and for a never-saved draft the
      // journal is the ONLY persistence (the project-store [_flush]
      // below no-ops without a projectId). Without this the last
      // <=750 ms of edits are lost with no journal on disk to recover.
      //
      // The handle opens asynchronously on commit ([_scheduleJournal]),
      // and a pause can land before that open resolves — so open it
      // inline here rather than skipping when [_journal] is still null.
      // Otherwise the very first edits of a session (the most fragile,
      // never-yet-persisted ones) would be exactly what's lost. Reads
      // state only; the racing async open stays the canonical owner of
      // [_journal]. Best-effort, like every journal write.
      final journalId =
          ref.read(editorSessionProvider)?.projectId ?? draftJournalId;
      final doc = ref.read(documentControllerProvider);
      var journal = _journal;
      if (journal == null || _journalProjectId != journalId) {
        try {
          journal = await EditJournal.open(journalId);
        } catch (_) {
          journal = null;
        }
      }
      if (journal != null) {
        // Identity travels with this flush too. `_scheduleJournal` is
        // driven by document COMMITS, and a session can reach the exit
        // without one — a photo import loads its document rather than
        // executing a command — so relying on the commit path alone
        // left exactly those sessions with a journal and no name, i.e.
        // resuming a photo as an untitled design.
        final name = ref.read(editorSessionProvider)?.name;
        if (name != null) await journal.writeMeta(name: name);
        await journal.flushNow(doc);
      }
    }
    await _flush();
  }

  Future<void> _flush() async {
    if (!ref.mounted) return;
    final session = ref.read(editorSessionProvider);
    final projectId = session?.projectId;
    if (projectId == null) return; // Rule 1.

    final doc = ref.read(documentControllerProvider);
    final projectsAsync = ref.read(projectStoreProvider);
    final projects = projectsAsync.value;
    if (projects == null) return; // Store still loading; try next tick.

    final idx = projects.indexWhere((p) => p.id == projectId);
    if (idx < 0) return; // Project was deleted from another surface.
    final existing = projects[idx];

    // Persist app-owned imported images as portable
    // `imported_images/<file>` references (same seam as manual save).
    final importedImagesDir = await ref.read(
      importedImagesDirectoryProvider.future,
    );
    final documentJson = ImportedImagePathCodec.encodeForStorage(
      doc,
      importedImagesDir: importedImagesDir.path,
    );
    final updated = existing.copyWith(
      documentJson: documentJson,
      width: doc.width,
      height: doc.height,
      lastModified: DateTime.now(),
      // Mark the cached thumbnail PNG as stale. Autosave does not
      // re-render the thumbnail (it would need a BuildContext +
      // Overlay we don't have here), so the bytes on disk are
      // out-of-date the moment the document JSON has changed. By
      // setting `thumbnailVersion: 0` (< currentThumbnailVersion),
      // the home grid's `pngIsFresh` gate flips to false and the
      // card live-renders the document until the user performs a
      // manual save (which regenerates the PNG).
      thumbnailVersion: 0,
      // createdAt + thumbnailPath preserved via copyWith defaults.
    );
    // Skip the write if the encoded payload matches what's on disk:
    // common when the only change was an in-place tool toggle that
    // produced an identical document (e.g. selecting an already-
    // selected font), or when undo/redo bounces back to a saved
    // state.
    if (updated.documentJson == existing.documentJson &&
        updated.width == existing.width &&
        updated.height == existing.height) {
      return;
    }
    await ref.read(projectStoreProvider.notifier).upsert(updated);
    // The persisted save now matches what's on disk; the journal's
    // pending entry is redundant. Clearing it avoids a stale
    // "recover?" prompt on next launch when the user has actually
    // saved cleanly.
    if (_journalProjectId == projectId) {
      await _journal?.clear();
    }
  }
}

final autosaveControllerProvider = NotifierProvider<AutosaveController, void>(
  AutosaveController.new,
);

/// True once a journal write has failed in this session — the crash
/// net is not working and the editor says so.
class JournalWriteFailedController extends Notifier<bool> {
  @override
  bool build() => false;

  void raise() {
    if (state) return;
    state = true;
  }
}

final journalWriteFailedProvider =
    NotifierProvider<JournalWriteFailedController, bool>(
      JournalWriteFailedController.new,
    );
