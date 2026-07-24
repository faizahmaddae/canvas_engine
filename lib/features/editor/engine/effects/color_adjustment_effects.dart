/// Concrete colour-adjustment effects for Phase 2.
///
/// Each effect carries one scalar value and is part of the sealed
/// [EditorEffect] hierarchy. The five concretes here mirror exactly
/// the five fields on the legacy [ImageAdjustments] struct so the
/// dual-write migration in [SetImageAdjustmentsCommand] can keep
/// both sides coherent.
///
/// ## Why one file, not five
///
/// AGENTS.md prefers one concept per file, but these five effects
/// are *one concept* (per-channel colour adjustment) split by axis.
/// Renderer Step 5 dispatches over the whole family in one switch
/// — keeping them together makes that switch easy to read and
/// trims four files of boilerplate.
///
/// ## Why separate effects (not one struct effect)
///
/// Effects compose: a brightness effect *above* a contrast effect
/// must produce a different result than the reverse, because the
/// renderer multiplies their colour matrices in stack order. The
/// legacy [ImageAdjustments] hard-codes a single ordering
/// (exposure → warmth → saturation → contrast → brightness). The
/// effect-stack form preserves that ordering for migrated layers
/// (see [ImageAdjustments.toEffectStack]) but lets future tools
/// rearrange or insert effects between them.
part of 'editor_effect.dart';

/// Brightness adjustment, additive in the `-100..100` range.
/// `0` is the identity. Maps to a `+brightness*2.55` channel
/// translation in the renderer's colour matrix.
final class BrightnessEffect extends EditorEffect {
  const BrightnessEffect({this.amount = 0, super.enabled, super.mask});

  /// `-100..100`, `0` is no change.
  final double amount;

  /// Soft clamp range. Stored on the type to keep magic numbers out
  /// of `engine_constants.dart` — these belong to this effect's API.
  static const double minAmount = -100;
  static const double maxAmount = 100;

  @override
  String get type => _kBrightnessType;

  @override
  EffectKind get kind => EffectKind.colorMatrix;

  @override
  bool get contributes => amount != 0;

  /// 4×5 colour matrix realising this effect's amount. Identity
  /// when [amount] is 0; the renderer should still gate on that
  /// before composing to avoid an unnecessary multiply.
  List<double> get colorMatrix => _brightnessMatrix(amount);

  @override
  BrightnessEffect withEnabled(bool value) =>
      BrightnessEffect(amount: amount, enabled: value, mask: mask);

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    ...baseJson(),
    if (amount != 0) 'amount': amount,
  };

  static BrightnessEffect fromJson(Map<String, dynamic> json) =>
      BrightnessEffect(
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        enabled: json['enabled'] as bool? ?? true,
        mask: _readMask(json),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BrightnessEffect &&
          other.amount == amount &&
          other.enabled == enabled &&
          other.mask == mask);

  @override
  int get hashCode => Object.hash(_kBrightnessType, amount, enabled, mask);
}

/// Contrast adjustment as a multiplier in `0..2`. `1` is identity.
/// `0` collapses every pixel to mid-grey, `2` doubles tonal range
/// (with the usual highlight/shadow clipping at the extremes).
final class ContrastEffect extends EditorEffect {
  const ContrastEffect({this.amount = 1, super.enabled, super.mask});

  final double amount;

  static const double minAmount = 0;
  static const double maxAmount = 2;
  static const double identityAmount = 1;

  @override
  String get type => _kContrastType;

  @override
  EffectKind get kind => EffectKind.colorMatrix;

  @override
  bool get contributes => amount != identityAmount;

  List<double> get colorMatrix => _contrastMatrix(amount);

