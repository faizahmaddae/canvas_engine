import 'dart:math' as math;
import 'dart:ui';

/// Pure helpers that build [Path]s for the non-trivial primitive shape
/// kinds. Kept outside [ShapeLayer] so the painter and any future
/// hit-testing code can share the exact same geometry, and so the
/// curves are unit-testable without spinning up a widget tree.
class ShapePaths {
  ShapePaths._();

  /// Equilateral-ish triangle pointing up, spanning the full [size].
  static Path triangle(Size size) {
    final p = Path();
    p.moveTo(size.width / 2, 0);
    p.lineTo(size.width, size.height);
    p.lineTo(0, size.height);
    p.close();
    return p;
  }

  /// 4-point diamond inscribed in [size].
  static Path diamond(Size size) {
    final p = Path();
    p.moveTo(size.width / 2, 0);
    p.lineTo(size.width, size.height / 2);
    p.lineTo(size.width / 2, size.height);
    p.lineTo(0, size.height / 2);
    p.close();
    return p;
  }

  /// Classic 5-point star inscribed in [size]. Outer radius hugs the
  /// shorter side; inner radius is the canonical golden-ratio derived
  /// value so the star reads as a star at any aspect.
  static Path star(Size size) {
    const points = 5;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outerR = math.min(size.width, size.height) / 2;
    final innerR = outerR * 0.40;
    final p = Path();
    // Start at the top point.
    final start = -math.pi / 2;
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? outerR : innerR;
      final theta = start + i * math.pi / points;
      final x = cx + r * math.cos(theta);
      final y = cy + r * math.sin(theta);
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    p.close();
    return p;
  }

  /// Symmetric heart inscribed in [size] — two top arcs joined to a
  /// bottom point. Implementation uses cubic curves so the silhouette
  /// stays smooth at any size.
  static Path heart(Size size) {
    final w = size.width;
    final h = size.height;
    final p = Path();
    // Bottom point.
    p.moveTo(w / 2, h);
    // Up the left side via a cubic to the top-left arc.
    p.cubicTo(
      -w * 0.05,
      h * 0.65, // ctl1 (out from bottom point, left)
      w * 0.05,
      h * 0.10, // ctl2 (up high on the left)
      w * 0.50,
      h * 0.30, // mid-top dip
    );
    // Up and over the right arc back to the bottom point.
    p.cubicTo(w * 0.95, h * 0.10, w * 1.05, h * 0.65, w / 2, h);
    p.close();
    return p;
  }

  /// Horizontal line spanning the full width, centred vertically.
  /// Returned as a 2-point path the painter strokes (no fill).
  static Path line(Size size) {
    final cy = size.height / 2;
    return Path()
      ..moveTo(0, cy)
      ..lineTo(size.width, cy);
  }

  /// Horizontal arrow: a stroked shaft plus a triangular head at the
  /// right edge. Returned as a single closed-ish path that the painter
  /// strokes — no fill — using the arrow's colour at the layer's
  /// stroke width.
  static Path arrow(Size size) {
    final cy = size.height / 2;
    final headSize = math.min(size.height * 0.9, size.width * 0.45);
    final shaftEnd = size.width - headSize * 0.6;
    return Path()
      ..moveTo(0, cy)
      ..lineTo(shaftEnd, cy)
      ..moveTo(size.width, cy)
      ..lineTo(size.width - headSize, cy - headSize / 2)
      ..moveTo(size.width, cy)
      ..lineTo(size.width - headSize, cy + headSize / 2);
  }

  /// Horizontal arrow pointing left. Mirror of [arrow] across the
  /// vertical centre.
  static Path arrowLeft(Size size) {
    final cy = size.height / 2;
    final headSize = math.min(size.height * 0.9, size.width * 0.45);
    final shaftStart = headSize * 0.6;
    return Path()
      ..moveTo(size.width, cy)
      ..lineTo(shaftStart, cy)
      ..moveTo(0, cy)
      ..lineTo(headSize, cy - headSize / 2)
      ..moveTo(0, cy)
      ..lineTo(headSize, cy + headSize / 2);
  }

  /// Vertical arrow pointing up.
  static Path arrowUp(Size size) {
    final cx = size.width / 2;
    final headSize = math.min(size.width * 0.9, size.height * 0.45);
    final shaftStart = headSize * 0.6;
    return Path()
      ..moveTo(cx, size.height)
      ..lineTo(cx, shaftStart)
      ..moveTo(cx, 0)
      ..lineTo(cx - headSize / 2, headSize)
      ..moveTo(cx, 0)
      ..lineTo(cx + headSize / 2, headSize);
  }

