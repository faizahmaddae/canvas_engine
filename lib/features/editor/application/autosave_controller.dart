import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/application/project_store.dart';
import 'document_controller.dart';
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

  @override
  void build() {
    // Subscribe once; the listener fires on every commit.
    ref.listen<int>(documentCommitVersionProvider, (_, _) => _schedule());
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(debounce, _flush);
  }

  /// Force any pending autosave to run immediately. Intended for
  /// "navigating away from the editor" hooks where the debounce
  /// timer might otherwise drop the latest edits on the floor.
  Future<void> flushNow() async {
    _timer?.cancel();
    _timer = null;
    await _flush();
  }

  Future<void> _flush() async {
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
  }
}

final autosaveControllerProvider =
    NotifierProvider<AutosaveController, void>(AutosaveController.new);
