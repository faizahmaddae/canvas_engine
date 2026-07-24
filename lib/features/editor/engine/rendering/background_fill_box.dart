import 'package:flutter/widgets.dart';

import '../core/background_fill.dart';

/// Paints any [BackgroundFill] variant — solid, linear gradient, or
/// radial gradient — at the size of its parent.
///
/// Single source of truth for "how a [BackgroundFill] becomes pixels".
/// Used by:
///   * `DocumentView` (canvas backdrop in editor + export pipeline)
///   * `EditorCanvas` (live editor)
///   * `DocumentThumbnail` (Home strip)
/// so a fill can never look different across surfaces.
///
/// Sealed-type exhaustive switch on the fill — adding a new variant to
/// [BackgroundFill] forces this widget to be updated.
class BackgroundFillBox extends StatelessWidget {
  const BackgroundFillBox({super.key, required this.fill});

  final BackgroundFill fill;

  @override
  Widget build(BuildContext context) {
    return switch (fill) {
      SolidBackground(:final color) => ColoredBox(color: color),
      final LinearGradientBackground g => DecoratedBox(
        decoration: BoxDecoration(gradient: g.toFlutterGradient()),
      ),
      final RadialGradientBackground g => DecoratedBox(
        decoration: BoxDecoration(gradient: g.toFlutterGradient()),
      ),
    };
  }
}
