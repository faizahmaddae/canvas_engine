import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/project.dart';

/// Persistence-backed list of saved [Project]s.
///
/// Stored as a single JSON-encoded list under [_storageKey] in
/// [SharedPreferences]. Keeps the home layer free of any platform
/// channel calls scattered through widgets.
class ProjectStore extends AsyncNotifier<List<Project>> {
  static const String _storageKey = 'home.projects.v1';

  late SharedPreferences _prefs;

  @override
  Future<List<Project>> build() async {
    _prefs = await SharedPreferences.getInstance();
    return _readAll();
  }

  List<Project> _readAll() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => Project.fromJson(Map<String, Object?>.from(e as Map)))
          .toList(growable: false);
      // Most recent first.
      list.sort((a, b) => b.lastModified.compareTo(a.lastModified));
      return list;
    } catch (_) {
      // Corrupt / older format: treat as empty rather than crash the app.
      return const [];
    }
  }

  Future<void> _writeAll(List<Project> projects) async {
    await _prefs.setString(
      _storageKey,
      jsonEncode(projects.map((p) => p.toJson()).toList()),
    );
    state = AsyncData(List.unmodifiable(projects));
  }

  /// Insert or update [project] (matched by [Project.id]). Returns the
  /// resulting persisted list.
  Future<void> upsert(Project project) async {
    final current = state.value ?? const <Project>[];
    final next = [...current];
    final idx = next.indexWhere((p) => p.id == project.id);
    if (idx >= 0) {
      next[idx] = project;
    } else {
      next.add(project);
    }
    next.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    await _writeAll(next);
  }

  Future<void> delete(String projectId) async {
    final current = state.value ?? const <Project>[];
    final next = current.where((p) => p.id != projectId).toList();
    if (next.length == current.length) return;
    await _writeAll(next);
  }

  Future<void> rename(String projectId, String name) async {
    final current = state.value ?? const <Project>[];
    final idx = current.indexWhere((p) => p.id == projectId);
    if (idx < 0) return;
    final updated = current[idx].copyWith(
      name: name,
      lastModified: DateTime.now(),
    );
    final next = [...current]..[idx] = updated;
    next.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    await _writeAll(next);
  }

  /// Insert a copy of an existing project with a new id and a
  /// "(copy)" suffix on the name. Reuses the same thumbnail path so
  /// the duplicate gets a preview immediately. Returns the new id, or
  /// null if [projectId] no longer exists.
  Future<String?> duplicate(String projectId, String newId) async {
    final current = state.value ?? const <Project>[];
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
    final next = [...current, copy]
      ..sort((a, b) => b.lastModified.compareTo(a.lastModified));
    await _writeAll(next);
    return newId;
  }
}

/// Tracks the id of the last project the user opened, so the home
/// grid can show a small "last opened" badge. Persisted across runs.
class LastOpenedProjectController extends AsyncNotifier<String?> {
  static const String _key = 'home.last_opened_project.v1';

  late SharedPreferences _prefs;

  @override
  Future<String?> build() async {
    _prefs = await SharedPreferences.getInstance();
    return _prefs.getString(_key);
  }

  Future<void> set(String? id) async {
    if (id == null) {
      await _prefs.remove(_key);
    } else {
      await _prefs.setString(_key, id);
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
