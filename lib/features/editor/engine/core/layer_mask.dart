import 'dart:math' as math;
import 'dart:ui' show Path, PathFillType;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset, Rect;

/// Per-pixel alpha mask used by the effect system to restrict where
/// effects write into a layer's pixels.
///
/// **Naming note — do not conflate with [`ImageMask`].** This codebase
/// already has a type named `ImageMask` (see
/// `engine/modules/image/image_layer.dart`). That is a fixed enum of
/// decorative clip silhouettes (`rounded`, `circle`, `heart`, …) used
/// only by [`ImageLayer`]. `LayerMask` is the opposite: an immutable
/// geometric description that produces a per-pixel `0..1` alpha sample.
/// They share the noun "mask" because both restrict visible pixels,
/// but they answer different questions and serialize under different
/// keys. Future raster / gradient masks become new [`LayerMask`]
/// variants; they do not extend [`ImageMask`].
///
/// **Coordinate space.** [`LayerMask`] geometry is always in
/// **layer-local space**: the rect / ellipse / path coordinates assume
/// the layer's top-left is `(0, 0)` and the layer's bottom-right is
/// `(transform.size.width, transform.size.height)`. The mask never
/// transforms with the canvas — when the user resizes a layer, the
/// mask's geometry stays the same in layer-local terms (so a
/// "full-layer" rect stays full-layer after a resize).
///
/// **`feather`** is also in layer-local px and scales with the layer.
/// A 12-px feather on a 100×100 layer at 2× canvas zoom paints as
/// 24 canvas-px of softness — visually consistent with the layer.
///
/// Used by `EditorEffect.mask` (per-effect clip) and
/// `EffectStack.stackMask` (per-stack final clip). They compose at
/// sample time via `min(α)`; see [`composedAlpha`]. We deliberately
/// do **not** pre-merge two [`LayerMask`]s into a third instance —
/// the intersection of a rect and an ellipse is not representable
/// as either, and forcing every composition into [`PathMask`] would
/// allocate a path even when one input is a 4-double rect.
sealed class LayerMask {
  const LayerMask({this.inverted = false, this.feather = 0.0})
      : assert(feather >= 0.0 && feather <= maxFeatherPx,
            'feather must be in [0, $maxFeatherPx] px (layer-local)');

  /// Default feather value. Omitted from JSON.
  static const double defaultFeather = 0.0;

  /// Upper clamp on feather, in layer-local px. The cap is a visual
  /// sanity bound — beyond ~256 px softness the mask reads as a
  /// gradient overlay rather than a mask, and pre-bounding here lets
  /// the future renderer allocate a fixed-size feather kernel
  /// without per-mask reallocation.
  static const double maxFeatherPx = 256.0;

  /// JSON discriminator key. Every variant tags itself with this
  /// key under the value listed in [`shapeRect`] / [`shapeEllipse`]
  /// / [`shapePath`].
  static const String _shapeKey = 'shape';
  static const String shapeRect = 'rect';
  static const String shapeEllipse = 'ellipse';
  static const String shapePath = 'path';

  /// Inverts the alpha after evaluation (`α := 1 - α`). Omitted from
  /// JSON when `false` (the default).
  final bool inverted;

  /// Edge softness in layer-local px. Omitted from JSON when `0.0`.
  /// Sampling outside the inner shape but within `feather` px ramps
  /// linearly from 1.0 to 0.0; see [`sampleAlpha`].
  final double feather;

  /// Sample the alpha contribution at [`point`] in layer-local
  /// coordinates. Returns a value in `[0, 1]`. Implementations must
  /// honour [`inverted`] and [`feather`]. Pure; never reads global
  /// state.
  double sampleAlpha(Offset point);

  /// Encode to a tagged JSON map. Defaults are omitted (codec
  /// invariant — see `docs/effects.md` §7).
  Object toJson();

