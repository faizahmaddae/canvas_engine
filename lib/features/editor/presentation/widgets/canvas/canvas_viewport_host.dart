import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/editor_session.dart';
import '../../../application/project_viewport_store.dart';
import '../../../application/viewport_controller.dart';
import '../../../engine/core/viewport_state.dart';

/// Owns the editor canvas' fit/refit lifecycle and its per-project
/// zoom/pan persistence.
///
/// Split out of `editor_canvas.dart` so the "when do we fit, when do we
/// preserve, when do we restore" decision lives in one place. The
/// canvas widget keeps the visibility gate ([fittedOnce]) and calls
/// [syncToLayout] from its `LayoutBuilder`; everything else — the
/// post-frame scheduling, the saved-viewport restore, the debounced
/// write-back — is in here.
class CanvasViewportHost {
  CanvasViewportHost({
    required WidgetRef ref,
    required bool Function() isMounted,
    required VoidCallback onFirstFit,
  }) : _ref = ref,
       _isMounted = isMounted,
       _onFirstFit = onFirstFit;

  final WidgetRef _ref;

  /// The host widget's `mounted`, read lazily: every path below defers
  /// to a post-frame callback or a debounce timer, so the widget may be
  /// gone by the time the work runs.
  final bool Function() _isMounted;

  /// Invoked exactly once, the first time [fittedOnce] flips true, so
  /// the host can rebuild and drop the visibility gate.
  final VoidCallback _onFirstFit;

  /// Tracks the last screen size + doc size that we auto-fitted, so we
  /// re-fit on rotation, window resize, or document size change.
  ///
  /// We deliberately key on (screen size, doc size) rather than on the
  /// `EditorDocument` instance: the document is immutable, so every
  /// command (drag commit, add layer, undo, redo) produces a brand-new
  /// instance. Resetting the fit on instance change would re-run the
  /// auto-fit on every interaction and reset the user's pan/zoom — and
  /// because the visibility gate below depends on `_fittedOnce`, it
  /// would also produce a one-frame full-screen blank flash on every
  /// commit. That looked, on a real iPhone release build, like the
  /// whole canvas was briefly turning off and on.
  ///
  /// To re-fit after picking a same-size new document the user has the
  /// "Fit to screen" app-bar button.
  Size? _lastFitScreen;
  Size? _lastFitDoc;

  /// Becomes true after the first auto-fit has actually been applied to
  /// the viewport. Until then we hide the canvas content so the user
  /// never sees the unfitted identity-viewport frame (a flash where the
  /// document appears at the top-left at 1:1 scale before the fit lands).
  /// Once true it stays true for the lifetime of the widget — there is
  /// no code path that flips it back, which guarantees no further
  /// flashes during normal interaction.
  bool _fittedOnce = false;

  bool get fittedOnce => _fittedOnce;

  /// Per-project zoom/pan persistence. Owned by the canvas widget so
  /// load + save share a single [SharedPreferences] handle (cached on
  /// the store after first call) and survive across rebuilds.
  final ProjectViewportStore _viewportStore = ProjectViewportStore();

  /// Debounce window for viewport persistence. 600 ms is long enough
  /// that a single pinch + settle yields one write, short enough that
  /// a backgrounded app keeps a fresh enough value to feel correct
  /// on the next launch.
  static const Duration _kViewportSaveDebounce = Duration(milliseconds: 600);

  Timer? _viewportSaveTimer;

  /// Wires up viewport persistence. Called once from the host's
  /// `initState`.
  void attach() {
    // Persist viewport changes per-project. We listen here (not in
    // build) so the subscription is single-shot and doesn't
    // re-register on every rebuild. The save is debounced by
    // [_kViewportSaveDebounce] so a pinch-zoom that emits 60
    // intermediate states writes once on settle, not 60 times.
    _ref.listenManual<ViewportState>(viewportControllerProvider, (prev, next) {
      if (prev == next) return;
      if (!_fittedOnce) {
        // The very first viewport push is the auto-fit/restore
        // itself; do not write it back over a possibly-still-
        // loading saved entry.
        return;
      }
      final session = _ref.read(editorSessionProvider);
      final projectId = session?.projectId;
      if (projectId == null) return;
      // Persist the adjustment INTENT alongside the transform. Both ride on
      // the same immutable `next` snapshot (`next.userAdjusted`), so the
      // stored pair is always self-consistent — no late read of a mutable
      // flag that could belong to a different transition. Because intent is
      // part of the observed value, an intent-only change (e.g. an explicit
      // Fit that recomputes the same transform, flipping adjusted→false)
      // still passes the `prev == next` guard above and is persisted, so
      // reopening after Fit re-fits.
      _viewportSaveTimer?.cancel();
      _viewportSaveTimer = Timer(_kViewportSaveDebounce, () {
        if (!_isMounted()) return;
        _viewportStore.save(projectId, next, userAdjusted: next.userAdjusted);
      });
    });
  }

