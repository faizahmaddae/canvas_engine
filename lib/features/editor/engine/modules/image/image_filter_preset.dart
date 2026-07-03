// Curated filter presets for [ImageLayer], split out of
// image_layer.dart. Data-only: the enum plus its matrix lookup.
part of 'image_layer.dart';

/// Curated colour-grade preset applied **before** [ImageAdjustments]
/// in the render pipeline. Each preset is a fixed 4×5 colour matrix
/// designed to read as a single tasteful look — Instagram-style.
/// Adding a new preset is one enum value plus one branch in
/// [imageFilterMatrix].
enum ImageFilterPreset {
  /// No filter — the renderer skips the extra `ColorFilter` wrapper.
  none,
  warm,
  cool,
  vintage,
  mono,
  fade,
  dramatic,
}

/// Returns the 4×5 colour matrix for [preset] or `null` for
/// [ImageFilterPreset.none] (so the renderer can short-circuit). All
/// matrices are tuned for the same neutral exposure baseline so the
/// presets read as different *looks* rather than different brightness
/// levels.
List<double>? imageFilterMatrix(ImageFilterPreset preset) {
  switch (preset) {
    case ImageFilterPreset.none:
      return null;
    case ImageFilterPreset.warm:
      // Lift R+G, drop B slightly.
      return const <double>[
        1.10,
        0.00,
        0.00,
        0,
        12,
        0.00,
        1.05,
        0.00,
        0,
        6,
        0.00,
        0.00,
        0.92,
        0,
        -10,
        0.00,
        0.00,
        0.00,
        1,
        0,
      ];
    case ImageFilterPreset.cool:
      // Drop R, lift B for icy tones.
      return const <double>[
        0.92,
        0.00,
        0.00,
        0,
        -8,
        0.00,
        0.98,
        0.00,
        0,
        4,
        0.00,
        0.00,
        1.10,
        0,
        12,
        0.00,
        0.00,
        0.00,
        1,
        0,
      ];
    case ImageFilterPreset.vintage:
      // Sepia-flavoured cross-channel mix + slight contrast lift.
      return const <double>[
        0.62,
        0.30,
        0.18,
        0,
        0,
        0.30,
        0.65,
        0.16,
        0,
        0,
        0.22,
        0.28,
        0.55,
        0,
        0,
        0.00,
        0.00,
        0.00,
        1,
        0,
      ];
    case ImageFilterPreset.mono:
      // BT.601 luma weights — clean black & white.
      return const <double>[
        0.299,
        0.587,
        0.114,
        0,
        0,
        0.299,
        0.587,
        0.114,
        0,
        0,
        0.299,
        0.587,
        0.114,
        0,
        0,
        0.000,
        0.000,
        0.000,
        1,
        0,
      ];
    case ImageFilterPreset.fade:
      // Lift blacks, compress range — milky vintage film look.
      return const <double>[
        0.85,
        0.00,
        0.00,
        0,
        30,
        0.00,
        0.85,
        0.00,
        0,
        30,
        0.00,
        0.00,
        0.85,
        0,
        30,
        0.00,
        0.00,
        0.00,
        1,
        0,
      ];
    case ImageFilterPreset.dramatic:
      // Strong contrast around mid-grey, slight desaturation.
      return const <double>[
        1.30,
        0.00,
        0.00,
        0,
        -38,
        0.00,
        1.30,
        0.00,
        0,
        -38,
        0.00,
        0.00,
        1.30,
        0,
        -38,
        0.00,
        0.00,
        0.00,
        1,
        0,
      ];
  }
}