  @override
  ContrastEffect withEnabled(bool value) =>
      ContrastEffect(amount: amount, enabled: value, mask: mask);

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    ...baseJson(),
    if (amount != identityAmount) 'amount': amount,
  };

  static ContrastEffect fromJson(Map<String, dynamic> json) => ContrastEffect(
    amount: (json['amount'] as num?)?.toDouble() ?? identityAmount,
    enabled: json['enabled'] as bool? ?? true,
    mask: _readMask(json),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContrastEffect &&
          other.amount == amount &&
          other.enabled == enabled &&
          other.mask == mask);

  @override
  int get hashCode => Object.hash(_kContrastType, amount, enabled, mask);
}

/// Saturation as a multiplier in `0..2`. `1` is identity, `0` is
/// fully desaturated (greyscale, ITU-R BT.601 weights), `2`
/// doubles colour intensity.
final class SaturationEffect extends EditorEffect {
  const SaturationEffect({this.amount = 1, super.enabled, super.mask});

  final double amount;

  static const double minAmount = 0;
  static const double maxAmount = 2;
  static const double identityAmount = 1;

  @override
  String get type => _kSaturationType;

  @override
  EffectKind get kind => EffectKind.colorMatrix;

  @override
  bool get contributes => amount != identityAmount;

  List<double> get colorMatrix => _saturationMatrix(amount);

  @override
  SaturationEffect withEnabled(bool value) =>
      SaturationEffect(amount: amount, enabled: value, mask: mask);

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    ...baseJson(),
    if (amount != identityAmount) 'amount': amount,
  };

  static SaturationEffect fromJson(Map<String, dynamic> json) =>
      SaturationEffect(
        amount: (json['amount'] as num?)?.toDouble() ?? identityAmount,
        enabled: json['enabled'] as bool? ?? true,
        mask: _readMask(json),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SaturationEffect &&
          other.amount == amount &&
          other.enabled == enabled &&
          other.mask == mask);

  @override
  int get hashCode => Object.hash(_kSaturationType, amount, enabled, mask);
}

/// Camera-style exposure stop. Range `-100..100`, `0` identity.
/// Multiplicative gain `1 + amount/100` applied before warmth /
/// saturation / contrast / brightness.
final class ExposureEffect extends EditorEffect {
  const ExposureEffect({this.amount = 0, super.enabled, super.mask});

  final double amount;

  static const double minAmount = -100;
  static const double maxAmount = 100;

  @override
  String get type => _kExposureType;

  @override
  EffectKind get kind => EffectKind.colorMatrix;

  @override
  bool get contributes => amount != 0;

  List<double> get colorMatrix => _exposureMatrix(amount);

  @override
  ExposureEffect withEnabled(bool value) =>
      ExposureEffect(amount: amount, enabled: value, mask: mask);

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    ...baseJson(),
    if (amount != 0) 'amount': amount,
  };

  static ExposureEffect fromJson(Map<String, dynamic> json) => ExposureEffect(
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    enabled: json['enabled'] as bool? ?? true,
    mask: _readMask(json),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExposureEffect &&
          other.amount == amount &&
          other.enabled == enabled &&
          other.mask == mask);

  @override
  int get hashCode => Object.hash(_kExposureType, amount, enabled, mask);
}

/// Warm/cool colour-temperature shift. Range `-100..100`, `0`
/// identity. Positive warms (boosts red, drops blue), negative
/// cools.
final class WarmthEffect extends EditorEffect {
  const WarmthEffect({this.amount = 0, super.enabled, super.mask});

  final double amount;

  static const double minAmount = -100;
  static const double maxAmount = 100;

  @override
  String get type => _kWarmthType;

  @override
  EffectKind get kind => EffectKind.colorMatrix;

  @override
  bool get contributes => amount != 0;

  List<double> get colorMatrix => _warmthMatrix(amount);

  @override
  WarmthEffect withEnabled(bool value) =>
      WarmthEffect(amount: amount, enabled: value, mask: mask);

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    ...baseJson(),
    if (amount != 0) 'amount': amount,
  };

  static WarmthEffect fromJson(Map<String, dynamic> json) => WarmthEffect(
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    enabled: json['enabled'] as bool? ?? true,
    mask: _readMask(json),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WarmthEffect &&
          other.amount == amount &&
          other.enabled == enabled &&
          other.mask == mask);

  @override
  int get hashCode => Object.hash(_kWarmthType, amount, enabled, mask);
}

