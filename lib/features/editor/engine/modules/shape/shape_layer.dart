import 'package:flutter/material.dart';

import '../../core/background_fill.dart';
import '../../core/editor_layer.dart';
import '../../core/layer_capabilities.dart';
import '../../core/layer_transform.dart';
import 'shape_paths.dart';

/// Supported primitive shape kinds. New kinds can be added without any
/// engine change — rendering is handled inside [ShapeLayer.buildContent].
///
/// Filled vs. stroked split:
///   * [rectangle], [roundedRectangle], [circle], [oval], [triangle],
///     [diamond], [hexagon], [star], [heart], [speechBubble],
///     [quoteBubble], [plus] are **filled** shapes — they paint a fill
///     plus an optional border.
///   * [line], [arrow], [arrowLeft], [arrowUp], [arrowDown], [check],
///     [cross] are **stroked** shapes — they have no fill body;
///     [fillColor] is reused as the stroke colour and [strokeWidth] as
///     the line thickness so the existing Style/Border panels can drive
///     them without bespoke fields.
///
/// Adding a new kind: extend [shape_paths.dart] with the geometry,
/// then update the switches in [isAspectLockedShapeKind],
/// [_ShapePainter._pathFor], [shapeOutlinePath] and the picker
/// preview painter — the analyzer will flag every site that needs a
/// new branch because every switch is exhaustive.
enum ShapeKind {
  rectangle,
  roundedRectangle,
  circle,
  oval,
  triangle,
  diamond,
  hexagon,
  star,
  heart,
  speechBubble,
  quoteBubble,
  plus,
  check,
  cross,
  line,
  arrow,
  arrowLeft,
  arrowUp,
  arrowDown,
}

/// True for kinds that paint as a stroked outline only (no fill body).
bool isStrokedShapeKind(ShapeKind k) {
  switch (k) {
    case ShapeKind.line:
    case ShapeKind.arrow:
    case ShapeKind.arrowLeft:
    case ShapeKind.arrowUp:
    case ShapeKind.arrowDown:
    case ShapeKind.check:
    case ShapeKind.cross:
      return true;
    case ShapeKind.rectangle:
    case ShapeKind.roundedRectangle:
    case ShapeKind.circle:
    case ShapeKind.oval:
    case ShapeKind.triangle:
    case ShapeKind.diamond:
    case ShapeKind.hexagon:
    case ShapeKind.star:
    case ShapeKind.heart:
    case ShapeKind.speechBubble:
    case ShapeKind.quoteBubble:
    case ShapeKind.plus:
      return false;
  }
}

/// True for shape kinds whose visual identity depends on a 1:1 (or
/// otherwise fixed) aspect ratio — stretching them looks broken.
/// Mirrors the principle behind [PaintResizeMode.scale]: the engine
/// asks the layer's [LayerCapabilities] whether to lock aspect; the
/// resize math itself stays generic.
///
/// Rectangle / roundedRectangle / oval / line / arrow* / bubbles are
/// intentionally excluded — they are container / linear / free-form
/// primitives the user expects to stretch freely.
bool isAspectLockedShapeKind(ShapeKind k) {
  switch (k) {
    case ShapeKind.circle:
    case ShapeKind.triangle:
    case ShapeKind.diamond:
    case ShapeKind.hexagon:
    case ShapeKind.star:
    case ShapeKind.heart:
    case ShapeKind.plus:
    case ShapeKind.check:
    case ShapeKind.cross:
      return true;
    case ShapeKind.rectangle:
    case ShapeKind.roundedRectangle:
    case ShapeKind.oval:
    case ShapeKind.speechBubble:
    case ShapeKind.quoteBubble:
    case ShapeKind.line:
    case ShapeKind.arrow:
    case ShapeKind.arrowLeft:
    case ShapeKind.arrowUp:
    case ShapeKind.arrowDown:
      return false;
  }
}

