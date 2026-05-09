import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

/// Output-dimension presets surfaced in the export sheet.
///
/// These do **not** mutate the document canvas — they only change the
/// pixel rectangle the exported file is rendered into. The document
/// is composited into the target rect with `BoxFit.contain` math and
/// the canvas background colour fills any letterbox bands, so the
/// exported image is always the exact requested size **without
/// stretching** the original artwork.
///
/// Presets are intentionally limited to the four most-used social
/// sizes plus an `original` passthrough and a `custom` escape hatch.
/// Adding a new preset only requires extending this enum — the
/// renderer (`ExportController.exportImage`) and the picker UI both
/// drive off `ExportSize.values`.
@immutable
class ExportSize {
  const ExportSize._({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.target,
    this.isCustom = false,
  });

  /// Stable identifier used for analytics + as the picker's selected
  /// value. Never localise.
  final String id;

  /// Short display label (e.g. "Square").
  final String label;

  /// Short subtitle — typically the dimensions or platform hint.
  final String subtitle;

  /// Target output rectangle in pixels, or `null` for [original]
  /// (export uses the canvas size × the user's quality multiplier).
  final Size? target;

  /// True for [custom]; the picker uses this to open the dimensions
  /// dialog instead of selecting a fixed target.
  final bool isCustom;

  // ──────────────────────────── presets ─────────────────────────────
  static const ExportSize original = ExportSize._(
    id: 'original',
    label: 'Original',
    subtitle: 'Use canvas size',
    target: null,
  );

  static const ExportSize square1080 = ExportSize._(
    id: 'square_1080',
    label: 'Square',
    subtitle: '1080 × 1080',
    target: Size(1080, 1080),
  );

  static const ExportSize story1080x1920 = ExportSize._(
    id: 'story_1080x1920',
    label: 'Story',
    subtitle: '1080 × 1920',
    target: Size(1080, 1920),
  );

  static const ExportSize portrait1080x1350 = ExportSize._(
    id: 'portrait_1080x1350',
    label: 'Portrait',
    subtitle: '1080 × 1350 · 4:5',
    target: Size(1080, 1350),
  );

  static const ExportSize custom = ExportSize._(
    id: 'custom',
    label: 'Custom…',
    subtitle: 'Pick exact pixels',
    target: null,
    isCustom: true,
  );

  /// Display order in the picker.
  static const List<ExportSize> values = [
    original,
    square1080,
    story1080x1920,
    portrait1080x1350,
    custom,
  ];

  /// Build a one-off custom preset for the user's typed dimensions.
  /// Carries [isCustom] = true so callers can distinguish it from a
  /// preset without value-comparing every field.
  factory ExportSize.customSize(int width, int height) {
    assert(width > 0 && height > 0, 'custom dimensions must be positive');
    return ExportSize._(
      id: 'custom_${width}x$height',
      label: 'Custom',
      subtitle: '$width × $height',
      target: Size(width.toDouble(), height.toDouble()),
      isCustom: true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportSize &&
          other.id == id &&
          other.target == target &&
          other.isCustom == isCustom;

  @override
  int get hashCode => Object.hash(id, target, isCustom);

  @override
  String toString() => 'ExportSize($id, $target)';
}

/// Pure aspect-fit math shared by the preset renderer and tests.
///
/// Returns the destination rectangle (in target-pixel coordinates) the
/// source content should be drawn into so it fits inside [target]
/// without distortion. Centred horizontally and vertically; bands of
/// uncovered area are letterboxed by the caller.
({double left, double top, double width, double height}) fitContain({
  required Size source,
  required Size target,
}) {
  if (source.width <= 0 || source.height <= 0) {
    return (left: 0, top: 0, width: 0, height: 0);
  }
  final scale = (target.width / source.width) <= (target.height / source.height)
      ? target.width / source.width
      : target.height / source.height;
  final w = source.width * scale;
  final h = source.height * scale;
  return (
    left: (target.width - w) / 2,
    top: (target.height - h) / 2,
    width: w,
    height: h,
  );
}
