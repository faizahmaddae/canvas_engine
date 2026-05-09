import 'package:flutter/material.dart';

import '../../engine/core/editor_layer.dart';
import '../../engine/core/layer_transform.dart';

/// Renders one layer at its [transform]. Zero business logic – purely
/// translates the engine's transform into Flutter widgets.
class LayerRenderer extends StatelessWidget {
  const LayerRenderer({
    super.key,
    required this.layer,
    required this.transform,
  });

  final EditorLayer layer;

  /// Transform to render at. Usually the layer's own transform, but during
  /// an active interaction we pass a "live" transform so drag feedback is
  /// smooth without mutating the document.
  final LayerTransform transform;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: transform.position.dx,
      top: transform.position.dy,
      width: transform.size.width,
      height: transform.size.height,
      child: Transform.rotate(
        angle: transform.rotation,
        alignment: Alignment.center,
        // Each layer gets its own raster cache so that dragging one layer
        // does not re-rasterize the others (or the canvas background).
        //
        // The `ValueKey('rb-${layer.id}')` is intentional defence-in-
        // depth: the parent `_LayerGestureWrapper` already keys this
        // subtree by `layer.id`, so widget reconciliation is correct
        // either way. Flutter's [RasterCache], however, keys cached
        // pictures off the [RenderRepaintBoundary] identity. Without
        // this key, edits that swap a layer out of and back into the
        // tree (e.g. visibility toggle, group restructuring) can briefly
        // alias one layer's cached raster onto another \u2014 producing
        // intermittent "wrong sibling went black / disappeared / showed
        // stale style" glitches that look like emoji rendering bugs but
        // are really raster-cache aliasing across layers.
        child: RepaintBoundary(
          key: ValueKey<String>('layer-rb-${layer.id}'),
          // Layer-level opacity wraps the entire composition (fill +
          // border + shadow + mask) so transparency reads as one
          // coherent element. Skip the wrapper at full opacity to
          // avoid an extra compositing layer in the common case.
          child: layer.opacity < 1.0
              ? Opacity(
                  opacity: layer.opacity.clamp(0.0, 1.0),
                  child: layer.buildContent(context),
                )
              : layer.buildContent(context),
        ),
      ),
    );
  }
}
