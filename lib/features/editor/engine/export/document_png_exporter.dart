import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../core/editor_document.dart';
import '../rendering/document_view.dart';
import 'png_color_space.dart';

/// Thrown when the document cannot be rasterised. Wraps the underlying
/// engine cause (timeout, missing render boundary, etc.) so callers
/// only need a single `try/catch`.
class DocumentExportException implements Exception {
  const DocumentExportException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'DocumentExportException: $message'
      : 'DocumentExportException: $message ($cause)';
}

/// Headless PNG exporter for [EditorDocument].
///
/// Architecturally separate from any editor widget: it builds a fresh
/// [DocumentView] inside an [OverlayEntry], waits for one frame, snapshots
/// the [RepaintBoundary] via `toImage`, then removes the entry. Selection
/// chrome, handles, snap guides, mode chips and the viewport transform
/// are *not* part of [DocumentView], so they cannot leak into the output.
///
/// **Color-space contract.** The captured pixels are sRGB-encoded,
/// premultiplied-alpha (matches the on-screen `DocumentView` contract;
/// see `docs/effects.md` §6). PNGs are post-processed via
/// [tagPngAsSrgb] to embed an `sRGB` (+ `gAMA`) chunk so wide-gamut
/// viewers (iOS Photos, macOS Preview on a Display-P3 device) don't
/// expand the untagged content into the device's gamut. The pixels
/// themselves remain plain sRGB; this is the right answer today and
/// matches the rendering math of every shipped effect. A wide-gamut
/// / HDR pipeline is a future change tracked in `docs/effects.md`.
///
/// Two entry points:
///
///   * [export] — high-level. Mounts and captures in one call. Requires
///     a live [BuildContext] to reach the [Overlay].
///   * [captureBoundary] — low-level. Snapshots an existing
///     [RepaintBoundary] identified by [GlobalKey]. Tests and custom
///     hosts (e.g. an off-screen `RenderRepaintBoundary` driven by a
///     `pumpWidget` harness) use this directly.
class DocumentPngExporter {
  DocumentPngExporter._();

  /// Default device-pixel ratio used when the caller does not supply
  /// one. Two is high-enough for crisp output on retina displays
  /// without ballooning file size.
  static const double defaultPixelRatio = 2.0;

  /// Hard ceiling on the pixel count of a single rasterised export.
  ///
  /// 24 megapixels (≈ 6000 × 4000) is well under iOS / Android
  /// per-process graphics-memory limits even when the image is
  /// briefly held alongside the encoded byte buffer:
  ///
  ///   24 000 000 px × 4 B (RGBA) ≈ 91 MB raw,
  ///   plus ≈ 30–60 MB encoded PNG / JPEG = ≈ 150 MB peak.
  ///
  /// Above this, low-end Android devices reliably OOM during
  /// `toImage` or PNG encoding. Callers that exceed the cap have
  /// their `pixelRatio` (or composite `target` size) silently scaled
  /// down to fit, with aspect ratio preserved.
  static const int maxOutputPixels = 24 * 1000 * 1000;

  /// Lower bound for the device-aware cap. Even a tiny / unknown
  /// screen still allows ≈ 16 MB raw — enough for a 2K square
  /// thumbnail — so cheap thumbnail rasters are never starved.
  static const int _minDeviceCapPixels = 4 * 1000 * 1000;

  /// Multiplier applied to the device's screen pixel count to derive
  /// a per-device export ceiling. 8× covers every realistic share
  /// resolution (a 1080p phone → ≈ 16 Mpx cap, an iPad Pro → hits the
  /// global 24 Mpx ceiling) while still pulling low-end / small
  /// devices well below the absolute maximum.
  static const int _deviceCapMultiplier = 8;

