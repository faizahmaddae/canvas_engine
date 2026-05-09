import 'package:flutter/services.dart';

/// Centralised haptic feedback for editor interactions.
///
/// Premium mobile editors (Canva, CapCut, Procreate) use subtle,
/// consistent haptics to signal state changes. We expose a small
/// vocabulary of intents instead of raw HapticFeedback calls so
/// the feel can be tuned globally.
class EditorHaptics {
  EditorHaptics._();

  /// Tile / chip / segment tap.
  static void tap() => HapticFeedback.selectionClick();

  /// Toggle on/off (B/I/U, switch).
  static void toggle() => HapticFeedback.lightImpact();

  /// Slider snapped to a preset value.
  static void snap() => HapticFeedback.selectionClick();

  /// Confirmation / commit (apply, done).
  static void confirm() => HapticFeedback.mediumImpact();

  /// Sheet opened / closed via swipe.
  static void sheet() => HapticFeedback.lightImpact();
}
