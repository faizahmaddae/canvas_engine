import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/editor_layer.dart';
import '../../core/layer_capabilities.dart';
import '../../core/layer_transform.dart';

/// Visual mask applied to an [ImageLayer]'s pixels. The transform
/// (position / size / rotation) is unaffected — the mask only
/// changes which part of the image is visible inside the layer's
/// bounds, so undo/redo, selection handles, and gestures keep
/// working unchanged.
enum ImageMask {
  /// Full rectangular bounds (the default — no clipping applied).
  original,

  /// Soft rounded corners with a consistent radius.
  rounded,

  /// Perfect circle inscribed inside the layer's shortest side.
  circle,

  /// Continuous-corner squircle (Apple-style rounded square).
  squircle,

  /// Five-point star inscribed in the layer's bounds.
  star,

  /// Heart inscribed in the layer's bounds.
  heart,
}

/// Lightweight source descriptor for an [ImageLayer]. The engine stays
/// agnostic to how pixels reach the screen — it only knows about the
/// layer's [LayerTransform] and [LayerCapabilities].
@immutable
class ImageSource {
  const ImageSource.asset(String this.assetName)
      : networkUrl = null,
        filePath = null;
  const ImageSource.network(String this.networkUrl)
      : assetName = null,
        filePath = null;

  /// Local on-device file path (e.g. one returned by `image_picker`
  /// after copying into app-documents storage). Stored as a string so
  /// the engine has no `dart:io` dependency at the type level.
  const ImageSource.file(String this.filePath)
      : assetName = null,
        networkUrl = null;

  final String? assetName;
  final String? networkUrl;
  final String? filePath;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageSource &&
          other.assetName == assetName &&
          other.networkUrl == networkUrl &&
          other.filePath == filePath;

  @override
  int get hashCode => Object.hash(assetName, networkUrl, filePath);

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (assetName != null) 'asset': assetName,
        if (networkUrl != null) 'url': networkUrl,
        if (filePath != null) 'file': filePath,
      };

  /// At least one of `asset`, `url` or `file` must be present, mirroring
  /// the named constructors. Throws otherwise — silent fallback would
  /// render a blank box for what was originally a real image.
  factory ImageSource.fromJson(Map<String, dynamic> json) {
    final asset = json['asset'];
    final url = json['url'];
    final file = json['file'];
    if (asset is String) return ImageSource.asset(asset);
    if (url is String) return ImageSource.network(url);
    if (file is String) return ImageSource.file(file);
    throw const FormatException(
      'ImageSource requires either "asset", "url" or "file"',
    );
  }
}

/// Per-pixel colour grading parameters for an [ImageLayer]. Stored
/// as engine-friendly scalars so undo/redo, JSON, and equality all
/// stay trivial; the actual matrix is computed lazily by
/// [toMatrix] when the layer renders.
///
/// Ranges (chosen to match the UI sliders 1:1 so callers don't need
/// to scale values):
/// - [brightness]: `-100..100` — `0` is unchanged, positive
///   brightens, negative darkens. Translated to a uniform RGB
///   offset of `brightness * 2.55` so ±100 maps to ±full luminance.
/// - [contrast]: `0..2` — `1` is unchanged. Implemented as a
///   linear scale around mid-grey (128) so values < 1 flatten and
///   values > 1 expand the tonal range.
/// - [saturation]: `0..2` — `1` is unchanged. `0` collapses to
///   greyscale, `2` doubles colour intensity. Uses the standard
///   ITU-R BT.601 luma weights (0.299 / 0.587 / 0.114).
@immutable
class ImageAdjustments {
  const ImageAdjustments({
    this.brightness = 0,
    this.contrast = 1,
    this.saturation = 1,
    this.exposure = 0,
    this.warmth = 0,
  });

  final double brightness;
  final double contrast;
  final double saturation;

  /// Multiplicative gain applied to RGB before contrast / brightness.
  /// Range `-100..100`; `0` is unchanged. Mapped to a multiplier of
  /// `1 + exposure / 100` so ±100 doubles or zeroes the channel
  /// intensity. Conceptually the camera-style exposure stop, not the
  /// additive brightness offset.
  final double exposure;

  /// Colour-temperature shift along the blue↔orange axis. Range
  /// `-100..100`; `0` is unchanged. Positive values warm the image
  /// (boost red, drop blue); negative values cool it. Mapped to ±20%
  /// channel offsets at the extremes so it never burns out highlights.
  final double warmth;

  static const ImageAdjustments identity = ImageAdjustments();

