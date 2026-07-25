import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/engine_constants.dart';

const _uuid = Uuid();

/// Application-layer image-import primitives shared by every flow
/// that lets the user pick a photo (editor "Add image", image-layer
/// "Replace"): natural-size resolution and stable on-disk
/// persistence. Extracted out of `editor_screen.dart` (Phase 4 plan
/// §5.2) — presentation code should not own file IO.
///
/// Each caller keeps its own orchestration and policy
/// (`_addImage`'s base-photo-claim logic, `replaceImageLayer`'s
/// relink messaging) — only the mechanical IO steps are shared here.

/// The source-picker sheet used to live here and, because this is the
/// APPLICATION layer, it could not reach the presentation layer's
/// shared sheet host — so it shipped as bare stock Material chrome.
/// tb2 8/16 recorded the relocation as the real fix; it now lives at
/// `presentation/widgets/image_source_sheet.dart`. This file keeps
/// only the mechanical IO it was extracted to own.

/// Aspect-preserving longest-side cap for imported photos
/// ([EngineConstants.kMaxImportDimension], tb3 7/7).
///
/// The heavy lifting happens in image_picker: every `pickImage` call
/// passes `maxWidth`/`maxHeight` so oversized photos are downscaled
/// by the OS BEFORE the bitmap enters the app. This pure helper is
/// the belt-and-braces companion for the dimensions the app then
/// derives (photo-project document size, image-layer natural size):
/// if a decoder path ever slips past the picker cap (platform quirk,
/// future import channel), the derived geometry still lands inside
/// the ceiling. Sizes at or under the cap pass through unchanged —
/// imports are never upscaled.
Size capImportSize(Size natural) {
  final longest = math.max(natural.width, natural.height);
  if (longest <= EngineConstants.kMaxImportDimension || longest <= 0) {
    return natural;
  }
  final f = EngineConstants.kMaxImportDimension / longest;
  return Size(
    (natural.width * f).roundToDouble().clamp(1, double.infinity),
    (natural.height * f).roundToDouble().clamp(1, double.infinity),
  );
}

/// Resolve the natural pixel size of [file] without decoding it
/// fully into a widget tree.
Future<Size> resolveImageSize(File file) {
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

/// Copy [tempPath] into app-documents so the image survives the OS
/// clearing the picker temp dir.
Future<String> persistPickedImage(String tempPath) async {
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
