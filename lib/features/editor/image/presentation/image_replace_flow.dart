import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' as picker;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/utils/haptics.dart';
import '../../../../core/utils/user_error.dart';
import '../../../../l10n/l10n.dart';
import '../../application/document_controller.dart';
import '../../application/selection_controller.dart';
import '../../engine/commands/image_commands.dart';
import '../../engine/modules/image/image_layer.dart';

const _uuid = Uuid();

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
    picked = await pick.pickImage(source: source, imageQuality: 92);
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

  final stable = await _persistPickedImage(picked.path);
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
  return showModalBottomSheet<picker.ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                imageSourceIsKnownUnavailable(layer.source)
                    ? Icons.link_rounded
                    : Icons.swap_horiz_rounded,
              ),
              title: Text(title),
              subtitle: imageSourceIsKnownUnavailable(layer.source)
                  ? Text(l10n.imageUnavailableLabel)
                  : null,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.galleryAction),
              onTap: () {
                EditorHaptics.tap();
                Navigator.pop(ctx, picker.ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.cameraAction),
              onTap: () {
                EditorHaptics.tap();
                Navigator.pop(ctx, picker.ImageSource.camera);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
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
