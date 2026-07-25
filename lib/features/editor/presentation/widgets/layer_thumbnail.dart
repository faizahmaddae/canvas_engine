import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../engine/core/editor_layer.dart';
import '../../engine/modules/image/image_layer.dart';
import '../../engine/modules/image/image_source_provider.dart';
import '../../engine/modules/shape/shape_layer.dart';
import '../../engine/modules/text/text_layer.dart';
import '../../../../app/theme/app_icons.dart';

/// Renders a small, type-aware preview of an [EditorLayer] for use in
/// the Layers panel. Unlike the on-canvas widgets (which build the
/// full transformable subtree), this widget targets a fixed
/// thumbnail size — typically 36–40 px — and trades visual fidelity
/// for speed: no shadows, no adjustments, no editor handles.
///
/// Picks a dedicated render strategy per layer type:
///
/// * [ImageLayer] → the actual pixels via [Image] + [ResizeImage] so
///   the underlying decode is bounded to the thumbnail's pixel
///   budget. The layer's [ImageLayer.cropRect] and (rounded / circle
///   / etc.) [ImageMask] are honoured via `ClipRect` + `ClipPath`.
/// * [ShapeLayer] → reuses [shapeOutlinePath] so the silhouette
///   matches what the canvas paints, then fills + strokes with the
///   layer's own colours.
/// * [TextLayer] (sticker) → the emoji rendered large and centred.
/// * [TextLayer] (normal) → the actual text, scaled down with
///   `maxLines:2` ellipsis truncation, in the layer's own font /
///   colour.
/// * Anything else → falls back to a generic icon so unknown layer
///   types keep rendering.
class LayerThumbnail extends StatelessWidget {
  const LayerThumbnail({super.key, required this.layer, this.size = 40});

  final EditorLayer layer;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const radius = 8.0;
    final box = BoxDecoration(
      color: AppTokens.of(context).surfaceMuted,
      border: Border.all(color: theme.dividerColor, width: 1),
      borderRadius: BorderRadius.circular(radius),
    );

    final layer = this.layer;
    Widget child;
    if (layer is ImageLayer) {
      child = _ImageThumb(layer: layer, size: size);
    } else if (layer is ShapeLayer) {
      child = _ShapeThumb(layer: layer, size: size);
    } else if (layer is TextLayer) {
      child = _TextThumb(layer: layer, size: size);
    } else {
      child = const Icon(AppIcons.layersPanel, size: 18);
    }

    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: box,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - 1),
          child: child,
        ),
      ),
    );
  }
}

/// Image preview honouring [ImageLayer.cropRect] and [ImageLayer.mask].
///
/// Crop is applied by oversizing the [Image] to `1/cropSize` of the
/// thumbnail, translating it so the crop origin lands at (0, 0), and
/// clipping back to the thumbnail rect. This is the same algorithm
/// the canvas uses, just at thumbnail scale.
class _ImageThumb extends StatelessWidget {
  const _ImageThumb({required this.layer, required this.size});

  final ImageLayer layer;
  final double size;

  ImageProvider? _provider() => imageProviderFor(layer.source);

  @override
  Widget build(BuildContext context) {
    final provider = _provider();
    if (provider == null) {
      return const _Fallback(icon: AppIcons.imagePlaceholder);
    }
    // Cap decode at 2× the thumbnail to keep memory tiny while
    // staying crisp on hi-DPI screens.
    final cacheW = (size * 2).round();
    final image = Image(
      image: ResizeImage(provider, width: cacheW),
      fit: BoxFit.cover,
      width: size,
      height: size,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const _Fallback(icon: AppIcons.imageBroken),
    );

    final crop = layer.cropRect;
    Widget visual;
    if (layer.isFullCrop) {
      visual = image;
    } else {
      final cw = crop.width.clamp(0.001, 1.0).toDouble();
      final ch = crop.height.clamp(0.001, 1.0).toDouble();
      final w = size / cw;
      final h = size / ch;
      visual = ClipRect(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: -crop.left * w,
                top: -crop.top * h,
                width: w,
                height: h,
                child: Image(
                  image: ResizeImage(provider, width: cacheW),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) =>
                      const _Fallback(icon: AppIcons.imageBroken),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Subtle dark backing so transparent PNGs are visible.
    final backed = ColoredBox(color: const Color(0x22000000), child: visual);

    if (layer.mask == ImageMask.original) return backed;
    return ClipPath(clipper: _MaskPathClipper(layer.mask), child: backed);
  }
}

class _MaskPathClipper extends CustomClipper<Path> {
  const _MaskPathClipper(this.mask);
  final ImageMask mask;
  @override
  Path getClip(Size size) => imageMaskPath(mask, size);
  @override
  bool shouldReclip(covariant _MaskPathClipper oldClipper) =>
      oldClipper.mask != mask;
}

/// Shape preview that renders the same outline as the canvas, just
/// at thumbnail size. Insets the paint rect by the stroke radius so
/// the stroke is never clipped by the thumbnail border.
class _ShapeThumb extends StatelessWidget {
  const _ShapeThumb({required this.layer, required this.size});

  final ShapeLayer layer;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ShapeThumbPainter(layer: layer),
    );
  }
}