  /// True when the configured values are visually a no-op so the
  /// renderer can skip the [ColorFiltered] wrapper entirely —
  /// avoids paying the per-frame matrix cost on the 95% of images
  /// the user never tunes.
  bool get isIdentity =>
      brightness == 0 &&
      contrast == 1 &&
      saturation == 1 &&
      exposure == 0 &&
      warmth == 0;

  ImageAdjustments copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? exposure,
    double? warmth,
  }) {
    return ImageAdjustments(
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      exposure: exposure ?? this.exposure,
      warmth: warmth ?? this.warmth,
    );
  }

  /// Composes every adjustment into a single 4×5 colour matrix
  /// suitable for [ColorFilter.matrix]. Order:
  /// **exposure → warmth → saturation → contrast → brightness**
  /// so the multiplicative camera stages run first, the colour
  /// shift lands on the gained pixels, and the user-facing
  /// brightness/contrast sliders trim the final tonal range.
  List<double> toMatrix() {
    // 1) Exposure: pure RGB gain. Mid-grey passes through scaled.
    final ex = 1 + exposure / 100;
    final expM = <double>[
      ex, 0,  0,  0, 0,
      0,  ex, 0,  0, 0,
      0,  0,  ex, 0, 0,
      0,  0,  0,  1, 0,
    ];

    // 2) Warmth: shift blue↔orange. ±100 → ±20% additive on R/B.
    //    Green gets a smaller nudge so the white point stays neutral.
    final wOff = warmth * 0.2 * 2.55; // 0.2 of full range, in 0..255.
    final warmM = <double>[
      1, 0, 0, 0, wOff,
      0, 1, 0, 0, wOff * 0.4,
      0, 0, 1, 0, -wOff,
      0, 0, 0, 1, 0,
    ];

    final s = saturation;
    // ITU-R BT.601 luma weights.
    const lr = 0.299;
    const lg = 0.587;
    const lb = 0.114;
    final sr0 = (1 - s) * lr;
    final sg0 = (1 - s) * lg;
    final sb0 = (1 - s) * lb;
    final sat = <double>[
      sr0 + s, sg0,     sb0,     0, 0,
      sr0,     sg0 + s, sb0,     0, 0,
      sr0,     sg0,     sb0 + s, 0, 0,
      0,       0,       0,       1, 0,
    ];

    final c = contrast;
    final cTrans = 128 * (1 - c);
    final con = <double>[
      c, 0, 0, 0, cTrans,
      0, c, 0, 0, cTrans,
      0, 0, c, 0, cTrans,
      0, 0, 0, 1, 0,
    ];

    final bTrans = brightness * 2.55;
    final bri = <double>[
      1, 0, 0, 0, bTrans,
      0, 1, 0, 0, bTrans,
      0, 0, 1, 0, bTrans,
      0, 0, 0, 1, 0,
    ];

    // Apply outermost-last: bri( con( sat( warm( exp(c) ) ) ) ).
    return composeColorMatrices(
      bri,
      composeColorMatrices(
        con,
        composeColorMatrices(
          sat,
          composeColorMatrices(warmM, expM),
        ),
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (brightness != 0) 'brightness': brightness,
        if (contrast != 1) 'contrast': contrast,
        if (saturation != 1) 'saturation': saturation,
        if (exposure != 0) 'exposure': exposure,
        if (warmth != 0) 'warmth': warmth,
      };

  factory ImageAdjustments.fromJson(Map<String, dynamic> json) {
    return ImageAdjustments(
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 1,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 1,
      exposure: (json['exposure'] as num?)?.toDouble() ?? 0,
      warmth: (json['warmth'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageAdjustments &&
          other.brightness == brightness &&
          other.contrast == contrast &&
          other.saturation == saturation &&
          other.exposure == exposure &&
          other.warmth == warmth;

  @override
  int get hashCode =>
      Object.hash(brightness, contrast, saturation, exposure, warmth);
}

/// Curated colour-grade preset applied **before** [ImageAdjustments]
/// in the render pipeline. Each preset is a fixed 4×5 colour matrix
/// designed to read as a single tasteful look — Instagram-style.
/// Adding a new preset is one enum value plus one branch in
/// [imageFilterMatrix].
enum ImageFilterPreset {
  /// No filter — the renderer skips the extra `ColorFilter` wrapper.
  none,
  warm,
  cool,
  vintage,
  mono,
  fade,
  dramatic,
}

/// Returns the 4×5 colour matrix for [preset] or `null` for
/// [ImageFilterPreset.none] (so the renderer can short-circuit). All
/// matrices are tuned for the same neutral exposure baseline so the
/// presets read as different *looks* rather than different brightness
/// levels.
List<double>? imageFilterMatrix(ImageFilterPreset preset) {
  switch (preset) {
    case ImageFilterPreset.none:
      return null;
    case ImageFilterPreset.warm:
      // Lift R+G, drop B slightly.
      return const <double>[
        1.10, 0.00, 0.00, 0, 12,
        0.00, 1.05, 0.00, 0, 6,
        0.00, 0.00, 0.92, 0, -10,
        0.00, 0.00, 0.00, 1, 0,
      ];
    case ImageFilterPreset.cool:
      // Drop R, lift B for icy tones.
      return const <double>[
        0.92, 0.00, 0.00, 0, -8,
        0.00, 0.98, 0.00, 0, 4,
        0.00, 0.00, 1.10, 0, 12,
        0.00, 0.00, 0.00, 1, 0,
      ];
    case ImageFilterPreset.vintage:
      // Sepia-flavoured cross-channel mix + slight contrast lift.
      return const <double>[
        0.62, 0.30, 0.18, 0, 0,
        0.30, 0.65, 0.16, 0, 0,
        0.22, 0.28, 0.55, 0, 0,
        0.00, 0.00, 0.00, 1, 0,
      ];
    case ImageFilterPreset.mono:
      // BT.601 luma weights — clean black & white.
      return const <double>[
        0.299, 0.587, 0.114, 0, 0,
        0.299, 0.587, 0.114, 0, 0,
        0.299, 0.587, 0.114, 0, 0,
        0.000, 0.000, 0.000, 1, 0,
      ];
    case ImageFilterPreset.fade:
      // Lift blacks, compress range — milky vintage film look.
      return const <double>[
        0.85, 0.00, 0.00, 0, 30,
        0.00, 0.85, 0.00, 0, 30,
        0.00, 0.00, 0.85, 0, 30,
        0.00, 0.00, 0.00, 1, 0,
      ];
    case ImageFilterPreset.dramatic:
      // Strong contrast around mid-grey, slight desaturation.
      return const <double>[
        1.30, 0.00, 0.00, 0, -38,
        0.00, 1.30, 0.00, 0, -38,
        0.00, 0.00, 1.30, 0, -38,
        0.00, 0.00, 0.00, 1, 0,
      ];
  }
}

/// Composes two affine 4×5 colour matrices ([a] applied after [b])
/// into a single equivalent 4×5 matrix. Treats each as the top
/// four rows of a 5×5 with `[0,0,0,0,1]` appended, then multiplies.
///
/// Exposed (non-private) so the filter pipeline can compose preset
/// matrices with the user-tuned [ImageAdjustments] matrix into a
/// single `ColorFilter` per paint.
List<double> composeColorMatrices(List<double> a, List<double> b) {
  final out = List<double>.filled(20, 0);
  for (var i = 0; i < 4; i++) {
    for (var j = 0; j < 5; j++) {
      double sum = 0;
      for (var k = 0; k < 4; k++) {
        sum += a[i * 5 + k] * b[k * 5 + j];
      }
      if (j == 4) sum += a[i * 5 + 4];
      out[i * 5 + j] = sum;
    }
  }
  return out;
}

/// Concrete layer rendering a raster image inside its [transform] bounds.
/// Declares its own [LayerCapabilities] (aspect-locked, non-editable) and
/// participates in the generic interaction pipeline without modifying it.
class ImageLayer extends EditorLayer {
  const ImageLayer({
    required super.id,
    required super.transform,
    required this.source,
    this.fit = BoxFit.cover,
    this.mask = ImageMask.original,
    this.borderColor = const Color(0xFF000000),
    this.borderWidth = 0,
    this.shadowColor = const Color(0xFF000000),
    this.shadowBlur = 0,
    this.shadowOffset = Offset.zero,
    this.shadowOpacity = 0,
    this.adjustments = ImageAdjustments.identity,
    this.cropRect = fullCrop,
    this.filterPreset = ImageFilterPreset.none,
    super.name,
    super.visible,
    super.locked,
    super.opacity,
  }) : super(capabilities: _imageCaps);

  final ImageSource source;
  final BoxFit fit;

  /// Visible silhouette applied on top of the raw pixels. Defaults
  /// to [ImageMask.original] (no clip) so existing layers and
  /// freshly inserted images keep their full rectangle.
  final ImageMask mask;

  /// Stroke colour (with embedded alpha) used by the border overlay.
  /// Has no visual effect when [borderWidth] is `0`.
  final Color borderColor;

  /// Border thickness in logical canvas pixels. `0` means no border
  /// is drawn — this is the default so existing layers stay clean.
  final double borderWidth;

  /// Drop-shadow tint. The actual painted alpha is
  /// `shadowColor.alpha * shadowOpacity` so callers can tweak
  /// strength independently of hue.
  final Color shadowColor;

  /// Gaussian blur sigma (in logical px) for the silhouette shadow.
  /// `0` = crisp edge.
  final double shadowBlur;

  /// Translation applied to the shadow path relative to the image.
  /// `Offset.zero` produces a centred glow.
  final Offset shadowOffset;

  /// `0..1` shadow strength. `0` is the default and means no
  /// shadow is rendered at all (skipping the painter entirely).
  final double shadowOpacity;

  /// Per-pixel colour adjustments (brightness / contrast /
  /// saturation) applied to the raw image before clipping. Defaults
  /// to [ImageAdjustments.identity] so existing layers and freshly
  /// inserted images render unchanged.
  final ImageAdjustments adjustments;

  /// Normalised crop window into the post-fit image, expressed in
  /// the layer's own coordinate system (0..1 on each axis). Defaults
  /// to [fullCrop] (`Rect.fromLTRB(0, 0, 1, 1)`) so existing layers
  /// render the entire fitted image. Smaller rects zoom into a
  /// sub-region without changing the layer's transform on the
  /// canvas — the layer keeps its size, position, and rotation
  /// handles work unchanged.
  final Rect cropRect;

  /// Sentinel "no crop" rect. Held as a `static const` so equality
  /// checks against the default never allocate.
  static const Rect fullCrop = Rect.fromLTRB(0, 0, 1, 1);

  /// Convenience: true when [cropRect] is the default full window.
  bool get isFullCrop =>
      cropRect.left == 0 &&
      cropRect.top == 0 &&
      cropRect.right == 1 &&
      cropRect.bottom == 1;

  /// Curated colour-grade preset applied **before** [adjustments] in
  /// the render pipeline. Defaults to [ImageFilterPreset.none] so
  /// existing layers and freshly inserted images render unchanged.
  final ImageFilterPreset filterPreset;

  static const _imageCaps = LayerCapabilities(
    keepsAspectRatio: true,
    editable: false,
  );

  @override
  String get type => 'image';

  @override
  EditorLayer withTransform(LayerTransform transform) => ImageLayer(
        id: id,
        transform: transform,
        source: source,
        fit: fit,
        mask: mask,
        borderColor: borderColor,
        borderWidth: borderWidth,
        shadowColor: shadowColor,
        shadowBlur: shadowBlur,
        shadowOffset: shadowOffset,
        shadowOpacity: shadowOpacity,
        adjustments: adjustments,
        cropRect: cropRect,
        filterPreset: filterPreset,
        name: name,
        visible: visible,
        locked: locked,
        opacity: opacity,
      );

  @override
  EditorLayer withVisibility(bool visible) => ImageLayer(
        id: id,
        transform: transform,
        source: source,
        fit: fit,
        mask: mask,
        borderColor: borderColor,
        borderWidth: borderWidth,
        shadowColor: shadowColor,
        shadowBlur: shadowBlur,
        shadowOffset: shadowOffset,
        shadowOpacity: shadowOpacity,
        adjustments: adjustments,
        cropRect: cropRect,
        filterPreset: filterPreset,
        name: name,
        visible: visible,
        locked: locked,
        opacity: opacity,
      );

  @override
  EditorLayer withLocked(bool locked) => ImageLayer(
        id: id,
        transform: transform,
        source: source,
        fit: fit,
        mask: mask,
        borderColor: borderColor,
        borderWidth: borderWidth,
        shadowColor: shadowColor,
        shadowBlur: shadowBlur,
        shadowOffset: shadowOffset,
        shadowOpacity: shadowOpacity,
        adjustments: adjustments,
        cropRect: cropRect,
        filterPreset: filterPreset,
        name: name,
        visible: visible,
        locked: locked,
        opacity: opacity,
      );

  @override
  EditorLayer withOpacity(double opacity) => ImageLayer(
        id: id,
        transform: transform,
        source: source,
        fit: fit,
        mask: mask,
        borderColor: borderColor,
        borderWidth: borderWidth,
        shadowColor: shadowColor,
        shadowBlur: shadowBlur,
        shadowOffset: shadowOffset,
        shadowOpacity: shadowOpacity,
        adjustments: adjustments,
        cropRect: cropRect,
        filterPreset: filterPreset,
        name: name,
        visible: visible,
        locked: locked,
        opacity: opacity.clamp(0.0, 1.0),
      );

  @override
  Widget buildContent(BuildContext context) {
    // Decode-size cap: tell the image pipeline to rasterise at (close
    // to) the layer's *canvas-space* width rather than the source's
    // native resolution. A 12 MP photo dropped onto a 200×200-canvas
    // layer would otherwise decode at full size (~48 MB raw RGBA) and
    // either blow Flutter's default 100 MB ImageCache budget or push
    // other layers out of it on every rebuild.
    //
    // We cap the hint at [_kImageDecodeMaxEdge] so a layer the user
    // has resized very large still doesn't allocate an unbounded
    // raster. The result is sharp at 1× viewport zoom and slightly
    // soft at extreme zoom-in — an acceptable trade for memory
    // safety on low-end devices.
    //
    // Flutter's ImageCache deduplicates `FileImage` / `AssetImage` /
    // `NetworkImage` by their stable cache key (path / asset name /
    // URL), so rebuilds of this widget do NOT re-decode the bytes —
    // they just rebind the same cached `ui.Image`. No custom layer
    // cache is required on top.
    final int? cacheWidth = _decodeCacheWidth(transform.size.width);
    final rawPixels = switch (source) {
      ImageSource(:final assetName?) =>
        Image.asset(assetName, fit: fit, cacheWidth: cacheWidth),
      ImageSource(:final networkUrl?) =>
        Image.network(networkUrl, fit: fit, cacheWidth: cacheWidth),
      ImageSource(:final filePath?) =>
        Image.file(File(filePath), fit: fit, cacheWidth: cacheWidth),
      _ => const ColoredBox(color: Color(0x22FFFFFF)),
    };
    // Compose filter preset and user adjustments into a single
    // colour matrix so we only pay the [ColorFiltered] cost once.
    // The filter is applied first (acts on the raw pixels), then
    // adjustments fine-tune the result — matches Instagram-style
    // "pick a look, then trim it" mental model. Wrapping inside
    // the clip means border and shadow keep their own colours.
    final filterMatrix = imageFilterMatrix(filterPreset);
    final adjMatrix = adjustments.isIdentity ? null : adjustments.toMatrix();
    final List<double>? combined;
    if (filterMatrix == null) {
      combined = adjMatrix;
    } else if (adjMatrix == null) {
      combined = filterMatrix;
    } else {
      combined = composeColorMatrices(adjMatrix, filterMatrix);
    }
    final adjusted = combined == null
        ? rawPixels
        : ColorFiltered(
            colorFilter: ColorFilter.matrix(combined),
            child: rawPixels,
          );
    // Crop window selects a sub-rect of the post-fit image. Applied
    // *before* the mask/border/shadow stack so cropping zooms into
    // the visible silhouette but the silhouette itself, the
    // border, and the shadow stay anchored to the layer bounds —
    // exactly like cropping in any photo editor.
    final pixels = isFullCrop ? adjusted : _applyCrop(adjusted);
    final clipped = _maskClip(mask, pixels);
    final hasBorder = borderWidth > 0;
    final body = hasBorder
        ? Stack(
            fit: StackFit.expand,
            children: [
              clipped,
              // Border overlays the masked pixels using the same
              // silhouette path — rectangle/rounded/circle/squircle/
              // star/heart all stay visually consistent with the
              // clipped image edge. IgnorePointer keeps gestures
              // (transform handles, taps) on the underlying layer.
              IgnorePointer(
                child: CustomPaint(
                  painter: _MaskBorderPainter(
                    mask: mask,
                    color: borderColor,
                    width: borderWidth,
                  ),
                ),
              ),
            ],
          )
        : clipped;
    final hasShadow = shadowOpacity > 0;
    return SizedBox.fromSize(
      size: transform.size,
      child: hasShadow
          ? Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                // Shadow paints behind the body using the same
                // silhouette path so it tracks every mask shape.
                // Painter draws outside its size box (Stack uses
                // Clip.none) so blurred edges and offset shadows
                // aren't sliced at the layer rect.
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _MaskShadowPainter(
                        mask: mask,
                        color: shadowColor,
                        opacity: shadowOpacity,
                        blur: shadowBlur,
                        offset: shadowOffset,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(child: body),
              ],
            )
          : body,
    );
  }

  /// Wraps the (already fitted + adjusted) pixel widget in a
  /// scale+translate transform so only the configured [cropRect]
  /// region is visible inside the layer bounds. The image is scaled
  /// up by `1/cropWidth` × `1/cropHeight` so the cropped sub-rect
  /// fills the box, then offset so the crop's top-left lands at
  /// `(0, 0)`. A `ClipRect` makes sure the oversized child never
  /// bleeds outside the layer bounds (which would corrupt the
  /// shadow/border layers stacked on top).
  Widget _applyCrop(Widget pixels) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          // Guard against degenerate crop rects (zero area would
          // produce an infinite scale and crash the framework).
          final cw = cropRect.width <= 0 ? 1.0 : cropRect.width;
          final ch = cropRect.height <= 0 ? 1.0 : cropRect.height;
          return OverflowBox(
            minWidth: 0,
            minHeight: 0,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            alignment: Alignment.topLeft,
            child: Transform(
              alignment: Alignment.topLeft,
              transform: Matrix4.identity()
                ..scaleByDouble(1 / cw, 1 / ch, 1, 1)
                ..translateByDouble(-cropRect.left * w, -cropRect.top * h, 0, 1),
              child: SizedBox(
                width: w,
                height: h,
                child: pixels,
              ),
            ),
          );
        },
      ),
    );
  }

  // Override equality to include image-specific fields (source, fit,
  // mask, border). The base [EditorLayer.==] only covers id/transform/
  // visibility, so without this override two ImageLayers that differ
  // ONLY in mask / fit / source / border compare equal — which makes
  // [EditorDocument.==] think nothing changed and Riverpod skips the
  // rebuild, leaving the canvas stale until the next unrelated tap
  // forces a refresh.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageLayer &&
          super == other &&
          other.source == source &&
          other.fit == fit &&
          other.mask == mask &&
          other.borderColor == borderColor &&
          other.borderWidth == borderWidth &&
          other.shadowColor == shadowColor &&
          other.shadowBlur == shadowBlur &&
          other.shadowOffset == shadowOffset &&
          other.shadowOpacity == shadowOpacity &&
          other.adjustments == adjustments &&
          other.cropRect == cropRect &&
          other.filterPreset == filterPreset;

  @override
  int get hashCode => Object.hash(
        super.hashCode,
        source,
        fit,
        mask,
        borderColor,
        borderWidth,
        shadowColor,
        shadowBlur,
        shadowOffset,
        shadowOpacity,
        adjustments,
        cropRect,
        filterPreset,
      );

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        ...baseJson(),
        'source': source.toJson(),
        'fit': fit.name,
        'mask': mask.name,
        if (borderWidth > 0) 'borderWidth': borderWidth,
        if (borderWidth > 0) 'borderColor': borderColor.toARGB32(),
        if (shadowOpacity > 0) 'shadowOpacity': shadowOpacity,
        if (shadowOpacity > 0) 'shadowBlur': shadowBlur,
        if (shadowOpacity > 0) 'shadowOffsetX': shadowOffset.dx,
        if (shadowOpacity > 0) 'shadowOffsetY': shadowOffset.dy,
        if (shadowOpacity > 0) 'shadowColor': shadowColor.toARGB32(),
        if (!adjustments.isIdentity) 'adjustments': adjustments.toJson(),
        if (!isFullCrop) 'cropL': cropRect.left,
        if (!isFullCrop) 'cropT': cropRect.top,
        if (!isFullCrop) 'cropR': cropRect.right,
        if (!isFullCrop) 'cropB': cropRect.bottom,
        if (filterPreset != ImageFilterPreset.none)
          'filterPreset': filterPreset.name,
      };

  factory ImageLayer.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String) {
      throw const FormatException('ImageLayer.id missing or not a string');
    }
    final transformJson = json['transform'];
    if (transformJson is! Map) {
      throw const FormatException('ImageLayer.transform missing');
    }
    final sourceJson = json['source'];
    if (sourceJson is! Map) {
      throw const FormatException('ImageLayer.source missing');
    }
    final fitName = json['fit'];
    final fit = fitName is String
        ? BoxFit.values.firstWhere(
            (f) => f.name == fitName,
            orElse: () => BoxFit.cover,
          )
        : BoxFit.cover;
    final maskName = json['mask'];
    final mask = maskName is String
        ? ImageMask.values.firstWhere(
            (m) => m.name == maskName,
            orElse: () => ImageMask.original,
          )
        : ImageMask.original;
    return ImageLayer(
      id: id,
      transform: LayerTransform.fromJson(
        Map<String, dynamic>.from(transformJson),
      ),
      source: ImageSource.fromJson(Map<String, dynamic>.from(sourceJson)),
      fit: fit,
      mask: mask,
      borderColor: (json['borderColor'] is int)
          ? Color(json['borderColor'] as int)
          : const Color(0xFF000000),
      borderWidth: (json['borderWidth'] as num?)?.toDouble() ?? 0,
      shadowColor: (json['shadowColor'] is int)
          ? Color(json['shadowColor'] as int)
          : const Color(0xFF000000),
      shadowBlur: (json['shadowBlur'] as num?)?.toDouble() ?? 0,
      shadowOffset: Offset(
        (json['shadowOffsetX'] as num?)?.toDouble() ?? 0,
        (json['shadowOffsetY'] as num?)?.toDouble() ?? 0,
      ),
      shadowOpacity: (json['shadowOpacity'] as num?)?.toDouble() ?? 0,
      adjustments: () {
        final a = json['adjustments'];
        if (a is Map) {
          return ImageAdjustments.fromJson(
            Map<String, dynamic>.from(a),
          );
        }
        return ImageAdjustments.identity;
      }(),
      cropRect: () {
        final l = (json['cropL'] as num?)?.toDouble();
        final t = (json['cropT'] as num?)?.toDouble();
        final r = (json['cropR'] as num?)?.toDouble();
        final b = (json['cropB'] as num?)?.toDouble();
        if (l == null || t == null || r == null || b == null) {
          return ImageLayer.fullCrop;
        }
        return Rect.fromLTRB(l, t, r, b);
      }(),
      filterPreset: () {
        final raw = json['filterPreset'];
        if (raw is! String) return ImageFilterPreset.none;
        return ImageFilterPreset.values.firstWhere(
          (f) => f.name == raw,
          orElse: () => ImageFilterPreset.none,
        );
      }(),
      name: json['name'] as String?,
      visible: json['visible'] as bool? ?? true,
      locked: json['locked'] as bool? ?? false,
      opacity: ((json['opacity'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0),
    );
  }
}

