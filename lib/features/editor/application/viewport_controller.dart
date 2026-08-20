import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/engine_constants.dart';
import '../engine/core/viewport_state.dart';

/// Reactive holder of the current [ViewportState].
///
/// The viewport is a presentation-only concern: zoom and pan only affect
/// how the canvas is rendered onto the screen. The engine, commands and
/// layer transforms remain in **logical canvas pixels** at all times.
class ViewportController extends Notifier<ViewportState> {
  /// Hard limits keep the user from zooming so far in/out that interaction
  /// becomes impossible (and to avoid degenerate floating-point cases).
  ///
  /// The MIN bound is no longer a flat constant (tb3 7/7): a >7000px
  /// photo on a phone pane needs a fit scale BELOW 0.05, so the
  /// effective floor derives from the fit — see [_effectiveMinScale].
  /// [_absoluteMinScale] remains the floor for ordinary documents.
  static const double _absoluteMinScale = 0.05;
  static const double _maxScale = 32.0;

  /// The most recent ([screenSize], [canvasSize]) pair handed to [fit].
  ///
  /// Cached so [refit] (used by the user-facing "Fit to screen" menu
  /// action) replays the **exact** geometry the auto-fit was computed
  /// against — the canvas pane size measured by the [EditorCanvas]
  /// `LayoutBuilder`. Any other source (e.g. `MediaQuery.size` minus a
  /// best-effort app-bar guess) silently disagrees with the layout's
  /// real pane and produces an off-centre result. Keeping the source of
  /// truth here removes the duplication and the divergence.
  ({Size screenSize, Size canvasSize, double? padding})? _lastFitContext;

  /// Pure helper exposed for tests / rare callers that need to inspect
  /// what [refit] would replay.
  ({Size screenSize, Size canvasSize, double? padding})? get lastFitContext =>
      _lastFitContext;

  /// Whether the user has manually panned/zoomed since the last
  /// programmatic fit — read straight off the current [state.userAdjusted].
  ///
  /// This is the signal the canvas uses to decide what to do when the
  /// on-screen canvas pane changes size — which happens every time a tool
  /// panel opens, closes, or switches and reflows the canvas. While it is
  /// `false` (a freshly auto-fitted viewport the user has not touched) the
  /// canvas keeps the existing "re-fit on layout change" behaviour. Once it
  /// is `true` the canvas must NOT snap back to fit on a pane reflow — it
  /// preserves the user's zoom via [reflowPreservingZoom].
  ///
  /// Because the flag lives ON the state value (not a side field), clearing
  /// it via [fit]/[reset] is an OBSERVABLE transition even when the
  /// transform is unchanged — so the persistence listener still fires and
  /// stores `adjusted=false`. Set by [panBy]/[zoomBy]/[gestureUpdate]/
  /// [restore]; cleared by [fit] (and therefore [refit]) and [reset].
  bool get userAdjusted => state.userAdjusted;

  @override
  ViewportState build() => ViewportState.identity;

