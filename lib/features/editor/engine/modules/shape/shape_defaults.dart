import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'shape_layer.dart';

/// Pure helper that returns smart default visual properties for a newly
/// inserted [ShapeLayer] based on the canvas background colour.
///
/// Goals:
///   * Inserted shapes must be immediately visible — no white-on-white
///     or black-on-black first impression.
///   * No theme / BuildContext dependency — works identically in unit
///     tests and in the UI without any extra wiring.
///   * Single source of truth for "what colour does a fresh shape get".
///
/// Usage:
/// ```dart
/// final fill = ShapeDefaults.fillColorForCanvas(Colors.white, kind);
/// ```
class ShapeDefaults {
  ShapeDefaults._();

  // ─── Palette ────────────────────────────────────────────────────────────
  /// On-brand blue used as the default fill for solid shapes on a
  /// light canvas.  Chosen to be high-contrast against white and to
  /// feel like a sensible primary accent rather than a random colour.
  static const Color fillOnLight = Color(0xFF4C8BF5);

  /// Near-black used as the default fill/stroke for stroked shapes
  /// (line / arrow) on a light canvas.
  static const Color strokeOnLight = Color(0xFF1F2937);

  /// White fill/stroke for shapes on dark canvases.
  static const Color fillOnDark = Color(0xFFFFFFFF);

  // ─── Luminance threshold ────────────────────────────────────────────────
  /// WCAG relative-luminance threshold.  Values ≥ 0.5 are considered
  /// light; values < 0.5 are considered dark.
  static const double lightThreshold = 0.5;

  // ─── Public API ─────────────────────────────────────────────────────────
  /// Returns the default [fillColor] for a newly inserted shape of
  /// [kind] inserted onto a canvas whose background colour is
  /// [background].
  ///
  /// For *stroked* kinds ([ShapeKind.line] / [ShapeKind.arrow]),
  /// `fillColor` doubles as the stroke colour (the engine reuses it
  /// that way — see [ShapeLayer] docstring).
  ///
  /// For *filled* kinds (everything else) the colour is painted solid
  /// inside the shape.
  ///
  /// If [background] is `null` (or a future "no background" state),
  /// treat the canvas as light (white).
  static Color fillColorForCanvas(Color background, ShapeKind kind) {
    final isLight = _luminance(background) >= lightThreshold;
    if (isStrokedShapeKind(kind)) {
      return isLight ? strokeOnLight : fillOnDark;
    }
    return isLight ? fillOnLight : fillOnDark;
  }

  // ─── Internal ───────────────────────────────────────────────────────────
  /// WCAG 2.1 relative luminance.  Same formula as the private
  /// `_presetLuminance` used in `text_style_presets.dart` — kept
  /// local here so this file has no cross-feature dependency.
  static double _luminance(Color c) {
    double ch(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }
}
