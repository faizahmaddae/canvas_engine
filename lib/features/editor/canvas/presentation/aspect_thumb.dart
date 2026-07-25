import 'package:flutter/material.dart';

/// A canvas preset drawn at its own aspect ratio.
///
/// The size presets used to carry glyphs — and the one fact that
/// distinguishes them, the SHAPE, was the one thing those glyphs did
/// not convey. Portrait and Landscape were literally the same
/// rectangle icon; Square and Story were near-identical at 18dp. A
/// row of four tiles asked the user to read the labels because the
/// pictures were interchangeable.
///
/// This just draws the rectangle. Square is a square, Story is tall
/// and narrow, Landscape is short and wide — the tile answers "what
/// shape will my canvas be" before the label is read, and no two
/// presets can collide because the artwork IS the ratio.
class AspectThumb extends StatelessWidget {
  const AspectThumb({
    super.key,
    required this.width,
    required this.height,
    this.extent = 22,
    this.dashed = false,
  });

  final double width;
  final double height;

  /// Longest side, in logical pixels. The short side scales down from
  /// it, so every thumb occupies the same optical square and the row
  /// keeps a flat baseline.
  final double extent;

  /// Draws a dashed outline instead of a solid one — used by Custom,
  /// which has no ratio of its own to show.
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final color =
        IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    final ratio = height <= 0 ? 1.0 : width / height;
    final w = ratio >= 1 ? extent : extent * ratio;
    final h = ratio >= 1 ? extent / ratio : extent;

    return SizedBox(
      width: extent,
      height: extent,
      child: Center(
        child: CustomPaint(
          size: Size(w, h),
          painter: _AspectPainter(color: color, dashed: dashed),
        ),
      ),
    );
  }
}

class _AspectPainter extends CustomPainter {
  const _AspectPainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      // Matches Phosphor Regular's stroke, so a thumb sitting in a row
      // of icon tiles reads as the same family.
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(2.5),
    );
    if (!dashed) {
      canvas.drawRRect(rect, paint);
      return;
    }
    // Dashes are walked along the path so the corners stay rounded —
    // drawing four dashed straight edges would square them off.
    const dash = 3.0;
    const gap = 2.6;
    final path = Path()..addRRect(rect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_AspectPainter old) =>
      old.color != color || old.dashed != dashed;
}
