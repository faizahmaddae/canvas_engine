import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/core/editor_document.dart';
import '../engine/export/document_jpg_exporter.dart';
import '../engine/export/document_png_exporter.dart';
import 'document_controller.dart';
import 'export_format.dart';

/// Application-facing service for exporting the current document.
///
/// Pure delegation to the engine exporters — it exists so presentation
/// code never reaches into the engine directly, mirroring the
/// `exportJson` / `importJson` shape on [DocumentController].
class ExportController {
  const ExportController(this._ref);

  final Ref _ref;

  /// Render the current document at [pixelRatio] in the requested
  /// [format]. For [ExportFormat.jpg], [jpgQuality] is the 0.0..1.0
  /// fraction surfaced to users; PNG ignores it.
  ///
  /// Quality and pixelRatio are independent: pixelRatio controls
  /// raster dimensions, quality controls JPEG compression only.
  ///
  /// [background] is the solid colour painted under the layers when
  /// the document is opaque (or as a JPG flatten / `targetSize`
  /// letterbox). Pass `null` (the default) to use the document's
  /// own [EditorDocument.backgroundColor] — callers should leave
  /// this null so the exported image always matches the editor
  /// canvas. Hardcoded values are reserved for explicit overrides
  /// (e.g. an export-to-Instagram-feed preset that wants white).
  ///
  /// [targetSize] is the optional fixed output rectangle (e.g. a
  /// 1080×1920 Story preset). When supplied:
  ///   * the document is rendered at the smallest pixelRatio that
  ///     still resolves to the destination rect at full sharpness
  ///     (clamped to ≥ 1.0 so we never up-sample beyond the canvas
  ///     resolution itself);
  ///   * it is composited into a new image of exactly [targetSize]
  ///     using `BoxFit.contain` math (no stretching);
  ///   * any letterbox bands are filled with [background].
  ///   * [pixelRatio] is **ignored** — the output rect is fixed.
  /// When `null`, the export uses the canvas size × [pixelRatio]
  /// (the existing behaviour).
  Future<Uint8List> exportImage({
    required BuildContext context,
    required ExportFormat format,
    double pixelRatio = DocumentPngExporter.defaultPixelRatio,
    double jpgQuality = 0.9,
    Color? background,
    ui.Size? targetSize,
  }) async {
    final EditorDocument doc = _ref.read(documentControllerProvider);
    // Resolve the fill the exporter should paint:
    //  * explicit Color override → wrap into SolidBackground
    //  * else → the document's own BackgroundFill (preserves gradients)
    final BackgroundFill effectiveFill = background != null
        ? SolidBackground(color: background)
        : doc.background;
    // Legacy solid colour for the letterbox / JPG flatten composite
    // path which still needs a single Color (gradients are baked into
    // the *source* image; the surround stays solid).
    // ignore: deprecated_member_use
    final Color effectiveBackground = background ?? doc.backgroundColor;
    if (targetSize != null) {
      return _exportToTarget(
        context: context,
        document: doc,
        format: format,
        target: targetSize,
        background: effectiveBackground,
        backgroundFill: effectiveFill,
        jpgQuality: jpgQuality,
      );
    }
    switch (format) {
      case ExportFormat.png:
        return DocumentPngExporter.export(
          context: context,
          document: doc,
          pixelRatio: pixelRatio,
          background: effectiveBackground,
          backgroundFill: effectiveFill,
        );
      case ExportFormat.jpg:
        return DocumentJpgExporter.export(
          context: context,
          document: doc,
          pixelRatio: pixelRatio,
          quality: (jpgQuality.clamp(0.0, 1.0) * 100).round(),
          background: effectiveBackground,
          backgroundFill: effectiveFill,
        );
    }
  }

  /// Back-compat shortcut for PNG-only callers / tests.
  Future<Uint8List> exportPng({
    required BuildContext context,
    double pixelRatio = DocumentPngExporter.defaultPixelRatio,
    Color? background,
  }) {
    return exportImage(
      context: context,
      format: ExportFormat.png,
      pixelRatio: pixelRatio,
      background: background,
    );
  }

