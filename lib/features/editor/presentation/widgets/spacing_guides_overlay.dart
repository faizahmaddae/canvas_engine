import 'package:flutter/material.dart';

import '../../engine/interaction/snap_engine.dart';

/// Paints equal-spacing indicators (Figma-style measurement brackets
/// with a pixel-distance label between two paired gap segments). Pure
/// presentation: reads [SpacingGuide] data produced by the engine.
///
/// Visual contract:
///   * Each spacing guide describes two equal segments (`fromStart..End`
///     and `toStart..End`) along the axis the gaps run.
///   * For a vertical-axis guide (a horizontal row of rects), gaps run
///     along X at the shared Y midline; we draw two horizontal segments
///     with short tick caps and centre the gap label between them.
///   * For a horizontal-axis guide (a vertical column), the same
///     layout is rotated 90°.
///
/// The overlay sits inside the viewport transform; to keep strokes,
/// ticks, and label text a constant on-screen size at any zoom we
/// divide [strokeWidth] / [tickLength] by [viewportScale] and paint
/// the label glyphs after re-scaling them by `1 / viewportScale`.
class SpacingGuidesOverlay extends StatelessWidget {
  const SpacingGuidesOverlay({
    super.key,
    required this.guides,
    required this.viewportScale,
    this.color = const Color(0xFFFF2D95),
    this.strokeWidth = 1.0,
    this.tickLength = 6.0,
    this.labelStyle = const TextStyle(
      color: Colors.white,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      height: 1.0,
      letterSpacing: 0.1,
    ),
    this.labelBackground = const Color(0xFFFF2D95),
  });

  final List<SpacingGuide> guides;
  final double viewportScale;
  final Color color;

  /// Screen-pixel stroke thickness; divided by [viewportScale].
  final double strokeWidth;

  /// Screen-pixel total length of perpendicular tick caps; divided by
  /// [viewportScale].
  final double tickLength;

  /// Label glyph style. Painted at screen-pixel size by counter-scaling
  /// the canvas by `1 / viewportScale` around the anchor point.
  final TextStyle labelStyle;
  final Color labelBackground;

  @override
  Widget build(BuildContext context) {
    if (guides.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _SpacingGuidesPainter(
          guides: guides,
          color: color,
          strokeWidth: strokeWidth / viewportScale,
          tickHalf: (tickLength / 2) / viewportScale,
          labelStyle: labelStyle,
          labelBackground: labelBackground,
          viewportScale: viewportScale,
        ),
      ),
    );
  }
}

class _SpacingGuidesPainter extends CustomPainter {
  _SpacingGuidesPainter({
    required this.guides,
    required this.color,
    required this.strokeWidth,
    required this.tickHalf,
    required this.labelStyle,
    required this.labelBackground,
    required this.viewportScale,
  });

  final List<SpacingGuide> guides;
  final Color color;
  final double strokeWidth;
  final double tickHalf;
  final TextStyle labelStyle;
  final Color labelBackground;
  final double viewportScale;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = true;
    for (final g in guides) {
      switch (g.axis) {
        case SnapAxis.vertical:
          _drawSegment(
            canvas,
            paint,
            Offset(g.fromStart, g.crossCoord),
            Offset(g.fromEnd, g.crossCoord),
            horizontalAxis: true,
          );
          _drawSegment(
            canvas,
            paint,
            Offset(g.toStart, g.crossCoord),
            Offset(g.toEnd, g.crossCoord),
            horizontalAxis: true,
          );
        case SnapAxis.horizontal:
          _drawSegment(
            canvas,
            paint,
            Offset(g.crossCoord, g.fromStart),
            Offset(g.crossCoord, g.fromEnd),
            horizontalAxis: false,
          );
          _drawSegment(
            canvas,
            paint,
            Offset(g.crossCoord, g.toStart),
            Offset(g.crossCoord, g.toEnd),
            horizontalAxis: false,
          );
      }
      _drawLabel(canvas, g);
    }
  }

  /// Draw a single gap segment plus two perpendicular tick caps so the
  /// segment reads as a measurement bracket.
  void _drawSegment(
    Canvas canvas,
    Paint paint,
    Offset a,
    Offset b, {
    required bool horizontalAxis,
  }) {
    canvas.drawLine(a, b, paint);
    if (horizontalAxis) {
      canvas.drawLine(
        Offset(a.dx, a.dy - tickHalf),
        Offset(a.dx, a.dy + tickHalf),
        paint,
      );
      canvas.drawLine(
        Offset(b.dx, b.dy - tickHalf),
        Offset(b.dx, b.dy + tickHalf),
        paint,
      );
    } else {
      canvas.drawLine(
        Offset(a.dx - tickHalf, a.dy),
        Offset(a.dx + tickHalf, a.dy),
        paint,
      );
      canvas.drawLine(
        Offset(b.dx - tickHalf, b.dy),
        Offset(b.dx + tickHalf, b.dy),
        paint,
      );
    }
  }

  /// Render the gap measurement once per guide as a small rounded pill,
  /// centred between the two equal segments. Painted at screen-pixel
  /// size by counter-scaling the canvas around the anchor so the label
  /// stays crisp and readable at any zoom level.
  void _drawLabel(Canvas canvas, SpacingGuide g) {
    if (g.gap < 0.5) return;
    final tp = TextPainter(
      text: TextSpan(text: g.gap.toStringAsFixed(0), style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    // Padding around the text inside the pill (screen px).
    const padX = 5.0;
    const padY = 2.0;
    final pillW = tp.width + padX * 2;
    final pillH = tp.height + padY * 2;

    // Anchor in canvas space — between the two segments, offset off
    // the line so brackets stay readable.
    Offset anchor;
    switch (g.axis) {
      case SnapAxis.vertical:
        final midX = (g.fromEnd + g.toStart) / 2;
        anchor = Offset(midX, g.crossCoord - 6 / viewportScale);
      case SnapAxis.horizontal:
        final midY = (g.fromEnd + g.toStart) / 2;
        anchor = Offset(g.crossCoord + 6 / viewportScale, midY);
    }

    // Counter-scale so glyphs render at screen-pixel size around the
    // anchor; then translate so the pill is centred horizontally and
    // bottom-aligned (vertical axis) or vertically-centred (horizontal
    // axis) on the anchor.
    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    canvas.scale(1 / viewportScale);
    final Offset pillTopLeft;
    switch (g.axis) {
      case SnapAxis.vertical:
        pillTopLeft = Offset(-pillW / 2, -pillH);
      case SnapAxis.horizontal:
        pillTopLeft = Offset(0, -pillH / 2);
    }
    final pillRect = Rect.fromLTWH(
      pillTopLeft.dx,
      pillTopLeft.dy,
      pillW,
      pillH,
    );
    final rrect = RRect.fromRectAndRadius(pillRect, const Radius.circular(3));
    canvas.drawRRect(rrect, Paint()..color = labelBackground);
    tp.paint(canvas, Offset(pillTopLeft.dx + padX, pillTopLeft.dy + padY));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpacingGuidesPainter old) =>
      old.guides != guides ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.tickHalf != tickHalf ||
      old.labelStyle != labelStyle ||
      old.labelBackground != labelBackground ||
      old.viewportScale != viewportScale;
}
