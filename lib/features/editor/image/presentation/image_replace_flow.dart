import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' as picker;

import '../../../../core/constants/engine_constants.dart';
import '../../../../core/utils/haptics.dart';
import '../../presentation/widgets/editor_modal_sheet.dart';
import '../../../../core/utils/user_error.dart';
import '../../../../l10n/l10n.dart';
import '../../application/document_controller.dart';
import '../../application/image_import_service.dart';
import '../../application/selection_controller.dart';
import '../../engine/commands/image_commands.dart';
import '../../engine/modules/image/image_layer.dart';
import '../../../../app/theme/app_icons.dart';

bool imageSourceIsKnownUnavailable(ImageSource source) {
  final path = source.filePath;
  if (path == null) return false;
  return !File(path).existsSync();
}

String imageReplacementActionLabel(BuildContext context, ImageLayer layer) {
  return imageSourceIsKnownUnavailable(layer.source)
      ? context.l10n.relinkImageAction
      : context.l10n.replaceImageAction;
}

Future<void> replaceImageLayer(
  BuildContext context,
  WidgetRef ref,
  ImageLayer layer, {
  String debugLabel = 'image/replaceImageLayer',
}) async {
  EditorHaptics.tap();
  final source = await _pickImageSource(context, layer);
  if (source == null || !context.mounted) return;

  final pick = picker.ImagePicker();
  final picker.XFile? picked;
  try {
    picked = await pick.pickImage(
      source: source,
      imageQuality: 92,
      // Longest-side import ceiling — the OS downscales
      // aspect-preserving before the bitmap enters the app. See
      // [EngineConstants.kMaxImportDimension].
      maxWidth: EngineConstants.kMaxImportDimension,
      maxHeight: EngineConstants.kMaxImportDimension,
    );
  } catch (e, st) {
    debugLogError('$debugLabel/pickImage', e, st);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          userMessageFor(
            e,
            fallback: context.l10n.couldntOpenPhoto,
            permissionDeniedMessage: context.l10n.allowPhotoAccessSettings,
            genericMessage: context.l10n.somethingWentWrong,
          ),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }
  if (picked == null) return;

  final stable = await persistPickedImage(picked.path);
  if (!context.mounted) return;
  ref
      .read(documentControllerProvider.notifier)
      .execute(
        ReplaceImageSourceCommand(
          layerId: layer.id,
          source: ImageSource.file(stable),
        ),
      );
  ref.read(selectionControllerProvider.notifier).select(layer.id);
}

Future<picker.ImageSource?> _pickImageSource(
  BuildContext context,
  ImageLayer layer,
) {
  final l10n = context.l10n;
  final title = imageReplacementActionLabel(context, layer);
  // FULL barrier (contract §9: list sheets). Card + handle come
  // from the shared modal host (tb2 8/16).
  return showEditorSheet<picker.ImageSource>(
    context,
    builder: (ctx) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(
              imageSourceIsKnownUnavailable(layer.source)
                  ? AppIcons.imageSourceUnavailable
                  : AppIcons.replace,
            ),
            title: Text(title),
            subtitle: imageSourceIsKnownUnavailable(layer.source)
                ? Text(l10n.imageUnavailableLabel)
                : null,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(AppIcons.photoLibrary),
            title: Text(l10n.galleryAction),
            onTap: () {
              EditorHaptics.tap();
              Navigator.pop(ctx, picker.ImageSource.gallery);
            },
          ),
          ListTile(
            leading: const Icon(AppIcons.camera),
            title: Text(l10n.cameraAction),
            onTap: () {
              EditorHaptics.tap();
              Navigator.pop(ctx, picker.ImageSource.camera);
            },
          ),
          const SizedBox(height: 8),
        ],
      );
    },
  );
}
