import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/editor_layer.dart';
import '../../core/layer_capabilities.dart';
import '../../core/layer_transform.dart';

/// Paint primitive kinds. New kinds plug in here without changes to
/// the gesture pipeline as long as their geometry can be expressed as
/// a [PaintLayer] (points + bounding box, optionally `sides` /
/// `blurSigma`).
enum PaintKind {
  freestyle,
  line,
  arrow,
  rectangle,
  circle,
  dashLine,
  dashDotLine,
  hexagon,
  polygon,
  blur,
}

/// How a [PaintLayer] reacts when its bounding box is resized.
///
/// The Paint floating toolbar exposes this as a per-layer choice
/// ("Resize behavior"). It is not a global app setting.
///
/// * [free] — default. Width and height resize independently. Corner
///   drag can stretch / squash the shape. Matches the historical
///   behavior of paint layers.
/// * [scale] — aspect-locked. Corner drag preserves the shape's
///   original proportions. Useful for objects that must keep their
///   form (circle stays a circle, hexagon stays regular).
enum PaintResizeMode { free, scale }

/// A finished paint stroke / shape committed to the document.
///
/// Geometry is stored as **normalized 0..1 points relative to the
/// bounding [transform.size]**. That keeps PaintLayer compatible with
/// the generic transform pipeline: resize the bounding box and the path
/// stretches naturally, no special-case math required. Stroke width is
/// kept in absolute canvas pixels so resizing doesn't fatten the line.
///
/// For [PaintKind.rectangle], [PaintKind.circle], [PaintKind.hexagon],
/// [PaintKind.polygon] and [PaintKind.blur] the [normalizedPoints]
/// list is unused at render time — the bounding box itself IS the
/// shape (or, for blur, the region to filter).
class PaintLayer extends EditorLayer {
  const PaintLayer({
    required super.id,
    required super.transform,
    required this.kind,
    required this.normalizedPoints,
    this.strokeColor = const Color(0xFFFF3B30),
    this.strokeWidth = 6.0,
    this.fillColor,
    this.sides = 6,
    this.blurSigma = 12.0,
    this.resizeMode = PaintResizeMode.free,
    super.name,
    super.visible,
    super.locked,
    super.opacity,
  }) : super(
          capabilities: resizeMode == PaintResizeMode.scale
              ? _paintCapsScale
              : _paintCapsFree,
        );

  final PaintKind kind;
  final List<Offset> normalizedPoints;
  final Color strokeColor;
  final double strokeWidth;
  final Color? fillColor;

  /// Number of sides for [PaintKind.polygon] / [PaintKind.hexagon].
  /// Hexagon ignores this and uses 6.
  final int sides;

  /// Gaussian blur sigma for [PaintKind.blur]. Pixels of the underlying
  /// composition are blurred by this much; ignored for other kinds.
  final double blurSigma;

  /// How corner-drag resizes the bounding box. See [PaintResizeMode].
  final PaintResizeMode resizeMode;

  /// Capabilities for [PaintResizeMode.free] — corner drag stretches
  /// independently in both axes. Historical default.
  static const _paintCapsFree = LayerCapabilities(editable: false);

  /// Capabilities for [PaintResizeMode.scale] — corner drag preserves
  /// aspect ratio so the shape keeps its proportions.
  static const _paintCapsScale = LayerCapabilities(
    editable: false,
    keepsAspectRatio: true,
  );

  @override
  String get type => 'paint';

  @override
  EditorLayer withTransform(LayerTransform transform) => PaintLayer(
        id: id,
        transform: transform,
        kind: kind,
        normalizedPoints: normalizedPoints,
        strokeColor: strokeColor,
        strokeWidth: strokeWidth,
        fillColor: fillColor,
        sides: sides,
        blurSigma: blurSigma,
        resizeMode: resizeMode,
        name: name,
        visible: visible,
        locked: locked,
        opacity: opacity,
      );

  @override
  EditorLayer withVisibility(bool visible) => PaintLayer(
        id: id,
        transform: transform,
        kind: kind,
        normalizedPoints: normalizedPoints,
        strokeColor: strokeColor,
        strokeWidth: strokeWidth,
        fillColor: fillColor,
        sides: sides,
        blurSigma: blurSigma,
        resizeMode: resizeMode,
        name: name,
        visible: visible,
        locked: locked,
        opacity: opacity,
      );

  @override
  EditorLayer withLocked(bool locked) => PaintLayer(
        id: id,
        transform: transform,
        kind: kind,
        normalizedPoints: normalizedPoints,
        strokeColor: strokeColor,
        strokeWidth: strokeWidth,
        fillColor: fillColor,
        sides: sides,
        blurSigma: blurSigma,
        resizeMode: resizeMode,
        name: name,
        visible: visible,
        locked: locked,
        opacity: opacity,
      );

