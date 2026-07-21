import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Owns the on-device project-thumbnail directory and every file-level
/// operation over it.
///
/// Centralising the `<appDocs>/project_thumbs/<uuid>.png` convention in one
/// place means project **saving**, **duplication**, and **deletion** all agree
/// on where thumbnails live and how they are named — the precondition for
/// per-project thumbnail ownership and reference-aware cleanup.
///
/// Application layer: it performs real filesystem IO so the [Project] model
/// stays pure. It reaches the documents directory through `path_provider`,
/// exactly like `ProjectSaveService` did before, so tests drive it without
/// platform channels via the same fake documents dir the store already uses.
///
/// Every filename is a fresh UUID (never derived from a project id), so a new
/// path is unique by construction — two projects can only end up sharing a
/// path via a pre-fix legacy duplicate, which the reference-aware cleanup in
/// `ProjectStore` handles.
class ProjectThumbnailStore {
  const ProjectThumbnailStore();

  static const Uuid _uuid = Uuid();

  /// The `project_thumbs` directory under application-documents, created on
  /// first use.
  Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final folder = Directory('${docs.path}/project_thumbs');
    if (!await folder.exists()) await folder.create(recursive: true);
    return folder;
  }

  String _newPathIn(Directory dir) => '${dir.path}/${_uuid.v4()}.png';

  /// Write [bytes] to a fresh, uniquely-named PNG and return its path.
  ///
  /// Torn-write safe (tmp + rename, matching the project-file store): a crash
  /// mid-write leaves a stale `.tmp`, never a truncated thumbnail. The bytes
  /// are flushed before the rename so the path is durable the moment it is
  /// published in project metadata.
  Future<String> writeBytes(Uint8List bytes) async {
    final dir = await _dir();
    final path = _newPathIn(dir);
    final tmp = File('$path.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(path);
    return path;
  }

  /// Copy [sourcePath] to a fresh, uniquely-named PNG and return the new path.
  ///
  /// Returns null when the source file is absent — the caller degrades to the
  /// nullable "no thumbnail yet" contract rather than pointing at a missing
  /// or shared file. If the source exists but cannot be copied the failure
  /// propagates, and the partial temp is removed first so no artifact leaks.
  Future<String?> copyToNew(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) return null;
    final dir = await _dir();
    final path = _newPathIn(dir);
    final tmp = File('$path.tmp');
    try {
      await source.copy(tmp.path);
      await tmp.rename(path);
      return path;
    } catch (_) {
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {
          // Best-effort temp cleanup; the original failure is what matters.
        }
      }
      rethrow;
    }
  }

  /// Best-effort delete of the thumbnail at [path]. A missing file is a no-op.
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
