import 'dart:math' as math;
import 'dart:ui';

import '../core/layer_transform.dart';
import '../core/viewport_state.dart';

/// Pure round-trip between the three coordinate spaces every overlay
/// has to juggle (AGENTS.md rule 8):
///
///   * **layer-local** — origin at the layer's top-left, un-rotated;
///     the space `LayerMask` geometry lives in.
///   * **canvas** — document logical pixels; the layer sits at
///     `transform.position`, rotated by `transform.rotation` about
///     its centre.
///   * **screen** — canvas-widget-local pixels after the viewport's
///     uniform scale + translation (`p·scale + translation`, the
///     same convention the selection overlay uses; the viewport has
///     no rotation by design, so rotation composes only from the
///     layer).
///
/// Exists so mask-edit chrome (and future layer-anchored overlays)
/// doesn't grow a fourth private `_rotate` copy — the three existing
/// duplicates are flagged for consolidation onto this helper in the
/// Phase 4 pass.
final class LayerSpaceMapper {
  const LayerSpaceMapper({required this.transform, required this.viewport});

  final LayerTransform transform;
  final ViewportState viewport;

  /// layer-local → canvas: rotate about the layer centre.
  /// `c = center + R(rotation)·(l − size/2)`
  Offset layerToCanvas(Offset local) {
    final lc = Offset(
      transform.size.width / 2,
      transform.size.height / 2,
    );
    final v = local - lc;
    final cosR = math.cos(transform.rotation);
    final sinR = math.sin(transform.rotation);
    return transform.center +
        Offset(v.dx * cosR - v.dy * sinR, v.dx * sinR + v.dy * cosR);
  }

  /// canvas → layer-local: inverse rotation about the layer centre.
  Offset canvasToLayer(Offset canvas) {
    final v = canvas - transform.center;
    final cosR = math.cos(-transform.rotation);
    final sinR = math.sin(-transform.rotation);
    return Offset(
          v.dx * cosR - v.dy * sinR,
          v.dx * sinR + v.dy * cosR,
        ) +
        Offset(transform.size.width / 2, transform.size.height / 2);
  }

  Offset canvasToScreen(Offset canvas) =>
      canvas * viewport.scale + viewport.translation;

  Offset screenToCanvas(Offset screen) =>
      (screen - viewport.translation) / viewport.scale;

  Offset layerToScreen(Offset local) => canvasToScreen(layerToCanvas(local));

  Offset screenToLayer(Offset screen) => canvasToLayer(screenToCanvas(screen));
}