/// How corner-drag resizes a [ShapeLayer]. Mirrors [PaintResizeMode]
/// so the floating toolbar toggle is the same affordance the user
/// already learned in Paint.
///
/// * [free]  — corner drag stretches independently in both axes.
///            Container / linear primitives default to this.
/// * [scale] — corner drag preserves the original aspect ratio so
///            circles stay round, stars / hearts / diamonds /
///            triangles keep their silhouette.
enum ShapeResizeMode { free, scale }

/// Default resize mode for [k] when the layer doesn't carry an
/// explicit choice (insert defaults / pre-resize-mode JSON files).
ShapeResizeMode defaultShapeResizeMode(ShapeKind k) =>
    isAspectLockedShapeKind(k) ? ShapeResizeMode.scale : ShapeResizeMode.free;

/// Concrete layer rendering a primitive shape inside its [transform] bounds.
/// Participates in the generic interaction pipeline unchanged.
class ShapeLayer extends EditorLayer {
  const ShapeLayer({
    required super.id,
    required super.transform,
    required this.kind,
    this.fillColor = const Color(0xFFFFFFFF),
    this.fill,
    this.fillOpacity = 1,
    this.strokeColor,
    this.strokeWidth = 0,
    this.cornerRadius = 0,
    this.shadowColor = const Color(0xFF000000),
    this.shadowBlur = 0,
    this.shadowOffset = Offset.zero,
    this.shadowOpacity = 0,
    this.resizeMode,
    super.name,
    super.visible,
    super.locked,
    super.opacity,
  }) : super(
          // Inline so the constructor stays `const`. Honour an
          // explicit per-instance [resizeMode] first; otherwise fall
          // back to the kind-based default — the centralised helper
          // [isAspectLockedShapeKind] decides which silhouettes
          // collapse when stretched (circle / star / heart / hexagon
          // / plus / check / cross / triangle / diamond) and which
          // are container / linear / free-form primitives.
          capabilities: resizeMode == ShapeResizeMode.scale
              ? _shapeCapsAspect
              : resizeMode == ShapeResizeMode.free
                  ? _shapeCapsFree
                  : (kind == ShapeKind.circle ||
                          kind == ShapeKind.triangle ||
                          kind == ShapeKind.diamond ||
                          kind == ShapeKind.hexagon ||
                          kind == ShapeKind.star ||
                          kind == ShapeKind.heart ||
                          kind == ShapeKind.plus ||
                          kind == ShapeKind.check ||
                          kind == ShapeKind.cross)
                      ? _shapeCapsAspect
                      : _shapeCapsFree,
        );

  final ShapeKind kind;

  /// Legacy solid fill colour. Kept as the *fallback* when [fill] is
  /// null so every existing template, command and test that sets only
  /// `fillColor: ...` still paints a solid colour. New code should
  /// prefer setting [fill] (which can be a [SolidBackground], a
  /// [LinearGradientBackground] or a [RadialGradientBackground]).
  final Color fillColor;

  /// Sealed fill descriptor. When non-null, takes precedence over
  /// [fillColor]. Resolution rule (mirrored everywhere this is
  /// consumed):
  ///
  /// ```dart
  /// final effectiveFill = layer.fill ?? SolidBackground(color: layer.fillColor);
  /// ```
  ///
  /// Resize / rotation / opacity transforms operate on the painted
  /// shape, not on the gradient stops, so a rotated rectangle keeps
  /// the same colour direction relative to its own box.
  final BackgroundFill? fill;

  /// Resolved [BackgroundFill] after applying the precedence rule.
  /// Use this in renderer / painter code so a future fill type only
  /// requires updating one switch.
  BackgroundFill get effectiveFill =>
      fill ?? SolidBackground(color: fillColor);

  /// 0..1, applied to [fillColor] only. Default 1 (fully opaque).
  /// Stroke is intentionally untouched so a thin outline stays
  /// visible on top of a translucent fill.
  final double fillOpacity;

  final Color? strokeColor;
  final double strokeWidth;

  /// Logical-pixel corner radius. Only meaningful for
  /// [ShapeKind.rectangle]; [ShapeKind.circle] always renders as a
  /// full ellipse and ignores this value.
  final double cornerRadius;

