import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
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
    this.color,
    this.strokeWidth = 1.0,
  });

  final List<SnapGuide> guides;
  final double viewportScale;

  /// Overrides the theme-resolved guide colour. `null` uses the
  /// token — see [_guideColor].
  final Color? color;

  /// Stroke thickness in **screen pixels** — the painter divides by
  /// [viewportScale] so the visible width stays constant at any zoom.
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    if (guides.isEmpty) return const SizedBox.shrink();
    final guideColor = color ?? _guideColor(context);
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _SnapGuidesPainter(
          guides: guides,
          color: guideColor,
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

/// Guides read as the app's teal, not as a magenta left over from a
/// retired palette.
///
/// Teal is one of the three category accents, which are deliberately
/// FIXED across light and dark — so a guide keeps a constant identity
/// while paper and ink swap around it. It is also not saffron, which
/// matters: saffron is selection chrome, and a guide that shared its
/// colour would read as part of the thing being dragged rather than
/// as the alignment it snapped to.
Color _guideColor(BuildContext context) => AppTokens.of(context).teal;
