import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' as painting;

/// Text-only visual style. Kept separate from [TextLayer] so it can be
/// edited as a value object (and later serialized) without rebuilding the
/// whole layer identity.
@immutable
class TextStyleSpec {
  const TextStyleSpec({
    this.fontFamily,
    this.fontSize = 96,
    this.color = const Color(0xFFFFFFFF),
    this.fontWeight = FontWeight.w600,
    this.italic = false,
    this.underline = false,
    this.letterSpacing = 0,
    this.lineHeight = 1.2,
    this.alignment = TextAlign.center,
    this.shadowColor,
    this.shadowBlur = 4,
    this.shadowOffset = const Offset(0, 2),
    this.outlineColor,
    this.outlineWidth = 2,
    this.backgroundColor,
    this.backgroundRadius = 0,
    this.backgroundPaddingX = 8,
    this.backgroundPaddingY = 4,
  });

  final String? fontFamily;
  final double fontSize;
  final Color color;
  final FontWeight fontWeight;
  final bool italic;
  final bool underline;
  final double letterSpacing;

  /// Multiplier on the font's natural line-height (CSS-style). 1.0 is
  /// tight, 1.2 is comfortable default, 1.5 is loose.
  final double lineHeight;
  final TextAlign alignment;

  /// Drop-shadow colour. `null` disables the shadow entirely. When
  /// non-null, [shadowBlur] and [shadowOffset] describe its softness
  /// and position; the colour's alpha doubles as the shadow opacity.
  final Color? shadowColor;
  final double shadowBlur;
  final Offset shadowOffset;

  /// Glyph outline ("border") colour. `null` disables the outline
  /// entirely. When non-null, [outlineWidth] is the stroke width in
  /// logical pixels, applied around each glyph (Canva-style).
  final Color? outlineColor;
  final double outlineWidth;

  /// Per-layer background fill rendered behind the text. `null` means
  /// no background — the text draws against the canvas. Padding around
  /// the text inside the fill is controlled by [backgroundPaddingX]
  /// (horizontal) and [backgroundPaddingY] (vertical).
  final Color? backgroundColor;

  /// Corner roundness of the background fill, expressed as a fraction
  /// of `min(boxWidth, boxHeight) / 2`:
  ///   * `0.0` — perfectly square corners.
  ///   * `0.5` — moderately rounded.
  ///   * `1.0` — a true pill (radius == half the shorter side), no
  ///     matter how large the text becomes.
  ///
  /// Stored as a percentage so chips/badges stay visually pill-shaped
  /// across font sizes — a fixed-px radius would shrink at large text.
  /// Always clamped to `[0, 1]`. The default is `0` (square).
  final double backgroundRadius;

  /// Horizontal inset between text and background edge (px each side).
  final double backgroundPaddingX;

  /// Vertical inset between text and background edge (px each side).
  final double backgroundPaddingY;

  /// True when [fontWeight] is at or above [FontWeight.w600]. Lets the
  /// toolbar treat "bold" as a boolean toggle without exposing the
  /// full weight ladder yet (a future phase can add a weight picker).
  bool get isBold => fontWeight.value >= FontWeight.w600.value;

  /// Copy with optional overrides. Pass [clearShadow]/[clearBackground]
  /// `true` to explicitly null the field — needed because
  /// `?? this.field` cannot distinguish "not provided" from "set to
  /// null" with nullable parameters.
  TextStyleSpec copyWith({
    String? fontFamily,
    double? fontSize,
    Color? color,
    FontWeight? fontWeight,
    bool? italic,
    bool? underline,
    double? letterSpacing,
    double? lineHeight,
    TextAlign? alignment,
    Color? shadowColor,
    double? shadowBlur,
    Offset? shadowOffset,
    Color? outlineColor,
    double? outlineWidth,
    Color? backgroundColor,
    double? backgroundRadius,
    double? backgroundPaddingX,
    double? backgroundPaddingY,
    bool clearShadow = false,
    bool clearOutline = false,
    bool clearBackground = false,
    bool clearFontFamily = false,
  }) {
    return TextStyleSpec(
      fontFamily: clearFontFamily ? null : (fontFamily ?? this.fontFamily),
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      fontWeight: fontWeight ?? this.fontWeight,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      lineHeight: lineHeight ?? this.lineHeight,
      alignment: alignment ?? this.alignment,
      shadowColor: clearShadow ? null : (shadowColor ?? this.shadowColor),
      shadowBlur: shadowBlur ?? this.shadowBlur,
      shadowOffset: shadowOffset ?? this.shadowOffset,
      outlineColor:
          clearOutline ? null : (outlineColor ?? this.outlineColor),
      outlineWidth: outlineWidth ?? this.outlineWidth,
      backgroundColor:
          clearBackground ? null : (backgroundColor ?? this.backgroundColor),
      backgroundRadius: backgroundRadius ?? this.backgroundRadius,
      backgroundPaddingX: backgroundPaddingX ?? this.backgroundPaddingX,
      backgroundPaddingY: backgroundPaddingY ?? this.backgroundPaddingY,
    );
  }

