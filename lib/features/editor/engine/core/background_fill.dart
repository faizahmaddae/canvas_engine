import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Describes how the canvas backdrop (and, with [Sprint 2 Task 4], a shape)
/// is filled.
///
/// Sealed so the renderer, codec, and tooling can exhaustively switch over
/// every variant without a default branch — adding a new fill type forces
/// every call site to acknowledge it.
///
/// Fill types intentionally do **not** describe whether the canvas is
/// transparent — that is a separate concern owned by `CanvasBackgroundMode`
/// in `editor_document.dart`. When the canvas is in transparent mode, the
/// fill is ignored at paint time but preserved on the model so toggling
/// back restores the user's last choice.
sealed class BackgroundFill {
  const BackgroundFill();

  /// JSON discriminator key used at the top of every gradient variant's
  /// payload. `SolidBackground` is *not* serialised as a tagged map —
  /// it is written as a bare ARGB int for backward-compatibility with
  /// schema v1, which only knew solid colours.
  static const String _typeKey = 'type';

  /// Discriminator value for [LinearGradientBackground].
  static const String typeLinear = 'linear';

  /// Discriminator value for [RadialGradientBackground].
  static const String typeRadial = 'radial';

  /// Decode a fill from the value the codec stored under the
  /// document's `'background'` key.
  ///
  ///   * `int`  → legacy v1 solid colour, wrapped as [SolidBackground]
  ///   * `Map`  → tagged variant, dispatched by [_typeKey]
  ///
  /// Throws [FormatException] on unknown discriminators or malformed
  /// payloads — the document codec wraps those in
  /// `DocumentDecodeException`.
  static BackgroundFill fromJson(Object json) {
    if (json is int) {
      return SolidBackground(color: Color(json));
    }
    if (json is Map) {
      final m = Map<String, dynamic>.from(json);
      final type = m[_typeKey];
      switch (type) {
        case typeLinear:
          return LinearGradientBackground._fromJson(m);
        case typeRadial:
          return RadialGradientBackground._fromJson(m);
        default:
          throw FormatException('unknown BackgroundFill discriminator "$type"');
      }
    }
    throw FormatException(
      'BackgroundFill JSON must be int (legacy) or Map, got ${json.runtimeType}',
    );
  }

  /// Encode this fill back to the codec's `'background'` value.
  /// Solid colours collapse to a bare `int` so v1 readers can still
  /// open documents that only use solid backgrounds.
  Object toJson();
}

/// A single flat colour. The historical default for every existing document.
@immutable
class SolidBackground extends BackgroundFill {
  const SolidBackground({required this.color});

  final Color color;

  @override
  Object toJson() => color.toARGB32();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SolidBackground && other.color == color);

  @override
  int get hashCode => color.hashCode;
}

/// A two-stop linear gradient between [startColor] and [endColor].
///
/// [angleDegrees] is measured clockwise from "up" — i.e. the direction the
/// gradient *flows* from start to end:
///   *   0°  — bottom → top
///   *  90°  — left   → right
///   * 180°  — top    → bottom
///   * 270°  — right  → left
///   * 135°  — top-left → bottom-right (default — pleasant diagonal)
///
/// In general, the unit direction vector is
/// `(sin(angle), -cos(angle))` in Flutter's `Alignment` space (y-down).
///
/// [stops] is optional; when omitted the renderer uses `[0.0, 1.0]`. When
/// provided it must contain exactly two values in `[0, 1]` matching the two
/// colours, in ascending order. Future variants may relax this to N stops.
@immutable
class LinearGradientBackground extends BackgroundFill {
  const LinearGradientBackground({
    required this.startColor,
    required this.endColor,
    this.angleDegrees = 135,
    this.stops,
  });

  final Color startColor;
  final Color endColor;
  final double angleDegrees;
  final List<double>? stops;

  /// Convert to Flutter's painting [LinearGradient]. Used by the
  /// background renderer (`BoxDecoration(gradient: ...)`) and the
  /// shape painter (`Paint()..shader = ...createShader(rect)`).
  /// Direction vector is `(sin θ, -cos θ)` (clockwise from up).
  LinearGradient toFlutterGradient() {
    final radians = angleDegrees * math.pi / 180.0;
    final dx = math.sin(radians);
    final dy = -math.cos(radians);
    return LinearGradient(
      begin: Alignment(-dx, -dy),
      end: Alignment(dx, dy),
      colors: [startColor, endColor],
      stops: stops,
    );
  }

