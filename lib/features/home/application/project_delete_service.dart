import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/user_error.dart';
import '../../editor/application/edit_journal.dart';
import '../../editor/application/project_viewport_store.dart';
import '../domain/project.dart';
import 'project_store.dart';

/// Deletes a project *and* its per-project artifacts. Before this
/// existed, `ProjectStore.delete` removed only the store record and
/// three artifacts leaked forever: the thumbnail PNG under
/// `project_thumbs/`, the `viewport.<id>` prefs key, and the crash
/// journal file — `ProjectViewportStore.clear`'s doc even said
/// "called when a project is deleted" while having zero callers.
///
/// The record delete is authoritative and its failure propagates;
/// artifact cleanup is best-effort (a leaked thumbnail is not worth
/// failing the user's delete) but logged in dev builds.
class ProjectDeleteService {
  ProjectDeleteService(this._ref);

  final Ref _ref;

  Future<void> delete(String projectId) async {
    // Capture the record before it disappears — it carries the
    // thumbnail path.
    final projects = await _ref.read(projectStoreProvider.future);
    Project? record;
    for (final p in projects) {
      if (p.id == projectId) {
        record = p;
        break;
      }
    }

    await _ref.read(projectStoreProvider.notifier).delete(projectId);

    // Reference-aware thumbnail cleanup: unlink the PNG only when no remaining
    // project still points at it. Legacy installs may share one thumbnail path
    // across projects (pre-fix duplicates), so an unconditional delete here
    // would blank a sibling's preview. The store runs the delete against its
    // post-delete list, which no longer contains this project.
    await _ref
        .read(projectStoreProvider.notifier)
        .releaseThumbnailIfUnreferenced(record?.thumbnailPath);
    try {
      await ProjectViewportStore().clear(projectId);
    } catch (e, st) {
      debugLogError('ProjectDeleteService: viewport cleanup', e, st);
    }
    try {
      final journal = await EditJournal.open(projectId);
      await journal.clear();
    } catch (e, st) {
      debugLogError('ProjectDeleteService: journal cleanup', e, st);
    }
  }
}

final projectDeleteServiceProvider = Provider<ProjectDeleteService>(
  ProjectDeleteService.new,
);
