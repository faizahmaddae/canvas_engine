// Render-only private painters and clippers for [ImageLayer], split
// out of image_layer.dart along the data/render axis. Everything here
// is library-private; shared helpers (imageMaskPath, _starPath, …)
// stay in the library root so both the layer and these painters keep
// one source of truth for silhouette geometry.
part of 'image_layer.dart';

class _MissingImagePlaceholder extends StatelessWidget {
  const _MissingImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    final label = _missingImageLabel(context);
    return Semantics(
      label: label,
      child: CustomPaint(
        painter: const _MissingImagePlaceholderPainter(),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFF4B5563),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MissingImagePlaceholderPainter extends CustomPainter {
  const _MissingImagePlaceholderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final bg = Paint()..color = const Color(0xFFF2F4F7);
    final stroke = Paint()
      ..color = const Color(0xFF9AA4B2)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    canvas.drawRect(rect, bg);
    canvas.drawRect(rect.deflate(0.75), stroke);

    final inset = size.shortestSide * 0.18;
    canvas.drawLine(
      Offset(inset, inset),
      Offset(size.width - inset, size.height - inset),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width - inset, inset),
      Offset(inset, size.height - inset),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _MissingImagePlaceholderPainter oldDelegate) =>
      false;
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
    final path = imageMaskPath(mask, innerSize).shift(Offset(inset, inset));
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

/// Runs every contributing custom-paint [EditorEffect] (vignette,
/// future grain, …) over the layer's local bounds, in stack order.
/// Painted *inside* the layer mask clip so each effect inherits the
/// silhouette without having to know the mask shape.
///
/// Repaints only when the *list* of contributing effects changes
/// (`==` comparison), so a stable stack pays nothing per frame.
class _CustomPaintEffectsPainter extends CustomPainter {
  const _CustomPaintEffectsPainter({required this.effects});

  final List<EditorEffect> effects;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    for (final eff in effects) {
      eff.paint(canvas, bounds);
    }
  }

  @override
  bool shouldRepaint(covariant _CustomPaintEffectsPainter old) =>
      !listEquals(old.effects, effects);
}
