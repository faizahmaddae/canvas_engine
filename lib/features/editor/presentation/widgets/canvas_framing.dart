import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../engine/core/viewport_state.dart';

/// Editor-style framing for the logical canvas.
///
/// Renders three pieces of professional chrome around the document:
///
///   1. A soft drop shadow underneath the canvas, so the document feels
///      elevated above the calm workspace.
///   2. A semi-transparent dim mask covering everything *outside* the
///      canvas. Off-canvas portions of layers are still visible (we
///      don't clip them) but visually recede so the user instantly
///      understands what is part of the final output and what is not.
///   3. A 1-px hairline border around the canvas, so the boundary
///      between in-output and out-of-output is unambiguous even on
///      empty regions.
///
/// v2 identity: every colour comes from the ambient theme
/// ([AppTokens] + [ColorScheme]) — the workspace is warm paper-muted
/// in light and deep ink in dark, never pure black — and the canvas
/// corners are slightly rounded so the document reads as a floating
/// sheet. The rounding is *chrome only*: layers are never clipped;
/// the dim mask simply covers the sub-pixel corner nubs.
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

  /// Slight screen-space corner rounding of the floating canvas.
  static const double cornerRadius = 6;

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
    final tokens = AppTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _CanvasFramingPainter(
            canvasRect: _canvasScreenRect(),
            layer: layer,
            // Dimming matches the workspace hue so off-canvas content
            // recedes into the workspace instead of into a black wash.
            dimColor: tokens.workspace.withValues(alpha: 0.78),
            borderColor: switch (borderEmphasis) {
              CanvasBorderEmphasis.standard => tokens.border,
              CanvasBorderEmphasis.subtle =>
                tokens.border.withValues(alpha: 0.45),
            },
            // scheme.shadow is the theme's shadow ink; dark mode needs
            // a stronger halo to read against the deep-ink workspace.
            shadowColor: scheme.shadow.withValues(alpha: isDark ? 0.5 : 0.22),
          ),
        ),
      ),
    );
  }
}

/// Paint pass identifier so a single painter implementation can serve
/// both the under-document shadow and the over-document dim+border.
enum CanvasFramingLayer { shadowBelow, dimAndBorderAbove }

/// How loudly the canvas border reads against the workspace.
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
    required this.dimColor,
    required this.borderColor,
    required this.shadowColor,
  });

  final Rect canvasRect;
  final CanvasFramingLayer layer;
  final Color dimColor;
  final Color borderColor;
  final Color shadowColor;

  RRect get _canvasRRect => RRect.fromRectAndRadius(
        canvasRect,
        const Radius.circular(CanvasFraming.cornerRadius),
      );

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
    // Inflated, blurred rect — gives the document a soft floating
    // shadow on the workspace. Painted under the document, so the
    // halo only shows around the canvas edges (the document itself
    // covers the shadow inside).
    final paint = Paint()
      ..color = shadowColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawRRect(
      _canvasRRect.shift(const Offset(0, 4)).inflate(2),
      paint,
    );
  }

  void _paintDimMask(Canvas canvas, Size size) {
    // Even-odd fill: the outer rect minus the (rounded) canvas rect
    // leaves a frame shape covering only the off-canvas region. Layers
    // extending outside the canvas are dimmed by this overlay but
    // remain fully visible for selection and recovery.
    final viewport = Offset.zero & size;
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(viewport)
      ..addRRect(_canvasRRect);
    canvas.drawPath(path, Paint()..color = dimColor);
  }

  void _paintBorder(Canvas canvas) {
    // 1-logical-px stroke; anti-aliased because the rounded corners
    // would otherwise stair-step.
    final paint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;
    canvas.drawRRect(_canvasRRect, paint);
  }

  @override
  bool shouldRepaint(_CanvasFramingPainter old) =>
      old.canvasRect != canvasRect ||
      old.layer != layer ||
      old.dimColor != dimColor ||
      old.borderColor != borderColor ||
      old.shadowColor != shadowColor;
}