  /// Decode any [`LayerMask`] variant from its tagged JSON map.
  /// Throws [`FormatException`] on missing / unknown discriminators
  /// — the document codec wraps those in `DocumentDecodeException`.
  static LayerMask fromJson(Object json) {
    if (json is! Map) {
      throw FormatException(
        'LayerMask JSON must be a Map, got ${json.runtimeType}',
      );
    }
    final m = Map<String, dynamic>.from(json);
    final shape = m[_shapeKey];
    switch (shape) {
      case shapeRect:
        return RectMask._fromJson(m);
      case shapeEllipse:
        return EllipseMask._fromJson(m);
      case shapePath:
        return PathMask._fromJson(m);
      default:
        throw FormatException('unknown LayerMask shape "$shape"');
    }
  }

  /// Compose two optional masks at one sample point via `min(α)`.
  /// Either side may be `null` (interpreted as fully opaque). Returns
  /// `1.0` when both are `null`.
  ///
  /// This is the **only** composition rule used by the effect
  /// pipeline — per-effect mask and stack mask combine here, not
  /// through any data-side merge. Sample-time `min` is `O(1)` per
  /// pixel and avoids the rect-vs-ellipse representability problem
  /// that data-side merge would force into a `PathMask`.
  static double composedAlpha(LayerMask? a, LayerMask? b, Offset point) {
    if (a == null && b == null) return 1.0;
    if (a == null) return b!.sampleAlpha(point);
    if (b == null) return a.sampleAlpha(point);
    return math.min(a.sampleAlpha(point), b.sampleAlpha(point));
  }

  /// Helper for subclass [`toJson`] overrides: write `inverted` /
  /// `feather` only when non-default.
  void _writeCommon(Map<String, dynamic> out) {
    if (inverted) out['inverted'] = true;
    if (feather != defaultFeather) out['feather'] = feather;
  }

  /// Helper for subclass `_fromJson` factories: read the optional
  /// `inverted` / `feather` keys with type checks.
  static ({bool inverted, double feather}) _readCommon(
    Map<String, dynamic> json,
  ) {
    final rawInverted = json['inverted'];
    final inverted = rawInverted is bool ? rawInverted : false;
    final rawFeather = json['feather'];
    final feather = rawFeather is num ? rawFeather.toDouble() : defaultFeather;
    if (feather < 0.0 || feather > maxFeatherPx) {
      throw FormatException(
        'LayerMask "feather" out of range [0, $maxFeatherPx]: $feather',
      );
    }
    return (inverted: inverted, feather: feather);
  }
}

/// Axis-aligned rectangular mask. Coordinates are layer-local.
@immutable
final class RectMask extends LayerMask {
  const RectMask({
    required this.rect,
    super.inverted,
    super.feather,
  });

  final Rect rect;

  @override
  double sampleAlpha(Offset point) {
    final inside = _rectAlpha(rect, point, feather);
    return inverted ? 1.0 - inside : inside;
  }

  @override
  Object toJson() {
    final out = <String, dynamic>{
      LayerMask._shapeKey: LayerMask.shapeRect,
      'rect': <double>[rect.left, rect.top, rect.width, rect.height],
    };
    _writeCommon(out);
    return out;
  }

  factory RectMask._fromJson(Map<String, dynamic> json) {
    final raw = json['rect'];
    if (raw is! List || raw.length != 4) {
      throw const FormatException(
        'RectMask requires "rect" as [x, y, w, h]',
      );
    }
    final coords = raw.map((v) => (v as num).toDouble()).toList(growable: false);
    final common = LayerMask._readCommon(json);
    return RectMask(
      rect: Rect.fromLTWH(coords[0], coords[1], coords[2], coords[3]),
      inverted: common.inverted,
      feather: common.feather,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RectMask &&
          other.rect == rect &&
          other.inverted == inverted &&
          other.feather == feather);

  @override
  int get hashCode => Object.hash(rect, inverted, feather);
}

/// Ellipse inscribed in [`bounds`]. Coordinates are layer-local.
@immutable
final class EllipseMask extends LayerMask {
  const EllipseMask({
    required this.bounds,
    super.inverted,
    super.feather,
  });

  final Rect bounds;

  @override
  double sampleAlpha(Offset point) {
    final inside = _ellipseAlpha(bounds, point, feather);
    return inverted ? 1.0 - inside : inside;
  }

  @override
  Object toJson() {
    final out = <String, dynamic>{
      LayerMask._shapeKey: LayerMask.shapeEllipse,
      'bounds': <double>[
        bounds.left,
        bounds.top,
        bounds.width,
        bounds.height,
      ],
    };
    _writeCommon(out);
    return out;
  }