  painting.TextStyle toPaintingStyle() => painting.TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        color: color,
        fontWeight: fontWeight,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        decoration: underline ? TextDecoration.underline : null,
        letterSpacing: letterSpacing,
        height: lineHeight,
        shadows: shadowColor == null
            ? null
            : [
                painting.Shadow(
                  color: shadowColor!,
                  blurRadius: shadowBlur,
                  offset: shadowOffset,
                ),
              ],
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextStyleSpec &&
          other.fontFamily == fontFamily &&
          other.fontSize == fontSize &&
          other.color == color &&
          other.fontWeight == fontWeight &&
          other.italic == italic &&
          other.underline == underline &&
          other.letterSpacing == letterSpacing &&
          other.lineHeight == lineHeight &&
          other.alignment == alignment &&
          other.shadowColor == shadowColor &&
          other.shadowBlur == shadowBlur &&
          other.shadowOffset == shadowOffset &&
          other.outlineColor == outlineColor &&
          other.outlineWidth == outlineWidth &&
          other.backgroundColor == backgroundColor &&
          other.backgroundRadius == backgroundRadius &&
          other.backgroundPaddingX == backgroundPaddingX &&
          other.backgroundPaddingY == backgroundPaddingY;

  @override
  int get hashCode => Object.hash(
        fontFamily,
        fontSize,
        color,
        fontWeight,
        italic,
        underline,
        letterSpacing,
        lineHeight,
        alignment,
        shadowColor,
        shadowBlur,
        shadowOffset,
        outlineColor,
        outlineWidth,
        backgroundColor,
        backgroundRadius,
        backgroundPaddingX,
        backgroundPaddingY,
      );

  // ----- serialization -----

  /// Encode as plain JSON-friendly primitives. `fontWeight` is stored as
  /// its numeric weight (100..900) — stable across Flutter versions —
  /// rather than its enum index. `color` is stored as a 32-bit ARGB int.
  /// `alignment` uses the enum name so it stays readable in stored files.
  Map<String, dynamic> toJson() => <String, dynamic>{
        if (fontFamily != null) 'fontFamily': fontFamily,
        'fontSize': fontSize,
        'color': _encodeColor(color),
        'fontWeight': fontWeight.value,
        if (italic) 'italic': true,
        if (underline) 'underline': true,
        'letterSpacing': letterSpacing,
        'lineHeight': lineHeight,
        'alignment': alignment.name,
        if (shadowColor != null) ...{
          'shadowColor': _encodeColor(shadowColor!),
          'shadowBlur': shadowBlur,
          'shadowDx': shadowOffset.dx,
          'shadowDy': shadowOffset.dy,
        },
        if (outlineColor != null) ...{
          'outlineColor': _encodeColor(outlineColor!),
          'outlineWidth': outlineWidth,
        },
        if (backgroundColor != null) ...{
          'backgroundColor': _encodeColor(backgroundColor!),
          'backgroundRadius': backgroundRadius,
          'backgroundPaddingX': backgroundPaddingX,
          'backgroundPaddingY': backgroundPaddingY,
        },
      };

  factory TextStyleSpec.fromJson(Map<String, dynamic> json) {
    final fontWeightValue = json['fontWeight'];
    final fontWeight = fontWeightValue is num
        ? _fontWeightFromValue(fontWeightValue.toInt())
        : FontWeight.w600;
    final alignName = json['alignment'];
    final alignment = alignName is String
        ? TextAlign.values.firstWhere(
            (a) => a.name == alignName,
            orElse: () => TextAlign.center,
          )
        : TextAlign.center;
    // Defaults intentionally mirror the unnamed constructor so a JSON
    // payload that omits an optional field round-trips into the same
    // value the user would get from `const TextStyleSpec()`.
    return TextStyleSpec(
      fontFamily: json['fontFamily'] as String?,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 96,
      color: _decodeColor(json['color']) ?? const Color(0xFFFFFFFF),
      fontWeight: fontWeight,
      italic: json['italic'] as bool? ?? false,
      underline: json['underline'] as bool? ?? false,
      letterSpacing: (json['letterSpacing'] as num?)?.toDouble() ?? 0,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.2,
      alignment: alignment,
      shadowColor: _decodeColor(json['shadowColor']),
      shadowBlur: (json['shadowBlur'] as num?)?.toDouble() ?? 4,
      shadowOffset: Offset(
        (json['shadowDx'] as num?)?.toDouble() ?? 0,
        (json['shadowDy'] as num?)?.toDouble() ?? 2,
      ),
      outlineColor: _decodeColor(json['outlineColor']),
      outlineWidth: (json['outlineWidth'] as num?)?.toDouble() ?? 2,
      backgroundColor: _decodeColor(json['backgroundColor']),
      // Migration: pre-percent docs stored radius in logical pixels
      // (typical range 0..40). Anything > 1 is treated as legacy and
      // converted into the new 0..1 percent space; new docs are
      // already in range and pass through unchanged.
      backgroundRadius: () {
        final raw = (json['backgroundRadius'] as num?)?.toDouble() ?? 0.0;
        if (raw > 1.0) return (raw / 40.0).clamp(0.0, 1.0);
        return raw.clamp(0.0, 1.0);
      }(),
      backgroundPaddingX:
          (json['backgroundPaddingX'] as num?)?.toDouble() ?? 8,
      backgroundPaddingY:
          (json['backgroundPaddingY'] as num?)?.toDouble() ?? 4,
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

  /// Map a numeric weight (100..900) to a [FontWeight]. Falls back to
  /// the closest standard weight if the input is non-standard.
  static FontWeight _fontWeightFromValue(int value) {
    const weights = <FontWeight>[
      FontWeight.w100,
      FontWeight.w200,
      FontWeight.w300,
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
      FontWeight.w800,
      FontWeight.w900,
    ];
    var best = weights.first;
    var bestDiff = (best.value - value).abs();
    for (final w in weights) {
      final d = (w.value - value).abs();
      if (d < bestDiff) {
        best = w;
        bestDiff = d;
      }
    }
    return best;
  }
}
