import 'package:flutter/widgets.dart';

/// Tiled checkerboard backdrop signalling transparency. Used by:
///   * the editor canvas when [CanvasBackgroundMode.transparent] is
///     active, so the user can see what "empty" means;
///   * the export preview, so PNG alpha is visible.
///
/// Paints at a fixed tile size in *logical pixels*. Sits inside the
/// canvas's logical-pixel coordinate system, so as the viewport zooms
/// the tiles zoom with the canvas -- the same way a hand-painted
/// background colour would.
class CanvasCheckerboard extends StatelessWidget {
  const CanvasCheckerboard({
    super.key,
    this.light = const Color(0xFFFFFFFF),
    this.dark = const Color(0xFFE5E7EB),
    this.tile = 12,
  });

  final Color light;
  final Color dark;
  final double tile;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CheckerboardPainter(light: light, dark: dark, tile: tile),
      // Empty child so the painter fills its parent's bounds.
      child: const SizedBox.expand(),
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  _CheckerboardPainter({
    required this.light,
    required this.dark,
    required this.tile,
  });

  final Color light;
  final Color dark;
  final double tile;

  @override
  void paint(Canvas canvas, Size size) {
    final lightPaint = Paint()..color = light;
    final darkPaint = Paint()..color = dark;
    canvas.drawRect(Offset.zero & size, lightPaint);
    final cols = (size.width / tile).ceil();
    final rows = (size.height / tile).ceil();
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if ((r + c).isOdd) {
          canvas.drawRect(
            Rect.fromLTWH(c * tile, r * tile, tile, tile),
            darkPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerboardPainter old) =>
      old.light != light || old.dark != dark || old.tile != tile;
}
