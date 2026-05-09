import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../home/application/project_store.dart';
import '../../home/domain/project.dart';
import '../engine/export/document_png_exporter.dart';
import '../engine/rendering/document_thumbnail.dart';
import 'document_controller.dart';
import 'editor_session.dart';

const _uuid = Uuid();

/// Saves the current editor document into the home [ProjectStore],
/// rendering a small PNG thumbnail along the way.
///
/// Lives in `editor/application` because it bridges the editor's
/// engine-facing controllers (document + export) and the home-facing
/// [ProjectStore]. Presentation only invokes [save].
class ProjectSaveService {
  const ProjectSaveService(this._ref);

  final Ref _ref;

  /// Thumbnail target longest-edge in px. Small so the home grid
  /// stays light, large enough to look crisp on hi-dpi screens.
  static const double _thumbMaxEdge = 320;

  /// Render + persist. Returns the saved [Project]. If the active
  /// [EditorSession] has a `projectId`, that record is updated;
  /// otherwise a new project is inserted and the session is rebound
  /// to the new id.
  Future<Project> save(BuildContext context) async {
    final session = _ref.read(editorSessionProvider);
    final docCtrl = _ref.read(documentControllerProvider.notifier);
    final doc = _ref.read(documentControllerProvider);

    // Render the thumbnail BEFORE awaits that might unmount widgets:
    // the exporter needs a valid Overlay-bearing context.
    String? thumbPath;
    try {
      final pixelRatio = _thumbnailPixelRatio(doc.width, doc.height);
      // Funnel through the same rule the live `DocumentThumbnail`
      // uses on Home so the saved PNG and any in-memory preview can
      // never disagree about canvas background. Without this the
      // exporter defaulted to opaque white and recent thumbnails
      // for coloured/transparent canvases drifted from the editor.
      final bytes = await DocumentPngExporter.export(
        context: context,
        document: doc,
        pixelRatio: pixelRatio,
        background: DocumentThumbnail.backgroundFor(doc),
      );
      thumbPath = await _writeThumbnail(bytes);
    } catch (_) {
      // Thumbnail failure shouldn't block saving the document itself
      // — the home grid will fall back to a generated card.
      thumbPath = null;
    }

    final id = session?.projectId ?? _uuid.v4();
    final name = session?.name ?? 'Untitled design';
    // Preserve `createdAt` across updates: only stamp it on the
    // first save of a project. We look up the existing record by id
    // (works for both manual save and autosave) and fall back to
    // `now` when the project hasn't been persisted yet.
    final existing = _ref
        .read(projectStoreProvider)
        .value
        ?.where((p) => p.id == id)
        .cast<Project?>()
        .firstWhere((_) => true, orElse: () => null);
    final now = DateTime.now();
    final project = Project(
      id: id,
      name: name,
      width: doc.width,
      height: doc.height,
      createdAt: existing?.createdAt ?? now,
      lastModified: now,
      documentJson: docCtrl.exportJson(),
      thumbnailPath: thumbPath ?? existing?.thumbnailPath,
      // Stamp the renderer version we used so the Recent grid
      // knows it can trust the cached PNG. If the PNG capture
      // failed and we're falling back to an older `thumbnailPath`,
      // record that older version instead so the grid live-renders
      // until the next successful save.
      thumbnailVersion: thumbPath != null
          ? Project.currentThumbnailVersion
          : (existing?.thumbnailVersion ?? 0),
    );
    await _ref.read(projectStoreProvider.notifier).upsert(project);

    // Bind the new id back to the session so subsequent saves update.
    if (session?.projectId == null) {
      _ref.read(editorSessionProvider.notifier).state = EditorSession(
        name: name,
        projectId: id,
      );
    }
    return project;
  }

  double _thumbnailPixelRatio(double w, double h) {
    final longest = w > h ? w : h;
    if (longest <= 0) return 1;
    return (_thumbMaxEdge / longest).clamp(0.05, 1.0);
  }

  Future<String> _writeThumbnail(Uint8List bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/project_thumbs');
    if (!await folder.exists()) await folder.create(recursive: true);
    final path = '${folder.path}/${_uuid.v4()}.png';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }
}

final projectSaveServiceProvider = Provider<ProjectSaveService>(
  ProjectSaveService.new,
);
