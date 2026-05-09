import 'dart:math' as math;

/// Engine-wide constants. Keep small and focused.
class EngineConstants {
  EngineConstants._();

  /// Minimum layer size (logical px) to prevent collapse during resize.
  /// This is the engine-wide floor; individual layers may require larger
  /// minimums via [LayerCapabilities.minWidth] / [LayerCapabilities.minHeight].
  static const double minLayerSize = 24.0;

  /// Maximum layer size (logical px) on either axis. Hard cap that
  /// prevents pinch gestures from growing a layer unboundedly off-screen
  /// and detaching the selection frame from visible content.
  static const double maxLayerSize = 8000.0;

  /// Minimum cumulative scale factor a single gesture session may apply
  /// to the initial transform. Prevents shrinking a layer to a dot.
  static const double minGestureScale = 0.2;

  /// Maximum cumulative scale factor a single gesture session may apply
  /// to the initial transform. Prevents runaway growth on fast pinches.
  static const double maxGestureScale = 8.0;

  /// Touch target for handles. 48 is comfortable on touch devices while
  /// still leaving healthy space between adjacent handles on a small
  /// selection. The visible glyph is smaller; the rest is invisible hit area.
  static const double handleTouchSize = 48.0;

  /// Visual handle size (corner square / rotate circle).
  static const double handleVisualSize = 14.0;

  /// Multiplier applied to a handle's visible glyph while it is actively
  /// being dragged. Subtle emphasis — not an animation.
  static const double handleActiveScale = 1.25;

  /// Selection frame stroke width.
  static const double selectionStroke = 1.5;

  /// Visual gap (logical px, screen-space) between the layer's
  /// rendered bounds and the selection chrome (frame stroke + corner
  /// / rotate handles). Pushes the outline slightly outside the
  /// content so it never visually fuses with shape borders, rounded
  /// corners, text backgrounds or image masks — matches the
  /// professional editor convention (Figma, Canva, Keynote).
  ///
  /// Applied AFTER the canvas → screen-space mapping, so the gap
  /// stays a constant number of dp at any zoom level. Does NOT
  /// change the layer's real transform — resize/rotate still operate
  /// on the underlying [LayerTransform] via pointer deltas.
  static const double selectionOutset = 6.0;

  // ---------------------------------------------------------------------
  // Rotation snapping
  // ---------------------------------------------------------------------

  /// Angle (radians) between snap targets. `pi/4` = every 45°, i.e. the
  /// eight cardinal/diagonal angles (0, 45, 90, 135, 180, 225, 270, 315).
  static const double rotationSnapIncrement = math.pi / 4;

  /// Half-width (radians) of the magnetic zone around each snap target.
  /// ~4° feels positive but does not stick. Outside this zone rotation is
  /// completely free.
  static const double rotationSnapThreshold = 4 * math.pi / 180;

  /// Wider magnetic zone applied only at the cardinal angles
  /// (0 / 90 / 180 / 270). Users expect those to "click" harder than the
  /// 45° diagonals, which are used less often and benefit from a more
  /// permissive free-rotation feel. Anything outside this zone behaves
  /// exactly like [rotationSnapThreshold].
  static const double rotationCardinalSnapThreshold = 7 * math.pi / 180;

  // ---------------------------------------------------------------------
  // Debug
  // ---------------------------------------------------------------------

  /// Debug: draw tinted rectangles around every handle hit box and log
  /// their global bounds. Flip to `true` while tuning.
  static const bool debugPaintHitBoxes = false;
}