class _ShapeThumbPainter extends CustomPainter {
  const _ShapeThumbPainter({required this.layer});
  final ShapeLayer layer;

  bool get _isStroked => isStrokedShapeKind(layer.kind);

  @override
  void paint(Canvas canvas, Size size) {
    // Reserve a margin so the shape never bleeds into the rounded
    // thumbnail border. Use the stroke width as a floor so thick
    // outlines don't get clipped.
    final stroke = layer.strokeWidth.clamp(0.0, 8.0).toDouble();
    final inset = (stroke / 2).clamp(2.0, 8.0);
    final inner = Size(
      (size.width - inset * 2).clamp(1.0, size.width),
      (size.height - inset * 2).clamp(1.0, size.height),
    );
    canvas.translate(inset, inset);

    final path = shapeOutlinePath(
      layer.kind,
      inner,
      cornerRadius: layer.cornerRadius,
    );

    if (_isStroked) {
      // Lines & arrows: paint the path with the layer's own colour as
      // a stroke (matches _ShapePainter's behaviour for these kinds).
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = stroke == 0 ? 2 : stroke
        ..color = layer.fillColor.withValues(
          alpha: (layer.fillColor.a * layer.fillOpacity).clamp(0.0, 1.0),
        );
      canvas.drawPath(path, p);
      return;
    }

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = layer.fillColor.withValues(
        alpha: (layer.fillColor.a * layer.fillOpacity).clamp(0.0, 1.0),
      );
    canvas.drawPath(path, fill);

    final strokeColor = layer.strokeColor;
    if (strokeColor != null && stroke > 0) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round
        ..color = strokeColor;
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _ShapeThumbPainter old) =>
      old.layer.kind != layer.kind ||
      old.layer.fillColor != layer.fillColor ||
      old.layer.fillOpacity != layer.fillOpacity ||
      old.layer.strokeColor != layer.strokeColor ||
      old.layer.strokeWidth != layer.strokeWidth ||
      old.layer.cornerRadius != layer.cornerRadius;
}

/// Text preview. Stickers (single-glyph emoji layers) render their
/// glyph large and centred so they read at a glance. Normal text
/// renders the actual content in the layer's own colour / family,
/// truncated to fit the thumbnail.
class _TextThumb extends StatelessWidget {
  const _TextThumb({required this.layer, required this.size});

  final TextLayer layer;
  final double size;

  @override
  Widget build(BuildContext context) {
    final raw = layer.content.trim();
    if (raw.isEmpty) {
      return const _Fallback(icon: AppIcons.textLayer);
    }

    if (layer.isSticker) {
      // Use the glyph itself, sized to ~70% of the thumbnail. Don't
      // pull fontFamily — emoji should always use the platform's
      // emoji font, not the layer's text font.
      return Center(
        child: Text(
          raw,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(fontSize: size * 0.7, height: 1.0),
        ),
      );
    }

    // Truncate aggressively — beyond ~12 chars we're guaranteed to
    // wrap or overflow. The 2-line ellipsis below handles the
    // remainder gracefully if a long word doesn't break.
    final display = raw.length > 14 ? '${raw.substring(0, 14)}…' : raw;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: Center(
        child: Text(
          display,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: layer.style.fontFamily,
            color: layer.style.color,
            fontWeight: layer.style.fontWeight,
            fontStyle: layer.style.italic ? FontStyle.italic : FontStyle.normal,
            // Use a small, fixed thumbnail size — the layer's own
            // fontSize is canvas-relative (often 96+) so it would
            // never fit. 11px is comfortably readable inside 40px.
            fontSize: 11,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.icon});
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(child: Icon(icon, size: 18));
}
