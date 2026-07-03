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
  // History
  // ---------------------------------------------------------------------

  /// Soft byte budget for the undo (and redo) stack. When exceeded the
  /// oldest entries are evicted on the next push until the running
  /// total fits under this cap. Counted as the sum of each entry's
  /// `forward.estimatedByteSize + inverse.estimatedByteSize`.
  ///
  /// Sized for "mid-range Android device with 4 GB RAM" — generous
  /// enough that ordinary photo-editing sessions never trigger
  /// eviction, but tight enough that runaway paint-stroke history can
  /// no longer silently OOM the app during PNG export. The budget is
  /// soft: a single command larger than the budget is still kept (we
  /// would rather lose older history than corrupt the most-recent
  /// undo). Tune later from real device traces.
  static const int kHistoryByteBudget = 256 * 1024 * 1024; // 256 MB

  /// Per-entry structural overhead added to every command's reported
  /// `estimatedByteSize`. Accounts for the command object header,
  /// inline scalar fields, and the [_HistoryEntry] wrapper itself.
  /// Without this baseline a stream of millions of "no payload"
  /// commands would cost zero on paper but tens of MB in practice.
  static const int kHistoryEntryOverheadBytes = 64;

  /// Maximum idle gap within one mergeable command stream. A command
  /// only merges into the top history entry if that entry was pushed
  /// or last merged within this window — so a slider drag (frames
  /// arrive every ~16 ms) collapses into one undo entry, while a
  /// second drag of the same knob a few seconds later starts a fresh
  /// entry instead of silently extending the first.
  ///
  /// Why a time gate and not a drag-end "settle" command: the settle
  /// would have to be threaded through every slider's onChangeEnd
  /// (ten near-duplicate private slider widgets today), and a
  /// same-value settle is swallowed by the no-op guard before it can
  /// break the chain anyway. One second is a compromise: holding
  /// still >1 s mid-drag splits that drag into two entries (rare,
  /// costs one extra undo press), and two deliberate re-drags within
  /// 1 s merge (equally rare, costs one missing undo stop). Both
  /// failure modes are one granularity step, never lost work.
  static const Duration kLiveMergeWindow = Duration(seconds: 1);

  // ---------------------------------------------------------------------
  // Effect cache (docs/effects.md §10)
  // ---------------------------------------------------------------------

  /// Maximum cached effected pictures retained per layer. Sized for
  /// "current params + last two for fast undo preview" so a quick
  /// undo / redo flick on a slider repaint hits the cache instead of
  /// re-baking. Older entries evicted on insert. Mirrors the per-key
  /// LRU shape used elsewhere in the engine.
  static const int kEffectCachePerLayerLruCap = 3;

  /// Soft global byte budget for the **committed** effect-picture
  /// cache (post-stroke / post-slider-release renders). Half the
  /// history budget because effects are larger than commands; an
  /// effected `ui.Picture` rasterises to a `ui.Image` whose footprint
  /// is `width * height * 4` bytes, easily into the megabytes for a
  /// full-canvas adjustment layer. Soft: a single picture exceeding
  /// the budget is still cached for one frame to avoid a flash, then
  /// evicted by the next insert. Tune from real device traces.
  ///
  /// Source of truth for §10 of docs/effects.md.
  static const int kEffectCacheByteBudget = 128 * 1024 * 1024; // 128 MB

  /// Soft global byte budget for the **transient** in-gesture
  /// (LiveOverlay) effect cache. Smaller than [kEffectCacheByteBudget]
  /// because only one gesture stream can be active at a time, so the
  /// working-set is bounded by per-frame churn rather than session
  /// history. Cleared wholesale on `LiveOverlay.clear()` — no LRU
  /// needed across gesture boundaries.
  static const int kEffectOverlayCacheByteBudget = 32 * 1024 * 1024; // 32 MB

  // ---------------------------------------------------------------------
  // Debug
  // ---------------------------------------------------------------------

  /// Debug: draw tinted rectangles around every handle hit box and log
  /// their global bounds. Flip to `true` while tuning.
  static const bool debugPaintHitBoxes = false;
}
