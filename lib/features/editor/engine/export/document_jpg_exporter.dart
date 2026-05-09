import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

import '../core/editor_document.dart';
import 'document_png_exporter.dart';

/// Headless JPEG exporter for [EditorDocument].
///
/// Reuses [DocumentPngExporter.captureRawImage] for the
/// rasterisation (off-screen overlay mount + boundary snapshot) and
/// only differs in the encoding step: the captured [ui.Image] is
/// converted to raw RGBA, wrapped in `package:image`'s [img.Image],
/// and encoded by [img.JpegEncoder].
///
/// Quality vs. resolution are independent knobs:
///   * `pixelRatio` → raster dimensions, identical semantics to PNG.
///   * `quality` → JPEG compression (1..100). The app-layer surface
///     accepts a 0.0..1.0 fraction; this engine takes the int directly
///     to keep the engine free of UI concerns.
class DocumentJpgExporter {
  DocumentJpgExporter._();

  /// Engine-side default JPEG quality (90 / 100). Mirrors the UI
  /// default but lives here so the exporter is usable without UI.
  static const int defaultQuality = 90;

  /// Render [document] to JPEG bytes.
  ///
  /// [pixelRatio] — raster resolution multiplier; same semantics as
  ///   [DocumentPngExporter.export].
  /// [quality] — JPEG quality, clamped to 1..100. Higher = larger file.
  /// [background] — solid backdrop. JPEG has no alpha channel, so a
  ///   non-opaque background gets composited over white.
  static Future<Uint8List> export({
    required BuildContext context,
    required EditorDocument document,
    double pixelRatio = DocumentPngExporter.defaultPixelRatio,
    int quality = defaultQuality,
    Color background = const Color(0xFFFFFFFF),
    BackgroundFill? backgroundFill,
  }) async {
    final clampedQuality = quality.clamp(1, 100);
    final image = await DocumentPngExporter.captureRawImage(
      context: context,
      document: document,
      pixelRatio: pixelRatio,
      background: background,
      backgroundFill: backgroundFill,
    );
    try {
      return await encodeImageAsJpg(image, quality: clampedQuality);
    } finally {
      image.dispose();
    }
  }

  /// Encode an existing [ui.Image] as JPEG. Exposed so tests and
  /// custom hosts can drive their own rasterisation while reusing the
  /// JPEG encode pipeline.
  static Future<Uint8List> encodeImageAsJpg(
    ui.Image image, {
    int quality = defaultQuality,
  }) async {
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      throw const DocumentExportException(
        'toByteData returned null — render produced no pixels',
      );
    }
    final imgImage = img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: byteData.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return img.encodeJpg(imgImage, quality: quality.clamp(1, 100));
  }
}
