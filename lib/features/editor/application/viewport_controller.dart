import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/core/viewport_state.dart';

/// Reactive holder of the current [ViewportState].
///
/// The viewport is a presentation-only concern: zoom and pan only affect
/// how the canvas is rendered onto the screen. The engine, commands and
/// layer transforms remain in **logical canvas pixels** at all times.
class ViewportController extends Notifier<ViewportState> {
  /// Hard limits keep the user from zooming so far in/out that interaction
  /// becomes impossible (and to avoid degenerate floating-point cases).
  static const double _minScale = 0.05;
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
    final pad = padding != null
        ? (horizontal: padding, vertical: padding)
        : adaptivePaddingFor(screenSize);
    final available = Size(
      (screenSize.width - pad.horizontal * 2).clamp(1, double.infinity),
      (screenSize.height - pad.vertical * 2).clamp(1, double.infinity),
    );
    final scale = (available.width / canvasSize.width)
        .clamp(_minScale, _maxScale)
        .toDouble();
    final scaleH = (available.height / canvasSize.height)
        .clamp(_minScale, _maxScale)
        .toDouble();
    final s = scale < scaleH ? scale : scaleH;
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

  /// Pan the viewport by a screen-space delta.
  void panBy(Offset delta) {
    if (delta == Offset.zero) return;
    state = state.copyWith(
      translation: state.translation + delta,
      userAdjusted: true,
    );
  }

  /// Zoom around a screen-space focal point so the point under the user's
  /// finger stays put. Used by pinch-to-zoom and the +/- buttons.
  void zoomBy(double factor, Offset focal) {
    final newScale = (state.scale * factor)
        .clamp(_minScale, _maxScale)
        .toDouble();
    final actualFactor = newScale / state.scale;
    if (actualFactor == 1.0) return;
    // Keep the focal point fixed: translate' = focal - (focal - translate) * factor
    final newTranslation = focal - (focal - state.translation) * actualFactor;
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
        .clamp(_minScale, _maxScale)
        .toDouble();
    // The point on the canvas under [startFocal] at gesture start:
    //   canvasPoint = (startFocal - startState.translation) / startState.scale
    // We want that same canvasPoint to sit under [currentFocal] now:
    //   currentFocal = canvasPoint * newScale + newTranslation
    final canvasPoint =
        (startFocal - startState.translation) / startState.scale;
    final newTranslation = currentFocal - canvasPoint * newScale;
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
    // Fold the restored viewport's ORIGIN into the value: a genuine user
    // adjustment ([userAdjusted] true) must survive a later tool-panel
    // reflow, while a restored automatic fit (false) must keep re-fitting.
    // The canvas reads the persisted flag from [ProjectViewportStore] and
    // passes it here, so reopening an untouched project is not silently
    // promoted to "adjusted".
    state = viewport.copyWith(userAdjusted: userAdjusted);
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
    // copyWith preserves the existing userAdjusted (this is only scheduled
    // when it is already true), so a programmatic reflow keeps the intent.
    state = state.copyWith(translation: newTranslation);
    final ctx = _lastFitContext;
    _lastFitContext = (
      screenSize: newScreen,
      canvasSize: canvasSize,
      padding: ctx?.padding,
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
