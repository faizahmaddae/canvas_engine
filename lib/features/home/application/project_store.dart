import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/user_error.dart';
import '../domain/project.dart';

/// Directory holding one JSON file per saved project
/// (`<appDocs>/projects/<id>.json`). A provider so tests can override
/// it with a temp directory instead of mocking platform channels.
final projectsDirectoryProvider = FutureProvider<Directory>((ref) async {
  final docs = await getApplicationDocumentsDirectory();
  return Directory('${docs.path}${Platform.pathSeparator}projects');
});

/// Persistence-backed list of saved [Project]s.
///
/// One JSON file per project, written atomically (tmp + rename). The
/// previous format — the entire library as a single JSON string under
/// one SharedPreferences key — meant every autosave re-encoded and
/// rewrote every project, and one corrupt byte silently emptied the
/// whole library. Now:
///
///   * a save touches exactly one file;
///   * a corrupt file is quarantined (renamed `*.corrupt`) and only
///     that project drops out of the list, loudly in dev logs;
///   * write failures throw to the caller (manual save surfaces an
///     error snackbar) instead of being reported as success.
///
/// The legacy prefs blob is migrated to files on first build and the
/// key is removed only after every migrated file verifiably reads
/// back.
class ProjectStore extends AsyncNotifier<List<Project>> {
  static const String _legacyPrefsKey = 'home.projects.v1';

  late Directory _dir;

  @override
  Future<List<Project>> build() async {
    _dir = await ref.watch(projectsDirectoryProvider.future);
    await _dir.create(recursive: true);
    await _migrateLegacyPrefs();
    return _readAll();
  }

  File _fileFor(String id) =>
      File('${_dir.path}${Platform.pathSeparator}$id.json');

