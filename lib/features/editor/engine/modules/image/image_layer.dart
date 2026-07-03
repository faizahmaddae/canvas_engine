/// Image layer module, split into `part` files along the data /
/// render axis. The library root keeps every import and the
/// [composeColorMatrices] re-export so the module's external import
/// surface is unchanged by the split.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../core/editor_layer.dart';
import '../../core/layer_capabilities.dart';
import '../../core/layer_transform.dart';
import '../../effects/color_matrix_ops.dart';
import '../../effects/editor_effect.dart';

// Re-export so existing imports of `image_layer.dart` keep resolving
// `composeColorMatrices` after the symbol moved into the shared
// effects module.
export '../../effects/color_matrix_ops.dart' show composeColorMatrices;

part 'image_adjustments.dart';
part 'image_filter_preset.dart';
part 'image_layer_render.dart';
part 'image_source.dart';

/// Sentinel used by [ImageLayer.copyAll] to distinguish "leave the
/// nullable [EditorLayer.name] field alone" from "explicitly clear it
/// to null". `null` cannot serve as the default for that purpose.
const Object _kCopySentinel = Object();

/// Concrete layer rendering a raster image inside its [transform] bounds.
/// Declares its own [LayerCapabilities] (aspect-locked, non-editable) and
/// participates in the generic interaction pipeline without modifying it.
class ImageLayer extends EditorLayer {
  // Non-const because the default value of [adjustments] is
  // [ImageAdjustments.identity], which is now `static final` rather than
  // `static const` (see the note on the [ImageAdjustments] constructor).
  // ignore: prefer_const_constructors_in_immutables
  ImageLayer({
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
    this.cropRect = fullCrop,
    this.filterPreset = ImageFilterPreset.none,
    super.name,
    super.visible,
    super.locked,
    super.opacity,
    super.effects,
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
  /// saturation / exposure / warmth) projected from the layer's
  /// [EffectStack]. Derived (not stored) so the canonical state
  /// lives in [effects] and the legacy slider UI keeps reading a
  /// flat value object.
  ImageAdjustments get adjustments => ImageAdjustments.fromEffectStack(effects);

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

  /// Single source of truth for cloning an [ImageLayer] with one or
  /// more fields replaced. Every `with*` override in this class
  /// delegates here so adding a new field to [ImageLayer] is a
  /// **one-line** change (parameter + delegation) instead of editing
  /// every per-field copy method individually.
  ///
  /// Semantics:
  /// * Omitted parameters preserve the receiver's value verbatim.
  /// * [name] uses a sentinel so callers can both *leave it alone*
  ///   (omit) and *clear it* (pass `null`) — without the sentinel
  ///   `name: null` would be indistinguishable from "leave alone".
  /// * [opacity] is clamped to `0..1` only when the caller explicitly
  ///   passes it. `this.opacity` is never re-clamped, so a no-op
  ///   `copyAll()` is identity (preserves equality + serialization
  ///   round-trip guarantees the undo system depends on).
  /// * A debug-only assert catches programmer error pre-clamp; the
  ///   clamp itself is the production safety net.
  ImageLayer copyAll({
    String? id,
    LayerTransform? transform,
    ImageSource? source,
    BoxFit? fit,
    ImageMask? mask,
    Color? borderColor,
    double? borderWidth,
    Color? shadowColor,
    double? shadowBlur,
    Offset? shadowOffset,
    double? shadowOpacity,
    Rect? cropRect,
    ImageFilterPreset? filterPreset,
    Object? name = _kCopySentinel,
    bool? visible,
    bool? locked,
    double? opacity,
    EffectStack? effects,
  }) {
    assert(
      opacity == null || (opacity >= 0.0 && opacity <= 1.0),
      'opacity must be in 0..1 (got $opacity)',
    );
    return ImageLayer(
      id: id ?? this.id,
      transform: transform ?? this.transform,
      source: source ?? this.source,
      fit: fit ?? this.fit,
      mask: mask ?? this.mask,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      shadowColor: shadowColor ?? this.shadowColor,
      shadowBlur: shadowBlur ?? this.shadowBlur,
      shadowOffset: shadowOffset ?? this.shadowOffset,
      shadowOpacity: shadowOpacity ?? this.shadowOpacity,
      cropRect: cropRect ?? this.cropRect,
      filterPreset: filterPreset ?? this.filterPreset,
      name: identical(name, _kCopySentinel) ? this.name : name as String?,
      visible: visible ?? this.visible,
      locked: locked ?? this.locked,
      opacity: opacity == null ? this.opacity : opacity.clamp(0.0, 1.0),
      effects: effects ?? this.effects,
    );
  }

  @override
  EditorLayer withTransform(LayerTransform transform) =>
      copyAll(transform: transform);

  @override
  EditorLayer withVisibility(bool visible) => copyAll(visible: visible);

  @override
  EditorLayer withLocked(bool locked) => copyAll(locked: locked);

  @override
  EditorLayer withOpacity(double opacity) =>
      copyAll(opacity: opacity.clamp(0.0, 1.0));

  @override
  EditorLayer withName(String? name) => copyAll(name: name);

  @override
  // Pixel data is NOT held by the layer — it lives in the OS image
  // cache, keyed by asset / file path / URL. The layer only retains
  // those small string identifiers, so an undo entry pinning an
  // `ImageLayer` is cheap regardless of how big the photo is.
  int get estimatedByteSize =>
      EditorLayer.kLayerBaseBytes + source.estimatedByteSize;

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
    // Compose filter preset and the layer's effect stack into a
    // single colour matrix so we only pay the [ColorFiltered] cost
    // once. The filter is applied first (acts on the raw pixels),
    // then the effect stack fine-tunes the result \u2014 matches
    // Instagram-style "pick a look, then trim it" mental model.
    // Wrapping inside the clip means border and shadow keep their
    // own colours.
    final filterMatrix = imageFilterMatrix(filterPreset);
    final adjMatrix = effects.composedColorMatrix;
    final List<double>? combined;
    if (filterMatrix == null) {
      combined = adjMatrix;
    } else if (adjMatrix == null) {
      combined = filterMatrix;
    } else {
      combined = composeColorMatrices(adjMatrix, filterMatrix);
    }
    final int? cacheWidth = _decodeCacheWidth(transform.size.width);
    final adjusted = _loadableImage(
      cacheWidth: cacheWidth,
      colorMatrix: combined,
    );
    // Crop window selects a sub-rect of the post-fit image. Applied
    // *before* the mask/border/shadow stack so cropping zooms into
    // the visible silhouette but the silhouette itself, the
    // border, and the shadow stay anchored to the layer bounds —
    // exactly like cropping in any photo editor.
    final pixels = isFullCrop ? adjusted : _applyCrop(adjusted);
    // Custom-paint effect overlay (vignette, future grain, etc.).
    // Painted *over* the pixels but *inside* the mask clip so it
    // tracks every silhouette shape for free \u2014 same trick the
    // border / shadow painters use. When no custom-paint effect
    // contributes, we omit the wrapping `Stack` entirely so the
    // widget tree is byte-identical to a pre-effect document
    // (this is what keeps the v3 byte-identity gate green for
    // documents whose vignette intensity is 0).
    final painted = effects.hasContributingCustomPaint
        ? Stack(
            fit: StackFit.expand,
            children: [
              pixels,
              IgnorePointer(
                child: CustomPaint(
                  painter: _CustomPaintEffectsPainter(
                    effects: effects.customPaintEffects.toList(growable: false),
                  ),
                ),
              ),
            ],
          )
        : pixels;
    final clipped = _maskClip(mask, painted);
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

  /// Build the source image with a deterministic fallback for broken
  /// asset / network / file references. The colour matrix is applied
  /// through [Image.frameBuilder] so it wraps successful pixels only;
  /// the missing-image placeholder remains readable even when the
  /// layer carries a heavy filter/effect stack.
  Widget _loadableImage({
    required int? cacheWidth,
    required List<double>? colorMatrix,
  }) {
    Widget frameBuilder(
      BuildContext context,
      Widget child,
      int? frame,
      bool wasSynchronouslyLoaded,
    ) {
      if (colorMatrix == null) return child;
      return ColorFiltered(
        colorFilter: ColorFilter.matrix(colorMatrix),
        child: child,
      );
    }

    Widget errorBuilder(
      BuildContext context,
      Object error,
      StackTrace? stackTrace,
    ) {
      return const _MissingImagePlaceholder();
    }

    return switch (source) {
      ImageSource(:final assetName?) => Image.asset(
        assetName,
        fit: fit,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
        frameBuilder: frameBuilder,
        errorBuilder: errorBuilder,
      ),
      ImageSource(:final networkUrl?) => Image.network(
        networkUrl,
        fit: fit,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
        frameBuilder: frameBuilder,
        errorBuilder: errorBuilder,
      ),
      ImageSource(:final filePath?) => _fileImage(
        filePath,
        cacheWidth: cacheWidth,
        frameBuilder: frameBuilder,
        errorBuilder: errorBuilder,
      ),
      _ => const _MissingImagePlaceholder(),
    };
  }

  Widget _fileImage(
    String filePath, {
    required int? cacheWidth,
    required ImageFrameBuilder frameBuilder,
    required ImageErrorWidgetBuilder errorBuilder,
  }) {
    final file = File(filePath);
    if (!file.existsSync()) return const _MissingImagePlaceholder();
    return Image.file(
      file,
      fit: fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      frameBuilder: frameBuilder,
      errorBuilder: errorBuilder,
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
                ..translateByDouble(
                  -cropRect.left * w,
                  -cropRect.top * h,
                  0,
                  1,
                ),
              child: SizedBox(width: w, height: h, child: pixels),
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
      effects: _readEffectsWithLegacyLift(json),
    );
  }

  /// Decode the layer's effect stack with one-shot upgrade for the
  /// legacy `adjustments: {...}` slot.
  ///
  /// * v3+ docs: pure `effects: [...]` decode; legacy slot ignored
  ///   (effects-array entries are the canonical form on read).
  /// * v2 docs: no `effects` key, but possibly an `adjustments`
  ///   map. Lift the five-knob struct into its equivalent
  ///   [EditorEffect] sequence so the in-memory layer carries no
  ///   trace of the retired field.
  ///
  /// The lift is read-only: re-encoding writes the v3 `effects`
  /// shape, never the legacy key. That re-shapes any v2 doc the
  /// user opens-and-saves, but the wire-format change is *to* the
  /// current schema \u2014 no on-disk doc becomes unreadable.
  static EffectStack _readEffectsWithLegacyLift(Map<String, dynamic> json) {
    final fromArray = EditorLayer.parseEffects(json);
    if (fromArray.isNotEmpty) return fromArray;
    final legacy = json['adjustments'];
    if (legacy is! Map) return fromArray;
    final adj = ImageAdjustments.fromJson(Map<String, dynamic>.from(legacy));
    final lifted = adj.toEffectStack();
    if (lifted.isEmpty) return EffectStack.empty;
    return EffectStack(List<EditorEffect>.unmodifiable(lifted));
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

String _missingImageLabel(BuildContext context) {
  final locale = Localizations.maybeLocaleOf(context);
  if (locale?.languageCode == 'fa') return 'تصویر در دسترس نیست';
  return 'Image unavailable';
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
      return Path()..addOval(
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
  path.cubicTo(w - w * 0.15, -h * 0.05, w + w * 0.1, h * 0.6, w / 2, h * 0.95);
  path.close();
  return path;
}
