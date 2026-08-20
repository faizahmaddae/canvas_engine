import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/user_error.dart';
import 'export_format.dart';

/// Outcome of a save-or-share request, surfaced to presentation as a
/// flat sealed enum so the UI can render success/error/permission
/// messaging without needing to catch typed exceptions.
///
/// [cancelled] is the user closing the system share sheet without
/// picking a target: not a success (nothing left the device — a
/// "Shared!" toast would be a lie) and not an error (nothing to fix
/// or retry loudly). Presentation stays quiet and keeps the flow
/// alive. [unavailable] is the platform reporting share is not
/// possible at all — actionable copy, distinct from a generic
/// failure.
enum ImageExportOutcome {
  success,
  cancelled,
  permissionDenied,
  unavailable,
  failed,
}

class ImageExportResult {
  const ImageExportResult(this.outcome);

  final ImageExportOutcome outcome;

  bool get isSuccess => outcome == ImageExportOutcome.success;
}

/// Application-layer service that takes raw PNG bytes (produced by
/// [ExportController]) and either persists them to the user's photo
/// library or hands them off to the system share sheet.
///
/// All platform-specific concerns live here:
///   * [Gal] handles iOS Photos / Android MediaStore writes including
///     permission prompts (NSPhotoLibraryAddUsageDescription on iOS,
///     scoped storage on Android 10+).
///   * [SharePlus] writes a temp file under the hood and invokes the
///     system share sheet (AirDrop, WhatsApp, Telegram, Email, …).
///
/// The engine remains untouched.
class ImageExportService {
  const ImageExportService();

  /// Default album name used when saving to the iOS Photos library /
  /// Android gallery.
  static const String albumName = 'Canvas Engine';

  /// Build a deterministic, sortable filename — `design_YYYYMMDD_HHmmss.<ext>`.
  /// Uses the local clock so users see filenames that match when they
  /// saved/shared the design. Extension comes from [format].
  String buildFilename({
    DateTime? now,
    ExportFormat format = ExportFormat.png,
  }) {
    final dt = now ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${dt.year}${two(dt.month)}${two(dt.day)}_'
        '${two(dt.hour)}${two(dt.minute)}${two(dt.second)}';
    return 'design_$stamp.${format.extension}';
  }

  /// Persist [bytes] to the device photo library / gallery.
  ///
  /// Permission flow:
  ///   * On iOS, the first call triggers the system "Allow access to
  ///     Photos" prompt; subsequent denials surface as
  ///     [ImageExportOutcome.permissionDenied].
  ///   * On Android 10+ the save uses MediaStore and needs no runtime
  ///     permission. Older Android versions may prompt for storage.
  Future<ImageExportResult> saveToGallery(
    Uint8List bytes, {
    String? filename,
    ExportFormat format = ExportFormat.png,
  }) async {
    final name = filename ?? buildFilename(format: format);
    try {
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          return const ImageExportResult(ImageExportOutcome.permissionDenied);
        }
      }
      // gal infers the file type from the name's extension and adds
      // it itself if missing. Strip whichever extension we built so
      // gal doesn't end up with `design_….png.png`.
      final dotIdx = name.lastIndexOf('.');
      final bareName = dotIdx > 0 ? name.substring(0, dotIdx) : name;
      await Gal.putImageBytes(bytes, album: albumName, name: bareName);
      return const ImageExportResult(ImageExportOutcome.success);
    } on GalException catch (e, st) {
      debugLogError('imageExport/saveToGallery/gal', e, st);
      // GalException covers permission, IO and not-supported cases.
      // Presentation owns the friendly text; this service only reports
      // the outcome type and logs details for debugging.
      if (e.type == GalExceptionType.accessDenied) {
        return const ImageExportResult(ImageExportOutcome.permissionDenied);
      }
      return const ImageExportResult(ImageExportOutcome.failed);
    } catch (e, st) {
      debugLogError('imageExport/saveToGallery', e, st);
      return const ImageExportResult(ImageExportOutcome.failed);
    }
  }

  /// Hand [bytes] to the system share sheet.
  ///
  /// [shareOrigin] is required on iPad, where the sheet must be
  /// anchored to the triggering widget (passing a render-box rect
  /// avoids the "must specify popoverPresentationController" crash).
  Future<ImageExportResult> share(
    Uint8List bytes, {
    String? filename,
    String? subject,
    String? text,
    Rect? shareOrigin,
    ExportFormat format = ExportFormat.png,
  }) async {
    final name = filename ?? buildFilename(format: format);
    try {
      final file = XFile.fromData(
        bytes,
        name: name,
        mimeType: format.mimeType,
        length: bytes.length,
      );
      final params = ShareParams(
        files: [file],
        fileNameOverrides: [name],
        subject: subject,
        text: text,
        sharePositionOrigin: shareOrigin,
      );
      final result = await SharePlus.instance.share(params);
      switch (result.status) {
        case ShareResultStatus.success:
          return const ImageExportResult(ImageExportOutcome.success);
        case ShareResultStatus.dismissed:
          return const ImageExportResult(ImageExportOutcome.cancelled);
        case ShareResultStatus.unavailable:
          return const ImageExportResult(ImageExportOutcome.unavailable);
      }
    } catch (e, st) {
      debugLogError('imageExport/share', e, st);
      return const ImageExportResult(ImageExportOutcome.failed);
    }
  }
}

/// Re-export [Rect] so callers don't need a separate `dart:ui` import
/// just to pass [ImageExportService.share]'s [Rect] argument.

final imageExportServiceProvider = Provider<ImageExportService>(
  (_) => const ImageExportService(),
);