  /// Render [document] into an image of exactly [target] pixels using
  /// `BoxFit.contain` math (centre + letterbox). Encodes the result
  /// to [format]'s byte representation.
  ///
  /// Pure composition step on top of the existing engine — the engine
  /// exporters remain unchanged and simply hand back a `ui.Image`.
  Future<Uint8List> _exportToTarget({
    required BuildContext context,
    required EditorDocument document,
    required ExportFormat format,
    required ui.Size target,
    required Color background,
    required BackgroundFill backgroundFill,
    required double jpgQuality,
  }) async {
    // Safety: if the requested target rect itself exceeds the engine
    // export cap, shrink it proportionally before rasterising. The
    // alternative (clamping only the source pixelRatio) would leave
    // the composer allocating a huge destination image and OOM on
    // low-end devices.
    final effectiveTarget = clampTargetSizeForExport(target: target);

    // Choose source raster ratio = the scale factor needed to fill
    // the target rect, clamped so we never up-sample beyond canvas
    // resolution (no value in spending memory on resolution we
    // don't have) and capped at 4× to avoid pathological memory.
    final scale = _fitScale(
      sourceW: document.width,
      sourceH: document.height,
      targetW: effectiveTarget.width,
      targetH: effectiveTarget.height,
    );
    final captureRatio = scale.clamp(1.0, 4.0);

    final source = await DocumentPngExporter.captureRawImage(
      context: context,
      document: document,
      pixelRatio: captureRatio,
      background: background,
      backgroundFill: backgroundFill,
      // Always honour transparent mode for the *source* — the
      // composite step paints the background once underneath, so
      // double-painting it would tint translucent pixels.
      honorTransparentMode: true,
    );
    try {
      final composed = await composeFitContain(
        source: source,
        target: effectiveTarget,
        background: background,
        // PNG keeps alpha; JPG must composite over an opaque fill.
        opaqueBackground:
            format == ExportFormat.jpg ||
            document.backgroundMode == CanvasBackgroundMode.color,
      );
      try {
        switch (format) {
          case ExportFormat.png:
            final byteData = await composed.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (byteData == null) {
              throw const DocumentExportException(
                'toByteData returned null — composed image has no pixels',
              );
            }
            return byteData.buffer.asUint8List();
          case ExportFormat.jpg:
            return DocumentJpgExporter.encodeImageAsJpg(
              composed,
              quality: (jpgQuality.clamp(0.0, 1.0) * 100).round(),
            );
        }
      } finally {
        composed.dispose();
      }
    } finally {
      source.dispose();
    }
  }

  /// Shrink [target] proportionally so its pixel area never exceeds
  /// the running device's effective export ceiling
  /// ([DocumentPngExporter.devicePixelCap]). Aspect ratio preserved;
  /// returns [target] unchanged when it already fits.
  static ui.Size clampTargetSizeForExport({
    required ui.Size target,
    int? maxPixels,
  }) {
    final pixels = target.width * target.height;
    if (pixels <= 0) return target;
    final cap = maxPixels ?? DocumentPngExporter.devicePixelCap();
    if (pixels <= cap) return target;
    final shrink = math.sqrt(cap / pixels);
    return ui.Size(target.width * shrink, target.height * shrink);
  }

  /// True when the current document + a fixed export target would be
  /// downscaled by the device-aware export cap. UI uses this to
  /// surface a "saved at reduced resolution" notice.
  ///
  /// When [target] is null the check is performed on the canvas size
  /// at [pixelRatio]; otherwise the target rect itself is checked.
  bool willReduceResolution({
    required EditorDocument document,
    required double pixelRatio,
    ui.Size? target,
  }) {
    if (target != null) {
      return target.width * target.height >
          DocumentPngExporter.devicePixelCap();
    }
    return DocumentPngExporter.willReducePixelRatio(
      width: document.width,
      height: document.height,
      requested: pixelRatio,
    );
  }

  /// `BoxFit.contain` scale factor — the min of horizontal/vertical
  /// fit ratios.
  static double _fitScale({
    required double sourceW,
    required double sourceH,
    required double targetW,
    required double targetH,
  }) {
    if (sourceW <= 0 || sourceH <= 0) return 1.0;
    final sx = targetW / sourceW;
    final sy = targetH / sourceH;
    return sx <= sy ? sx : sy;
  }
}

/// Paint [source] into a fresh image of [target] pixels, fitted
/// (`BoxFit.contain`) and centred. Letterbox bands receive [background]
/// when [opaqueBackground] is true; otherwise the bands stay
/// transparent (PNG with transparent canvas mode).
///
/// Top-level so widget tests can drive the composer with a synthesised
/// [ui.Image] without spinning up the off-screen overlay path.
Future<ui.Image> composeFitContain({
  required ui.Image source,
  required ui.Size target,
  required Color background,
  required bool opaqueBackground,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, target.width, target.height),
  );

  if (opaqueBackground) {
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, target.width, target.height),
      ui.Paint()..color = background,
    );
  }

  final scaleX = target.width / source.width;
  final scaleY = target.height / source.height;
  final scale = scaleX <= scaleY ? scaleX : scaleY;
  final destW = source.width * scale;
  final destH = source.height * scale;
  final destLeft = (target.width - destW) / 2;
  final destTop = (target.height - destH) / 2;

  canvas.drawImageRect(
    source,
    ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    ui.Rect.fromLTWH(destLeft, destTop, destW, destH),
    ui.Paint()
      ..filterQuality = ui.FilterQuality.high
      ..isAntiAlias = true,
  );

  final picture = recorder.endRecording();
  try {
    return await picture.toImage(target.width.round(), target.height.round());
  } finally {
    picture.dispose();
  }
}

final exportControllerProvider = Provider<ExportController>(
  ExportController.new,
);
