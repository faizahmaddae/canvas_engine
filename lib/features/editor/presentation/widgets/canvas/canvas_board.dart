import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_tokens.dart';
import '../../../application/interaction_controller.dart';
import '../../../canvas/presentation/widgets/canvas_checkerboard.dart';
import '../../../engine/core/editor_document.dart';
import '../../../engine/core/editor_layer.dart';
import '../../../engine/core/layer_transform.dart';
import '../../../engine/core/selection_state.dart';
import '../../../engine/core/viewport_state.dart';
import '../../../engine/interaction/snap_engine.dart';
import '../../../engine/rendering/background_fill_box.dart';
import '../../../engine/rendering/layer_renderer.dart';
import '../../../paint/presentation/paint_gesture_surface.dart';
import '../animated_guides_layer.dart';
import '../canvas_framing.dart';
import '../selection_overlay.dart';

/// Builds the **document board** slice of the editor canvas' outer
/// Stack: the paper shadow, the viewport-transformed board itself
/// (background, layers, multi-select outlines, guides, paint surface),
/// and the dim mask + canvas border that paint back over it.
///
/// Returned as a flat list so the caller can spread it into the Stack
/// unchanged — the z-order of these three siblings, and of the board's
/// own children, is load-bearing and must not be nested.
List<Widget> buildCanvasBoard({
  required GlobalKey boardKey,
  required GlobalKey boardBoundaryKey,
  required GlobalKey viewportBodyKey,
  required EditorDocument doc,
  required Size docSize,
  required SelectionState selection,
  required ViewportState viewport,
  required String? activeLayerId,
  required List<SnapGuide> snapGuides,
  required List<SpacingGuide> spacingGuides,
}) {
  return [
    // Drop shadow under the canvas — paints first so the
    // document covers it everywhere except along its
    // edges, producing a subtle floating-paper effect on
    // the dark workbench.
    CanvasFraming(
      docSize: docSize,
      viewport: viewport,
      layer: CanvasFramingLayer.shadowBelow,
    ),
    OverflowBox(
      minWidth: 0,
      minHeight: 0,
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      alignment: Alignment.topLeft,
      child: Transform(
        alignment: Alignment.topLeft,
        transform: viewport.toMatrix(),
        child: SizedBox(
          width: doc.width,
          height: doc.height,
          // Snapshot boundary for the colour
          // picker's eyedropper: sits inside the
          // viewport transform so a capture is
          // 1 px per logical canvas unit at any
          // zoom. The dim mask + border framing
          // paint above (outside) it, so samples
          // are the raw design colours.
          child: RepaintBoundary(
            key: boardBoundaryKey,
            child: Stack(
              key: boardKey,
              clipBehavior: Clip.none,
              children: [
                // The document's own background. When
                // mode is `color`, paints the picked
                // solid fill -- the Canvas tool's
                // colour change shows up here and on
                // PNG export. When mode is
                // `transparent`, paints a tiled
                // checkerboard so the user can see
                // through to "empty" -- the export
                // pipeline writes alpha instead.
                Positioned.fill(
                  child: doc.backgroundMode == CanvasBackgroundMode.transparent
                      ? const CanvasCheckerboard()
                      : BackgroundFillBox(fill: doc.background),
                ),
                for (final layer in doc.layers)
                  if (layer.visible)
                    _LayerGestureWrapper(
                      key: ValueKey(layer.id),
                      layer: layer,
                      isActive: activeLayerId == layer.id,
                    ),
                // Per-member outlines for multi-select.
                // Drawn inside the viewport transform so
                // they hug each layer's rotated rect
                // pixel-accurately. No handles — the
                // group selection chrome (screen-space)
                // owns transformation.
                if (selection.count > 1)
                  _GroupMemberOutlines(
                    layers: doc.layers,
                    selection: selection,
                    viewportScale: viewport.scale,
                  ),
                // Engine-driven alignment + spacing
                // overlays. Wrapped together so a single
                // opacity fade governs appearance and
                // disappearance, eliminating flicker as
                // snaps engage and release. Both painters
                // counter-scale stroke widths by
                // viewport.scale so guides stay 1px on
                // screen at any zoom.
                AnimatedGuidesLayer(
                  snapGuides: snapGuides,
                  spacingGuides: spacingGuides,
                  viewportScale: viewport.scale,
                ),
                // Paint drawing surface — mounted only when
                // a paint tool is active. Sits as the
                // topmost child of the doc board so it
                // claims canvas-area gestures before any
                // layer wrapper, and provides drag-to-draw
                // + tap-to-erase. Coordinates arrive in
                // canvas-local space because we're inside
                // the viewport transform.
                PaintGestureSurface(
                  docSize: docSize,
                  viewportBodyKey: viewportBodyKey,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    // Dim mask + canvas border — paints OVER layers so
    // off-canvas portions of layers visibly recede while
    // staying selectable. Sits below the selection chrome
    // so handles + body surface remain crisp on top.
    //
    // Photo projects use the SUBTLE border emphasis so
    // the hairline doesn't trace the imported base
    // photo's edge in a way that reads like a permanent
    // selection outline. Design projects keep the
    // STANDARD emphasis -- on a blank/transparent
    // canvas the border is the only artboard cue and
    // needs to be clearly visible.
    CanvasFraming(
      docSize: docSize,
      viewport: viewport,
      layer: CanvasFramingLayer.dimAndBorderAbove,
      borderEmphasis: doc.projectKind == ProjectKind.photo
          ? CanvasBorderEmphasis.subtle
          : CanvasBorderEmphasis.standard,
    ),
  ];
}

class _LayerGestureWrapper extends ConsumerWidget {
  const _LayerGestureWrapper({
    super.key,
    required this.layer,
    required this.isActive,
  });

  final EditorLayer layer;

  /// True when this layer is the target of an active interaction
  /// session — drives the [interactionControllerProvider.liveTransform]
  /// subscription so unrelated layers don't rebuild on every drag tick.
  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resolve the live transform for this layer:
    //   * If this layer is the gesture's primary (`isActive`), read
    //     `liveTransform` directly.
    //   * Otherwise, this layer might be a *secondary* in an active
    //     group-move session — read its entry in `groupLive`. The
    //     `select` returns null when the layer is not part of any
    //     active group, so non-participating layers don't rebuild on
    //     drag ticks.
    final liveTransform = isActive
        ? ref.watch(
            interactionControllerProvider.select((s) => s.liveTransform),
          )
        : ref.watch(
            interactionControllerProvider.select((s) => s.groupLive[layer.id]),
          );
    final transform = liveTransform ?? layer.transform;
    // The body-drag gesture lives in screen space (see
    // [LayerSelectionOverlay._BodyDragSurface]). That gesture surface
    // claims the gesture arena on pointer-down and is reachable even
    // when the layer is partially or fully outside the canvas, which
    // solves the "off-canvas layer cannot be dragged back" bug. This
    // wrapper is therefore now purely a paint host — it never installs
    // its own gesture detector and so cannot compete with the screen-
    // space surface or the viewport's pan/pinch detector.
    return LayerRenderer(layer: layer, transform: transform);
  }
}

/// Renders the subtle per-member outlines for an active multi-selection.
/// Sits inside the viewport transform so each rect hugs the rotated
/// layer geometry pixel-accurately.
///
/// Watches the live group transforms so each outline tracks the layer
/// during a group transform without going through the document.
class _GroupMemberOutlines extends ConsumerWidget {
  const _GroupMemberOutlines({
    required this.layers,
    required this.selection,
    required this.viewportScale,
  });

  final List<EditorLayer> layers;
  final SelectionState selection;
  final double viewportScale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupLive = ref.watch(
      interactionControllerProvider.select((s) => s.groupLive),
    );
    final selectedSet = selection.selectedIds.toSet();
    final transforms = <LayerTransform>[
      for (final l in layers)
        if (selectedSet.contains(l.id) && l.visible)
          groupLive[l.id] ?? l.transform,
    ];
    if (transforms.isEmpty) return const SizedBox.shrink();
    final color = AppTokens.of(context).accent;
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: GroupMemberOutlinePainter(
          transforms: transforms,
          color: color,
          viewportScale: viewportScale,
        ),
      ),
    );
  }
}