  @override
  Object toJson() => <String, dynamic>{
    BackgroundFill._typeKey: BackgroundFill.typeLinear,
    'startColor': startColor.toARGB32(),
    'endColor': endColor.toARGB32(),
    'angleDegrees': angleDegrees,
    if (stops != null) 'stops': stops,
  };

  factory LinearGradientBackground._fromJson(Map<String, dynamic> json) {
    final start = json['startColor'];
    final end = json['endColor'];
    final angle = json['angleDegrees'];
    if (start is! int || end is! int) {
      throw const FormatException(
        'LinearGradientBackground requires int "startColor" and "endColor"',
      );
    }
    if (angle is! num) {
      throw const FormatException(
        'LinearGradientBackground requires numeric "angleDegrees"',
      );
    }
    final rawStops = json['stops'];
    List<double>? stops;
    if (rawStops is List) {
      stops = rawStops
          .map((s) => (s as num).toDouble())
          .toList(growable: false);
    }
    return LinearGradientBackground(
      startColor: Color(start),
      endColor: Color(end),
      angleDegrees: angle.toDouble(),
      stops: stops,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LinearGradientBackground &&
          other.startColor == startColor &&
          other.endColor == endColor &&
          other.angleDegrees == angleDegrees &&
          listEquals(other.stops, stops));

  @override
  int get hashCode => Object.hash(
    startColor,
    endColor,
    angleDegrees,
    stops == null ? null : Object.hashAll(stops!),
  );
}

/// A radial gradient from [centerColor] at [focalPoint] outward to
/// [edgeColor] at [radius].
///
/// [focalPoint] is in Flutter's `Alignment` space: `(-1, -1)` is top-left,
/// `(0, 0)` is centre, `(1, 1)` is bottom-right. Defaults to centre.
///
/// [radius] is expressed as a fraction of the canvas's shorter side
/// (so `1.0` reaches the edge of a square canvas). Values > 1.0 are
/// allowed for "fade past the edge" effects.
@immutable
class RadialGradientBackground extends BackgroundFill {
  const RadialGradientBackground({
    required this.centerColor,
    required this.edgeColor,
    this.focalPoint = Alignment.center,
    this.radius = 1.0,
  });

  final Color centerColor;
  final Color edgeColor;
  final Alignment focalPoint;
  final double radius;

  /// Convert to Flutter's painting [RadialGradient]. Both
  /// [RadialGradient.radius] and [RadialGradientBackground.radius]
  /// are expressed as a fraction of the box's shorter side, so the
  /// value passes through unchanged.
  RadialGradient toFlutterGradient() => RadialGradient(
    center: focalPoint,
    radius: radius,
    colors: [centerColor, edgeColor],
  );

  @override
  Object toJson() => <String, dynamic>{
    BackgroundFill._typeKey: BackgroundFill.typeRadial,
    'centerColor': centerColor.toARGB32(),
    'edgeColor': edgeColor.toARGB32(),
    'focalX': focalPoint.x,
    'focalY': focalPoint.y,
    'radius': radius,
  };

  factory RadialGradientBackground._fromJson(Map<String, dynamic> json) {
    final c = json['centerColor'];
    final e = json['edgeColor'];
    final fx = json['focalX'];
    final fy = json['focalY'];
    final r = json['radius'];
    if (c is! int || e is! int) {
      throw const FormatException(
        'RadialGradientBackground requires int "centerColor" and "edgeColor"',
      );
    }
    if (fx is! num || fy is! num || r is! num) {
      throw const FormatException(
        'RadialGradientBackground requires numeric "focalX"/"focalY"/"radius"',
      );
    }
    return RadialGradientBackground(
      centerColor: Color(c),
      edgeColor: Color(e),
      focalPoint: Alignment(fx.toDouble(), fy.toDouble()),
      radius: r.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RadialGradientBackground &&
          other.centerColor == centerColor &&
          other.edgeColor == edgeColor &&
          other.focalPoint == focalPoint &&
          other.radius == radius);

  @override
  int get hashCode => Object.hash(centerColor, edgeColor, focalPoint, radius);
}