  /// Drop-shadow tint. The actual painted alpha is
  /// `shadowColor.alpha * shadowOpacity` so callers can tweak
  /// strength independently of hue. Mirrors [ImageLayer.shadowColor].
  final Color shadowColor;

  /// Gaussian blur sigma (in logical px) for the silhouette shadow.
  /// `0` = crisp edge.
  final double shadowBlur;

  /// Translation applied to the shadow path relative to the shape.
  /// `Offset.zero` produces a centred glow.
  final Offset shadowOffset;

  /// `0..1` shadow strength. `0` is the default and means no
  /// shadow is rendered at all (skipping the painter entirely).
  final double shadowOpacity;

  /// Explicit user choice of corner-drag behaviour, or `null` to fall
  /// back to [defaultShapeResizeMode] for the current [kind]. Older
  /// JSON files (pre-resize-mode) decode to `null` and therefore keep
  /// behaving exactly the same way they did before this field existed.
  final ShapeResizeMode? resizeMode;

  /// Resolved resize mode after applying the kind-based default. Use
  /// this in UI / commands so toggling away from the default
  /// snapshots the resolved value first.
  ShapeResizeMode get effectiveResizeMode =>
      resizeMode ?? defaultShapeResizeMode(kind);

  /// Free-resize capabilities — corner drag stretches independently in
  /// both axes. Used by rectangles, lines and arrows where stretching
  /// is the expected behaviour.
  static const _shapeCapsFree = LayerCapabilities(
    editable: false,
  );

  /// Aspect-locked capabilities — corner drag preserves proportions
  /// so circles stay round, stars / hearts / diamonds / triangles
  /// keep their intended silhouette. Same flag the engine already
  /// honours for [ImageLayer] and aspect-locked [PaintLayer].
  static const _shapeCapsAspect = LayerCapabilities(
    editable: false,
    keepsAspectRatio: true,
  );

  @override
  String get type => 'shape';

  @override
  EditorLayer withTransform(LayerTransform transform) => ShapeLayer(
        id: id,
        transform: transform,
        kind: kind,
        fillColor: fillColor,
        fill: fill,
        fillOpacity: fillOpacity,
        strokeColor: strokeColor,
        strokeWidth: strokeWidth,
        cornerRadius: cornerRadius,
        shadowColor: shadowColor,
        shadowBlur: shadowBlur,
        shadowOffset: shadowOffset,
        shadowOpacity: shadowOpacity,
        resizeMode: resizeMode,
        name: name,
        visible: visible,
        locked: locked,
        opacity: opacity,
      );

  @override
  EditorLayer withVisibility(bool visible) => ShapeLayer(
        id: id,
        transform: transform,
        kind: kind,
        fillColor: fillColor,
        fill: fill,
        fillOpacity: fillOpacity,
        strokeColor: strokeColor,
        strokeWidth: strokeWidth,
        cornerRadius: cornerRadius,
        shadowColor: shadowColor,
        shadowBlur: shadowBlur,
        shadowOffset: shadowOffset,
        shadowOpacity: shadowOpacity,
        resizeMode: resizeMode,
        name: name,
        visible: visible,
        locked: locked,
        opacity: opacity,
      );

  @override
  EditorLayer withLocked(bool locked) => ShapeLayer(
        id: id,
        transform: transform,
        kind: kind,
        fillColor: fillColor,
        fill: fill,
        fillOpacity: fillOpacity,
        strokeColor: strokeColor,
        strokeWidth: strokeWidth,
        cornerRadius: cornerRadius,
        shadowColor: shadowColor,
        shadowBlur: shadowBlur,
        shadowOffset: shadowOffset,
        shadowOpacity: shadowOpacity,
        resizeMode: resizeMode,
        name: name,
        visible: visible,
        locked: locked,
        opacity: opacity,
      );

  @override
  EditorLayer withOpacity(double opacity) => ShapeLayer(
        id: id,
        transform: transform,
        kind: kind,
        fillColor: fillColor,
        fill: fill,
        fillOpacity: fillOpacity,
        strokeColor: strokeColor,
        strokeWidth: strokeWidth,
        cornerRadius: cornerRadius,
        shadowColor: shadowColor,
        shadowBlur: shadowBlur,
        shadowOffset: shadowOffset,
        shadowOpacity: shadowOpacity,
        resizeMode: resizeMode,
        name: name,
        visible: visible,
        locked: locked,
        opacity: opacity.clamp(0.0, 1.0),
      );

