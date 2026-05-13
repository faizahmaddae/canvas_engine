/// Vignette effect — the first non-colour-matrix effect, and the
/// proof-of-vehicle for the dual rendering path documented on
/// [EditorEffect].
///
/// A vignette is a soft radial darkening (or tinting) from the
/// centre of the layer outward. It is *spatial*, not chromatic — a
/// 4×5 colour matrix can't represent it because the operation
/// depends on the pixel's position, not just its value. This is
/// what motivates [EffectKind.customPaint]: each such effect runs
/// its own `paint(Canvas, Rect)` over the already-colour-graded
/// pixels.
///
/// ## Parameters
///
/// * [intensity] — `0..1`. `0` is the identity (the renderer skips
///   the overlay entirely so byte-identity holds). `1` is the
///   tint colour at full opacity at the corners.
/// * [feather] — `0..1`. `0` produces a hard-edged ring near the
///   layer edge; `1` produces a smooth gradient that starts almost
///   from the centre. `0.5` is a sensible default for the
///   "Snapseed-like" look.
/// * [color] — the tint. Defaults to opaque black for the classic
///   darkening vignette; setting white gives a "halo" / soft-light
///   effect, and a low-saturation tint can warm the corners.
///
/// ## Render math
///
/// A `ui.Gradient.radial` from the layer centre, with two stops:
///
///   * inner stop at `feather` (0..1 of the half-diagonal radius),
///     fully transparent.
///   * outer stop at `1.0`, [color] with alpha = `intensity *
///     color.opacity`.
///
/// The gradient is painted over the layer's local bounds. The
/// renderer wraps the painter inside the layer's mask clip, so the
/// vignette automatically follows rounded / circle / squircle
/// silhouettes for free.
part of 'editor_effect.dart';

/// Soft radial overlay that darkens (or tints) the corners of a
/// layer. See the file-level doc for the math.
final class VignetteEffect extends EditorEffect {
  const VignetteEffect({
    this.intensity = 0,
    this.feather = 0.5,
    this.color = const Color(0xFF000000),
    super.enabled,
    super.mask,
  });

  /// `0..1`. `0` is the identity; the renderer omits the overlay
  /// when [intensity] is zero so byte-identity with a
  /// vignette-free document is preserved.
  final double intensity;

  /// `0..1`. Controls where the gradient starts: the inner
  /// transparent stop sits at this fraction of the layer's
  /// half-diagonal radius. Larger values produce softer, more
  /// gradual falloff.
  final double feather;

  /// Tint colour. Opaque black is the classic darkening look. The
  /// effect's [intensity] scales the colour's own alpha so a
  /// pre-baked translucent colour stays consistent with the slider.
  final Color color;

  /// Soft clamp ranges. Stored on the type to keep magic numbers
  /// out of `engine_constants.dart` — these belong to this effect's
  /// API, exactly the same convention the colour-matrix concretes
  /// follow for their `min/maxAmount` constants.
  static const double minIntensity = 0;
  static const double maxIntensity = 1;
  static const double minFeather = 0;
  static const double maxFeather = 1;

  /// Defaults pulled out as constants so the omit-on-default JSON
  /// gate has a single source of truth.
  static const double defaultIntensity = 0;
  static const double defaultFeather = 0.5;
  static const int defaultColorValue = 0xFF000000;

  @override
  String get type => _kVignetteType;

  @override
  EffectKind get kind => EffectKind.customPaint;

  @override
  bool get contributes => intensity > 0;

  /// Paint the radial overlay. Called by the renderer after
  /// colour-grading and after the layer mask has been clipped, so
  /// implementations don't need to re-clip — the canvas is already
  /// silhouette-bounded.
  @override
  void paint(Canvas canvas, Rect bounds) {
    if (!contributes) return;
    final centre = bounds.center;
    // Half-diagonal so a circular falloff still reaches the
    // corners of a wide / tall rectangle. Using width/2 alone
    // would clip the gradient short on landscape layers.
    final radius = math.sqrt(
      bounds.width * bounds.width + bounds.height * bounds.height,
    ) /
        2;
    if (radius <= 0) return;
    // Compose intensity onto the tint's own alpha. A user who has
    // chosen a translucent tint expects the slider to scale that
    // translucency, not blow it back to opaque.
    final outerAlpha = color.a * intensity.clamp(0.0, 1.0);
    final innerStop = feather.clamp(0.0, 1.0);
    // Smoothstep-shaped falloff (Hermite `3t² − 2t³`). A two-stop
    // linear gradient produces a visible kink at the inner stop
    // — readable as a faint ring at the start of the darkening
    // on smooth photos. Sampling smoothstep at 6 intermediate
    // positions between [innerStop, 1.0] gives a perceptually
    // continuous fall-off without paying the cost of a custom
    // shader. The endpoints are duplicated so the resulting
    // gradient still pins exactly to (transparent→outerColor).
    const samples = 8;
    final colors = <Color>[];
    final stops = <double>[];
    for (var i = 0; i < samples; i++) {
      final t = i / (samples - 1); // 0..1
      final s = t * t * (3 - 2 * t); // smoothstep
      colors.add(
        color.withValues(alpha: (outerAlpha * s).clamp(0.0, 1.0)),
      );
      stops.add(innerStop + (1.0 - innerStop) * t);
    }
    final shader = ui.Gradient.radial(
      ui.Offset(centre.dx, centre.dy),
      radius,
      colors,
      stops,
    );
    final paint = Paint()..shader = shader;
    canvas.drawRect(bounds, paint);
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        ...baseJson(),
        if (intensity != defaultIntensity) 'intensity': intensity,
        if (feather != defaultFeather) 'feather': feather,
        // Encode colour as 32-bit ARGB int — same convention every
        // other engine module uses for `Color` round-trip.
        if (color.toARGB32() != defaultColorValue) 'color': color.toARGB32(),
      };

  static VignetteEffect fromJson(Map<String, dynamic> json) => VignetteEffect(
        intensity:
            (json['intensity'] as num?)?.toDouble() ?? defaultIntensity,
        feather: (json['feather'] as num?)?.toDouble() ?? defaultFeather,
        color: Color((json['color'] as int?) ?? defaultColorValue),
        enabled: json['enabled'] as bool? ?? true,
        mask: _readMask(json),
      );

  /// Functional copy. Only the four content fields are
  /// copy-touchable; the renderer never builds a vignette with a
  /// different `enabled`/`mask` than the user-edited one.
  VignetteEffect copyWith({
    double? intensity,
    double? feather,
    Color? color,
    bool? enabled,
    LayerMask? mask,
  }) =>
      VignetteEffect(
        intensity: intensity ?? this.intensity,
        feather: feather ?? this.feather,
        color: color ?? this.color,
        enabled: enabled ?? this.enabled,
        mask: mask ?? this.mask,
      );

  @override
  VignetteEffect withEnabled(bool value) => copyWith(enabled: value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VignetteEffect &&
          other.intensity == intensity &&
          other.feather == feather &&
          other.color == color &&
          other.enabled == enabled &&
          other.mask == mask);

  @override
  int get hashCode =>
      Object.hash(_kVignetteType, intensity, feather, color, enabled, mask);
}

const String _kVignetteType = 'vignette';

/// Lazily-evaluated registration sentinel. Touched from
/// [EditorEffect.fromJson] so the decoder is guaranteed to be in
/// the registry the first time any document is decoded, regardless
/// of whether a caller has otherwise referenced [VignetteEffect].
final bool _kVignetteEffectRegistered = (() {
  registerEffect(_kVignetteType, VignetteEffect.fromJson);
  return true;
}());