/// Wraps [child] with the appropriate clip widget for [mask]. Pulled
/// out of [ImageLayer.buildContent] so the engine doesn't need to
/// know about each shape — adding a new mask is one enum value plus
/// one branch here. Uses [imageMaskPath] under the hood so the clip
/// silhouette and the [_MaskBorderPainter] stroke share one source
/// of truth and stay perfectly aligned at every aspect ratio.
Widget _maskClip(ImageMask mask, Widget child) {
  if (mask == ImageMask.original) return child;
  return ClipPath(clipper: _MaskClipper(mask), child: child);
}

/// Returns the silhouette path for [mask] inside a [size]-sized box.
/// Used by both [_MaskClipper] (to clip the pixels) and
/// [_MaskBorderPainter] (to stroke the visible edge), so the border
/// always traces the same outline as the visible image.
Path imageMaskPath(ImageMask mask, Size size) {
  final rect = Offset.zero & size;
  switch (mask) {
    case ImageMask.original:
      return Path()..addRect(rect);
    case ImageMask.rounded:
      return Path()
        ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(24)));
    case ImageMask.circle:
      final r = size.shortestSide / 2;
      return Path()
        ..addOval(
          Rect.fromCircle(
            center: Offset(size.width / 2, size.height / 2),
            radius: r,
          ),
        );
    case ImageMask.squircle:
      return ContinuousRectangleBorder(
        borderRadius: BorderRadius.circular(size.shortestSide * 0.4),
      ).getOuterPath(rect);
    case ImageMask.star:
      return _starPath(size);
    case ImageMask.heart:
      return _heartPath(size);
  }
}

