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

  /// Maximum DOCUMENT dimension (logical px) on either axis — the one
  /// ceiling the create dialog, the in-editor canvas resize and the
  /// export custom-size dialog all validate against. Deliberately
  /// equal to [maxLayerSize]: a canvas larger than the largest
  /// possible layer would let no layer ever cover it (the UX audit
  /// P2-20 repro was a 16384 canvas whose shapes stopped growing at
  /// half its width), and Skia surface allocations beyond ~8K square
  /// start to fail on mid-tier devices anyway. Imports keep their own
  /// [kMaxImportDimension] (a GPU-texture concern, ≥ this so an
  /// imported photo can always fill a maximal canvas). Documents
  /// stored above this ceiling still open and render — the cap gates
  /// dialog input only, never serialization. An int because every
  /// consumer is a whole-pixel input validator.
  static const int maxDocumentDimension = 8000;

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

  /// Distance (logical px, screen-space) from the selection frame's
  /// top-edge midpoint to the centre of the dedicated rotation knob
  /// (tb3 6/7, decision D-a). Like [selectionOutset] it is applied
  /// AFTER the canvas → screen mapping along the frame's rotated
  /// up-axis, so the stem length stays constant in dp at any zoom.
  /// 28dp clears the 48dp handle touch boxes on the top corners
  /// (their pads end ~24dp past the corner) while keeping the knob
  /// close enough to read as part of the selection chrome.
  static const double rotateHandleOffset = 28.0;

  /// How long the paint surface buffers a first finger's down-point
  /// before flushing it into a visible stroke draft (contract §5
  /// rows 2/3, tb3 4/7).
  ///
  /// A pinch's two fingers rarely land on the exact same frame; if
  /// the draft started on pointer-down, every two-finger navigation
  /// that begins over the canvas would flash a stroke dot before the
  /// second finger arrives. Buffering the first point until movement
  /// past `kTouchSlop`, this latency elapsing, or a second finger
  /// landing (whichever comes first) means fingers that land within
  /// this window start a clean viewport pinch with no draft flash —
  /// while a deliberate press-and-hold still shows its dot preview
  /// after only ~4 frames, and a sub-slop release commits the
  /// freestyle dot regardless (the buffered point is the dot).
  static const Duration paintDraftBufferLatency = Duration(milliseconds: 64);

  // ---------------------------------------------------------------------
  // Viewport guardrails (tb3 7/7)
  // ---------------------------------------------------------------------

  /// Minimum sliver of canvas (logical px, screen space) that must
  /// remain on-screen per axis after any pan/zoom or restored
  /// viewport. 48dp = the platform hit-target floor (44) plus margin:
  /// whatever is left visible is always big enough to grab with one
  /// finger and drag back, so a wild fling can never strand the
  /// document irrecoverably off-screen.
  static const double kViewportMinVisibleEdge = 48.0;

  /// How far below the auto-fit scale a pinch may zoom out, as a
  /// fraction of the fit scale. Applies only when the fit scale is
  /// already below the flat 0.05 floor (huge photos): 0.5 lets the
  /// user pull back to half the fitted size — whole canvas plus
  /// breathing room for context — without opening a zoom range so
  /// deep the document becomes a speck.
  static const double kViewportMinZoomOutFactor = 0.5;

  /// Longest-side ceiling (px) for imported photos; larger picks are
  /// downscaled aspect-preserving AT IMPORT (the image_picker
  /// maxWidth/maxHeight path, before the full bitmap ever enters the
  /// app). 8192 is the safe GPU texture ceiling on the device classes
  /// this app targets (Metal / GLES3), so an imported photo can
  /// always be rendered and exported at full document resolution
  /// without tiling, and a decoded frame stays ≤ 8192² RGBA — a
  /// bounded worst case instead of whatever a 100-megapixel camera
  /// produces.
  static const double kMaxImportDimension = 8192.0;

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
  /// or last merged within this window — so a repeat-fire burst
  /// (stepper nudges every ~100 ms, canvas-background live streams)
  /// collapses into one undo entry, while re-engaging the same
  /// control a few seconds later starts a fresh entry instead of
  /// silently extending the first.
  ///
  /// Since the tb2 6/16 merge-gate flip, this window is the
  /// COALESCER for the two sanctioned `live: true` streams only —
  /// steppers/nudges and the canvas-background §2 exemption. Slider
  /// drags no longer pass through it at all: they preview on the
  /// live overlay and commit exactly one non-live command on
  /// release, and non-live commands never merge regardless of
  /// timing (contract §3). One second is a compromise for the
  /// burst case: pausing >1 s mid-burst splits it into two entries
  /// (rare, costs one extra undo press); both failure modes are one
  /// granularity step, never lost work.
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
