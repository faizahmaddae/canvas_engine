import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/application/project_store.dart';
import 'document_controller.dart';
import 'edit_journal.dart';
import 'editor_session.dart';

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

  Timer? _timer;

  /// Per-project journal handle. Lazily opened on the first write
  /// for a given session — cheap (one mkdir-if-needed + a struct
  /// allocation), but wasteful to do on every flush.
  EditJournal? _journal;
  String? _journalProjectId;

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
    final projectId = session?.projectId;
    if (projectId == null) return;
    if (_journalProjectId != projectId) {
      _journal = null;
      _journalProjectId = projectId;
      EditJournal.open(projectId)
          .then((j) {
            if (!ref.mounted) return;
            if (_journalProjectId != projectId) return;
            _journal = j;
            _journal!.scheduleWrite(ref.read(documentControllerProvider));
          })
          .catchError((_) {
            /* swallow */
          });
      return;
    }
    final journal = _journal;
    if (journal == null) return;
    journal.scheduleWrite(ref.read(documentControllerProvider));
  }

  /// Force any pending autosave to run immediately. Intended for
  /// "navigating away from the editor" hooks where the debounce
  /// timer might otherwise drop the latest edits on the floor.
  Future<void> flushNow() async {
    _timer?.cancel();
    _timer = null;
    if (!ref.mounted) return;
    await _flush();
  }

  Future<void> _flush() async {
    if (!ref.mounted) return;
    final session = ref.read(editorSessionProvider);
    final projectId = session?.projectId;
    if (projectId == null) return; // Rule 1.

    final docCtrl = ref.read(documentControllerProvider.notifier);
    final doc = ref.read(documentControllerProvider);
    final projectsAsync = ref.read(projectStoreProvider);
    final projects = projectsAsync.value;
    if (projects == null) return; // Store still loading; try next tick.

    final idx = projects.indexWhere((p) => p.id == projectId);
    if (idx < 0) return; // Project was deleted from another surface.
    final existing = projects[idx];

    final updated = existing.copyWith(
      documentJson: docCtrl.exportJson(),
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
