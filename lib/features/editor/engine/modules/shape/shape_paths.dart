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

  /// Regular polygon with [sides] corners inscribed in the [size]
  /// ellipse (radii w/2 × h/2), starting at [startAngle]. Scaling to
  /// the ellipse — rather than the shorter side's circle — keeps the
  /// silhouette filling its box when a free-resize user stretches it.
  static Path _regularPolygon(Size size, int sides, double startAngle) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final p = Path();
    for (var i = 0; i < sides; i++) {
      final theta = startAngle + i * 2 * math.pi / sides;
      final x = cx + cx * math.cos(theta);
      final y = cy + cy * math.sin(theta);
      i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    p.close();
    return p;
  }

  /// Regular pentagon, point up.
  static Path pentagon(Size size) => _regularPolygon(size, 5, -math.pi / 2);

  /// Regular octagon, flat top (the stop-sign orientation).
  static Path octagon(Size size) =>
      _regularPolygon(size, 8, -math.pi / 2 + math.pi / 8);

  /// Upper half-ellipse dome with a flat bottom edge.
  static Path semicircle(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(0, h)
      // The full ellipse is twice the box height; sweeping the top
      // half traces the dome from the left corner over to the right.
      ..arcTo(Rect.fromLTWH(0, 0, w, h * 2), math.pi, math.pi, false)
      ..close();
  }

  /// Right triangle — right angle at the bottom-left, hypotenuse
  /// rising to the top-left corner's opposite.
  static Path rightTriangle(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  /// Parallelogram leaning right — top edge shifted by a fixed
  /// fraction of the width.
  static Path parallelogram(Size size) {
    final w = size.width;
    final h = size.height;
    final skew = w * 0.22;
    return Path()
      ..moveTo(skew, 0)
      ..lineTo(w, 0)
      ..lineTo(w - skew, h)
      ..lineTo(0, h)
      ..close();
  }

  /// Isosceles trapezoid — top edge inset symmetrically.
  static Path trapezoid(Size size) {
    final w = size.width;
    final h = size.height;
    final inset = w * 0.22;
    return Path()
      ..moveTo(inset, 0)
      ..lineTo(w - inset, 0)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
  }

  /// Ring / donut — the box ellipse minus a concentric inner
  /// ellipse. Even-odd fill keeps the hole a real hole for fills,
  /// and a stroke traces both edges of the band.
  static Path ring(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Offset.zero & size)
      ..addOval(Rect.fromLTWH(w * 0.19, h * 0.19, w * 0.62, h * 0.62));
  }

  /// Four-point sparkle — N/E/S/W points joined by concave
  /// quadratics pulled toward the centre, the classic "twinkle".
  static Path sparkle(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w / 2, 0)
      ..quadraticBezierTo(w * 0.60, h * 0.40, w, h / 2)
      ..quadraticBezierTo(w * 0.60, h * 0.60, w / 2, h)
      ..quadraticBezierTo(w * 0.40, h * 0.60, 0, h / 2)
      ..quadraticBezierTo(w * 0.40, h * 0.40, w / 2, 0)
      ..close();
  }

  /// Twelve-point badge burst — a shallow starburst (inner radius
  /// 82 % of outer) scaled to the box ellipse, the classic seal /
  /// price-badge silhouette.
  static Path seal(Size size) {
    const points = 12;
    const innerFactor = 0.82;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final p = Path();
    const start = -math.pi / 2;
    for (var i = 0; i < points * 2; i++) {
      final f = i.isEven ? 1.0 : innerFactor;
      final theta = start + i * math.pi / points;
      final x = cx + cx * f * math.cos(theta);
      final y = cy + cy * f * math.sin(theta);
      i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    p.close();
    return p;
  }

  /// Lightning bolt — the classic seven-point zigzag polygon.
  static Path bolt(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * 0.62, 0)
      ..lineTo(w * 0.10, h * 0.60)
      ..lineTo(w * 0.42, h * 0.60)
      ..lineTo(w * 0.30, h)
      ..lineTo(w * 0.90, h * 0.38)
      ..lineTo(w * 0.55, h * 0.38)
      ..close();
  }

  /// Heater shield — softly-rounded top corners, sides curving to a
  /// bottom point.
  static Path shield(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w / 2, h)
      ..cubicTo(w * 0.10, h * 0.82, 0, h * 0.58, 0, h * 0.22)
      ..lineTo(0, h * 0.10)
      ..quadraticBezierTo(0, 0, w * 0.10, 0)
      ..lineTo(w * 0.90, 0)
      ..quadraticBezierTo(w, 0, w, h * 0.10)
      ..lineTo(w, h * 0.22)
      ..cubicTo(w, h * 0.58, w * 0.90, h * 0.82, w / 2, h)
      ..close();
  }

  /// Crescent moon — the box ellipse minus the same ellipse shifted
  /// right, leaving a vertical crescent with its horns opening to
  /// the right. Boolean difference keeps the outline a single clean
  /// curve for strokes and shadows.
  static Path crescent(Size size) {
    final w = size.width;
    final full = Path()..addOval(Offset.zero & size);
    final cutter = Path()
      ..addOval((Offset.zero & size).shift(Offset(w * 0.38, 0)));
    return Path.combine(PathOperation.difference, full, cutter);
  }

  /// Cloud — three overlapping bumps unioned onto a wide base pill
  /// so the outline is one seamless silhouette (a plain multi-oval
  /// path would show internal seams the moment a border is applied).
  static Path cloud(Size size) {
    final w = size.width;
    final h = size.height;
    Path oval(double l, double t, double ow, double oh) =>
        Path()..addOval(Rect.fromLTWH(l * w, t * h, ow * w, oh * h));
    final base = Path()
      ..addRRect(
        RRect.fromLTRBR(
          0,
          h * 0.50,
          w,
          h,
          Radius.elliptical(w * 0.16, h * 0.25),
        ),
      );
    var p = Path.combine(
      PathOperation.union,
      base,
      oval(0.08, 0.30, 0.38, 0.48),
    );
    p = Path.combine(PathOperation.union, p, oval(0.30, 0.12, 0.44, 0.62));
    p = Path.combine(PathOperation.union, p, oval(0.56, 0.32, 0.36, 0.46));
    return p;
  }

  /// Thought bubble — a big oval body trailing two detached puffs
  /// toward the bottom-left, the comic-strip thought balloon.
  static Path thoughtBubble(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..addOval(Rect.fromLTWH(0, 0, w, h * 0.72))
      ..addOval(Rect.fromLTWH(w * 0.20, h * 0.74, w * 0.16, h * 0.14))
      ..addOval(Rect.fromLTWH(w * 0.10, h * 0.90, w * 0.10, h * 0.09));
  }
}
