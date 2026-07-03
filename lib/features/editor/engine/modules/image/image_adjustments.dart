// Colour-grading value object for [ImageLayer], split out of
// image_layer.dart. Part file: every symbol (composeColorMatrices,
// the effect classes, EffectStack) resolves via the library root's
// imports — add imports there, never here.
part of 'image_layer.dart';

/// Per-pixel colour grading parameters for an [ImageLayer]. Stored
/// as engine-friendly scalars so undo/redo, JSON, and equality all
/// stay trivial; the actual matrix is computed lazily by
/// [toMatrix] when the layer renders.
///
/// Ranges (chosen to match the UI sliders 1:1 so callers don't need
/// to scale values):
/// - [brightness]: `-100..100` — `0` is unchanged, positive
///   brightens, negative darkens. Translated to a uniform RGB
///   offset of `brightness * 2.55` so ±100 maps to ±full luminance.
/// - [contrast]: `0..2` — `1` is unchanged. Implemented as a
///   linear scale around mid-grey (128) so values < 1 flatten and
///   values > 1 expand the tonal range.
/// - [saturation]: `0..2` — `1` is unchanged. `0` collapses to
///   greyscale, `2` doubles colour intensity. Uses the standard
///   ITU-R BT.601 luma weights (0.299 / 0.587 / 0.114).
@immutable
class ImageAdjustments {
  // Non-const because of `late final colorMatrix` cache. The performance
  // win on the per-frame render path outweighs compile-time canonicalization,
  // which was unused in practice (only [ImageAdjustments.identity] was ever
  // const-constructed).
  // ignore: prefer_const_constructors_in_immutables
  ImageAdjustments({
    this.brightness = 0,
    this.contrast = 1,
    this.saturation = 1,
    this.exposure = 0,
    this.warmth = 0,
  });

  final double brightness;
  final double contrast;
  final double saturation;

  /// Multiplicative gain applied to RGB before contrast / brightness.
  /// Range `-100..100`; `0` is unchanged. Mapped to a multiplier of
  /// `1 + exposure / 100` so ±100 doubles or zeroes the channel
  /// intensity. Conceptually the camera-style exposure stop, not the
  /// additive brightness offset.
  final double exposure;

  /// Colour-temperature shift along the blue↔orange axis. Range
  /// `-100..100`; `0` is unchanged. Positive values warm the image
  /// (boost red, drop blue); negative values cool it. Mapped to ±20%
  /// channel offsets at the extremes so it never burns out highlights.
  final double warmth;

  // `static final` (not `const`) because the constructor is no longer const;
  // a single shared instance is still preserved.
  static final ImageAdjustments identity = ImageAdjustments();

  /// True when the configured values are visually a no-op so the
  /// renderer can skip the [ColorFiltered] wrapper entirely —
  /// avoids paying the per-frame matrix cost on the 95% of images
  /// the user never tunes.
  bool get isIdentity =>
      brightness == 0 &&
      contrast == 1 &&
      saturation == 1 &&
      exposure == 0 &&
      warmth == 0;

