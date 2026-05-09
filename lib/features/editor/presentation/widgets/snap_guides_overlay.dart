import 'package:flutter/material.dart';

import '../../engine/interaction/snap_engine.dart';

/// Paints the currently-active alignment guides. Pure presentation —
/// reads [SnapGuide] data produced by the snap engine and draws thin
/// lines. Never consumes pointer events (wrapped in [IgnorePointer]).
///
/// The overlay sits *inside* the viewport transform so guides hug
/// canvas-space coordinates pixel-accurately. To keep the lines a
/// constant on-screen thickness regardless of zoom, the supplied
/// [strokeWidth] is divided by [viewportScale] before painting.
class SnapGuidesOverlay extends StatelessWidget {
  const SnapGuidesOverlay({
    super.key,
    required this.guides,
    required this.viewportScale,
    this.color = const Color(0xFFFF2D95),
    this.strokeWidth = 1.0,
  });

  final List<SnapGuide> guides;
  final double viewportScale;
  final Color color;

  /// Stroke thickness in **screen pixels** — the painter divides by
  /// [viewportScale] so the visible width stays constant at any zoom.
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    if (guides.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _SnapGuidesPainter(
          guides: guides,
          color: color,
          strokeWidth: strokeWidth / viewportScale,
        ),
      ),
    );
  }
}

class _SnapGuidesPainter extends CustomPainter {
  _SnapGuidesPainter({
    required this.guides,
    required this.color,
    required this.strokeWidth,
  });

  final List<SnapGuide> guides;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    for (final g in guides) {
      switch (g.axis) {
        case SnapAxis.vertical:
          canvas.drawLine(
            Offset(g.coord, g.start),
            Offset(g.coord, g.end),
            paint,
          );
        case SnapAxis.horizontal:
          canvas.drawLine(
            Offset(g.start, g.coord),
            Offset(g.end, g.coord),
            paint,
          );
      }
    }
  }

  @override
  bool shouldRepaint(_SnapGuidesPainter old) =>
      old.guides != guides ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