  void dispose() {
    _viewportSaveTimer?.cancel();
  }

  /// Reconciles the current canvas pane size with the last one we
  /// fitted against. Called from the host's `LayoutBuilder` on every
  /// build; does nothing unless the (screen, doc) pair actually moved.
  void syncToLayout({required Size screen, required Size docSize}) {
    final hasValidSize =
        screen.width.isFinite &&
        screen.height.isFinite &&
        screen.width > 0 &&
        screen.height > 0 &&
        docSize.width > 0 &&
        docSize.height > 0;
    if (hasValidSize && (_lastFitScreen != screen || _lastFitDoc != docSize)) {
      final prevScreen = _lastFitScreen;
      final docChanged = _lastFitDoc != docSize;
      _lastFitScreen = screen;
      _lastFitDoc = docSize;
      // A pane-only size change — which is what a tool panel opening,
      // closing, or switching produces as it reflows the canvas — on a
      // viewport the user has manually zoomed/panned must PRESERVE that
      // zoom instead of snapping back to fit. Every other case keeps the
      // existing auto-fit behaviour: the first fit, a viewport the user
      // has never adjusted, or a genuine document size/identity change
      // (which should refit and clear the user-adjusted state).
      final userAdjusted = _ref
          .read(viewportControllerProvider.notifier)
          .userAdjusted;
      if (_fittedOnce && userAdjusted && !docChanged && prevScreen != null) {
        _schedulePreserveViewport(prevScreen, screen, docSize);
      } else {
        _scheduleFit(screen, docSize);
      }
    }
  }

  /// Schedule an auto-fit for the next frame. Idempotent within a frame.
  /// We can't update the viewport synchronously during build (Riverpod
  /// forbids state mutation while another provider is being read), so we
  /// defer to the post-frame callback and gate the canvas contents until
  /// the fit has actually been committed.
  ///
  /// **Restore-on-reopen.** If the active session has a `projectId`
  /// and the viewport store has a saved entry, the saved viewport is
  /// applied instead of running auto-fit. The saved viewport is
  /// validated lightly (finite values, scale > 0); a corrupt entry
  /// silently falls back to auto-fit so a bad pref never breaks the
  /// editor. Restoration only happens on the first fit of a session;
  /// later [_scheduleFit] calls (canvas resize, screen rotation) are
  /// genuine refits and must replay the auto-fit math.
  void _scheduleFit(Size screen, Size docSize) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_isMounted()) return;
      final controller = _ref.read(viewportControllerProvider.notifier);
      if (!_fittedOnce) {
        final session = _ref.read(editorSessionProvider);
        final projectId = session?.projectId;
        if (projectId != null) {
          final saved = await _viewportStore.load(projectId);
          if (!_isMounted()) return;
          // Restore (and later preserve across panel reflows) ONLY a
          // genuine user adjustment. An automatic-fit or legacy entry
          // (userAdjusted false) falls through to a fresh auto-fit below,
          // so an untouched reopened project behaves exactly like a fresh
          // one — the panel-reflow gate re-fits it. We still seed
          // lastFitContext via fit() first so "Fit to screen" has geometry
          // to replay against.
          if (saved != null &&
              saved.userAdjusted &&
              saved.viewport.scale > 0 &&
              saved.viewport.scale.isFinite) {
            controller.fit(screenSize: screen, canvasSize: docSize);
            controller.restore(saved.viewport, userAdjusted: true);
            _markFitted();
            return;
          }
        }
      }
      controller.fit(screenSize: screen, canvasSize: docSize);
      if (!_fittedOnce) {
        _markFitted();
      }
    });
  }

  void _markFitted() {
    _fittedOnce = true;
    _onFirstFit();
  }

  /// Schedule a viewport-preserving reflow for the next frame — the
  /// counterpart to [_scheduleFit] taken when the canvas pane changes size
  /// (a tool panel opened/closed/switched) while the user has a manually
  /// adjusted zoom/pan. Keeps the user's scale, re-centres on the same
  /// canvas detail, and re-clamps translation to the new pane instead of
  /// re-fitting. Deferred to the post-frame callback for the same reason
  /// [_scheduleFit] is: the viewport provider must not be mutated during
  /// build. Only reached after [fittedOnce], so no visibility gate is
  /// involved.
  void _schedulePreserveViewport(Size oldScreen, Size newScreen, Size docSize) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isMounted()) return;
      _ref
          .read(viewportControllerProvider.notifier)
          .reflowPreservingZoom(
            oldScreen: oldScreen,
            newScreen: newScreen,
            canvasSize: docSize,
          );
    });
  }
}