  /// Centre the canvas inside [screenSize] and pick the largest scale that
  /// fits with a small breathing-room margin. Used on document creation
  /// and on screen resize.
  ///
  /// If [padding] is omitted the controller picks *adaptive*, per-axis
  /// padding via [adaptivePaddingFor]. On phones the horizontal padding
  /// collapses to zero so the canvas can visually touch the left and
  /// right edges of the workspace; vertical padding is retained so the
  /// canvas never kisses the app-bar or FAB row. Tablets and desktops
  /// get symmetric breathing room. Pass an explicit [padding] only when
  /// the caller needs a deterministic value (tests, for instance) — the
  /// same value is then applied to both axes.
  void fit({
    required Size screenSize,
    required Size canvasSize,
    double? padding,
  }) {
    if (canvasSize.width <= 0 || canvasSize.height <= 0) return;
    // Deliberately NOT floored at [_absoluteMinScale]: the fit scale
    // for a huge photo (>7000px on a phone pane) sits below 0.05, and
    // flooring it here was exactly the bug that made such documents
    // unfittable — they rendered larger than the pane on open with no
    // way to zoom out. The max clamp stays (a tiny canvas on a huge
    // screen must not zoom past the interaction ceiling).
    final s = math.min(
      _fitScaleFor(
        screenSize: screenSize,
        canvasSize: canvasSize,
        padding: padding,
      ),
      _maxScale,
    );
    final tx = (screenSize.width - canvasSize.width * s) / 2;
    final ty = (screenSize.height - canvasSize.height * s) / 2;
    // userAdjusted:false — a programmatic fit re-enables auto-fit-on-reflow.
    // It rides on the value, so even when (s, tx, ty) equal the current
    // transform this assignment differs from a user-adjusted state and thus
    // notifies → the persistence listener stores adjusted=false. Covers the
    // app-bar "Fit to screen" action (it calls [refit] → [fit]).
    state = ViewportState(scale: s, translation: Offset(tx, ty));
    _lastFitContext = (
      screenSize: screenSize,
      canvasSize: canvasSize,
      padding: padding,
    );
  }

  /// Re-run the most recent [fit] with the same screen + canvas sizes.
  ///
  /// Returns `true` if a fit was replayed, `false` if no auto-fit has
  /// happened yet (the caller can decide whether that's an error — in
  /// practice [EditorCanvas] always seeds [_lastFitContext] before any
  /// user-facing action could fire).
  ///
  /// This is the canonical entry point for the "Fit to screen" menu
  /// action: it guarantees pixel-identical centring to the initial
  /// auto-fit because both code paths share the same inputs.
  bool refit() {
    final ctx = _lastFitContext;
    if (ctx == null) return false;
    fit(
      screenSize: ctx.screenSize,
      canvasSize: ctx.canvasSize,
      padding: ctx.padding,
    );
    return true;
  }

