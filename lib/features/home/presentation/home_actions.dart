import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' as picker;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../editor/application/document_controller.dart';
import '../../editor/application/editor_lifecycle.dart';
import '../../editor/application/editor_session.dart';
import '../../editor/application/selection_controller.dart';
import '../../editor/engine/commands/transform_commands.dart';
import '../../editor/engine/core/editor_document.dart';
import '../../editor/engine/core/layer_transform.dart';
import '../../editor/engine/modules/image/image_layer.dart';
import '../../editor/engine/serialization/document_codec.dart';
import '../../editor/presentation/editor_screen.dart';
import '../../templates/domain/template.dart';
import '../application/project_store.dart';
import '../domain/project.dart';
import 'recent_projects_screen.dart';
import 'widgets/size_picker_dialog.dart';

const _uuid = Uuid();

/// Single owner of every editor-launching navigation flow on Home.
///
/// Extracted out of `HomeScreen` so the screen + tab shell stay
/// pure presentation. Behaviour is identical to the previous inline
/// implementations — same providers, same composite commands, same
/// `_push` reset semantics — preserving the existing navigation
/// API. Nothing here reaches into engine internals beyond what the
/// editor's public command + provider surfaces already expose.
class HomeActions {
  const HomeActions(this.context, this.ref);

  final BuildContext context;
  final WidgetRef ref;

  // ───────────────────────── creation flows ────────────────────────

  /// "Blank canvas" CTA: ask for a size, then seed an empty
  /// document and open the editor.
  Future<void> createNew() async {
    final size = await SizePickerDialog.show(context);
    if (size == null || !context.mounted) return;
    _seedAndOpen(
      width: size.width,
      height: size.height,
      name: size.label ?? 'New design',
    );
  }

  /// "Edit a photo" CTA: pick an image, persist it, seed a photo
  /// project locked to the photo's pixel dimensions, then open the
  /// editor with no selection (so the photo reads as the canvas).
  Future<void> importPhoto() async {
    final messenger = ScaffoldMessenger.of(context);
    final pick = picker.ImagePicker();
    final picked = await pick.pickImage(source: picker.ImageSource.gallery);
    if (picked == null || !context.mounted) return;

    final Size dims;
    try {
      dims = await _resolveImageSize(File(picked.path));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not read image: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final stable = await _persistPickedImage(picked.path);
    if (!context.mounted) return;

    final docCtrl = ref.read(documentControllerProvider.notifier);
    docCtrl.newDocument(
      width: dims.width,
      height: dims.height,
      kind: ProjectKind.photo,
    );
    final id = _uuid.v4();
    docCtrl.execute(
      CompositeCommand(
        [
          AddLayerCommand(ImageLayer(
            id: id,
            transform: LayerTransform(
              position: Offset.zero,
              size: dims,
            ),
            source: ImageSource.file(stable),
            locked: true,
          )),
          SetBasePhotoCommand(id),
        ],
        labelOverride: 'Import photo',
      ),
    );
    docCtrl.clearHistory();
    ref.read(selectionControllerProvider.notifier).clear();
    ref.read(editorSessionProvider.notifier).state = const EditorSession(
      name: 'Imported image',
    );
    _push();
  }

  /// Open a built-in [Template]. Round-trips the seed document
  /// through the codec so the editor's load path stays uniform.
  void openTemplate(Template template) {
    final docCtrl = ref.read(documentControllerProvider.notifier);
    final doc = template.build();
    docCtrl.importJson(DocumentCodec.encode(doc));
    ref.read(selectionControllerProvider.notifier).clear();
    ref.read(editorSessionProvider.notifier).state =
        EditorSession(name: template.name);
    _push();
  }

  /// Open a saved [Project] from the Recent rail.
  void openProject(Project p) {
    final docCtrl = ref.read(documentControllerProvider.notifier);
    try {
      docCtrl.importJson(p.documentJson);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open project: $e')),
      );
      return;
    }
    ref.read(selectionControllerProvider.notifier).clear();
    ref.read(editorSessionProvider.notifier).state = EditorSession(
      name: p.name,
      projectId: p.id,
    );
    unawaited(
      ref.read(lastOpenedProjectIdProvider.notifier).set(p.id),
    );
    _push();
  }

  /// Push the dedicated full-list "Recent projects" screen. Open /
  /// create still flow back through this object so navigation
  /// stays in one place.
  void openRecentAll() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecentProjectsScreen(
          onCreate: createNew,
          onOpen: openProject,
        ),
      ),
    );
  }

  // ───────────────────────── internals ─────────────────────────────

  void _seedAndOpen({
    required double width,
    required double height,
    required String name,
  }) {
    ref
        .read(documentControllerProvider.notifier)
        .newDocument(width: width, height: height);
    ref.read(selectionControllerProvider.notifier).clear();
    ref.read(editorSessionProvider.notifier).state = EditorSession(name: name);
    _push();
  }

  /// Pushes the editor screen, resetting all ephemeral tool/UI
  /// state first so a project never inherits the previous one's
  /// open sheets, sticky preset chips, default text/paint style,
  /// recent colours, viewport zoom, multi-select mode, or stale
  /// editing target. Saved layer styles are unaffected — they live
  /// on the document, not on the providers reset here.
  void _push() {
    resetEditorEphemeralState(ref);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const EditorScreen()),
    );
  }

  Future<Size> _resolveImageSize(File file) async {
    final stream = FileImage(file).resolve(ImageConfiguration.empty);
    final completer = Completer<Size>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) {
          completer.complete(
            Size(info.image.width.toDouble(), info.image.height.toDouble()),
          );
        }
        stream.removeListener(listener);
      },
      onError: (e, _) {
        if (!completer.isCompleted) completer.completeError(e);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  Future<String> _persistPickedImage(String tempPath) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/imported_images');
    if (!await folder.exists()) await folder.create(recursive: true);
    final ext = tempPath.contains('.')
        ? tempPath.substring(tempPath.lastIndexOf('.'))
        : '.png';
    final dest = '${folder.path}/${_uuid.v4()}$ext';
    await File(tempPath).copy(dest);
    return dest;
  }
}
