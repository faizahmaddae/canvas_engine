import 'package:flutter/material.dart';

import '../../engine/core/viewport_state.dart';

/// Editor-style framing for the logical canvas.
///
/// Renders three pieces of professional chrome around the document:
///
///   1. A soft drop shadow underneath the canvas, so the document feels
///      elevated above the dark workbench.
///   2. A semi-transparent dim mask covering everything *outside* the
///      canvas. Off-canvas portions of layers are still visible (we
///      don't clip them) but visually recede so the user instantly
///      understands what is part of the final output and what is not.
///   3. A 1-px hairline border around the canvas, so the boundary
///      between in-output and out-of-output is unambiguous even on
///      empty regions.
///
/// All three pieces are painted in *screen space* using the canvas's
/// projected screen-space rect, so they stay crisp at any zoom and
/// never scale with the document.
///
/// Editor-only: this widget is mounted by `editor_canvas.dart`. The
/// pure rendering path used by the exporter (`DocumentView`) does not
/// include it, so the framing is **never** part of the saved bitmap.
class CanvasFraming extends StatelessWidget {
  const CanvasFraming({
    super.key,
    required this.docSize,
    required this.viewport,
    required this.layer,
    this.borderEmphasis = CanvasBorderEmphasis.standard,
  });

  /// Logical canvas size in document pixels.
  final Size docSize;

  /// Current viewport — used to compute the canvas's screen-space rect.
  final ViewportState viewport;

  /// Which framing element to paint. Two passes are needed because the
  /// drop shadow must sit *under* the document and the dim mask + border
  /// must sit *over* it.
  final CanvasFramingLayer layer;

  /// How loud the hairline canvas border is. Photo projects pick
  /// [CanvasBorderEmphasis.subtle] so the border doesn't trace the
  /// imported photo's edge in a way that reads like a selection
  /// outline; design projects keep [CanvasBorderEmphasis.standard] so
  /// the artboard bounds are clearly visible against an empty canvas.
  /// Ignored for the [CanvasFramingLayer.shadowBelow] pass.
  final CanvasBorderEmphasis borderEmphasis;

  Rect _canvasScreenRect() {
    final tl = viewport.translation;
    return Rect.fromLTWH(
      tl.dx,
      tl.dy,
      docSize.width * viewport.scale,
      docSize.height * viewport.scale,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _CanvasFramingPainter(
            canvasRect: _canvasScreenRect(),
            layer: layer,
            borderEmphasis: borderEmphasis,
          ),
        ),
      ),
    );
  }
}

/// Paint pass identifier so a single painter implementation can serve
/// both the under-document shadow and the over-document dim+border.
enum CanvasFramingLayer { shadowBelow, dimAndBorderAbove }

/// How loudly the canvas border reads against the workbench.
///
///   * [standard] -- the default. Suitable for blank/design canvases
///     where the border is the only edge cue.
///   * [subtle] -- ~half the alpha. Used when the document is fully
///     covered by content of its own (e.g. an imported photo) so the
///     border doesn't trace that content's edge in a way that reads
///     like a selection outline.
enum CanvasBorderEmphasis { standard, subtle }

class _CanvasFramingPainter extends CustomPainter {
  _CanvasFramingPainter({
    required this.canvasRect,
    required this.layer,
    required this.borderEmphasis,
  });

  final Rect canvasRect;
  final CanvasFramingLayer layer;
  final CanvasBorderEmphasis borderEmphasis;

  /// Subtle dim applied to off-canvas regions. Matches the workbench
  /// hue so the dimming reads as continuous shadowing rather than a
  /// translucent black wash.
  static const Color _dimColor = Color(0x66050608);

  /// Hairline boundary stroke -- standard emphasis. Slightly lighter
  /// than the workbench so the canvas edge is unmistakable on every
  /// background.
  static const Color _borderColorStandard = Color(0x55FFFFFF);

  /// Subtle variant -- about 40% as strong. Keeps the artboard hint
  /// without competing with content edges (typical of photo projects
  /// where the base photo already paints to the canvas edge).
  static const Color _borderColorSubtle = Color(0x22FFFFFF);

  Color get _borderColor => switch (borderEmphasis) {
    CanvasBorderEmphasis.standard => _borderColorStandard,
    CanvasBorderEmphasis.subtle => _borderColorSubtle,
  };

  @override
  void paint(Canvas canvas, Size size) {
    switch (layer) {
      case CanvasFramingLayer.shadowBelow:
        _paintShadow(canvas);
      case CanvasFramingLayer.dimAndBorderAbove:
        _paintDimMask(canvas, size);
        _paintBorder(canvas);
    }
  }

  void _paintShadow(Canvas canvas) {
    // Inflated, blurred dark rect — gives the document a soft floating
    // shadow on the workbench. Painted under the document, so the dark
    // halo only shows around the canvas edges (the document itself
    // covers the shadow inside).
    final paint = Paint()
      ..color = const Color(0x80000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawRect(canvasRect.translate(0, 4).inflate(2), paint);
  }

  void _paintDimMask(Canvas canvas, Size size) {
    // Even-odd fill: the outer rect minus the canvas rect leaves a
    // frame shape covering only the off-canvas region. Layers extending
    // outside the canvas are dimmed by this overlay but remain fully
    // visible for selection and recovery.
    final viewport = Offset.zero & size;
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(viewport)
      ..addRect(canvasRect);
    canvas.drawPath(path, Paint()..color = _dimColor);
  }

  void _paintBorder(Canvas canvas) {
    // 1-logical-px stroke aligned to pixel centres for crispness.
    final paint = Paint()
      ..color = _borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = false;
    canvas.drawRect(canvasRect, paint);
  }

  @override
  bool shouldRepaint(_CanvasFramingPainter old) =>
      old.canvasRect != canvasRect ||
      old.layer != layer ||
      old.borderEmphasis != borderEmphasis;
}