  /// Effective per-export pixel ceiling, taking the running device's
  /// physical screen size into account. Returns the smaller of the
  /// global [maxOutputPixels] and `screenPixels × _deviceCapMultiplier`,
  /// floored at [_minDeviceCapPixels]. Falls back to the global
  /// constant when no view is available (headless tests, isolates).
  ///
  /// Pure function of `PlatformDispatcher.implicitView`; no platform
  /// channels, no allocations beyond a couple of doubles.
  static int devicePixelCap() {
    final view = ui.PlatformDispatcher.instance.implicitView;
    if (view == null) return maxOutputPixels;
    final size = view.physicalSize;
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      return maxOutputPixels;
    }
    final screenPixels = (size.width * size.height).round();
    final scaled = screenPixels * _deviceCapMultiplier;
    final capped = scaled < maxOutputPixels ? scaled : maxOutputPixels;
    return capped < _minDeviceCapPixels ? _minDeviceCapPixels : capped;
  }

  /// Largest [pixelRatio] that keeps a [width] × [height] document
  /// under [maxPixels]. Returns [requested] unchanged when the
  /// requested ratio already fits.
  ///
  /// Aspect ratio is preserved automatically because the same scalar
  /// multiplies both dimensions.
  ///
  /// When [maxPixels] is omitted, the device-aware [devicePixelCap]
  /// is used instead of the static [maxOutputPixels] — this gives
  /// low-end devices a tighter ceiling without penalising tablets.
  /// Tests can pin the cap by passing [maxPixels] explicitly.
  static double clampPixelRatio({
    required double width,
    required double height,
    required double requested,
    int? maxPixels,
  }) {
    if (width <= 0 || height <= 0 || requested <= 0) return requested;
    final canvasPixels = width * height;
    if (canvasPixels <= 0) return requested;
    final cap = maxPixels ?? devicePixelCap();
    final maxRatio = math.sqrt(cap / canvasPixels);
    return requested > maxRatio ? maxRatio : requested;
  }

  /// True when [requested] would be reduced by [clampPixelRatio]
  /// for a [width] × [height] document. Useful for surfacing a
  /// "exporting at reduced resolution" notice in the UI before
  /// kicking off the (potentially expensive) export.
  static bool willReducePixelRatio({
    required double width,
    required double height,
    required double requested,
    int? maxPixels,
  }) {
    final clamped = clampPixelRatio(
      width: width,
      height: height,
      requested: requested,
      maxPixels: maxPixels,
    );
    // Tolerance for floating-point round-trips: only flag changes the
    // user would actually perceive in the output rect.
    return (requested - clamped) > 1e-6;
  }

  /// Render [document] to a PNG byte buffer.
  ///
  /// [pixelRatio] controls the output resolution: the resulting image
  /// has dimensions `document.width * pixelRatio` × `document.height *
  /// pixelRatio`. Use higher values for print/share quality.
  ///
  /// [background] is the solid backdrop painted under the layers when
  /// the document's [EditorDocument.backgroundMode] is
  /// [CanvasBackgroundMode.color]. When the mode is
  /// [CanvasBackgroundMode.transparent] the backdrop is skipped and
  /// the PNG carries real alpha through to disk.
  ///
  /// Throws [DocumentExportException] if the overlay can't be reached
  /// or the snapshot fails.
  static Future<Uint8List> export({
    required BuildContext context,
    required EditorDocument document,
    double pixelRatio = defaultPixelRatio,
    Color background = const Color(0xFFFFFFFF),
    BackgroundFill? backgroundFill,
  }) async {
    final image = await captureRawImage(
      context: context,
      document: document,
      pixelRatio: pixelRatio,
      background: background,
      backgroundFill: backgroundFill,
      // PNG supports alpha -- let the document's mode decide
      // whether a backdrop is painted at all.
      honorTransparentMode: true,
    );
    try {
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw const DocumentExportException(
          'toByteData returned null — render produced no pixels',
        );
      }
      // Flutter's PNG encoder writes no colour-space chunks; tag the
      // bytes as sRGB so iOS Photos.app and other wide-gamut viewers
      // don't expand the file into the device's gamut. See
      // [tagPngAsSrgb] for the rationale.
      return tagPngAsSrgb(byteData.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }

  /// Mount an off-screen [DocumentView], wait one frame, snapshot it
  /// into a [ui.Image] and return ownership to the caller.
  ///
  /// This is the shared engine path used by both [DocumentPngExporter]
  /// (for PNG encoding) and `DocumentJpgExporter` (for JPEG encoding).
  /// Encoding stays per-format; rasterisation is identical.
  ///
  /// **The caller MUST call `dispose()` on the returned image** to
  /// release native graphics memory.
  static Future<ui.Image> captureRawImage({
    required BuildContext context,
    required EditorDocument document,
    double pixelRatio = defaultPixelRatio,
    Color background = const Color(0xFFFFFFFF),
    BackgroundFill? backgroundFill,
    bool honorTransparentMode = false,
  }) async {
    // Safety: clamp the requested pixelRatio so a huge canvas never
    // allocates a backing image that ODs the device's graphics
    // memory budget. This is the single choke-point for every
    // exporter (PNG / JPG / thumbnail / project save) so capping
    // here is enough — callers don't have to remember to clamp.
    final effectiveRatio = clampPixelRatio(
      width: document.width,
      height: document.height,
      requested: pixelRatio,
    );
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      throw const DocumentExportException(
        'no Overlay in BuildContext — cannot mount export surface',
      );
    }

    final boundaryKey = GlobalKey();
    final completer = Completer<void>();
    final entry = OverlayEntry(
      // Off-screen positioning keeps the export surface invisible to
      // the user during the single frame it lives on the overlay. We
      // intentionally do *not* use `Offstage` (skips paint, breaks
      // toImage) or `Opacity(0)` (still triggers compositing).
      builder: (_) => Positioned(
        left: -document.width * effectiveRatio - 100,
        top: -document.height * effectiveRatio - 100,
        child: _ExportHost(
          boundaryKey: boundaryKey,
          document: document,
          background: background,
          backgroundFill: backgroundFill,
          honorTransparentMode: honorTransparentMode,
          onMounted: () {
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    );
    overlay.insert(entry);

    try {
      // Wait for the overlay frame to be built + painted. Without
      // this, the boundary's render object exists but has no
      // composited layer yet, and `toImage` returns a blank PNG.
      await completer.future;
      await _waitForFrame();

      final renderObject = boundaryKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        throw const DocumentExportException(
          'boundary key is not attached to a RenderRepaintBoundary',
        );
      }
      try {
        return await renderObject.toImage(pixelRatio: effectiveRatio);
      } on DocumentExportException {
        rethrow;
      } catch (e) {
        throw DocumentExportException('snapshot failed', e);
      }
    } finally {
      entry.remove();
    }
  }

  /// Snapshot an existing [RepaintBoundary] (identified by
  /// [boundaryKey]) to PNG bytes at [pixelRatio]. The caller is
  /// responsible for ensuring the widget is mounted and laid out.
  ///
  /// Surfaces a [DocumentExportException] for every failure mode:
  /// missing key, wrong render-object type, or `toByteData` returning
  /// null (which Flutter does for zero-area renders).
  static Future<Uint8List> captureBoundary({
    required GlobalKey boundaryKey,
    double pixelRatio = defaultPixelRatio,
  }) async {
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw const DocumentExportException(
        'boundary key is not attached to a RenderRepaintBoundary',
      );
    }
    ui.Image? image;
    try {
      image = await renderObject.toImage(pixelRatio: pixelRatio);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw const DocumentExportException(
          'toByteData returned null — render produced no pixels',
        );
      }
      return byteData.buffer.asUint8List();
    } on DocumentExportException {
      rethrow;
    } catch (e) {
      throw DocumentExportException('snapshot failed', e);
    } finally {
      image?.dispose();
    }
  }

  /// Wait for the next frame to be both built and painted. Uses a
  /// post-frame callback rather than `endOfFrame` because the latter
  /// can return *before* the layer tree is fully composited on some
  /// platforms.
  static Future<void> _waitForFrame() {
    final completer = Completer<void>();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      completer.complete();
    });
    SchedulerBinding.instance.scheduleFrame();
    return completer.future;
  }
}