  /// One-time move of the pre-file-store library (single prefs key)
  /// into per-project files. Existing files win over the blob (they
  /// are newer authority — a partial earlier migration must not roll
  /// projects back). The prefs key is deleted only after every
  /// migrated project reads back from disk, so a failed migration
  /// leaves the original data untouched for the next attempt.
  Future<void> _migrateLegacyPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_legacyPrefsKey);
    if (raw == null || raw.isEmpty) return;
    final List<Project> parsed;
    try {
      parsed = (jsonDecode(raw) as List<dynamic>)
          .map((e) => Project.fromJson(Map<String, Object?>.from(e as Map)))
          .toList(growable: false);
    } catch (e, st) {
      // Unreadable blob: keep the key for forensics; the file store
      // simply starts from whatever files exist.
      debugLogError('ProjectStore: legacy library unreadable', e, st);
      return;
    }
    for (final p in parsed) {
      if (await _fileFor(p.id).exists()) continue;
      await _writeProjectFile(p);
    }
    for (final p in parsed) {
      if (await _readProjectFile(_fileFor(p.id)) == null) {
        debugLogError(
          'ProjectStore: migration verify failed',
          'project ${p.id} did not read back; keeping legacy key',
        );
        return;
      }
    }
    await prefs.remove(_legacyPrefsKey);
  }

  Future<List<Project>> _readAll() async {
    final projects = <Project>[];
    await for (final entry in _dir.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      final project = await _readProjectFile(entry);
      if (project != null) {
        projects.add(project);
      } else {
        await _quarantine(entry);
      }
    }
    projects.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return List.unmodifiable(projects);
  }

  Future<Project?> _readProjectFile(File file) async {
    try {
      final raw = await file.readAsString();
      return Project.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } catch (e, st) {
      debugLogError('ProjectStore: unreadable project ${file.path}', e, st);
      return null;
    }
  }

  /// Move a corrupt file aside instead of deleting it — the bytes may
  /// still be partially recoverable by hand, and quarantining keeps
  /// the failure visible instead of silently shrinking the library
  /// on every launch.
  Future<void> _quarantine(File file) async {
    try {
      await file.rename(
        '${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (e, st) {
      debugLogError('ProjectStore: quarantine failed for ${file.path}', e, st);
    }
  }

  /// Torn-write safe: a crash mid-write leaves a stale `.tmp`, never
  /// a truncated project file (same pattern as EditJournal).
  Future<void> _writeProjectFile(Project project) async {
    final file = _fileFor(project.id);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(project.toJson()), flush: true);
    await tmp.rename(file.path);
  }

  /// Current list, waiting out an in-flight [build] instead of
  /// falling back to empty — the old `state.value ?? const []`
  /// fallback made a save issued during load throw (at best) or
  /// clobber (at worst).
  Future<List<Project>> _current() async => state.value ?? await future;

  static List<Project> _sorted(List<Project> list) {
    final next = [...list]
      ..sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return List.unmodifiable(next);
  }

  /// Insert or update [project] (matched by [Project.id]). Writes
  /// exactly one file; IO failures propagate to the caller.
  Future<void> upsert(Project project) async {
    final current = await _current();
    await _writeProjectFile(project);
    final next = [...current];
    final idx = next.indexWhere((p) => p.id == project.id);
    if (idx >= 0) {
      next[idx] = project;
    } else {
      next.add(project);
    }
    state = AsyncData(_sorted(next));
  }

  Future<void> delete(String projectId) async {
    final current = await _current();
    final next = current.where((p) => p.id != projectId).toList();
    if (next.length == current.length) return;
    final file = _fileFor(projectId);
    if (await file.exists()) await file.delete();
    state = AsyncData(_sorted(next));
  }

  Future<void> rename(String projectId, String name) async {
    final current = await _current();
    final idx = current.indexWhere((p) => p.id == projectId);
    if (idx < 0) return;
    final updated = current[idx].copyWith(
      name: name,
      lastModified: DateTime.now(),
    );
    await _writeProjectFile(updated);
    final next = [...current]..[idx] = updated;
    state = AsyncData(_sorted(next));
  }

  /// Insert a copy of an existing project with a new id and a
  /// "(copy)" suffix on the name. Reuses the same thumbnail path so
  /// the duplicate gets a preview immediately. Returns the new id, or
  /// null if [projectId] no longer exists.
  Future<String?> duplicate(String projectId, String newId) async {
    final current = await _current();
    final idx = current.indexWhere((p) => p.id == projectId);
    if (idx < 0) return null;
    final src = current[idx];
    final now = DateTime.now();
    final copy = Project(
      id: newId,
      name: '${src.name} (copy)',
      width: src.width,
      height: src.height,
      // A duplicate is a brand-new project record from the user's
      // point of view — its createdAt and lastModified both start
      // at "now", independent of the source's history.
      createdAt: now,
      lastModified: now,
      documentJson: src.documentJson,
      thumbnailPath: src.thumbnailPath,
      // Inherit the source's renderer version so a duplicate of a
      // legacy/stale-PNG project also live-renders until it's saved.
      thumbnailVersion: src.thumbnailVersion,
    );
    await _writeProjectFile(copy);
    state = AsyncData(_sorted([...current, copy]));
    return newId;
  }
}

/// Tracks the id of the last project the user opened, so the home
/// grid can show a small "last opened" badge. Persisted across runs.
class LastOpenedProjectController extends AsyncNotifier<String?> {
  static const String _key = 'home.last_opened_project.v1';

  @override
  Future<String?> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  /// Resolves SharedPreferences on demand instead of caching it in a
  /// `late` field from [build]: [set] can legally run BEFORE the
  /// first build completes (open a project straight from a cold
  /// home screen) and the late field crashed that path.
  /// `getInstance()` is a cached singleton, so this costs nothing
  /// after the first call.
  Future<void> set(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, id);
    }
    state = AsyncData(id);
  }
}

final lastOpenedProjectIdProvider =
    AsyncNotifierProvider<LastOpenedProjectController, String?>(
      LastOpenedProjectController.new,
    );

final projectStoreProvider = AsyncNotifierProvider<ProjectStore, List<Project>>(
  ProjectStore.new,
);
