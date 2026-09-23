/// Shared honest-ratio bounds for the app shell's preview tiles: the
/// continue hero's pane and both Home rails size their width from the
/// canvas's true aspect ratio, clamped to this band so a 9:16 story
/// still reads tall and a 16:9 thumbnail still reads wide without
/// either extreme degenerating into a sliver or a banner.
const double kThumbMinRatio = 0.62;
const double kThumbMaxRatio = 1.5;

/// Width of a fixed-[height] tile at [ratio] (w/h), clamped to the
/// shared band.
double thumbWidthFor({required double height, required double ratio}) =>
    height * ratio.clamp(kThumbMinRatio, kThumbMaxRatio);