  /// Vertical arrow pointing down.
  static Path arrowDown(Size size) {
    final cx = size.width / 2;
    final headSize = math.min(size.width * 0.9, size.height * 0.45);
    final shaftEnd = size.height - headSize * 0.6;
    return Path()
      ..moveTo(cx, 0)
      ..lineTo(cx, shaftEnd)
      ..moveTo(cx, size.height)
      ..lineTo(cx - headSize / 2, size.height - headSize)
      ..moveTo(cx, size.height)
      ..lineTo(cx + headSize / 2, size.height - headSize);
  }

  /// Regular hexagon (flat-top) inscribed in [size]. The two flat
  /// sides are at top and bottom; left/right are pointed corners.
  static Path hexagon(Size size) {
    final w = size.width;
    final h = size.height;
    // 1/4 inset on the horizontal so the hex reads cleanly at any
    // aspect ratio without becoming a stretched stop sign.
    final dx = w * 0.25;
    return Path()
      ..moveTo(dx, 0)
      ..lineTo(w - dx, 0)
      ..lineTo(w, h / 2)
      ..lineTo(w - dx, h)
      ..lineTo(dx, h)
      ..lineTo(0, h / 2)
      ..close();
  }

  /// Speech bubble — rounded-rect body with a small triangular tail
  /// at the bottom-left corner. Body fills the upper ~78 % of [size];
  /// the tail occupies the lower-left quadrant so a freshly inserted
  /// bubble already looks like a speech balloon without any tweak.
  static Path speechBubble(Size size) {
    final w = size.width;
    final h = size.height;
    final bodyH = h * 0.78;
    final r = math.min(w, bodyH) * 0.18;
    final body = RRect.fromLTRBR(0, 0, w, bodyH, Radius.circular(r));
    final tailLeft = w * 0.18;
    final tailRight = w * 0.36;
    final tailTip = Offset(w * 0.22, h);
    return Path()
      ..addRRect(body)
      ..moveTo(tailLeft, bodyH - 1) // -1 to overlap and avoid a seam
      ..lineTo(tailRight, bodyH - 1)
      ..lineTo(tailTip.dx, tailTip.dy)
      ..close();
  }

  /// Quote bubble — two oversized opening-quote glyphs filling [size].
  /// Each glyph is a comma-shaped lobe; together they read as the
  /// classic "double opening quote" mark.
  static Path quoteBubble(Size size) {
    final w = size.width;
    final h = size.height;
    final lobeW = w * 0.42;
    final lobeH = h * 0.7;
    final gap = w * 0.06;
    final yTop = h * 0.12;

    Path lobe(double left) {
      // A rounded blob with a small tail at the bottom-left so it
      // reads as a quotation mark rather than a pebble.
      final right = left + lobeW;
      final bottom = yTop + lobeH;
      final rr = math.min(lobeW, lobeH) * 0.45;
      final p = Path()
        ..addRRect(
          RRect.fromLTRBR(left, yTop, right, bottom, Radius.circular(rr)),
        );
      // Triangular tail under the lobe, anchored to its lower-left.
      final tailLeft = left + lobeW * 0.18;
      final tailRight = left + lobeW * 0.55;
      final tailTip = Offset(left + lobeW * 0.05, bottom + lobeH * 0.35);
      return p
        ..moveTo(tailLeft, bottom - 1)
        ..lineTo(tailRight, bottom - 1)
        ..lineTo(tailTip.dx, tailTip.dy)
        ..close();
    }

    final leftLobe = lobe(0);
    final rightLobe = lobe(lobeW + gap + (w - 2 * lobeW - gap) / 2);
    return Path()
      ..addPath(leftLobe, Offset.zero)
      ..addPath(rightLobe, Offset.zero);
  }

  /// Plus / cross-shape, filled. Two overlapping rectangles sharing
  /// the centre — the horizontal bar runs full width, the vertical
  /// bar runs full height. Bar thickness is ~32 % of the shorter
  /// side so the plus reads as chunky and friendly at every size.
  static Path plus(Size size) {
    final w = size.width;
    final h = size.height;
    final t = math.min(w, h) * 0.32;
    final hx = (w - t) / 2;
    final hy = (h - t) / 2;
    return Path()
      ..addRect(Rect.fromLTWH(hx, 0, t, h))
      ..addRect(Rect.fromLTWH(0, hy, w, t));
  }

  /// Check-mark glyph as an open stroked path. Two segments meeting
  /// at the lower-left point of the tick.
  static Path check(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * 0.12, h * 0.55)
      ..lineTo(w * 0.42, h * 0.82)
      ..lineTo(w * 0.92, h * 0.20);
  }

  /// X / cross — two open diagonal stroke segments.
  static Path cross(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * 0.15, h * 0.15)
      ..lineTo(w * 0.85, h * 0.85)
      ..moveTo(w * 0.85, h * 0.15)
      ..lineTo(w * 0.15, h * 0.85);
  }
}