  factory EllipseMask._fromJson(Map<String, dynamic> json) {
    final raw = json['bounds'];
    if (raw is! List || raw.length != 4) {
      throw const FormatException(
        'EllipseMask requires "bounds" as [x, y, w, h]',
      );
    }
    final coords = raw.map((v) => (v as num).toDouble()).toList(growable: false);
    final common = LayerMask._readCommon(json);
    return EllipseMask(
      bounds: Rect.fromLTWH(coords[0], coords[1], coords[2], coords[3]),
      inverted: common.inverted,
      feather: common.feather,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EllipseMask &&
          other.bounds == bounds &&
          other.inverted == inverted &&
          other.feather == feather);

  @override
  int get hashCode => Object.hash(bounds, inverted, feather);
}

/// One closed contour in a [`PathMask`]. Concrete segments
/// ([`LineSegment`], [`QuadSegment`], [`CubicSegment`]) carry their
/// own end-point coordinates in layer-local space.
@immutable
class PathContour {
  const PathContour({required this.start, required this.segments});

  final Offset start;
  final List<PathSegment> segments;

  Object toJson() => <String, dynamic>{
        'start': <double>[start.dx, start.dy],
        'segments':
            segments.map((s) => s.toJson()).toList(growable: false),
      };

  factory PathContour.fromJson(Map<String, dynamic> json) {
    final rawStart = json['start'];
    if (rawStart is! List || rawStart.length != 2) {
      throw const FormatException(
        'PathContour "start" must be [x, y]',
      );
    }
    final rawSegs = json['segments'];
    if (rawSegs is! List) {
      throw const FormatException('PathContour "segments" must be a List');
    }
    return PathContour(
      start: Offset(
        (rawStart[0] as num).toDouble(),
        (rawStart[1] as num).toDouble(),
      ),
      segments: rawSegs
          .map((s) => PathSegment.fromJson(s as List))
          .toList(growable: false),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PathContour &&
          other.start == start &&
          listEquals(other.segments, segments));

  @override
  int get hashCode => Object.hash(start, Object.hashAll(segments));
}

/// One segment within a [`PathContour`]. Serialized as a positional
/// list whose first element is a string kind tag.
///
/// Encoding shapes:
/// * `["line", x, y]`
/// * `["quad", cx, cy, x, y]`
/// * `["cubic", c1x, c1y, c2x, c2y, x, y]`
///
/// Positional encoding is ~3× smaller than a named-key map for
/// realistic 200-point freehand paths; the kind tag stays a string
/// (not an int) so saved JSON survives a debug dump without a
/// lookup table.
sealed class PathSegment {
  const PathSegment();

  static const String kindLine = 'line';
  static const String kindQuad = 'quad';
  static const String kindCubic = 'cubic';

  /// Layer-local end-point of the segment (where the pen lands).
  Offset get end;

  /// Encode as `[kind, ...doubles]`.
  List<Object> toJson();

  /// Decode any segment kind from its positional list.
  factory PathSegment.fromJson(List<dynamic> json) {
    if (json.isEmpty) {
      throw const FormatException('PathSegment encoding is empty');
    }
    final kind = json[0];
    switch (kind) {
      case kindLine:
        if (json.length != 3) {
          throw const FormatException('LineSegment requires [kind, x, y]');
        }
        return LineSegment(
          end: Offset(
            (json[1] as num).toDouble(),
            (json[2] as num).toDouble(),
          ),
        );
      case kindQuad:
        if (json.length != 5) {
          throw const FormatException(
            'QuadSegment requires [kind, cx, cy, x, y]',
          );
        }
        return QuadSegment(
          control: Offset(
            (json[1] as num).toDouble(),
            (json[2] as num).toDouble(),
          ),
          end: Offset(
            (json[3] as num).toDouble(),
            (json[4] as num).toDouble(),
          ),
        );
      case kindCubic:
        if (json.length != 7) {
          throw const FormatException(
            'CubicSegment requires [kind, c1x, c1y, c2x, c2y, x, y]',
          );
        }
        return CubicSegment(
          control1: Offset(
            (json[1] as num).toDouble(),
            (json[2] as num).toDouble(),
          ),
          control2: Offset(
            (json[3] as num).toDouble(),
            (json[4] as num).toDouble(),
          ),
          end: Offset(
            (json[5] as num).toDouble(),
            (json[6] as num).toDouble(),
          ),
        );
      default:
        throw FormatException('unknown PathSegment kind "$kind"');
    }
  }
}

@immutable
final class LineSegment extends PathSegment {
  const LineSegment({required this.end});

