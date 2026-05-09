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
    state = state.copyWith(translation: state.translation + delta);
  }

  /// Zoom around a screen-space focal point so the point under the user's
  /// finger stays put. Used by pinch-to-zoom and the +/- buttons.
  void zoomBy(double factor, Offset focal) {
    final newScale =
        (state.scale * factor).clamp(_minScale, _maxScale).toDouble();
    final actualFactor = newScale / state.scale;
    if (actualFactor == 1.0) return;
    // Keep the focal point fixed: translate' = focal - (focal - translate) * factor
    final newTranslation =
        focal - (focal - state.translation) * actualFactor;
    state = ViewportState(scale: newScale, translation: newTranslation);
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
    state = ViewportState(scale: newScale, translation: newTranslation);
  }

  void reset() => state = ViewportState.identity;

  /// Picks sensible per-axis "fit" padding for [screenSize] using its
  /// shortest side as the form-factor signal.
  ///
  /// On phones we deliberately collapse the **horizontal** padding to
  /// zero so the canvas spans the full workspace width — a typical
  /// portrait phone has plenty of vertical room but pixels to spare are
  /// rare on the horizontal axis. Vertical padding is retained so the
  /// canvas never touches the app-bar / floating actions.
  ///
  /// Tablets and desktops use symmetric padding for classic editor feel.
  ///
  ///   shortestSide ≤ 480  → h=0,  v=8    (compact phones)
  ///   480 … 720           → h=0…8, v=8…14 (large phones)
  ///   720 … 1024          → h=8…24, v=14…24 (tablets, lerp → symmetric)
  ///   shortestSide ≥ 1024 → h=32, v=32   (desktop)
  static ({double horizontal, double vertical}) adaptivePaddingFor(
    Size screenSize,
  ) {
    final shortest = screenSize.shortestSide;
    if (shortest <= 480) {
      return (horizontal: 0, vertical: 8);
    }
    if (shortest <= 720) {
      final t = (shortest - 480) / (720 - 480);
      return (horizontal: t * 8, vertical: 8 + t * (14 - 8));
    }
    if (shortest <= 1024) {
      final t = (shortest - 720) / (1024 - 720);
      return (horizontal: 8 + t * (24 - 8), vertical: 14 + t * (24 - 14));
    }
    return (horizontal: 32, vertical: 32);
  }
}

final viewportControllerProvider =
    NotifierProvider<ViewportController, ViewportState>(
  ViewportController.new,
);
