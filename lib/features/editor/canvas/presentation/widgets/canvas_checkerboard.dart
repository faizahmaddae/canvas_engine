import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../../../../app/theme/app_tokens.dart';

/// Tiled checkerboard backdrop signalling transparency. Used by:
///   * the editor canvas when [CanvasBackgroundMode.transparent] is
///     active, so the user can see what "empty" means;
///   * the export preview, so PNG alpha is visible.
///
/// Paints at a fixed tile size in *logical pixels*. Sits inside the
/// canvas's logical-pixel coordinate system, so as the viewport zooms
/// the tiles zoom with the canvas -- the same way a hand-painted
/// background colour would.
///
/// Colours default to the theme's surface pair so the pattern reads
/// as chrome in both light and dark rather than punching a permanent
/// white hole into a dark editor.
class CanvasCheckerboard extends StatelessWidget {
  const CanvasCheckerboard({super.key, this.light, this.dark, this.tile = 12});

  /// Overrides the theme-resolved light square. Rarely needed.
  final Color? light;

  /// Overrides the theme-resolved dark square.
  final Color? dark;

  final double tile;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return CustomPaint(
      painter: _CheckerboardPainter(
        light: light ?? tokens.surface,
        dark: dark ?? tokens.surfaceMuted,
        tile: tile,
      ),
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

  /// One 2×2-tile bitmap, tiled by the GPU.
  ///
  /// The old painter walked every tile and issued a `drawRect` per
  /// dark square: a 4000×4000 canvas at the default 12dp tile is
  /// ~111k draw calls PER PAINT, and this widget repaints on every
  /// viewport change. The pattern is periodic, so the whole thing is
  /// one `drawRect` with a repeating [ui.ImageShader] instead.
  ///
  /// Keyed on the three inputs and shared across every instance:
  /// the editor canvas and the export preview draw the same board.
  static final Map<(int, int, int), ui.Image> _tileCache =
      <(int, int, int), ui.Image>{};

  ui.Image _tileImage() {
    // Rounded to whole device-independent pixels so the cache key is
    // stable and the bitmap edges land on pixel boundaries.
    final side = tile.round().clamp(1, 512);
    final key = (light.toARGB32(), dark.toARGB32(), side);
    final cached = _tileCache[key];
    if (cached != null) return cached;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final lightPaint = Paint()..color = light;
    final darkPaint = Paint()..color = dark;
    final s = side.toDouble();
    canvas.drawRect(Rect.fromLTWH(0, 0, s * 2, s * 2), lightPaint);
    canvas.drawRect(Rect.fromLTWH(s, 0, s, s), darkPaint);
    canvas.drawRect(Rect.fromLTWH(0, s, s, s), darkPaint);
    final image = recorder.endRecording().toImageSync(side * 2, side * 2);
    _tileCache[key] = image;
    return image;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final image = _tileImage();
    // The bitmap is authored at `side` logical pixels per square, so
    // the shader needs no scale — identity keeps the squares crisp.
    final paint = Paint()
      ..shader = ui.ImageShader(
        image,
        TileMode.repeated,
        TileMode.repeated,
        Matrix4.identity().storage,
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _CheckerboardPainter old) =>
      old.light != light || old.dark != dark || old.tile != tile;
}