  @override
  final Offset end;

  @override
  List<Object> toJson() => <Object>[PathSegment.kindLine, end.dx, end.dy];

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is LineSegment && other.end == end);

  @override
  int get hashCode => Object.hash(PathSegment.kindLine, end);
}

@immutable
final class QuadSegment extends PathSegment {
  const QuadSegment({required this.control, required this.end});

  final Offset control;

  @override
  final Offset end;

  @override
  List<Object> toJson() => <Object>[
        PathSegment.kindQuad,
        control.dx,
        control.dy,
        end.dx,
        end.dy,
      ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QuadSegment && other.control == control && other.end == end);

  @override
  int get hashCode => Object.hash(PathSegment.kindQuad, control, end);
}

@immutable
final class CubicSegment extends PathSegment {
  const CubicSegment({
    required this.control1,
    required this.control2,
    required this.end,
  });

  final Offset control1;
  final Offset control2;

  @override
  final Offset end;

  @override
  List<Object> toJson() => <Object>[
        PathSegment.kindCubic,
        control1.dx,
        control1.dy,
        control2.dx,
        control2.dy,
        end.dx,
        end.dy,
      ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CubicSegment &&
          other.control1 == control1 &&
          other.control2 == control2 &&
          other.end == end);

  @override
  int get hashCode =>
      Object.hash(PathSegment.kindCubic, control1, control2, end);
}

/// Closed-contour path mask. Coordinates are layer-local.
///
/// `dart:ui`'s `Path` is opaque (no introspection, no equality, no
/// serialization), so the engine carries its own structural form
/// and converts to a `ui.Path` lazily inside the renderer — same
/// pattern `ImageAdjustments.colorMatrix` uses.
@immutable
final class PathMask extends LayerMask {
  const PathMask({
    required this.contours,
    this.fillType = PathFillType.nonZero,
    super.inverted,
    super.feather,
  });

  final List<PathContour> contours;
  final PathFillType fillType;

  @override
  double sampleAlpha(Offset point) {
    // Binary in/out coverage via dart:ui's even-odd / non-zero
    // tester. This is the cheap path that callers pre-renderer use
    // (hit-tests, mask-aware brushes that ask "is this pixel under
    // the mask?"). It deliberately does NOT honour [feather] —
    // feathering is a blurred-alpha operation that can only be
    // computed correctly with access to a raster of the surrounding
    // pixels, which sampleAlpha's pointwise contract can't provide.
    // The renderer applies feather as a post-pass on its own
    // rasterised alpha buffer; pre-renderer hit-tests get the hard
    // edge, which matches user intent ("did I tap inside the mask?").
    final path = _materialize();
    final inside = path.contains(point);
    final base = inside ? 1.0 : 0.0;
    return inverted ? 1.0 - base : base;
  }

  /// Cached `ui.Path` materialised from [contours] / [fillType]. The
  /// path is allocated on first call and held for the lifetime of
  /// this immutable instance — same lazy-cache pattern used for the
  /// composed colour matrix in [`EffectStack`].
  Path _materialize() {
    final cached = _pathCache[this];
    if (cached != null) return cached;
    final p = Path()..fillType = fillType;
    for (final contour in contours) {
      p.moveTo(contour.start.dx, contour.start.dy);
      for (final seg in contour.segments) {
        switch (seg) {
          case LineSegment():
            p.lineTo(seg.end.dx, seg.end.dy);
          case QuadSegment():
            p.quadraticBezierTo(
              seg.control.dx,
              seg.control.dy,
              seg.end.dx,
              seg.end.dy,
            );
          case CubicSegment():
            p.cubicTo(
              seg.control1.dx,
              seg.control1.dy,
              seg.control2.dx,
              seg.control2.dy,
              seg.end.dx,
              seg.end.dy,
            );
        }
      }
      p.close();
    }
    _pathCache[this] = p;
    return p;
  }