class _MaskClipper extends CustomClipper<Path> {
  const _MaskClipper(this.mask);
  final ImageMask mask;
  @override
  Path getClip(Size size) => imageMaskPath(mask, size);
  @override
  bool shouldReclip(covariant _MaskClipper oldClipper) =>
      oldClipper.mask != mask;
}

/// Maximum decode-edge hint passed to [Image.cacheWidth] for any
/// image layer. Large enough that 1× viewport zoom reads as crisp
/// on a 4K display, small enough that a single huge source photo
/// can never on its own exceed Flutter's default ImageCache size
/// budget (≈100 MB raw RGBA).
const int _kImageDecodeMaxEdge = 2048;

/// Compute a `cacheWidth` hint for a layer of [layerWidth] canvas
/// pixels. Returns `null` (let Flutter decide) for degenerate /
/// uninitialised layers, otherwise the next power of two ≥
/// [layerWidth], clamped to `[64, _kImageDecodeMaxEdge]`.
///
/// Power-of-two stepping gives **at most ~2× over-decode** at
/// bucket boundaries, but collapses every conceivable layer width
/// into ≤ 6 unique cache keys (64 / 128 / 256 / 512 / 1024 / 2048).
/// Two wins fall out of that:
///
///   1. Resize drags reuse the same decoded entry across a wide
///      range (e.g. 257 → 512 all share `cacheWidth=512`), so the
///      `ImageCache` is not churned per-frame;
///   2. The same image dropped onto multiple layers of similar
///      sizes shares decoded bytes, instead of each layer minting
///      its own raster.
int? _decodeCacheWidth(double layerWidth) {
  if (!layerWidth.isFinite || layerWidth <= 0) return null;
  // Clamp first so very small (< 64) or huge layers map to a
  // sensible bucket without log/round drift.
  final clamped = layerWidth.clamp(1.0, _kImageDecodeMaxEdge.toDouble());
  // Smallest power of two ≥ clamped, lower-bounded at 64 so we
  // never decode below a usable thumbnail size.
  int bucket = 64;
  while (bucket < clamped && bucket < _kImageDecodeMaxEdge) {
    bucket <<= 1;
  }
  return bucket;
}

