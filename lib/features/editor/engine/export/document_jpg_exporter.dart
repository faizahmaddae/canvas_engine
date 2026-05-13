import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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

  /// Engine-side default JPEG quality (95 / 100). Mirrors the UI
  /// default but lives here so the exporter is usable without UI.
  ///
  /// Picked at 95 because below ~92 visible blocking artefacts
  /// appear on smooth gradients (skin tones, sky) at typical
  /// screen viewing distances; pro editors (Lightroom, Affinity)
  /// default in the 95–98 range. The marginal file-size cost
  /// 90—95 is small relative to the perceptual gain.
  static const int defaultQuality = 95;

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
  ///
  /// **Off-thread.** The actual JPEG encode runs on a background
  /// isolate via [compute]. JPEG encoding is a CPU-bound DCT pass
  /// over every pixel; for a 12 MP image this can take 200–400 ms
  /// on a mid-range phone — long enough to drop frames if it ran on
  /// the UI thread. The raw RGBA bytes are copied across the
  /// isolate boundary (~48 MB for 12 MP), which costs a few extra
  /// ms but is far cheaper than the encode itself.
  static Future<Uint8List> encodeImageAsJpg(
    ui.Image image, {
    int quality = defaultQuality,
  }) async {
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      throw const DocumentExportException(
        'toImage returned null — render produced no pixels',
      );
    }
    return compute(
      _encodeJpgIsolate,
      _JpgEncodePayload(
        rgba: byteData.buffer.asUint8List(),
        width: image.width,
        height: image.height,
        quality: quality.clamp(1, 100),
      ),
    );
  }
}

/// Top-level isolate-friendly args for [_encodeJpgIsolate]. Has to
/// be a simple data carrier because Flutter's [compute] argument
/// must be transferable across isolate boundaries.
class _JpgEncodePayload {
  const _JpgEncodePayload({
    required this.rgba,
    required this.width,
    required this.height,
    required this.quality,
  });
  final Uint8List rgba;
  final int width;
  final int height;
  final int quality;
}

/// Top-level so it can be sent to a background isolate. Decodes the
/// raw RGBA buffer into an [img.Image] and runs the JPEG encoder.
Uint8List _encodeJpgIsolate(_JpgEncodePayload p) {
  final imgImage = img.Image.fromBytes(
    width: p.width,
    height: p.height,
    bytes: p.rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(imgImage, quality: p.quality);
}
