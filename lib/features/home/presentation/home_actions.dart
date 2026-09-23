import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' as picker;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/engine_constants.dart';
import '../../../core/utils/user_error.dart';
import '../../../l10n/l10n.dart';
import '../../editor/application/document_controller.dart';
import '../../editor/application/image_import_service.dart';
import '../../editor/application/editor_lifecycle.dart';
import '../../editor/application/editor_session.dart';
import '../../editor/application/imported_image_path_codec.dart';
import '../../editor/application/project_recovery_service.dart';
import '../../editor/application/selection_controller.dart';
import '../../editor/engine/commands/transform_commands.dart';
import '../../editor/engine/core/editor_document.dart';
import '../../editor/engine/core/layer_transform.dart';
import '../../editor/engine/modules/image/image_layer.dart';
import '../../editor/engine/modules/shape/shape_layer.dart';
import '../../editor/engine/modules/text/text_layer.dart';
import '../../editor/engine/serialization/document_codec.dart';
import '../../editor/presentation/editor_screen.dart';
import '../../templates/domain/template.dart';
import '../../templates/presentation/templates_browse_screen.dart';
import '../application/project_store.dart';
import '../domain/project.dart';
import 'recent_projects_screen.dart';
import '../../../app/ui/size_picker_sheet.dart';

const _uuid = Uuid();