/// Strokes the layer's silhouette with the configured colour and
/// width. The stroke is inset by half the width so the outer edge
/// stays inside the layer's bounds (matches what the user sees and
/// avoids a 1-px clip at the canvas edge).
class _MaskBorderPainter extends CustomPainter {
  const _MaskBorderPainter({
    required this.mask,
    required this.color,
    required this.width,
  });

  final ImageMask mask;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    if (width <= 0) return;
    // Inset so the stroke sits fully inside the layer rect.
    final inset = width / 2;
    final innerSize = Size(
      (size.width - inset * 2).clamp(0, size.width),
      (size.height - inset * 2).clamp(0, size.height),
    );
    if (innerSize.isEmpty) return;
    final path = imageMaskPath(mask, innerSize)
        .shift(Offset(inset, inset));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = color
      ..isAntiAlias = true;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MaskBorderPainter old) =>
      old.mask != mask || old.color != color || old.width != width;
}

/// Drops a blurred, optionally-offset silhouette of the layer
/// behind the masked pixels. Uses [imageMaskPath] so the shadow
/// always matches the visible image edge (rectangle/rounded/circle/
/// squircle/star/heart). A `MaskFilter.blur` keeps the cost low
/// (single path + GPU blur) instead of a multi-pass shadow stack.
class _MaskShadowPainter extends CustomPainter {
  const _MaskShadowPainter({
    required this.mask,
    required this.color,
    required this.opacity,
    required this.blur,
    required this.offset,
  });