  @override
  Object toJson() {
    final out = <String, dynamic>{
      LayerMask._shapeKey: LayerMask.shapePath,
      'contours': contours.map((c) => c.toJson()).toList(growable: false),
    };
    if (fillType != PathFillType.nonZero) {
      out['fillType'] = _fillTypeToJson(fillType);
    }
    _writeCommon(out);
    return out;
  }

  factory PathMask._fromJson(Map<String, dynamic> json) {
    final raw = json['contours'];
    if (raw is! List) {
      throw const FormatException('PathMask "contours" must be a List');
    }
    final fillRaw = json['fillType'];
    final fillType = fillRaw == null
        ? PathFillType.nonZero
        : _fillTypeFromJson(fillRaw);
    final common = LayerMask._readCommon(json);
    return PathMask(
      contours: raw
          .map((c) => PathContour.fromJson(Map<String, dynamic>.from(c as Map)))
          .toList(growable: false),
      fillType: fillType,
      inverted: common.inverted,
      feather: common.feather,
    );
  }

  static String _fillTypeToJson(PathFillType t) =>
      t == PathFillType.evenOdd ? 'evenOdd' : 'nonZero';

  static PathFillType _fillTypeFromJson(Object raw) {
    if (raw == 'evenOdd') return PathFillType.evenOdd;
    if (raw == 'nonZero') return PathFillType.nonZero;
    throw FormatException('unknown PathMask fillType "$raw"');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PathMask &&
          listEquals(other.contours, contours) &&
          other.fillType == fillType &&
          other.inverted == inverted &&
          other.feather == feather);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(contours),
        fillType,
        inverted,
        feather,
      );
}

// -----------------------------------------------------------------------------
// Sampling primitives.
//
// Pure, allocation-free, hot-path-friendly. Each returns the un-inverted
// coverage at one point; the variant's `sampleAlpha` applies inversion.
// Featherless paths take the constant branch so the common case stays a
// single float compare.
// -----------------------------------------------------------------------------

double _rectAlpha(Rect r, Offset p, double feather) {
  // Signed distance from the point to the rect: ≤ 0 inside or on
  // the boundary, > 0 outside. Feather extends *outward* from the
  // boundary (matches ellipse semantics; consistent across variants).
  final dx = math.max(r.left - p.dx, p.dx - r.right);
  final dy = math.max(r.top - p.dy, p.dy - r.bottom);
  final outside = math.max(dx, dy);
  if (feather <= 0.0) return outside <= 0.0 ? 1.0 : 0.0;
  if (outside <= 0.0) return 1.0;
  if (outside >= feather) return 0.0;
  return 1.0 - outside / feather;
}

double _ellipseAlpha(Rect b, Offset p, double feather) {
  final cx = b.center.dx;
  final cy = b.center.dy;
  final rx = b.width * 0.5;
  final ry = b.height * 0.5;
  if (rx <= 0.0 || ry <= 0.0) return 0.0;
  final nx = (p.dx - cx) / rx;
  final ny = (p.dy - cy) / ry;
  final r2 = nx * nx + ny * ny;
  if (feather <= 0.0) return r2 <= 1.0 ? 1.0 : 0.0;
  // Featherless boundary at r2 == 1. Convert feather (px) into a
  // normalized ramp using the smaller radius (the tighter axis), so a
  // long thin ellipse still reads as the user-set feather width along
  // its short side.
  final rMin = math.min(rx, ry);
  final ramp = feather / rMin;
  final rNorm = math.sqrt(r2);
  if (rNorm <= 1.0) return 1.0;
  if (rNorm >= 1.0 + ramp) return 0.0;
  return 1.0 - (rNorm - 1.0) / ramp;
}

/// Materialised `ui.Path` cache keyed on the [`PathMask`] instance.
/// Lives outside the class so it doesn't change the equality /
/// hashing contract — Expando uses identity, not value, for keys.
final Expando<Path> _pathCache = Expando<Path>('PathMask._pathCache');