  /// Returns a new shape with selected fields overridden.
  ///
  /// Pass [clearStroke]: true to explicitly drop the stroke colour;
  /// without it, a `null` [strokeColor] argument is treated as
  /// "keep current" so a fill-only edit doesn't blow away the
  /// existing outline.
  ShapeLayer copyWith({
    ShapeKind? kind,
    Color? fillColor,
    BackgroundFill? fill,
    bool clearFill = false,
    double? fillOpacity,
    Color? strokeColor,
    bool clearStroke = false,
    double? strokeWidth,
    double? cornerRadius,
    Color? shadowColor,
    double? shadowBlur,
    Offset? shadowOffset,
    double? shadowOpacity,
    ShapeResizeMode? resizeMode,
    String? name,
  }) {
    return ShapeLayer(
      id: id,
      transform: transform,
      kind: kind ?? this.kind,
      fillColor: fillColor ?? this.fillColor,
      fill: clearFill ? null : (fill ?? this.fill),
      fillOpacity: fillOpacity ?? this.fillOpacity,
      strokeColor: clearStroke ? null : (strokeColor ?? this.strokeColor),
      strokeWidth: strokeWidth ?? this.strokeWidth,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      shadowColor: shadowColor ?? this.shadowColor,
      shadowBlur: shadowBlur ?? this.shadowBlur,
      shadowOffset: shadowOffset ?? this.shadowOffset,
      shadowOpacity: shadowOpacity ?? this.shadowOpacity,
      resizeMode: resizeMode ?? this.resizeMode,
      name: name ?? this.name,
      visible: visible,
      locked: locked,
      opacity: opacity,
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    final hasStroke = strokeColor != null && strokeWidth > 0;
    final clampedFillOpacity = fillOpacity.clamp(0.0, 1.0);
    final resolvedFill = effectiveFill;
    final solidColor = resolvedFill is SolidBackground
        ? resolvedFill.color.withValues(alpha: clampedFillOpacity)
        : null;
    // For gradient fills we apply [fillOpacity] via a wrapping
    // [Opacity] so both colour stops fade together — mirrors how
    // [SolidBackground] honours `fillOpacity`. Stroke stays at full
    // alpha so a thin outline never disappears under a translucent
    // fill, matching the existing solid-fill behaviour.
    final gradient = resolvedFill is LinearGradientBackground
        ? resolvedFill.toFlutterGradient()
        : resolvedFill is RadialGradientBackground
            ? resolvedFill.toFlutterGradient()
            : null;
    final border = hasStroke
        ? Border.all(color: strokeColor!, width: strokeWidth)
        : null;

    Widget body;
    switch (kind) {
      case ShapeKind.rectangle:
      case ShapeKind.roundedRectangle:
        body = DecoratedBox(
          decoration: BoxDecoration(
            color: gradient == null ? solidColor : null,
            gradient: gradient,
            border: border,
            borderRadius: cornerRadius > 0
                ? BorderRadius.circular(cornerRadius)
                : null,
          ),
        );
      case ShapeKind.circle:
      case ShapeKind.oval:
        // Ellipse that fills the transform box — non-uniform resize
        // produces ovals (matches Figma / Keynote). The dedicated
        // [oval] kind exists purely so the picker can offer a
        // *free-resize* default; both kinds render identically.
        // [cornerRadius] is intentionally ignored here.
        body = ClipOval(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: gradient == null ? solidColor : null,
              gradient: gradient,
              border: border,
            ),
            child: const SizedBox.expand(),
          ),
        );
      case ShapeKind.triangle:
      case ShapeKind.diamond:
      case ShapeKind.hexagon:
      case ShapeKind.star:
      case ShapeKind.heart:
      case ShapeKind.speechBubble:
      case ShapeKind.quoteBubble:
      case ShapeKind.plus:
      case ShapeKind.check:
      case ShapeKind.cross:
      case ShapeKind.line:
      case ShapeKind.arrow:
      case ShapeKind.arrowLeft:
      case ShapeKind.arrowUp:
      case ShapeKind.arrowDown:
        // Path / stroke based kinds use a dedicated painter so fill,
        // opacity and stroke compose correctly. The painter respects
        // the same convention as the box-based kinds: fillOpacity
        // applies to the fill only; the stroke stays at full alpha.
        body = CustomPaint(
          painter: _ShapePainter(
            kind: kind,
            // Solid path passes the colour pre-multiplied with
            // fillOpacity (matches pre-Sprint-2 behaviour); the
            // gradient path receives the raw gradient and the
            // painter applies opacity via Paint.color.alpha.
            fill: solidColor ?? const Color(0xFFFFFFFF),
            gradient: gradient,
            fillAlpha: clampedFillOpacity,
            stroke: strokeColor,
            strokeWidth: strokeWidth,
          ),
          size: Size.infinite,
        );
    }

