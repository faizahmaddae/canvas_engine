import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'image_layer.dart';

/// The ONE mapping from an [ImageSource] to a Flutter [ImageProvider]
/// (tb5 8/9).
///
/// There were four copies — the canvas layer, the layer thumbnail,
/// the Look panel's filter chips and the crop preview — and they had
/// already drifted apart in three ways that matter:
///
///   * two checked whether a file exists before building a provider,
///     two did not, so a relinked-but-missing photo rendered as a
///     broken box in one surface and a placeholder in another;
///   * one guarded `kIsWeb` before touching `dart:io`, the others
///     would have thrown there;
///   * they disagreed about precedence when a source carries more
///     than one field.
///
/// Precedence here is asset → network → file, matching the canvas
/// (which is the surface users judge everything else against).
ImageProvider? imageProviderFor(ImageSource source, {int? decodeWidth}) {
  final asset = source.assetName;
  final url = source.networkUrl;
  final path = source.filePath;

  ImageProvider? base;
  if (asset != null) {
    base = AssetImage(asset);
  } else if (url != null) {
    base = NetworkImage(url);
  } else if (path != null && !kIsWeb && imageFileExists(path)) {
    base = FileImage(File(path));
  }
  if (base == null) return null;
  if (decodeWidth == null) return base;
  return ResizeImage.resizeIfNeeded(decodeWidth, null, base);
}

/// Existence check for an imported photo, with positive results
/// memoized.
///
/// The check runs inside `build()` on the canvas's hot path, so a
/// long-lived document was paying a stat syscall per layer per frame.
/// Only `true` is cached: a file that exists stays existing for the
/// life of a session, while a MISSING one has to stay re-checkable so
/// the relink flow shows the photo the moment it lands rather than
/// after a restart.
bool imageFileExists(String path) {
  if (kIsWeb) return false;
  if (_existing.contains(path)) return true;
  final exists = File(path).existsSync();
  if (exists) _existing.add(path);
  return exists;
}

final Set<String> _existing = <String>{};

/// Drop a path from the existence memo. For tests and for any flow
/// that deletes an imported file while the app is running.
@visibleForTesting
void resetImageFileExistsCache() => _existing.clear();