  @override
  EditorLayer withOpacity(double opacity) => PaintLayer(
        id: id,
        transform: transform,
        kind: kind,
        normalizedPoints: normalizedPoints,
        strokeColor: strokeColor,
        strokeWidth: strokeWidth,
        fillColor: fillColor,
        sides: sides,
        blurSigma: blurSigma,
        resizeMode: resizeMode,
        name: name,
        visible: visible,
        locked: locked,
        opacity: opacity.clamp(0.0, 1.0),
      );

  /// Returns a copy with the given fields replaced. The sentinel
  /// pattern on [fillColor] preserves the ability to clear it (set to
  /// null) versus leaving it untouched.
  PaintLayer copyWith({
    Color? strokeColor,
    double? strokeWidth,
    Object? fillColor = _sentinel,
    int? sides,
    double? blurSigma,
    PaintResizeMode? resizeMode,
    String? name,
  }) {
    return PaintLayer(
      id: id,
      transform: transform,
      kind: kind,
      normalizedPoints: normalizedPoints,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      fillColor:
          identical(fillColor, _sentinel) ? this.fillColor : fillColor as Color?,
      sides: sides ?? this.sides,
      blurSigma: blurSigma ?? this.blurSigma,
      resizeMode: resizeMode ?? this.resizeMode,
      name: name ?? this.name,
      visible: visible,
      locked: locked,
      opacity: opacity,
    );
  }

  static const Object _sentinel = Object();