    final hasShadow = shadowOpacity > 0;
    if (!hasShadow) return body;
    // Stack the shadow behind the shape so it tracks every silhouette
    // (rectangle / rounded / circle / triangle / diamond / star /
    // heart / line / arrow). Stack uses [Clip.none] so blurred edges
    // and offset shadows aren't sliced at the layer rect.
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _ShapeShadowPainter(
                kind: kind,
                cornerRadius: cornerRadius,
                strokeWidth: strokeWidth,
                color: shadowColor,
                opacity: shadowOpacity,
                blur: shadowBlur,
                offset: shadowOffset,
              ),
            ),
          ),
        ),
        Positioned.fill(child: body),
      ],
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        ...baseJson(),
        'kind': kind.name,
        'fillColor': _encodeColor(fillColor),
        // Only persist [fill] when present; legacy readers (and
        // legacy [SolidBackground] semantics) reconstruct from
        // [fillColor] alone. Encode as a tagged map even for solids
        // here so an explicit user choice round-trips losslessly.
        if (fill != null) 'fill': _encodeFill(fill!),
        if (fillOpacity < 1) 'fillOpacity': fillOpacity,
        if (strokeColor != null) 'strokeColor': _encodeColor(strokeColor!),
        'strokeWidth': strokeWidth,
        if (cornerRadius > 0) 'cornerRadius': cornerRadius,
        if (shadowOpacity > 0) 'shadowOpacity': shadowOpacity,
        if (shadowOpacity > 0) 'shadowBlur': shadowBlur,
        if (shadowOpacity > 0) 'shadowOffsetX': shadowOffset.dx,
        if (shadowOpacity > 0) 'shadowOffsetY': shadowOffset.dy,
        if (shadowOpacity > 0) 'shadowColor': _encodeColor(shadowColor),
        // Only persist when explicitly chosen — keeps round-trip
        // compatibility for files written before the field existed.
        if (resizeMode != null) 'resizeMode': resizeMode!.name,
      };

  /// Decode a [ShapeLayer] from JSON. Unknown `kind` values fall back to
  /// [ShapeKind.rectangle] so a legacy file never fails to open over a
  /// renamed enum value — the data itself (transform, colour) is intact.
  factory ShapeLayer.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String) {
      throw const FormatException('ShapeLayer.id missing or not a string');
    }
    final transformJson = json['transform'];
    if (transformJson is! Map) {
      throw const FormatException('ShapeLayer.transform missing');
    }
    final kindName = json['kind'];
    final kind = kindName is String
        ? ShapeKind.values.firstWhere(
            (k) => k.name == kindName,
            orElse: () => ShapeKind.rectangle,
          )
        : ShapeKind.rectangle;
    return ShapeLayer(
      id: id,
      transform: LayerTransform.fromJson(
        Map<String, dynamic>.from(transformJson),
      ),
      kind: kind,
      fillColor:
          _decodeColor(json['fillColor']) ?? const Color(0xFFFFFFFF),
      fill: _decodeFill(json['fill']),
      fillOpacity:
          ((json['fillOpacity'] as num?)?.toDouble() ?? 1).clamp(0.0, 1.0),
      strokeColor: _decodeColor(json['strokeColor']),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 0,
      cornerRadius: (json['cornerRadius'] as num?)?.toDouble() ?? 0,
      shadowColor:
          _decodeColor(json['shadowColor']) ?? const Color(0xFF000000),
      shadowBlur: (json['shadowBlur'] as num?)?.toDouble() ?? 0,
      shadowOffset: Offset(
        (json['shadowOffsetX'] as num?)?.toDouble() ?? 0,
        (json['shadowOffsetY'] as num?)?.toDouble() ?? 0,
      ),
      shadowOpacity: (json['shadowOpacity'] as num?)?.toDouble() ?? 0,
      resizeMode: _decodeResizeMode(json['resizeMode']),
      name: json['name'] as String?,
      visible: json['visible'] as bool? ?? true,
      locked: json['locked'] as bool? ?? false,
      opacity: ((json['opacity'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0),
    );
  }

  static int _encodeColor(Color c) {
    final a = (c.a * 255.0).round() & 0xff;
    final r = (c.r * 255.0).round() & 0xff;
    final g = (c.g * 255.0).round() & 0xff;
    final b = (c.b * 255.0).round() & 0xff;
    return (a << 24) | (r << 16) | (g << 8) | b;
  }

  /// Encode a [BackgroundFill] for the `'fill'` JSON slot. Solids
  /// are written as a tagged map (rather than the bare ARGB int form
  /// used by `EditorDocument.background`) so the presence of the
  /// `'fill'` key alone signals "explicit user fill" and the encoder
  /// stays uniform across variants.
  static Object _encodeFill(BackgroundFill fill) {
    return switch (fill) {
      SolidBackground(:final color) => <String, dynamic>{
          'type': 'solid',
          'color': _encodeColor(color),
        },
      LinearGradientBackground() ||
      RadialGradientBackground() =>
        fill.toJson(),
    };
  }

  /// Decode the `'fill'` JSON slot. Returns `null` for legacy files
  /// that never wrote the field. Throws [FormatException] for an
  /// unrecognised shape so a corrupt document fails loudly rather
  /// than silently dropping the user's gradient.
  static BackgroundFill? _decodeFill(Object? raw) {
    if (raw == null) return null;
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      if (map['type'] == 'solid') {
        final c = _decodeColor(map['color']);
        if (c == null) {
          throw const FormatException('ShapeLayer.fill solid missing color');
        }
        return SolidBackground(color: c);
      }
      // Linear / radial both round-trip through BackgroundFill.fromJson.
      return BackgroundFill.fromJson(map);
    }
    throw FormatException('ShapeLayer.fill: unsupported payload $raw');
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

  /// Lookup [ShapeResizeMode] by name; returns `null` (kind default)
  /// for legacy JSON that pre-dates the field.
  static ShapeResizeMode? _decodeResizeMode(Object? raw) {
    if (raw is! String) return null;
    for (final m in ShapeResizeMode.values) {
      if (m.name == raw) return m;
    }
    return null;
  }

  // Override == / hashCode so paint-only mutations (kind / fillColor /
  // strokeColor / strokeWidth) propagate through `EditorDocument.==`
  // and trigger a Notifier emit. Without this the base `EditorLayer.==`
  // ignores the shape payload and a fill-color change would not reach
  // the renderer until another interaction forced a rebuild.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShapeLayer &&
          super == other &&
          other.kind == kind &&
          other.fillColor == fillColor &&
          other.fill == fill &&
          other.fillOpacity == fillOpacity &&
          other.strokeColor == strokeColor &&
          other.strokeWidth == strokeWidth &&
          other.cornerRadius == cornerRadius &&
          other.shadowColor == shadowColor &&
          other.shadowBlur == shadowBlur &&
          other.shadowOffset == shadowOffset &&
          other.shadowOpacity == shadowOpacity &&
          other.resizeMode == resizeMode);

  @override
  int get hashCode => Object.hash(
        super.hashCode,
        kind,
        fillColor,
        fill,
        fillOpacity,
        strokeColor,
        strokeWidth,
        cornerRadius,
        shadowColor,
        shadowBlur,
        shadowOffset,
        shadowOpacity,
        resizeMode,
      );
}