// ---------------------------------------------------------------
// Per-effect colour-matrix builders.
//
// Lifted verbatim out of `ImageAdjustments._computeMatrix` so the
// renderer can compose effects in stack order rather than reading
// the legacy struct. Each builder is identity-safe: callers must
// gate on `amount != identity` before composing if they want to
// skip the no-op multiplication.
// ---------------------------------------------------------------

List<double> _brightnessMatrix(double amount) {
  final t = amount * 2.55;
  return <double>[1, 0, 0, 0, t, 0, 1, 0, 0, t, 0, 0, 1, 0, t, 0, 0, 0, 1, 0];
}

List<double> _contrastMatrix(double amount) {
  final t = 128 * (1 - amount);
  return <double>[
    amount,
    0,
    0,
    0,
    t,
    0,
    amount,
    0,
    0,
    t,
    0,
    0,
    amount,
    0,
    t,
    0,
    0,
    0,
    1,
    0,
  ];
}

List<double> _saturationMatrix(double amount) {
  // ITU-R BT.601 luma weights (matches `ImageAdjustments`).
  const lr = 0.299;
  const lg = 0.587;
  const lb = 0.114;
  final sr0 = (1 - amount) * lr;
  final sg0 = (1 - amount) * lg;
  final sb0 = (1 - amount) * lb;
  return <double>[
    sr0 + amount,
    sg0,
    sb0,
    0,
    0,
    sr0,
    sg0 + amount,
    sb0,
    0,
    0,
    sr0,
    sg0,
    sb0 + amount,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

List<double> _exposureMatrix(double amount) {
  final g = 1 + amount / 100;
  return <double>[g, 0, 0, 0, 0, 0, g, 0, 0, 0, 0, 0, g, 0, 0, 0, 0, 0, 1, 0];
}

List<double> _warmthMatrix(double amount) {
  // ±100 → ±20% additive on R/B, with a smaller G nudge so the
  // white point stays neutral. Matches `ImageAdjustments`.
  final off = amount * 0.2 * 2.55;
  return <double>[
    1,
    0,
    0,
    0,
    off,
    0,
    1,
    0,
    0,
    off * 0.4,
    0,
    0,
    1,
    0,
    -off,
    0,
    0,
    0,
    1,
    0,
  ];
}

// ---------------------------------------------------------------
// Type discriminators. Held as private constants so the strings
// only appear once and a typo in one place doesn't silently
// produce a fork in the registry / serialization.
// ---------------------------------------------------------------
const String _kBrightnessType = 'brightness';
const String _kContrastType = 'contrast';
const String _kSaturationType = 'saturation';
const String _kExposureType = 'exposure';
const String _kWarmthType = 'warmth';

/// Shared mask reader: every colour-adjustment effect handles the
/// optional `mask` JSON slot identically. Centralising avoids five
/// copies of the same null-check.
LayerMask? _readMask(Map<String, dynamic> json) {
  final raw = json['mask'];
  if (raw is! Map) return null;
  return LayerMask.fromJson(Map<String, dynamic>.from(raw));
}

/// Registers all five colour-adjustment effects with the
/// [EditorEffect] decoder registry. The block runs once at first
/// reference (Dart top-level final-initializer semantics) so every
/// caller of `EditorEffect.fromJson` sees the registered factories
/// without any explicit initialization step.
final bool _kColorAdjustmentEffectsRegistered = (() {
  registerEffect(_kBrightnessType, BrightnessEffect.fromJson);
  registerEffect(_kContrastType, ContrastEffect.fromJson);
  registerEffect(_kSaturationType, SaturationEffect.fromJson);
  registerEffect(_kExposureType, ExposureEffect.fromJson);
  registerEffect(_kWarmthType, WarmthEffect.fromJson);
  return true;
}());