  /// Canvas-space rect currently visible in the on-screen canvas pane,
  /// or `null` when no [fit] has seeded the pane geometry yet (headless
  /// unit tests, pre-first-frame). Derived from the live transform, so
  /// it tracks every pan / zoom / restore / reflow.
  ///
  /// This is the source the insertion flows read so a new layer lands
  /// where the user is actually looking instead of at the document
  /// centre (ux-audit P2-12: zoomed into a corner, an insert used to
  /// land off-screen and the canvas looked like nothing happened).
  Rect? get visibleCanvasRect {
    final ctx = _lastFitContext;
    if (ctx == null) return null;
    final topLeft = state.screenToCanvas(Offset.zero);
    return Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      ctx.screenSize.width / state.scale,
      ctx.screenSize.height / state.scale,
    );
  }

  /// Placement rule for newly-inserted layers (ux-audit P2-12).
  ///
  /// Centres a layer of [layerSize] on [visibleCentre] (canvas space),
  /// then clamps per axis so the layer lands **fully inside** the
  /// document whenever it fits — a visible centre out on the
  /// pasteboard resolves to the nearest in-document placement. An axis
  /// on which the layer is larger than the document falls back to
  /// document-centring, which is exactly the historical doc-centred
  /// insert, so oversized imports keep their old geometry.
  ///
  /// Pure and static: shared by every insert path (shape / sticker /
  /// image in the editor screen, the text composer's live session) so
  /// they can never disagree about where "here" is.
  static Offset insertPositionFor({
    required Offset visibleCentre,
    required Size layerSize,
    required Size docSize,
  }) {
    double axis(double centre, double layerExtent, double docExtent) {
      final hi = docExtent - layerExtent;
      // Layer larger than the document on this axis: centre it on the
      // document (negative position), matching the pre-P2-12 rule.
      if (hi < 0) return hi / 2;
      return (centre - layerExtent / 2).clamp(0.0, hi).toDouble();
    }

    return Offset(
      axis(visibleCentre.dx, layerSize.width, docSize.width),
      axis(visibleCentre.dy, layerSize.height, docSize.height),
    );
  }

  /// Raw (un-clamped) fit scale for the given geometry — the largest
  /// scale at which the whole canvas fits inside the padded pane.
  /// Shared by [fit] and [_effectiveMinScale] so the two can never
  /// disagree about what "fits" means.
  double _fitScaleFor({
    required Size screenSize,
    required Size canvasSize,
    double? padding,
  }) {
    final pad = padding != null
        ? (horizontal: padding, vertical: padding)
        : adaptivePaddingFor(screenSize);
    final available = Size(
      (screenSize.width - pad.horizontal * 2).clamp(1, double.infinity),
      (screenSize.height - pad.vertical * 2).clamp(1, double.infinity),
    );
    return math.min(
      available.width / canvasSize.width,
      available.height / canvasSize.height,
    );
  }

  /// Effective zoom-out floor. For ordinary documents this is the
  /// flat [_absoluteMinScale]; for documents whose FIT scale sits
  /// below it (huge photos) the floor derives from the fit instead —
  /// `fitScale × kViewportMinZoomOutFactor` — so the user can always
  /// see the whole canvas plus some context, and the pinch can't get
  /// stuck above "fits on screen". Falls back to the flat floor when
  /// no fit has happened yet (nothing to derive from).
  double get _effectiveMinScale {
    final ctx = _lastFitContext;
    if (ctx == null) return _absoluteMinScale;
    final fitScale = _fitScaleFor(
      screenSize: ctx.screenSize,
      canvasSize: ctx.canvasSize,
      padding: ctx.padding,
    );
    if (!fitScale.isFinite || fitScale <= 0) return _absoluteMinScale;
    return math.min(
      _absoluteMinScale,
      fitScale * EngineConstants.kViewportMinZoomOutFactor,
    );
  }

  /// Clamp [translation] so at least
  /// [EngineConstants.kViewportMinVisibleEdge] logical px of canvas
  /// remain on-screen per axis (tb3 7/7 guardrail): however hard the
  /// user flings, a grabbable sliver of the document always stays
  /// visible, so the canvas can never be stranded off-screen. Needs
  /// the fit-context geometry; a controller that has never fitted
  /// (headless unit tests, pre-first-frame) passes translations
  /// through untouched — there is no pane to clamp against.
  Offset _clampTranslation(Offset translation, double scale) {
    final ctx = _lastFitContext;
    if (ctx == null) return translation;
    final minEdge = EngineConstants.kViewportMinVisibleEdge;
    double clampAxis(double t, double screenExtent, double canvasExtent) {
      // Canvas occupies [t, t + canvasExtent·scale] on screen
      // [0, screenExtent]. Lower bound keeps ≥ minEdge of canvas
      // inside from the leading side, upper bound from the trailing
      // side. (A canvas smaller than minEdge on screen simply ends
      // up fully visible — the bounds tighten past its size.)
      final lo = minEdge - canvasExtent * scale;
      final hi = screenExtent - minEdge;
      if (lo >= hi) return (lo + hi) / 2; // degenerate pane; centre.
      return t.clamp(lo, hi);
    }

    return Offset(
      clampAxis(translation.dx, ctx.screenSize.width, ctx.canvasSize.width),
      clampAxis(translation.dy, ctx.screenSize.height, ctx.canvasSize.height),
    );
  }

  /// Pan the viewport by a screen-space delta.
  ///
  /// Programmatic seam, like [zoomBy]: the real gesture path goes
  /// through [gestureUpdate], and both of these survive tb5's dead-API
  /// sweep because the widget tests drive the viewport through them —
  /// deleting them would mean tests reaching into `state` directly,
  /// which is worse (it would bypass the clamps this controller owns).
  void panBy(Offset delta) {
    if (delta == Offset.zero) return;
    final next = _clampTranslation(state.translation + delta, state.scale);
    if (next == state.translation && state.userAdjusted) return;
    state = state.copyWith(translation: next, userAdjusted: true);
  }

  /// Zoom around a screen-space focal point so the point under the
  /// user's finger stays put. See [panBy] on why this is kept.
  void zoomBy(double factor, Offset focal) {
    final newScale = (state.scale * factor)
        .clamp(_effectiveMinScale, _maxScale)
        .toDouble();
    final actualFactor = newScale / state.scale;
    if (actualFactor == 1.0) return;
    // Keep the focal point fixed: translate' = focal - (focal - translate) * factor
    final newTranslation = _clampTranslation(
      focal - (focal - state.translation) * actualFactor,
      newScale,
    );
    state = ViewportState(
      scale: newScale,
      translation: newTranslation,
      userAdjusted: true,
    );
  }

  /// Combined pan + zoom around a focal point. Used by the background
  /// scale-gesture handler. Pass the viewport state captured at gesture
  /// start plus the cumulative scale and current focal — the controller
  /// solves for the new translation that keeps [startFocal] under
  /// [currentFocal].
  void gestureUpdate({
    required ViewportState startState,
    required Offset startFocal,
    required Offset currentFocal,
    required double scale,
  }) {
    final newScale = (startState.scale * scale)
        .clamp(_effectiveMinScale, _maxScale)
        .toDouble();
    // The point on the canvas under [startFocal] at gesture start:
    //   canvasPoint = (startFocal - startState.translation) / startState.scale
    // We want that same canvasPoint to sit under [currentFocal] now:
    //   currentFocal = canvasPoint * newScale + newTranslation
    final canvasPoint =
        (startFocal - startState.translation) / startState.scale;
    final newTranslation = _clampTranslation(
      currentFocal - canvasPoint * newScale,
      newScale,
    );
    // A net-zero gesture frame (finger held still at unit scale) must not
    // mark the viewport as user-adjusted. Compare the TRANSFORM only — full
    // value equality now also includes `userAdjusted`, so it would treat a
    // no-move frame on a not-yet-adjusted viewport as a change.
    if (newScale == state.scale && newTranslation == state.translation) {
      return;
    }
    state = ViewportState(
      scale: newScale,
      translation: newTranslation,
      userAdjusted: true,
    );
  }

  void reset() {
    // identity carries userAdjusted:false, so this clears the intent as an
    // observable transition even from an already-identity transform.
    state = ViewportState.identity;
  }

  /// Apply a previously-captured [viewport] verbatim. Used by the
  /// canvas to restore a per-project saved viewport on reopen
  /// without recomputing the fit. Does not seed [_lastFitContext];
  /// the canvas is responsible for calling [fit] separately if it
  /// wants the user-facing "Fit to screen" action to have geometry
  /// to replay against.
  void restore(ViewportState viewport, {required bool userAdjusted}) {
    // Sanitise before applying (tb3 7/7 clamp-on-restore): a corrupt
    // or stale store entry — non-finite numbers, a zoom outside the
    // legal range, a translation that strands the canvas off-screen
    // (saved on a different pane size / orientation) — must recover,
    // not reproduce. Bailing out keeps whatever the canvas already
    // applied (it always seeds a fresh [fit] before restoring), so
    // "ignore the entry" IS the auto-recovery path.
    if (!viewport.scale.isFinite || viewport.scale <= 0) return;
    if (!viewport.translation.dx.isFinite ||
        !viewport.translation.dy.isFinite) {
      return;
    }
    final scale = viewport.scale
        .clamp(_effectiveMinScale, _maxScale)
        .toDouble();
    final translation = _clampTranslation(viewport.translation, scale);
    // Fold the restored viewport's ORIGIN into the value: a genuine user
    // adjustment ([userAdjusted] true) must survive a later tool-panel
    // reflow, while a restored automatic fit (false) must keep re-fitting.
    // The canvas reads the persisted flag from [ProjectViewportStore] and
    // passes it here, so reopening an untouched project is not silently
    // promoted to "adjusted".
    state = ViewportState(
      scale: scale,
      translation: translation,
      userAdjusted: userAdjusted,
    );
  }

  /// Re-map the viewport for a change in the on-screen canvas pane size
  /// WITHOUT re-fitting, so a user's manual zoom/pan survives a tool-panel
  /// reflow (opening/closing/switching a panel resizes the canvas pane).
  ///
  /// Keeps the current [ViewportState.scale], moves the canvas point that
  /// sat under the old pane centre to the new pane centre (focal-stable as
  /// far as the resized pane allows), and re-seeds the fit context so a
  /// later [refit] targets the CURRENT pane rather than the pane measured
  /// before the reflow. Leaves [userAdjusted] `true`.
  ///
  /// There are no hard translation bounds in this editor (the canvas may
  /// pan freely onto the surrounding workspace), so "re-clamp" is realised
  /// as this focal-preserving recentre: a canvas that was visible before
  /// the reflow stays visible after it, and cannot be stranded off-screen.
  /// Editor-only: no document mutation, command dispatch, or history entry.
  void reflowPreservingZoom({
    required Size oldScreen,
    required Size newScreen,
    required Size canvasSize,
  }) {
    if (oldScreen.width <= 0 ||
        oldScreen.height <= 0 ||
        newScreen.width <= 0 ||
        newScreen.height <= 0) {
      return;
    }
    final oldCentre = Offset(oldScreen.width / 2, oldScreen.height / 2);
    final newCentre = Offset(newScreen.width / 2, newScreen.height / 2);
    // Canvas-space point currently under the old pane centre …
    final canvasPoint = (oldCentre - state.translation) / state.scale;
    // … kept under the new pane centre at the unchanged scale.
    final newTranslation = newCentre - canvasPoint * state.scale;
    // Re-seed the fit context FIRST so the visible-edge clamp below
    // runs against the pane the viewport is being re-mapped INTO.
    final ctx = _lastFitContext;
    _lastFitContext = (
      screenSize: newScreen,
      canvasSize: canvasSize,
      padding: ctx?.padding,
    );
    // copyWith preserves the existing userAdjusted (this is only scheduled
    // when it is already true), so a programmatic reflow keeps the intent.
    state = state.copyWith(
      translation: _clampTranslation(newTranslation, state.scale),
    );
  }

  /// Picks sensible per-axis "fit" padding for [screenSize] using its
  /// shortest side as the form-factor signal.
  ///
  /// v2 workspace contract: the canvas *floats* on the muted
  /// workspace with a comfortable margin on every side — its shadow,
  /// rounded corners and hairline border need room to read as a
  /// sheet of paper. The old edge-to-edge phone fit is gone with the
  /// black letterbox it was designed against.
  ///
  ///   shortestSide ≤ 480  → h=16, v=16   (compact phones)
  ///   480 … 720           → h=16…20, v=16…20 (large phones)
  ///   720 … 1024          → h=20…28, v=20…28 (tablets)
  ///   shortestSide ≥ 1024 → h=32, v=32   (desktop)
  static ({double horizontal, double vertical}) adaptivePaddingFor(
    Size screenSize,
  ) {
    final shortest = screenSize.shortestSide;
    if (shortest <= 480) {
      return (horizontal: 16, vertical: 16);
    }
    if (shortest <= 720) {
      final t = (shortest - 480) / (720 - 480);
      return (horizontal: 16 + t * (20 - 16), vertical: 16 + t * (20 - 16));
    }
    if (shortest <= 1024) {
      final t = (shortest - 720) / (1024 - 720);
      return (horizontal: 20 + t * (28 - 20), vertical: 20 + t * (28 - 20));
    }
    return (horizontal: 32, vertical: 32);
  }
}

final viewportControllerProvider =
    NotifierProvider<ViewportController, ViewportState>(ViewportController.new);