/// Paints path / stroke based [ShapeKind]s. For filled kinds (triangle,
/// diamond, star, heart) it paints the closed path with [fill] then,
/// if a stroke is set, an outline on top. For stroked kinds (line,
/// arrow) the path is drawn with [fill] as the stroke colour at a
/// minimum thickness so the line never visually disappears \u2014 the
/// `Border` panel still exposes the same [strokeWidth] field for fine
/// control, and any [stroke]/[strokeWidth] overrides are honoured.
class _ShapePainter extends CustomPainter {
  const _ShapePainter({
    required this.kind,
    required this.fill,
    required this.gradient,
    required this.fillAlpha,
    required this.stroke,
    required this.strokeWidth,
  });

  final ShapeKind kind;
  final Color fill;
  final Gradient? gradient;
  final double fillAlpha;
  final Color? stroke;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final stroked = isStrokedShapeKind(kind);
    if (stroked) {
      // Stroke-only kinds: use [fill] as the visible colour. Width
      // falls back to a sane default so a freshly-inserted line is
      // visible before the user opens the Border panel. Gradients on
      // line-style shapes degrade to [fill] (the resolved solid)
      // because a 1-D primitive has no meaningful gradient axis.
      final w = strokeWidth > 0 ? strokeWidth : 6.0;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = w
        ..color = fill;
      canvas.drawPath(_pathFor(kind, size), paint);
      return;
    }
    final fillPaint = Paint()..style = PaintingStyle.fill;
    if (gradient != null) {
      final rect = Offset.zero & size;
      fillPaint.shader = gradient!.createShader(rect);
      // Apply fillOpacity uniformly across the gradient by tinting
      // the painter's colour alpha (Skia multiplies the shader
      // output by Paint.color.alpha when a shader is set).
      fillPaint.color = const Color(0xFFFFFFFF).withValues(alpha: fillAlpha);
    } else {
      fillPaint.color = fill;
    }
    final path = _pathFor(kind, size);
    canvas.drawPath(path, fillPaint);
    if (stroke != null && strokeWidth > 0) {
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..color = stroke!;
      canvas.drawPath(path, strokePaint);
    }
  }

  Path _pathFor(ShapeKind k, Size size) {
    switch (k) {
      case ShapeKind.triangle:
        return ShapePaths.triangle(size);
      case ShapeKind.diamond:
        return ShapePaths.diamond(size);
      case ShapeKind.hexagon:
        return ShapePaths.hexagon(size);
      case ShapeKind.star:
        return ShapePaths.star(size);
      case ShapeKind.heart:
        return ShapePaths.heart(size);
      case ShapeKind.speechBubble:
        return ShapePaths.speechBubble(size);
      case ShapeKind.quoteBubble:
        return ShapePaths.quoteBubble(size);
      case ShapeKind.plus:
        return ShapePaths.plus(size);
      case ShapeKind.check:
        return ShapePaths.check(size);
      case ShapeKind.cross:
        return ShapePaths.cross(size);
      case ShapeKind.line:
        return ShapePaths.line(size);
      case ShapeKind.arrow:
        return ShapePaths.arrow(size);
      case ShapeKind.arrowLeft:
        return ShapePaths.arrowLeft(size);
      case ShapeKind.arrowUp:
        return ShapePaths.arrowUp(size);
      case ShapeKind.arrowDown:
        return ShapePaths.arrowDown(size);
      // Box-based kinds never reach the painter; keep the switch
      // exhaustive so adding a new kind forces an explicit decision.
      case ShapeKind.rectangle:
      case ShapeKind.roundedRectangle:
      case ShapeKind.circle:
      case ShapeKind.oval:
        return Path();
    }
  }

  @override
  bool shouldRepaint(covariant _ShapePainter old) =>
      old.kind != kind ||
      old.fill != fill ||
      old.gradient != gradient ||
      old.fillAlpha != fillAlpha ||
      old.stroke != stroke ||
      old.strokeWidth != strokeWidth;
}