/// Internal host widget for the off-screen export surface. Wraps the
/// [DocumentView] in a [RepaintBoundary] (so we have something to
/// snapshot) and the minimum [MediaQuery] / [Directionality] /
/// [Material] ambient widgets that Material descendants (Image, Text)
/// expect to find above them.
class _ExportHost extends StatefulWidget {
  const _ExportHost({
    required this.boundaryKey,
    required this.document,
    required this.background,
    required this.backgroundFill,
    required this.honorTransparentMode,
    required this.onMounted,
  });

  final GlobalKey boundaryKey;
  final EditorDocument document;
  final Color background;
  final BackgroundFill? backgroundFill;
  final bool honorTransparentMode;
  final VoidCallback onMounted;

  @override
  State<_ExportHost> createState() => _ExportHostState();
}

class _ExportHostState extends State<_ExportHost> {
  @override
  void initState() {
    super.initState();
    // Defer until after the first frame so the RepaintBoundary's render
    // object exists when the exporter tries to find it.
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onMounted());
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        // Force a 1.0 device-pixel ratio so layout maths stay in logical
        // pixels and `pixelRatio` on `toImage` is the *only* knob that
        // controls output resolution.
        data: const MediaQueryData(),
        child: Material(
          type: MaterialType.transparency,
          child: RepaintBoundary(
            key: widget.boundaryKey,
            child: DocumentView(
              document: widget.document,
              backgroundFill: widget.backgroundFill,
              // ignore: deprecated_member_use
              background: widget.background,
              honorTransparentMode: widget.honorTransparentMode,
            ),
          ),
        ),
      ),
    );
  }
}
