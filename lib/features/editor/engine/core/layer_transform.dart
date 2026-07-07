import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../../../core/utils/geometry.dart';

/// Immutable affine-like transform for a layer.
///
/// Conceptually: translate([position]) * rotate([rotation]) around the
/// layer's local center, scaled to [size].
///
/// All rendering and interaction code derives geometry from this value –
/// there is no other source of truth for a layer's pose.
class LayerTransform {
  const LayerTransform({
    required this.position,
    required this.size,
    this.rotation = 0,
  });

  /// Top-left position in canvas coordinates *before* rotation is applied.
  /// Rotation pivots around [center].
  final Offset position;
  final Size size;

  /// Rotation in radians around [center].
  final double rotation;

  Offset get center =>
      Offset(position.dx + size.width / 2, position.dy + size.height / 2);

  Rect get localRect => Offset.zero & size;

  /// Axis-aligned rect *before* rotation (useful for hit-testing locally).
  Rect get unrotatedRect => position & size;

  /// Corners in canvas space, rotation applied, in order TL, TR, BR, BL.
  List<Offset> get corners {
    final c = center;
    final r = unrotatedRect;
    return <Offset>[
      r.topLeft.rotateAround(c, rotation),
      r.topRight.rotateAround(c, rotation),
      r.bottomRight.rotateAround(c, rotation),
      r.bottomLeft.rotateAround(c, rotation),
    ];
  }

  LayerTransform copyWith({Offset? position, Size? size, double? rotation}) {
    return LayerTransform(
      position: position ?? this.position,
      size: size ?? this.size,
      rotation: rotation ?? this.rotation,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayerTransform &&
          other.position == position &&
          other.size == size &&
          other.rotation == rotation;

  @override
  int get hashCode => Object.hash(position, size, rotation);

  @override
  String toString() =>
      'LayerTransform(pos: $position, size: $size, rot: ${rotation.toStringAsFixed(3)})';

  // ----- serialization -----

  /// Stable JSON shape: `{x, y, w, h, r}`. Plain primitive fields keep
  /// the file format diff-friendly and stable across Flutter versions
  /// (no `Offset`/`Size` class names that could change).
  ///
  /// Non-finite guard: a `NaN` / `±Infinity` field can only ever arrive
  /// from a math bug (every legitimate pose is a real number), but JSON
  /// cannot represent one — a single non-finite value would make
  /// `JsonEncoder.convert` throw, rendering the whole document unsaveable
  /// and silently dropping the crash-recovery journal write (which
  /// swallows encode errors). Coerce to `0` so a transient bad frame
  /// never bricks save/autosave; `assert` in debug so the upstream bug
  /// still surfaces during development. Finite documents (all of them)
  /// serialize byte-for-byte identically.
  Map<String, dynamic> toJson() {
    // Warn loudly in debug (a non-finite field is always an upstream
    // math bug worth chasing) but NEVER throw — the coercion below has to
    // run so save / autosave still succeed. The always-true assert body
    // is compiled out of release entirely.
    assert(() {
      final ok =
          position.dx.isFinite &&
          position.dy.isFinite &&
          size.width.isFinite &&
          size.height.isFinite &&
          rotation.isFinite;
      if (!ok) {
        debugPrint('LayerTransform.toJson coerced a non-finite field: $this');
      }
      return true;
    }());
    return <String, dynamic>{
      'x': _finite(position.dx),
      'y': _finite(position.dy),
      'w': _finite(size.width),
      'h': _finite(size.height),
      'r': _finite(rotation),
    };
  }

  /// Returns [v] when finite, else `0` — the save-boundary fallback that
  /// keeps a bug-produced non-finite pose from making the document
  /// unencodable. See [toJson].
  static double _finite(double v) => v.isFinite ? v : 0.0;

  /// Inverse of [toJson]. Throws [FormatException] on missing or
  /// non-numeric fields — surfaced by `DocumentCodec` as a
  /// `DocumentDecodeException` so the existing document is never
  /// silently corrupted by bad input.
  factory LayerTransform.fromJson(Map<String, dynamic> json) {
    double n(String key) {
      final v = json[key];
      if (v is num) return v.toDouble();
      throw FormatException('LayerTransform.$key missing or not numeric', v);
    }

    return LayerTransform(
      position: Offset(n('x'), n('y')),
      size: Size(n('w'), n('h')),
      rotation: n('r'),
    );
  }
}