/// Returns the silhouette path for a [ShapeLayer] given its [kind],
/// [cornerRadius] and the painted [size]. Used both by the shadow
/// painter and any future hit-testing that wants to follow the
/// real shape edge instead of the bounding box.
///
/// Stroked kinds (line / arrow) return their open stroke geometry —
/// callers must paint with `PaintingStyle.stroke` and an appropriate
/// width.
Path shapeOutlinePath(ShapeKind kind, Size size, {double cornerRadius = 0}) {
  switch (kind) {
    case ShapeKind.rectangle:
      if (cornerRadius > 0) {
        return Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              Offset.zero & size,
              Radius.circular(cornerRadius),
            ),
          );
      }
      return Path()..addRect(Offset.zero & size);
    case ShapeKind.roundedRectangle:
      final r = cornerRadius > 0 ? cornerRadius : size.shortestSide * 0.18;
      return Path()
        ..addRRect(
          RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r)),
        );
    case ShapeKind.circle:
      return Path()..addOval(Offset.zero & size);
    case ShapeKind.oval:
      return Path()..addOval(Offset.zero & size);
    case ShapeKind.triangle:
      return ShapePaths.triangle(size);
    case ShapeKind.diamond:
      return ShapePaths.diamond(size);
    case ShapeKind.hexagon:
      return ShapePaths.hexagon(size);
    case ShapeKind.star:
      return ShapePaths.star(size);
    case ShapeKind.heart:
      return ShapePaths.heart(size);
    case ShapeKind.speechBubble:
      return ShapePaths.speechBubble(size);
    case ShapeKind.quoteBubble:
      return ShapePaths.quoteBubble(size);
    case ShapeKind.plus:
      return ShapePaths.plus(size);
    case ShapeKind.check:
      return ShapePaths.check(size);
    case ShapeKind.cross:
      return ShapePaths.cross(size);
    case ShapeKind.line:
      return ShapePaths.line(size);
    case ShapeKind.arrow:
      return ShapePaths.arrow(size);
    case ShapeKind.arrowLeft:
      return ShapePaths.arrowLeft(size);
    case ShapeKind.arrowUp:
      return ShapePaths.arrowUp(size);
    case ShapeKind.arrowDown:
      return ShapePaths.arrowDown(size);
  }
}

