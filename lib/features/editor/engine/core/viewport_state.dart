import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Matrix4;

/// Pure value object describing how the logical canvas is mapped onto the
/// screen. The engine itself is unaware of this — only the presentation
/// layer applies it. All layer coordinates remain in **logical canvas
/// pixels** regardless of viewport state.
@immutable
class ViewportState {
  const ViewportState({
    required this.scale,
    required this.translation,
  });

  /// Uniform zoom factor. 1.0 = render canvas pixel-for-pixel.
  final double scale;

  /// Translation applied AFTER scale, in screen pixels.
  final Offset translation;

  static const ViewportState identity =
      ViewportState(scale: 1.0, translation: Offset.zero);

  ViewportState copyWith({double? scale, Offset? translation}) {
    return ViewportState(
      scale: scale ?? this.scale,
      translation: translation ?? this.translation,
    );
  }

  /// Build the affine transform `Matrix4` that maps logical-canvas points
  /// into screen-space. Used by the presentation `Transform` widget only.
  Matrix4 toMatrix() {
    final m = Matrix4.identity();
    m.translateByDouble(translation.dx, translation.dy, 0, 1);
    m.scaleByDouble(scale, scale, 1, 1);
    return m;
  }

  /// Inverse mapping — convert a screen-space point to canvas-space. Used
  /// only when we cannot rely on Flutter's `globalToLocal` (which
  /// automatically walks the transform chain).
  Offset screenToCanvas(Offset screen) {
    return (screen - translation) / scale;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ViewportState &&
          other.scale == scale &&
          other.translation == translation;

  @override
  int get hashCode => Object.hash(scale, translation);
}