  final ImageMask mask;
  final Color color;
  final double opacity;
  final double blur;
  final Offset offset;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0 || size.isEmpty) return;
    final path = imageMaskPath(mask, size).shift(offset);
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: opacity.clamp(0.0, 1.0))
      ..isAntiAlias = true;
    if (blur > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MaskShadowPainter old) =>
      old.mask != mask ||
      old.color != color ||
      old.opacity != opacity ||
      old.blur != blur ||
      old.offset != offset;
}

/// Inscribed circle whose diameter is the layer's shortest side, so a
/// non-square image is never stretched into an ellipse — it's masked
/// by a true circle centered in the bounds.
/// Five-point star inscribed in the layer's bounds. Outer radius is
/// half the shortest side; inner radius keeps the classic ~0.4 ratio
/// so the points read crisply at any image size.
Path _starPath(Size size) {
  final cx = size.width / 2;
  final cy = size.height / 2;
  final outer = size.shortestSide / 2;
  final inner = outer * 0.4;
  final path = Path();
  const points = 5;
  for (var i = 0; i < points * 2; i++) {
    final r = i.isEven ? outer : inner;
    // Start at -pi/2 so the first point sits straight up.
    final angle = -math.pi / 2 + i * math.pi / points;
    final x = cx + r * math.cos(angle);
    final y = cy + r * math.sin(angle);
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
  return path;
}

/// Heart silhouette built from two top arcs and a bottom V. Inscribed
/// in the layer rect (with a small top inset so the cusp isn't
/// clipped by the bounds).
Path _heartPath(Size size) {
  final w = size.width;
  final h = size.height;
  final path = Path();
  path.moveTo(w / 2, h * 0.95);
  path.cubicTo(-w * 0.1, h * 0.6, w * 0.15, -h * 0.05, w / 2, h * 0.28);
  path.cubicTo(
    w - w * 0.15,
    -h * 0.05,
    w + w * 0.1,
    h * 0.6,
    w / 2,
    h * 0.95,
  );
  path.close();
  return path;
}