  ImageAdjustments copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? exposure,
    double? warmth,
  }) {
    return ImageAdjustments(
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      exposure: exposure ?? this.exposure,
      warmth: warmth ?? this.warmth,
    );
  }

  /// Composes every adjustment into a single 4×5 colour matrix
  /// suitable for [ColorFilter.matrix]. Order:
  /// **exposure → warmth → saturation → contrast → brightness**
  /// so the multiplicative camera stages run first, the colour
  /// shift lands on the gained pixels, and the user-facing
  /// brightness/contrast sliders trim the final tonal range.
  ///
  /// Cached on first read: matrix composition is a pure function of the
  /// five fields, and slider drags hold a value steady across many frames
  /// once the user releases. Recomputing per frame burned measurable CPU.
  /// `ImageAdjustments` is immutable, so the cache can never go stale —
  /// `copyWith` returns a new instance with its own fresh cache slot.
  late final List<double> colorMatrix = _computeMatrix();

  List<double> _computeMatrix() {
    // 1) Exposure: pure RGB gain. Mid-grey passes through scaled.
    final ex = 1 + exposure / 100;
    final expM = <double>[
      ex,
      0,
      0,
      0,
      0,
      0,
      ex,
      0,
      0,
      0,
      0,
      0,
      ex,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];

    // 2) Warmth: shift blue↔orange. ±100 → ±20% additive on R/B.
    //    Green gets a smaller nudge so the white point stays neutral.
    final wOff = warmth * 0.2 * 2.55; // 0.2 of full range, in 0..255.
    final warmM = <double>[
      1,
      0,
      0,
      0,
      wOff,
      0,
      1,
      0,
      0,
      wOff * 0.4,
      0,
      0,
      1,
      0,
      -wOff,
      0,
      0,
      0,
      1,
      0,
    ];

    final s = saturation;
    // ITU-R BT.601 luma weights.
    const lr = 0.299;
    const lg = 0.587;
    const lb = 0.114;
    final sr0 = (1 - s) * lr;
    final sg0 = (1 - s) * lg;
    final sb0 = (1 - s) * lb;
    final sat = <double>[
      sr0 + s,
      sg0,
      sb0,
      0,
      0,
      sr0,
      sg0 + s,
      sb0,
      0,
      0,
      sr0,
      sg0,
      sb0 + s,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];

    final c = contrast;
    final cTrans = 128 * (1 - c);
    final con = <double>[
      c,
      0,
      0,
      0,
      cTrans,
      0,
      c,
      0,
      0,
      cTrans,
      0,
      0,
      c,
      0,
      cTrans,
      0,
      0,
      0,
      1,
      0,
    ];

    final bTrans = brightness * 2.55;
    final bri = <double>[
      1,
      0,
      0,
      0,
      bTrans,
      0,
      1,
      0,
      0,
      bTrans,
      0,
      0,
      1,
      0,
      bTrans,
      0,
      0,
      0,
      1,
      0,
    ];

    // Apply outermost-last: bri( con( sat( warm( exp(c) ) ) ) ).
    return composeColorMatrices(
      bri,
      composeColorMatrices(
        con,
        composeColorMatrices(sat, composeColorMatrices(warmM, expM)),
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (brightness != 0) 'brightness': brightness,
    if (contrast != 1) 'contrast': contrast,
    if (saturation != 1) 'saturation': saturation,
    if (exposure != 0) 'exposure': exposure,
    if (warmth != 0) 'warmth': warmth,
  };

  factory ImageAdjustments.fromJson(Map<String, dynamic> json) {
    return ImageAdjustments(
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 1,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 1,
      exposure: (json['exposure'] as num?)?.toDouble() ?? 0,
      warmth: (json['warmth'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Project this adjustments value to the equivalent
  /// [EditorEffect] sequence, in the legacy fixed render order
  /// (exposure → warmth → saturation → contrast → brightness).
  ///
  /// Identity-valued fields are *omitted* — the renderer would
  /// short-circuit them anyway, and skipping keeps the stack minimal
  /// (smaller JSON, cheaper equality, less per-frame work).
  ///
  /// Bridge for the soft-retire migration: the layer no longer
  /// stores [ImageAdjustments] as a field. UI panels read the
  /// current per-knob values via [fromEffectStack], commit edits
  /// via [SetImageAdjustmentsCommand] (which writes effects
  /// directly), and legacy on-disk documents are lifted into the
  /// effect form on decode.
  List<EditorEffect> toEffectStack() {
    final out = <EditorEffect>[];
    if (exposure != 0) out.add(ExposureEffect(amount: exposure));
    if (warmth != 0) out.add(WarmthEffect(amount: warmth));
    if (saturation != 1) out.add(SaturationEffect(amount: saturation));
    if (contrast != 1) out.add(ContrastEffect(amount: contrast));
    if (brightness != 0) out.add(BrightnessEffect(amount: brightness));
    return out;
  }

  /// Reverse of [toEffectStack]: read the five canonical
  /// colour-adjustment effect amounts off [stack] and pack them
  /// into a value object the legacy UI panels can drive sliders
  /// against. Effects of other types and effects with masks /
  /// disabled flags are *ignored* — those don't have a
  /// representation in the flat-struct form.
  ///
  /// If [stack] contains multiple effects of the same derived type
  /// (which the dual-write canonical form never produces, but a
  /// future tool might), the **last** wins. That matches the
  /// renderer's stack-order semantics: the topmost matrix is the
  /// one the user sees in the slider value.
  static ImageAdjustments fromEffectStack(EffectStack stack) {
    double brightness = 0;
    double contrast = 1;
    double saturation = 1;
    double exposure = 0;
    double warmth = 0;
    for (final eff in stack.effects) {
      if (!eff.enabled || eff.mask != null) continue;
      switch (eff) {
        case BrightnessEffect():
          brightness = eff.amount;
        case ContrastEffect():
          contrast = eff.amount;
        case SaturationEffect():
          saturation = eff.amount;
        case ExposureEffect():
          exposure = eff.amount;
        case WarmthEffect():
          warmth = eff.amount;
        case VignetteEffect():
          // Vignette is a custom-paint effect; it does not feed
          // back into the legacy adjustments struct.
          break;
        case UnknownEffect():
          // Forward-compat carrier for an effect type unknown to
          // this binary (a newer build wrote it). It contributes
          // nothing to the legacy adjustments struct; the codec
          // round-trips its raw JSON so the data survives a resave.
          break;
      }
    }
    return ImageAdjustments(
      brightness: brightness,
      contrast: contrast,
      saturation: saturation,
      exposure: exposure,
      warmth: warmth,
    );
  }

  /// The five effect type discriminators an [ImageAdjustments]
  /// expands into. Used by the dual-write helper to strip the
  /// previous derived effects from a layer's stack before
  /// re-projecting the new value, so user-added effects of *other*
  /// types survive the rebuild.
  static const Set<String> derivedEffectTypes = <String>{
    'brightness',
    'contrast',
    'saturation',
    'exposure',
    'warmth',
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageAdjustments &&
          other.brightness == brightness &&
          other.contrast == contrast &&
          other.saturation == saturation &&
          other.exposure == exposure &&
          other.warmth == warmth;

  @override
  int get hashCode =>
      Object.hash(brightness, contrast, saturation, exposure, warmth);
}