/// Drops a blurred, optionally-offset silhouette of the shape behind
/// its body. Filled kinds use a fill paint along the outline path;
/// stroked kinds (line / arrow) use a stroke paint with the same
/// thickness as the visible stroke so the shadow tracks the line
/// itself rather than its bounding box. Mirrors [_MaskShadowPainter]
/// in `image_layer.dart` so the two surfaces stay visually
/// consistent.
class _ShapeShadowPainter extends CustomPainter {
  const _ShapeShadowPainter({
    required this.kind,
    required this.cornerRadius,
    required this.strokeWidth,
    required this.color,
    required this.opacity,
    required this.blur,
    required this.offset,
  });

  final ShapeKind kind;
  final double cornerRadius;
  final double strokeWidth;
  final Color color;
  final double opacity;
  final double blur;
  final Offset offset;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0 || size.isEmpty) return;
    final path = shapeOutlinePath(kind, size, cornerRadius: cornerRadius)
        .shift(offset);
    final paint = Paint()
      ..color = color.withValues(alpha: opacity.clamp(0.0, 1.0))
      ..isAntiAlias = true;
    if (isStrokedShapeKind(kind)) {
      // Line / arrow: trace the stroke with the same thickness so the
      // shadow follows the visible silhouette rather than a phantom
      // rectangle.
      final w = strokeWidth > 0 ? strokeWidth : 6.0;
      paint
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = w;
    } else {
      paint.style = PaintingStyle.fill;
    }
    if (blur > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ShapeShadowPainter old) =>
      old.kind != kind ||
      old.cornerRadius != cornerRadius ||
      old.strokeWidth != strokeWidth ||
      old.color != color ||
      old.opacity != opacity ||
      old.blur != blur ||
      old.offset != offset;
}