/// Bumped every time an editor route pushed from Home pops.
///
/// Home never remounts (it lives in the shell's IndexedStack), so
/// its once-per-mount draft-resume check goes permanently stale
/// after the first editor round-trip — exactly when a surviving
/// draft journal (back-out of an unsaved session) needs an offer.
/// HomeScreen listens and re-checks the slot on each bump.
class DraftOfferTick extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final draftOfferTickProvider = NotifierProvider<DraftOfferTick, int>(
  DraftOfferTick.new,
);

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
    final size = await SizePickerSheet.show(context);
    if (size == null || !context.mounted) return;
    _seedAndOpen(
      width: size.width,
      height: size.height,
      name: size.label ?? context.l10n.newDesignName,
    );
  }

  /// "Edit a photo" CTA: pick an image, persist it, seed a photo
  /// project locked to the photo's pixel dimensions, then open the
  /// editor with no selection (so the photo reads as the canvas).
  Future<void> importPhoto() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final pick = picker.ImagePicker();
    final picker.XFile? picked;
    try {
      picked = await pick.pickImage(
        source: picker.ImageSource.gallery,
        // Longest-side import ceiling — the OS downscales
        // aspect-preserving before the bitmap enters the app. See
        // [EngineConstants.kMaxImportDimension].
        maxWidth: EngineConstants.kMaxImportDimension,
        maxHeight: EngineConstants.kMaxImportDimension,
      );
    } catch (e, st) {
      debugLogError('importPhoto/pickImage', e, st);
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            userMessageFor(
              e,
              fallback: l10n.couldntOpenPhoto,
              permissionDeniedMessage: l10n.allowPhotoAccessSettings,
              genericMessage: l10n.somethingWentWrong,
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (picked == null || !context.mounted) return;

    final Size dims;
    try {
      // Belt-and-braces cap: the picker already downscaled, but the
      // photo-project document size derived from these dims must
      // never exceed the ceiling even if a platform path slips past.
      dims = capImportSize(await _resolveImageSize(File(picked.path)));
    } catch (e, st) {
      debugLogError('importPhoto/_resolveImageSize', e, st);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            userMessageFor(
              e,
              fallback: l10n.couldntOpenPhoto,
              permissionDeniedMessage: l10n.allowPhotoAccessSettings,
              genericMessage: l10n.somethingWentWrong,
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final stable = await _persistPickedImage(picked.path);
    if (!context.mounted) return;
    unawaited(preserveOrphanDraft());

    final docCtrl = ref.read(documentControllerProvider.notifier);
    docCtrl.newDocument(
      width: dims.width,
      height: dims.height,
      kind: ProjectKind.photo,
    );
    final id = _uuid.v4();
    docCtrl.execute(
      CompositeCommand([
        AddLayerCommand(
          ImageLayer(
            id: id,
            transform: LayerTransform(position: Offset.zero, size: dims),
            source: ImageSource.file(stable),
            locked: true,
          ),
        ),
        SetBasePhotoCommand(id),
      ], labelOverride: l10n.importPhotoCommand),
    );
    docCtrl.clearHistory();
    ref.read(selectionControllerProvider.notifier).clear();
    ref.read(editorSessionProvider.notifier).state = EditorSession(
      name: l10n.importedImageName,
    );
    _push();
  }

  /// Open a built-in [Template]. Round-trips the seed document
  /// through the codec so the editor's load path stays uniform.
  /// Rescue a pending unsaved draft before a NEW unsaved session
  /// overwrites the single 'draft' journal slot.
  ///
  /// Collision policy (roadmap tb0 0.4b): newest wins the slot; the
  /// prior draft is promoted to a regular project record first (the
  /// Recents grid live-renders its preview from documentJson), then
  /// the slot is cleared. No-op when the slot is empty. Best-effort:
  /// a decode/store failure leaves the slot untouched so the resume
  /// banner still gets a chance at it.
  Future<void> preserveOrphanDraft() async {
    final fallbackName = context.l10n.recoveredDraftName;
    final recovery = ref.read(projectRecoveryServiceProvider);
    try {
      final draftJson = await recovery.pendingDraftJson();
      if (draftJson == null) return;
      // Promote under the draft's OWN name. Every rescue used to land
      // as «Recovered draft», so a user who backed out of three
      // sessions got three projects with one identical title,
      // distinguishable only by dimensions and timestamp.
      final draftName = await recovery.pendingDraftName() ?? fallbackName;
      final doc = DocumentCodec.decode(draftJson);
      final now = DateTime.now();
      await ref
          .read(projectStoreProvider.notifier)
          .upsert(
            Project(
              id: _uuid.v4(),
              name: draftName,
              width: doc.width,
              height: doc.height,
              createdAt: now,
              lastModified: now,
              documentJson: draftJson,
            ),
          );
      await recovery.clearDraft();
    } catch (e, st) {
      debugLogError('home/preserveOrphanDraft', e, st);
    }
  }

  void openTemplate(Template template) {
    unawaited(preserveOrphanDraft());
    final docCtrl = ref.read(documentControllerProvider.notifier);
    final doc = template.build();
    docCtrl.importJson(DocumentCodec.encode(doc));
    ref.read(selectionControllerProvider.notifier).clear();
    ref.read(editorSessionProvider.notifier).state = EditorSession(
      name: template.name,
    );
    _push();
  }

  /// Open the template browser from Home CTAs without changing the
  /// user's app locale or persisted content-language preferences.
  void openTemplates({
    TemplateLanguage? initialLanguage,
    TemplateCategory? initialCategory,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TemplatesBrowseScreen(
          onOpen: openTemplate,
          initialLanguage: initialLanguage,
          initialCategory: initialCategory,
        ),
      ),
    );
  }

  /// Open a saved [Project] from the Recent rail. If a crash left a
  /// journal entry newer than the persisted save, offer to resume it
  /// before loading.
  Future<void> openProject(Project p) async {
    final recovery = ref.read(projectRecoveryServiceProvider);
    final importedImagesDir = await ref.read(
      importedImagesDirectoryProvider.future,
    );
    final pendingJson = await recovery.pendingJsonForProject(
      projectId: p.id,
      persistedJson: p.documentJson,
      importedImagesDir: importedImagesDir.path,
      fileExists: (path) => File(path).existsSync(),
    );
    if (!context.mounted) return;

    var documentJson = p.documentJson;
    if (pendingJson != null) {
      final resume = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.resumeEditsTitle),
          content: Text(context.l10n.resumeEditsBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.discardAction),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.resumeAction),
            ),
          ],
        ),
      );
      if (!context.mounted) return;
      if (resume ?? false) {
        documentJson = pendingJson;
        // Journal stays until the resumed session autosaves — if the
        // user closes the dialog's editor without an edit, the offer
        // simply reappears next open, which is the safe direction.
      } else {
        await recovery.clearForProject(p.id);
        if (!context.mounted) return;
      }
    }

    final docCtrl = ref.read(documentControllerProvider.notifier);
    try {
      docCtrl.loadDocument(await _hydrate(documentJson));
    } catch (e, st) {
      debugLogError('openProject/hydrate', e, st);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userMessageFor(e, fallback: context.l10n.somethingWentWrong),
          ),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    ref.read(selectionControllerProvider.notifier).clear();
    ref.read(editorSessionProvider.notifier).state = EditorSession(
      name: p.name,
      projectId: p.id,
    );
    unawaited(ref.read(lastOpenedProjectIdProvider.notifier).set(p.id));
    _push();
  }

  /// Decode a persisted/journal [documentJson] into a runtime document,
  /// resolving portable `imported_images/<file>` references (and rebasing
  /// recoverable legacy absolute paths) against the current documents
  /// directory so the editor receives usable absolute image paths.
  Future<EditorDocument> _hydrate(String documentJson) async {
    final importedImagesDir = await ref.read(
      importedImagesDirectoryProvider.future,
    );
    return ImportedImagePathCodec.decodeToRuntime(
      documentJson,
      importedImagesDir: importedImagesDir.path,
      fileExists: (path) => File(path).existsSync(),
    );
  }

  /// Resume a crashed never-saved session from the draft journal
  /// (Home banner action). The session stays unsaved — same state as
  /// before the crash — so autosave rule 1 still applies until the
  /// user explicitly saves.
  Future<void> resumeDraft(String draftJson) async {
    final docCtrl = ref.read(documentControllerProvider.notifier);
    try {
      docCtrl.loadDocument(await _hydrate(draftJson));
    } catch (e, st) {
      debugLogError('resumeDraft/hydrate', e, st);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userMessageFor(e, fallback: context.l10n.somethingWentWrong),
          ),
        ),
      );
      return;
    }
    // Restore the draft's own name. Hardcoding `newDesignName` here
    // renamed every resumed draft: a photo session came back as "New
    // design", and the eventual save carried that wrong name to disk.
    // The sidecar is best-effort, so a draft written before it existed
    // (or one whose meta write lost the race with the crash) still
    // falls back to the generic name.
    final recoveredName = await ref
        .read(projectRecoveryServiceProvider)
        .pendingDraftName();
    if (!context.mounted) return;
    ref.read(selectionControllerProvider.notifier).clear();
    ref.read(editorSessionProvider.notifier).state = EditorSession(
      name: recoveredName ?? context.l10n.newDesignName,
    );
    _push();
  }

  /// Push the dedicated full-list "Recent projects" screen. Open /
  /// create still flow back through this object so navigation
  /// stays in one place.
  void openRecentAll() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            RecentProjectsScreen(onCreate: createNew, onOpen: openProject),
      ),
    );
  }

  /// "Try a sample" path for first-time users: seeds an opinionated
  /// 1080-square demo document with a tinted shape and a heading
  /// text layer so the user sees something *editable* without
  /// having to import their own photo or pick a template.
  ///
  /// Why this exists separately from [createNew] / [openTemplate]:
  /// new users with an empty Recent rail otherwise face a blank
  /// canvas (intimidating) or a templates browser (commitment).
  /// A pre-populated demo is the lowest-friction on-ramp — they
  /// can drag, scale, recolour, undo, and discover the editor's
  /// shape *before* committing their own content.
  ///
  /// The sample is an EditorSession with no [Project] id, so the
  /// autosave controller will not pollute the Recent rail. If the
  /// user genuinely wants to keep it they can hit Save explicitly
  /// — the same rule [importPhoto] uses for picked photos.
  void openSample() {
    unawaited(preserveOrphanDraft());
    final l10n = context.l10n;
    const canvas = Size(1080, 1080);

    final docCtrl = ref.read(documentControllerProvider.notifier);
    docCtrl.newDocument(width: canvas.width, height: canvas.height);

    // A circle accent in the upper third + a heading text below.
    // Kept tiny so the user sees the editor, not a finished design.
    final shapeId = _uuid.v4();
    final textId = _uuid.v4();
    docCtrl.execute(
      CompositeCommand([
        AddLayerCommand(
          ShapeLayer(
            id: shapeId,
            transform: const LayerTransform(
              position: Offset(390, 220),
              size: Size(300, 300),
            ),
            kind: ShapeKind.circle,
            // Saffron — the demo doc should showcase the brand
            // accent, not the retired violet.
            fillColor: const Color(0xFFE5A044),
          ),
        ),
        AddLayerCommand(
          TextLayer(
            id: textId,
            transform: const LayerTransform(
              position: Offset(140, 600),
              size: Size(800, 220),
            ),
            content: 'Hello, Canvas',
            style: const TextStyleSpec(
              fontSize: 96,
              color: Color(0xFF1A1A1F),
              fontWeight: FontWeight.w800,
              alignment: TextAlign.center,
            ),
          ),
        ),
      ], labelOverride: l10n.sampleCommand),
    );
    docCtrl.clearHistory();
    ref.read(selectionControllerProvider.notifier).clear();
    ref.read(editorSessionProvider.notifier).state = EditorSession(
      name: l10n.sampleName,
    );
    _push();
  }

  // ───────────────────────── internals ─────────────────────────────

  void _seedAndOpen({
    required double width,
    required double height,
    required String name,
  }) {
    unawaited(preserveOrphanDraft());
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
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const EditorScreen()))
        .then((_) {
          // Editor popped. Home never remounts (it lives in the
          // shell's IndexedStack), so its once-per-mount draft offer
          // would otherwise never re-run — yet this is exactly the
          // moment a surviving draft journal (back-out of an unsaved
          // session) needs a resume offer. Bump the tick; HomeScreen
          // listens and re-checks the slot.
          if (context.mounted) {
            ref.read(draftOfferTickProvider.notifier).bump();
          }
        });
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