  @override
  Widget buildContent(BuildContext context) {
    // Blur is the one kind that can't be rendered with a CustomPaint:
    // it has to read the underlying composition. A `BackdropFilter`
    // inside a `ClipRect` does the right thing — Flutter blurs the
    // pixels currently behind this layer, gets composited into the
    // engine like any other widget, and exports correctly via
    // RepaintBoundary.toImage().
    if (kind == PaintKind.blur) {
      return ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: const SizedBox.expand(),
        ),
      );
    }
    return CustomPaint(
      painter: PaintLayerPainter(
        kind: kind,
        normalizedPoints: normalizedPoints,
        strokeColor: strokeColor,
        strokeWidth: strokeWidth,
        fillColor: fillColor,
        sides: sides,
      ),
      size: Size.infinite,
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        ...baseJson(),
        'kind': kind.name,
        'points': normalizedPoints
            .map((p) => <String, double>{'x': p.dx, 'y': p.dy})
            .toList(growable: false),
        'strokeColor': _encodeColor(strokeColor),
        'strokeWidth': strokeWidth,
        if (fillColor != null) 'fillColor': _encodeColor(fillColor!),
        if (kind == PaintKind.polygon || kind == PaintKind.hexagon)
          'sides': sides,
        if (kind == PaintKind.blur) 'blurSigma': blurSigma,
        'resizeMode': resizeMode.name,
      };

  factory PaintLayer.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String) {
      throw const FormatException('PaintLayer.id missing or not a string');
    }
    final transformJson = json['transform'];
    if (transformJson is! Map) {
      throw const FormatException('PaintLayer.transform missing');
    }
    final kindName = json['kind'];
    final kind = kindName is String
        ? PaintKind.values.firstWhere(
            (k) => k.name == kindName,
            orElse: () => PaintKind.freestyle,
          )
        : PaintKind.freestyle;
    final rawPoints = json['points'];
    final points = <Offset>[];
    if (rawPoints is List) {
      for (final entry in rawPoints) {
        if (entry is Map) {
          final x = (entry['x'] as num?)?.toDouble();
          final y = (entry['y'] as num?)?.toDouble();
          if (x != null && y != null) points.add(Offset(x, y));
        }
      }
    }
    return PaintLayer(
      id: id,
      transform: LayerTransform.fromJson(
        Map<String, dynamic>.from(transformJson),
      ),
      kind: kind,
      normalizedPoints: List.unmodifiable(points),
      strokeColor:
          _decodeColor(json['strokeColor']) ?? const Color(0xFFFF3B30),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 6.0,
      fillColor: _decodeColor(json['fillColor']),
      sides: (kind == PaintKind.polygon || kind == PaintKind.hexagon)
          ? ((json['sides'] as num?)?.toInt() ?? 6)
          : 6,
      blurSigma: kind == PaintKind.blur
          ? ((json['blurSigma'] as num?)?.toDouble() ?? 12.0)
          : 12.0,
      resizeMode: _decodeResizeMode(json['resizeMode']),
      name: json['name'] as String?,
      visible: json['visible'] as bool? ?? true,
      locked: json['locked'] as bool? ?? false,
      opacity: ((json['opacity'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0),
    );
  }

  // Older saves predate the resizeMode field; default to `free` so
  // they keep their historical behaviour exactly.
  static PaintResizeMode _decodeResizeMode(Object? raw) {
    if (raw is! String) return PaintResizeMode.free;
    return PaintResizeMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => PaintResizeMode.free,
    );
  }

  static int _encodeColor(Color c) {
    final a = (c.a * 255.0).round() & 0xff;
    final r = (c.r * 255.0).round() & 0xff;
    final g = (c.g * 255.0).round() & 0xff;
    final b = (c.b * 255.0).round() & 0xff;
    return (a << 24) | (r << 16) | (g << 8) | b;
  }

  static Color? _decodeColor(Object? raw) {
    if (raw is! num) return null;
    final v = raw.toInt();
    return Color.from(
      alpha: ((v >> 24) & 0xff) / 255.0,
      red: ((v >> 16) & 0xff) / 255.0,
      green: ((v >> 8) & 0xff) / 255.0,
      blue: (v & 0xff) / 255.0,
    );
  }

  // Base EditorLayer == only checks identity-level fields (id,
  // transform, capabilities, visible, locked, name). Without this
  // override, mutating a paint style via the floating toolbar would
  // not invalidate document equality and Notifier would skip the
  // emit — the canvas would not refresh until some other interaction
  // forced a rebuild. Mirrors the same fix on TextLayer.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PaintLayer &&
          super == other &&
          other.kind == kind &&
          other.strokeColor == strokeColor &&
          other.strokeWidth == strokeWidth &&
          other.fillColor == fillColor &&
          other.sides == sides &&
          other.blurSigma == blurSigma &&
          other.resizeMode == resizeMode &&
          _pointsEqual(other.normalizedPoints, normalizedPoints));

  @override
  int get hashCode => Object.hash(
        super.hashCode,
        kind,
        strokeColor,
        strokeWidth,
        fillColor,
        sides,
        blurSigma,
        resizeMode,
        normalizedPoints.length,
      );

  static bool _pointsEqual(List<Offset> a, List<Offset> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Stand-alone painter so the in-flight preview overlay can reuse the
/// exact same rendering as committed [PaintLayer]s — guarantees the
/// pixels under the user's finger match what they get on release.
class PaintLayerPainter extends CustomPainter {
  PaintLayerPainter({
    required this.kind,
    required this.normalizedPoints,
    required this.strokeColor,
    required this.strokeWidth,
    this.fillColor,
    this.sides = 6,
  });

  final PaintKind kind;
  final List<Offset> normalizedPoints;
  final Color strokeColor;
  final double strokeWidth;
  final Color? fillColor;
  final int sides;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final stroke = Paint()
      ..color = strokeColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    switch (kind) {
      case PaintKind.freestyle:
        _paintFreestyle(canvas, size, stroke);
      case PaintKind.line:
        _paintLine(canvas, size, stroke);
      case PaintKind.arrow:
        _paintArrow(canvas, size, stroke);
      case PaintKind.rectangle:
        _paintRectangle(canvas, size, stroke);
      case PaintKind.circle:
        _paintCircle(canvas, size, stroke);
      case PaintKind.dashLine:
        _paintDashLine(canvas, size, stroke, dotted: false);
      case PaintKind.dashDotLine:
        _paintDashLine(canvas, size, stroke, dotted: true);
      case PaintKind.hexagon:
        _paintPolygon(canvas, size, stroke, 6);
      case PaintKind.polygon:
        _paintPolygon(canvas, size, stroke, sides);
      case PaintKind.blur:
        // Rendered via BackdropFilter in buildContent — nothing to
        // paint at this layer. Reached only if someone instantiates
        // the painter directly (e.g. preview pre-commit).
        break;
    }
  }

  void _paintFreestyle(Canvas canvas, Size size, Paint stroke) {
    if (normalizedPoints.isEmpty) return;
    final path = Path();
    final first = _denormalize(normalizedPoints.first, size);
    path.moveTo(first.dx, first.dy);
    if (normalizedPoints.length == 1) {
      // Tap-only: draw a single dot.
      canvas.drawCircle(first, strokeWidth / 2, stroke..style = PaintingStyle.fill);
      return;
    }
    for (var i = 1; i < normalizedPoints.length; i++) {
      final p = _denormalize(normalizedPoints[i], size);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, stroke);
  }

  void _paintLine(Canvas canvas, Size size, Paint stroke) {
    if (normalizedPoints.length < 2) return;
    final a = _denormalize(normalizedPoints.first, size);
    final b = _denormalize(normalizedPoints.last, size);
    canvas.drawLine(a, b, stroke);
  }

  void _paintArrow(Canvas canvas, Size size, Paint stroke) {
    if (normalizedPoints.length < 2) return;
    final a = _denormalize(normalizedPoints.first, size);
    final b = _denormalize(normalizedPoints.last, size);
    canvas.drawLine(a, b, stroke);
    // Arrow head — proportional to stroke width with a sane minimum so
    // hair-thin strokes still get a visible barb.
    final headLen = math.max(strokeWidth * 3.5, 12.0);
    final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
    const sweep = math.pi / 7;
    final p1 = b -
        Offset(headLen * math.cos(angle - sweep),
            headLen * math.sin(angle - sweep));
    final p2 = b -
        Offset(headLen * math.cos(angle + sweep),
            headLen * math.sin(angle + sweep));
    canvas.drawLine(b, p1, stroke);
    canvas.drawLine(b, p2, stroke);
  }

  void _paintRectangle(Canvas canvas, Size size, Paint stroke) {
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      math.max(0.0, size.width - inset * 2),
      math.max(0.0, size.height - inset * 2),
    );
    if (fillColor != null) {
      canvas.drawRect(rect, Paint()..color = fillColor!);
    }
    canvas.drawRect(rect, stroke);
  }

  void _paintCircle(Canvas canvas, Size size, Paint stroke) {
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      math.max(0.0, size.width - inset * 2),
      math.max(0.0, size.height - inset * 2),
    );
    if (fillColor != null) {
      canvas.drawOval(rect, Paint()..color = fillColor!);
    }
    canvas.drawOval(rect, stroke);
  }

  Offset _denormalize(Offset p, Size size) =>
      Offset(p.dx * size.width, p.dy * size.height);

  /// Dashed line variant. With [dotted] true, alternates dash + dot for
  /// the dash-dot style. Dash length scales with stroke width so the
  /// pattern stays visually proportional regardless of size.
  void _paintDashLine(
    Canvas canvas,
    Size size,
    Paint stroke, {
    required bool dotted,
  }) {
    if (normalizedPoints.length < 2) return;
    final a = _denormalize(normalizedPoints.first, size);
    final b = _denormalize(normalizedPoints.last, size);
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    final dash = math.max(strokeWidth * 2.5, 8.0);
    final gap = math.max(strokeWidth * 1.6, 6.0);
    final dot = strokeWidth; // length of the "dot" segment
    var t = 0.0;
    var drawDash = true;
    while (t < total) {
      final segLen = drawDash ? dash : (dotted ? dot : gap);
      final end = math.min(t + segLen, total);
      if (drawDash || (dotted && !drawDash)) {
        // Dash visible; for dash-dot, the inter-dash slot is itself a
        // dot — render that too. Pure dashed (`!dotted`) draws gaps
        // empty.
        if (drawDash) {
          canvas.drawLine(a + dir * t, a + dir * end, stroke);
        } else {
          // Centered dot inside the gap.
          final mid = a + dir * ((t + end) / 2);
          canvas.drawCircle(
            mid,
            strokeWidth / 2,
            Paint()
              ..color = strokeColor
              ..isAntiAlias = true,
          );
        }
      }
      t = end + (drawDash ? gap : 0);
      // Sequence: dash → gap → (dot in gap, only for dash-dot) → dash …
      // We model that with a 3-state cycle for dash-dot, 2 for dashed.
      if (dotted) {
        drawDash = !drawDash;
        // After a dot we resume gap-then-dash, so insert another gap.
        if (drawDash) t += gap;
      } else {
        drawDash = true; // pure dashed: always alternate dash/gap
        // gap was already added above.
      }
    }
  }

  /// Regular polygon inscribed in the bounding box. Top vertex is at
  /// 12 o'clock so the user gets a familiar orientation (point-up
  /// hexagon, point-up triangle, etc.).
  void _paintPolygon(
    Canvas canvas,
    Size size,
    Paint stroke,
    int sideCount,
  ) {
    final n = sideCount.clamp(3, 24);
    final inset = strokeWidth / 2;
    final w = math.max(0.0, size.width - inset * 2);
    final h = math.max(0.0, size.height - inset * 2);
    if (w <= 0 || h <= 0) return;
    final cx = inset + w / 2;
    final cy = inset + h / 2;
    final rx = w / 2;
    final ry = h / 2;
    final path = Path();
    for (var i = 0; i < n; i++) {
      // Start at -π/2 so the first vertex points up.
      final theta = -math.pi / 2 + (2 * math.pi * i) / n;
      final x = cx + rx * math.cos(theta);
      final y = cy + ry * math.sin(theta);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    if (fillColor != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = fillColor!
          ..isAntiAlias = true,
      );
    }
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant PaintLayerPainter old) =>
      old.kind != kind ||
      old.strokeColor != strokeColor ||
      old.strokeWidth != strokeWidth ||
      old.fillColor != fillColor ||
      old.sides != sides ||
      !_listEq(old.normalizedPoints, normalizedPoints);

  static bool _listEq(List<Offset> a, List<Offset> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
