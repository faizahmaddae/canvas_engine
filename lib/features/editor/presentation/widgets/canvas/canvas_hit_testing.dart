// Pure canvas-space hit geometry for the editor canvas.
//
// Every function here is a free function over (layers, canvas-space
// point) — no provider reads, no widget bounds, no screen space. The
// current zoom enters only as an explicit `viewportScale` argument,
// which is what keeps these tests correct for layers dragged partly or
// fully off the canvas (the off-canvas recovery grab depends on it).
// The gesture router owns the provider read that supplies that scale.

import 'package:flutter/painting.dart';

import '../../../../../core/constants/engine_constants.dart';
import '../../../engine/core/editor_layer.dart';
import '../../../engine/core/viewport_state.dart';
import '../../../engine/interaction/layer_space_mapper.dart';

/// Returns the top-most layer whose rotated bounding box contains
/// [point] (in logical canvas coordinates). Hidden and locked layers
/// are skipped. Thin wrapper over [hitTestAllLayers] for call sites that
/// only care about the topmost.
EditorLayer? hitTestTopLayer(List<EditorLayer> layers, Offset point) {
  final hits = hitTestAllLayers(layers, point);
  return hits.isEmpty ? null : hits.first;
}

/// Returns ALL eligible layers under [point] in canvas coordinates,
/// ordered top-most first (matching paint z-order: later in the
/// layer list = visually on top). Hidden and locked layers are
/// skipped. Drives `CanvasGestureRouter.handleTap`'s overlapping-layer
/// cycling.
List<EditorLayer> hitTestAllLayers(List<EditorLayer> layers, Offset point) {
  final hits = <EditorLayer>[];
  for (var i = layers.length - 1; i >= 0; i--) {
    final l = layers[i];
    if (!l.visible || l.locked) continue;
    if (pointInLayerBbox(l, point)) hits.add(l);
  }
  return hits;
}

/// True iff [point] (canvas-space) is inside [layer]'s rotated
/// bounding box. Pure geometry — does not consider visibility,
/// lock state, or selection.
bool pointInLayerBbox(EditorLayer layer, Offset point) {
  final t = layer.transform;
  // `canvasToLayer` never reads `viewport` (only `transform`), so
  // `ViewportState.identity` is a correct, not just convenient,
  // stand-in — this hit-test works in canvas space, not screen space.
  final local = LayerSpaceMapper(
    transform: t,
    viewport: ViewportState.identity,
  ).canvasToLayer(point);
  return local.dx >= 0 &&
      local.dy >= 0 &&
      local.dx <= t.size.width &&
      local.dy <= t.size.height;
}

/// The selection chrome's screen-space outset converted into canvas
/// units at [viewportScale]. The overlay outsets its frame quad by
/// [EngineConstants.selectionOutset] SCREEN pixels along the rotated
/// axes ([outsetSelectionQuad] in `selection_overlay.dart`); since
/// the viewport map is conformal (uniform scale + translation, no
/// rotation), the same quad expressed in canvas space is the layer
/// rect inflated by `outset / viewport.scale`.
double chromeOutsetCanvas(double viewportScale) {
  if (!viewportScale.isFinite || viewportScale <= 0) {
    return EngineConstants.selectionOutset;
  }
  return EngineConstants.selectionOutset / viewportScale;
}

/// True iff [point] (canvas-space) lands on [layer]'s selection
/// CHROME QUAD — the rotated bbox inflated by the handle outset the
/// overlay actually draws, UNION the rotation knob's stem capsule
/// (tb3 6/7: the knob floats above the top edge, so a near-miss on
/// the knob or its stem must still read as "on the selection" and
/// never fall through to viewport pan). This is the contract §5
/// row 4 claim test: deliberately the drawn geometry, not the raw
/// bbox, so grabbing the frame edge between two handles still
/// counts as "on the selection". Pure canvas-space math (no widget
/// bounds), so it extrapolates correctly for layers dragged partly
/// or fully off the canvas — the off-canvas recovery grab keeps
/// working.
bool pointInChromeQuad(EditorLayer layer, Offset point, double viewportScale) {
  final t = layer.transform;
  final local = LayerSpaceMapper(
    transform: t,
    viewport: ViewportState.identity,
  ).canvasToLayer(point);
  final o = chromeOutsetCanvas(viewportScale);
  if (local.dx >= -o &&
      local.dy >= -o &&
      local.dx <= t.size.width + o &&
      local.dy <= t.size.height + o) {
    return true;
  }
  // Rotation-knob stem capsule: the segment from the frame's
  // top-edge midpoint to the knob centre, inflated by half the
  // handle touch box. All screen-dp values scale into layer units
  // by 1/viewport.scale, mirroring the overlay's drawn geometry.
  if (!viewportScale.isFinite || viewportScale <= 0) return false;
  final knobOffset = EngineConstants.rotateHandleOffset / viewportScale;
  final radius = (EngineConstants.handleTouchSize / 2) / viewportScale;
  final stemBase = Offset(t.size.width / 2, -o);
  final knobCentre = Offset(t.size.width / 2, -o - knobOffset);
  return distanceToSegment(local, stemBase, knobCentre) <= radius;
}

/// Group-frame analogue of [pointInChromeQuad]: true iff [point]
/// (canvas-space) lands on the GROUP selection chrome — the shared
/// axis-aligned [bounds] inflated by the drawn handle outset, UNION
/// the rotation knob's stem capsule above the top-edge midpoint.
/// Since ux-audit P3-9 the group frame draws the same stemmed knob as
/// the single-layer frame, so it needs the same guarantee: a near-miss
/// on the knob or its stem must read as "on the selection" and never
/// fall through to viewport pan. Axis-aligned throughout — the claim
/// decision happens on the FIRST pointer of a sequence, when the group
/// is at rest and its bounds are the members' AABB.
bool pointInGroupChromeQuad(Rect bounds, Offset point, double viewportScale) {
  final o = chromeOutsetCanvas(viewportScale);
  if (bounds.inflate(o).contains(point)) return true;
  // Stem capsule: segment from the inflated bounds' top-edge midpoint
  // to the knob centre, inflated by half the handle touch box. Same
  // screen-dp → canvas-unit conversion as [pointInChromeQuad].
  if (!viewportScale.isFinite || viewportScale <= 0) return false;
  final knobOffset = EngineConstants.rotateHandleOffset / viewportScale;
  final radius = (EngineConstants.handleTouchSize / 2) / viewportScale;
  final stemBase = Offset(bounds.center.dx, bounds.top - o);
  final knobCentre = Offset(bounds.center.dx, bounds.top - o - knobOffset);
  return distanceToSegment(point, stemBase, knobCentre) <= radius;
}

/// Distance from [p] to the segment [a]→[b].
double distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 <= 0) return (p - a).distance;
  final tParam = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(
    0.0,
    1.0,
  );
  return (p - (a + ab * tParam)).distance;
}
