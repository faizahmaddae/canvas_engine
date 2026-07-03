import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
import '../../../settings/application/settings_controller.dart';
import '../../application/document_controller.dart';
import '../../application/editing_controller.dart';
import '../../application/editor_lifecycle.dart';
import '../../application/editor_session.dart';
import '../../application/context_toolbar_controller.dart';
import '../../application/interaction_controller.dart';
import '../../application/live_overlay_controller.dart';
import '../../application/mask_edit_controller.dart';
import '../../application/project_viewport_store.dart';
import '../../application/selection_controller.dart';
import '../../application/viewport_controller.dart';
import '../../engine/core/editor_document.dart';
import '../../engine/core/editor_layer.dart';
import '../../engine/core/layer_transform.dart';
import '../../engine/core/selection_state.dart';
import '../../engine/core/viewport_state.dart';
import '../../engine/interaction/layer_space_mapper.dart';
import '../../engine/interaction/group_engine.dart';
import '../../engine/modules/image/image_layer.dart';
import '../../engine/modules/text/text_layer.dart';
import '../../engine/modules/paint/paint_layer.dart';
import '../../engine/modules/shape/shape_layer.dart';
import '../../engine/rendering/background_fill_box.dart';
import '../../engine/rendering/layer_renderer.dart';
import '../../crop/application/crop_controller.dart';
import '../../canvas/presentation/widgets/canvas_checkerboard.dart';
import '../../image/application/image_tool_controller.dart';
import '../../paint/application/paint_tool_controller.dart';
import '../../sticker/application/sticker_tool_controller.dart';
import '../../shape/application/shape_tool_controller.dart';
import '../../paint/presentation/paint_floating_toolbar.dart';
import '../../paint/presentation/paint_gesture_surface.dart';
import '../../shape/presentation/shape_floating_toolbar.dart';
import '../../text/application/text_tool_controller.dart';
import '../../text/presentation/add_text_composer_state.dart';
import '../../text/presentation/text_floating_toolbar.dart';
import 'animated_guides_layer.dart';
import 'canvas_framing.dart';
import 'mask_edit_overlay.dart';
import 'quick_actions_overlay.dart';
import 'selection_overlay.dart';
import 'transform_hud.dart';

/// Root canvas widget.
///
/// Renders the **logical canvas board** (its size comes from the document,
/// NOT from the screen) inside a [Transform] driven by the
/// [ViewportController]. Layer coordinates therefore stay in logical
/// canvas pixels regardless of device size, zoom or pan.
///
/// Pointer mapping: the `_canvasKey` lives on the inner board. A call to
/// `RenderBox.globalToLocal` on that box automatically walks the viewport
/// transform, so the existing interaction engine (which receives logical
/// coordinates) does not have to change.
class EditorCanvas extends ConsumerStatefulWidget {
  const EditorCanvas({super.key});

  @override
  ConsumerState<EditorCanvas> createState() => _EditorCanvasState();
}

class _EditorCanvasState extends ConsumerState<EditorCanvas>
    with WidgetsBindingObserver {
  final GlobalKey _canvasKey = GlobalKey();

  /// Captured at the start of a background pan/pinch so the controller can
  /// solve for the correct translation that keeps the focal point fixed.
  ViewportState? _gestureStartViewport;
  Offset? _gestureStartFocal;

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

  /// Per-project zoom/pan persistence. Owned by the canvas widget so
  /// load + save share a single [SharedPreferences] handle (cached on
  /// the store after first call) and survive across rebuilds.
  final ProjectViewportStore _viewportStore = ProjectViewportStore();

  // ------------------------------------------------------------------
  // Multi-finger tap shortcuts (Procreate-style):
  //   * 2-finger tap → undo
  //   * 3-finger tap → redo
  //
  // Implemented at the outer Listener so we observe every pointer
  // regardless of which deeper recogniser claims it. We disambiguate
  // tap from pinch using the standard `kTouchSlop` movement bound and
  // a short time window — identical heuristic to a single-finger tap,
  // just with a peak-pointer-count check.
  //
  // Aborted (no undo/redo fired) when:
  //   * any pointer moves > kTouchSlop (it's a pan/pinch, not a tap)
  //   * peak pointer count exceeds 3
  //   * the interaction controller becomes active during the window
  //     (an object body recogniser claimed it — that's not a viewport
  //     tap, it's an object gesture)
  //   * paint or inline-edit mode is active (those modes own the
  //     surface entirely)
  //   * total duration exceeds [_multiTapMaxDuration]
  // ------------------------------------------------------------------

  /// Maximum total duration from first pointer down to last pointer up
  /// for a multi-finger sequence to count as a tap. Beyond this it is
  /// considered a deliberate gesture (slow drag, rest-fingers, etc.).
  static const Duration _multiTapMaxDuration = Duration(milliseconds: 250);

  final Map<int, _MultiTapPointer> _multiTapPointers =
      <int, _MultiTapPointer>{};
  int _multiTapPeak = 0;
  DateTime? _multiTapFirstDownAt;
  bool _multiTapAborted = false;

  /// State for tap-cycling through overlapping layers.
  ///
  /// When the user taps the same screen position more than once in a
  /// row, each tap selects the *next* eligible layer below the current
  /// one in z-order. This solves the classic "I want to select the
  /// layer behind this one" problem without forcing a manual deselect
  /// or a layers-panel detour.
  ///
  /// Reset semantics:
  ///
  ///   * [_lastTapGlobal] is `null` until the first tap of a sequence;
  ///   * if the next tap lands further than [_tapCycleTolerancePx] away
  ///     from the last tap, the cycle restarts at the topmost layer;
  ///   * if the eligible-hit set under the new tap differs from the
  ///     previous one (layer added / removed / reordered between
  ///     taps), the cycle also restarts — prevents stale-index bugs.
  ///
  /// Stored on the State so the cycling is presentation-only; no
  /// engine, selection, or document state is touched by this logic
  /// other than the eventual `select(id)` call.
  Offset? _lastTapGlobal;
  List<String>? _lastTapHitIds;
  int _tapCycleIndex = 0;

  /// Maximum movement (in screen pixels) between two consecutive taps
  /// for them to be considered "the same spot" and therefore cycle.
  /// Comfortably larger than `kTouchSlop` so a finger that wobbles a
  /// few px between taps still cycles, but small enough that taps in
  /// genuinely different regions reset.
  static const double _tapCycleTolerancePx = 24.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Persist viewport changes per-project. We listen here (not in
    // build) so the subscription is single-shot and doesn't
    // re-register on every rebuild. The save is debounced by
    // [_kViewportSaveDebounce] so a pinch-zoom that emits 60
    // intermediate states writes once on settle, not 60 times.
    ref.listenManual<ViewportState>(viewportControllerProvider, (prev, next) {
      if (prev == next) return;
      if (!_fittedOnce) {
        // The very first viewport push is the auto-fit/restore
        // itself; do not write it back over a possibly-still-
        // loading saved entry.
        return;
      }
      final session = ref.read(editorSessionProvider);
      final projectId = session?.projectId;
      if (projectId == null) return;
      _viewportSaveTimer?.cancel();
      _viewportSaveTimer = Timer(_kViewportSaveDebounce, () {
        if (!mounted) return;
        _viewportStore.save(projectId, next);
      });
    });
  }

  /// Debounce window for viewport persistence. 600 ms is long enough
  /// that a single pinch + settle yields one write, short enough that
  /// a backgrounded app keeps a fresh enough value to feel correct
  /// on the next launch.
  static const Duration _kViewportSaveDebounce = Duration(milliseconds: 600);

  Timer? _viewportSaveTimer;

  @override
  void dispose() {
    _viewportSaveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    // Note: we deliberately do NOT call `interactionController.cancel()`
    // here — Riverpod's `ref` is unsafe inside dispose because the
    // BuildContext is already deactivated. The other cancel triggers
    // (pointer-cancel listener + app-lifecycle observer + the in-
    // controller document subscription) cover the realistic
    // interruption cases. A widget-unmount mid-gesture without any of
    // those signals is rare enough to accept; the next mount will see
    // a stale session but `cancel()` is safe to call from any later
    // gesture entry point.
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Anything other than `resumed` means the user has lost focus on
    // the editor (incoming call, app switcher, screen lock, control
    // centre, …). Cancel rather than risk committing a half-finished
    // gesture when the app comes back. `cancel()` is idempotent so the
    // common case (no active gesture) costs nothing.
    if (state != AppLifecycleState.resumed) {
      ref.read(interactionControllerProvider.notifier).cancel();
    }
  }

  Offset _toCanvas(Offset global) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return global;
    return box.globalToLocal(global);
  }

  // ------------------------------------------------------------------
  // Multi-finger tap handlers — see field-level docs above.
  // ------------------------------------------------------------------

  /// Aborts the in-flight multi-tap window without resetting it. The
  /// finalize step still runs on the final pointer-up but does nothing.
  /// Cheaper and safer than clearing mid-sequence.
  void _abortMultiTap() {
    _multiTapAborted = true;
  }

  /// Mirror of `kTouchSlop` for our movement check. Centralised here so
  /// the helpers below stay readable.
  static const double _multiTapMoveSlop = kTouchSlop;

  void _onMultiTapPointerDown(PointerDownEvent e) {
    // Feature flag: the 2-/3-finger tap shortcuts are opt-in. When
    // disabled (the default), we abort the window on every pointer-
    // down so no amount of subsequent lifts can trigger undo/redo.
    // The body / viewport recognisers are unaffected — they receive
    // the same pointers via their own listeners.
    if (!ref.read(appSettingsProvider).multiFingerUndoRedoEnabled) {
      _abortMultiTap();
      return;
    }
    // Mode gates: paint and inline-edit own the surface entirely; we
    // must not consume their touches with an undo shortcut.
    if (ref.read(paintToolControllerProvider).activeTool != null) {
      _abortMultiTap();
      return;
    }
    if (ref.read(editingControllerProvider) != null) {
      _abortMultiTap();
      return;
    }
    // Mask-edit mode rides on the live canvas (unlike crop's opaque
    // overlay) — a clean 2-finger tap must not fire undo under the
    // mode's draft.
    if (ref.read(maskEditControllerProvider).active) {
      _abortMultiTap();
      return;
    }
    // NOTE: we deliberately do NOT abort here when an interaction
    // session is already active. With the active-transform-surface
    // model, the body recogniser eagerly claims pointer-down whenever
    // a layer is selected — so `isActive` becomes true synchronously
    // for every gesture, including legitimate 2-/3-finger taps that
    // the user means as undo/redo. Movement is the real
    // disambiguator: the per-pointer slop check in
    // [_onMultiTapPointerMove] aborts the tap window the moment any
    // finger actually drags, leaving the body session in charge. If
    // no finger moves and the sequence finalises cleanly as a tap,
    // [_finalizeMultiTap] cancels the phantom session before firing
    // the shortcut.
    _multiTapPointers[e.pointer] = _MultiTapPointer(e.position);
    _multiTapFirstDownAt ??= DateTime.now();
    if (_multiTapPointers.length > _multiTapPeak) {
      _multiTapPeak = _multiTapPointers.length;
    }
    // Anything beyond 3 fingers is not a known shortcut — abort early
    // to avoid a 4-finger pinch ever firing redo on lift.
    if (_multiTapPeak > 3) {
      _abortMultiTap();
    }
  }

  void _onMultiTapPointerMove(PointerMoveEvent e) {
    final p = _multiTapPointers[e.pointer];
    if (p == null) return;
    if ((e.position - p.downPosition).distance > _multiTapMoveSlop) {
      _abortMultiTap();
    }
    // Movement is the sole gesture-vs-tap discriminator. We do NOT
    // abort on `interactionController.isActive` here because the body
    // recogniser claims on pointer-down for every selected-layer
    // gesture — doing so would kill the undo/redo shortcut whenever
    // anything is selected. As long as no finger crosses the slop
    // bound, the sequence remains a candidate tap.
  }

  void _onMultiTapPointerUp(PointerUpEvent e) {
    if (!_multiTapPointers.containsKey(e.pointer)) return;
    _multiTapPointers.remove(e.pointer);
    if (_multiTapPointers.isEmpty) {
      _finalizeMultiTap();
    }
  }

  void _onMultiTapPointerCancel(PointerCancelEvent e) {
    if (!_multiTapPointers.containsKey(e.pointer)) return;
    _multiTapPointers.remove(e.pointer);
    _abortMultiTap();
    if (_multiTapPointers.isEmpty) {
      _finalizeMultiTap();
    }
  }

  void _finalizeMultiTap() {
    final firstDown = _multiTapFirstDownAt;
    final peak = _multiTapPeak;
    final aborted = _multiTapAborted;
    _multiTapFirstDownAt = null;
    _multiTapPeak = 0;
    _multiTapAborted = false;
    if (aborted || firstDown == null) return;
    if (DateTime.now().difference(firstDown) > _multiTapMaxDuration) return;
    if (peak != 2 && peak != 3) return;
    final docCtl = ref.read(documentControllerProvider.notifier);
    final isUndo = peak == 2;
    if (isUndo ? !docCtl.canUndo : !docCtl.canRedo) return;
    // The active-transform-surface body recogniser may have claimed
    // these pointers and started a phantom session on pointer-down.
    // No finger ever moved (we just verified above), so no document
    // mutation has occurred — cancelling cleanly discards the live
    // (== initial) transform without committing. This is what makes
    // the undo/redo shortcut survive the eager-claim policy.
    ref.read(interactionControllerProvider.notifier).cancel();
    if (isUndo) {
      docCtl.undo();
    } else {
      docCtl.redo();
    }
    HapticFeedback.lightImpact().catchError((_) {});
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
      if (!mounted) return;
      final controller = ref.read(viewportControllerProvider.notifier);
      if (!_fittedOnce) {
        final session = ref.read(editorSessionProvider);
        final projectId = session?.projectId;
        if (projectId != null) {
          final saved = await _viewportStore.load(projectId);
          if (!mounted) return;
          if (saved != null && saved.scale > 0 && saved.scale.isFinite) {
            // We still need lastFitContext seeded so the user-facing
            // "Fit to screen" action has geometry to replay against.
            controller.fit(screenSize: screen, canvasSize: docSize);
            controller.restore(saved);
            setState(() => _fittedOnce = true);
            return;
          }
        }
      }
      controller.fit(screenSize: screen, canvasSize: docSize);
      if (!_fittedOnce) {
        setState(() => _fittedOnce = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // The canvas is the ONLY consumer that wants the merged "committed
    // + in-flight overlay" view, so a 60-fps slider drag rebuilds the
    // canvas (correct — it must show the preview) without rebuilding
    // the layers panel, undo rail, or any other widget that watches
    // [documentControllerProvider] directly.
    final doc = ref.watch(renderedDocumentProvider);
    final selection = ref.watch(selectionControllerProvider);
    final viewport = ref.watch(viewportControllerProvider);
    final activeLayerId = ref.watch(
      interactionControllerProvider.select((s) => s.session?.layerId),
    );
    final snapGuides = ref.watch(
      interactionControllerProvider.select((s) => s.snapGuides),
    );
    final spacingGuides = ref.watch(
      interactionControllerProvider.select((s) => s.spacingGuides),
    );
    // While the Add Text composer is up, every piece of selection
    // chrome is suppressed so the user's attention goes to the input
    // only. The staged layer keeps rendering (it shows where the
    // text will land), but handles, HUD, contextual toolbars and the
    // quick-action pill all hide. The modal scrim already dims the
    // canvas; this flag handles the rest.
    final addTextComposerOpen = ref.watch(addTextComposerOpenProvider);
    // Mask-edit mode replaces the selection chrome with its own
    // overlay: handles, HUD, floating toolbars and quick actions all
    // hide while the region editor owns the layer.
    final maskEditActive =
        ref.watch(maskEditControllerProvider.select((s) => s.active));
    final docSize = Size(doc.width, doc.height);

    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = constraints.biggest;
        final hasValidSize =
            screen.width.isFinite &&
            screen.height.isFinite &&
            screen.width > 0 &&
            screen.height > 0 &&
            docSize.width > 0 &&
            docSize.height > 0;
        if (hasValidSize &&
            (_lastFitScreen != screen || _lastFitDoc != docSize)) {
          _lastFitScreen = screen;
          _lastFitDoc = docSize;
          _scheduleFit(screen, docSize);
        }

        return Listener(
          // Surface OS-issued pointer cancellations to the interaction
          // controller. Real-world triggers: a system gesture (back-
          // swipe, notification shade), a parent route grabbing the
          // pointer, a touch being interrupted by an incoming call.
          // Without this, an in-flight gesture would silently leak its
          // session and the user could see a "ghost" live transform on
          // resume. `cancel()` is idempotent so off-session events cost
          // nothing.
          onPointerDown: _onMultiTapPointerDown,
          onPointerMove: _onMultiTapPointerMove,
          onPointerUp: _onMultiTapPointerUp,
          onPointerCancel: (e) {
            _onMultiTapPointerCancel(e);
            ref.read(interactionControllerProvider.notifier).cancel();
            // Belt-and-braces: `onScaleEnd` is not guaranteed to fire
            // when the framework cancels the viewport's scale gesture
            // (e.g. a parent route grabs the pointer, system gesture
            // intercepts). Without this reset, `_gestureStartViewport`
            // would stay non-null and the body recogniser's
            // first-finger-wins backstop would silently refuse every
            // subsequent gesture until the next clean viewport pan
            // completed. Reset on every cancel.
            _gestureStartViewport = null;
            _gestureStartFocal = null;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              // Paint mode owns the canvas — the paint surface (mounted
              // inside the viewport transform) handles taps that land
              // on the canvas itself. Taps that land OUTSIDE the canvas
              // (pasteboard / black area) reach this background
              // detector and must dismiss paint mode through the same
              // central seam, so the user has a way out without having
              // to first navigate back to the canvas. Drawing is a pan
              // gesture and never routes through onTapUp, so this is
              // safe mid-session.
              if (ref.read(paintToolControllerProvider).activeTool != null) {
                dismissActiveEditing(ref);
                return;
              }
              ref.read(editingControllerProvider.notifier).stop();
              _handleTap(d.globalPosition, doc.layers);
            },
            // Long-press: the dedicated mobile entry to multi-select
            // mode. Fires after the system long-press timeout on any
            // pointer that reaches this detector — i.e. taps on empty
            // canvas and on un-selected layers (a selected layer's body
            // surface eagerly claims pointer-down, so long-press over an
            // already-selected layer falls through to the body's tap
            // path on release; that's fine for v1).
            onLongPressStart: (d) {
              _handleLongPress(d.globalPosition, doc.layers);
            },
            onDoubleTapDown: (d) {
              // Double-tap is reserved for future non-text editable
              // affordances. Text editing is initiated exclusively from
              // the floating toolbar's edit pill so users never have to
              // discover two ways to do the same thing.
              final local = _toCanvas(d.globalPosition);
              final hit = _hitTest(doc.layers, local);
              if (hit == null || !hit.capabilities.editable) return;
              if (hit is TextLayer) return;
              ref.read(selectionControllerProvider.notifier).select(hit.id);
              ref.read(editingControllerProvider.notifier).start(hit.id);
            },
            onDoubleTap: () {},
            // Background pan + pinch-to-zoom for the viewport. Layer scale
            // recognisers sit deeper in the tree and win the gesture arena
            // when a finger lands on a selected layer; touches on empty
            // canvas / margin fall through to this handler.
            //
            // Defensive guard: even with the body's claim-on-down
            // recogniser, an out-of-order pointer (e.g. one finger on the
            // selected layer, a second finger lands on empty canvas) can
            // briefly satisfy this recogniser. Skipping start/update while
            // an interaction session is active prevents the viewport from
            // panning/zooming "alongside" an object transform — the
            // selected object owns the gesture, exclusively, until it
            // ends.
            onScaleStart: (d) {
              if (ref.read(interactionControllerProvider).isActive) return;
              // Paint mode suppresses viewport pan/zoom — the gesture
              // belongs to the drawing surface above.
              if (ref.read(paintToolControllerProvider).activeTool != null) {
                return;
              }
              final s = ref.read(appSettingsProvider);
              if (!s.canvasPanEnabled && !s.canvasZoomEnabled) return;
              _gestureStartViewport = ref.read(viewportControllerProvider);
              _gestureStartFocal = d.focalPoint;
            },
            onScaleUpdate: (d) {
              if (ref.read(interactionControllerProvider).isActive) return;
              if (ref.read(paintToolControllerProvider).activeTool != null) {
                return;
              }
              final start = _gestureStartViewport;
              final focal = _gestureStartFocal;
              if (start == null || focal == null) return;
              // Honour user gesture toggles. Disabling pan freezes the
              // focal point at gesture start so translation never moves;
              // disabling zoom forces unit scale so pinch becomes a no-op.
              // Object interaction (drag/resize) is unaffected — those
              // recognisers live deeper in the tree and never reach this
              // background handler.
              final settings = ref.read(appSettingsProvider);
              final effectiveFocal = settings.canvasPanEnabled
                  ? d.focalPoint
                  : focal;
              final effectiveScale = settings.canvasZoomEnabled ? d.scale : 1.0;
              ref
                  .read(viewportControllerProvider.notifier)
                  .gestureUpdate(
                    startState: start,
                    startFocal: focal,
                    currentFocal: effectiveFocal,
                    scale: effectiveScale,
                  );
            },
            onScaleEnd: (_) {
              _gestureStartViewport = null;
              _gestureStartFocal = null;
            },
            child: ColoredBox(
              color: const Color(0xFF111318),
              child: ClipRect(
                // Outer Stack: viewport-transformed canvas board (bottom)
                // + screen-space chrome (top). Selection handles + HUD live
                // in the screen-space layer so they stay constant size in
                // dp regardless of document size or zoom.
                //
                // Until the first auto-fit lands the canvas would briefly
                // appear at identity (top-left, 1:1) — a flash that reads
                // as "the canvas is the wrong size." Hiding the contents
                // with Visibility (rather than skipping the subtree) keeps
                // layout/state alive so the post-frame fit has correct
                // constraints to work with.
                child: Visibility(
                  visible: _fittedOnce,
                  maintainState: true,
                  maintainSize: true,
                  maintainAnimation: true,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
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
                            child: Stack(
                              key: _canvasKey,
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
                                  child:
                                      doc.backgroundMode ==
                                          CanvasBackgroundMode.transparent
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
                                PaintGestureSurface(docSize: docSize),
                              ],
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
                      // Screen-space chrome — sits OUTSIDE the viewport
                      // transform so handles never scale with zoom or doc
                      // size. Receives the current viewport so it can map
                      // canvas-space corners to screen coordinates.
                      //
                      // Routing:
                      //   * count == 1 → per-layer selection chrome that
                      //     hugs the rotated layer rect.
                      //   * count >  1 → group selection chrome on the
                      //     shared axis-aligned bounds. The per-layer
                      //     overlay is suppressed; subtle outlines are
                      //     painted *inside* the viewport (above) instead.
                      //
                      // Protected base photo (photo project + locked) is
                      // the canvas itself, not a movable object. UX:
                      //   * Selection FRAME is shown (outline only, no
                      //     handles, no body drag) so the user can see
                      //     what is selected when they pick the row in
                      //     the Layers panel and the bottom Image tools
                      //     appear. Without this the toolbar change is
                      //     unexplained.
                      //   * Transform HUD, floating duplicate/delete bar
                      //     and inline contextual toolbars stay
                      //     suppressed -- those imply move/scale/delete,
                      //     none of which apply to the base photo.
                      //   * A small "Base photo" badge is rendered near
                      //     the photo's top-left corner so the selection
                      //     state has a clear label. See
                      //     `_buildProtectedBaseBadge`.
                      // Handles + body drag suppression for protected
                      // base photo is handled inside
                      // `_buildSelectionOverlay` (it passes
                      // `showHandles: !locked` and `onBody: null` for
                      // locked layers).
                      if (selection.count == 1 &&
                          !addTextComposerOpen &&
                          !maskEditActive)
                        _buildSelectionOverlay(doc.layers, selection, viewport),
                      if (selection.count == 1 &&
                          _isProtectedSelection(doc, selection) &&
                          !maskEditActive)
                        _buildProtectedBaseBadge(
                          doc.layers,
                          selection,
                          viewport,
                        ),
                      if (selection.count > 1 &&
                          !addTextComposerOpen &&
                          !maskEditActive)
                        _buildGroupSelectionOverlay(
                          doc.layers,
                          selection,
                          viewport,
                        ),
                      if (selection.hasSelection &&
                          !_isProtectedSelection(doc, selection) &&
                          !addTextComposerOpen &&
                          !maskEditActive)
                        _buildHud(doc.layers, selection, viewport),
                      // Floating contextual text toolbar — appears next to
                      // the selected text layer with the high-frequency
                      // controls (color / size / bold). Mounted in the
                      // screen-space chrome so it stays a constant size at
                      // any zoom and never reflows the canvas.
                      if (selection.count == 1 &&
                          !addTextComposerOpen &&
                          !maskEditActive)
                        _buildTextFloatingToolbar(
                          doc.layers,
                          selection,
                          viewport,
                        ),
                      // Floating contextual paint toolbar — symmetric with
                      // the text toolbar above. Appears next to a selected
                      // paint layer with stroke color, size, and resize
                      // behavior toggle. Mutually exclusive with the text
                      // toolbar (each builder type-checks its layer kind).
                      if (selection.count == 1 &&
                          !addTextComposerOpen &&
                          !maskEditActive)
                        _buildPaintFloatingToolbar(
                          doc.layers,
                          selection,
                          viewport,
                        ),
                      // Floating contextual shape toolbar — mirror of
                      // the paint toolbar. Surfaces the resize-mode
                      // toggle (Scale ↔ Free) for the selected shape
                      // so the user can override the kind-based
                      // default (e.g. let a circle stretch, or lock
                      // a rectangle's aspect). Mutually exclusive
                      // with the other floating bars (each builder
                      // type-checks its layer kind).
                      if (selection.count == 1 &&
                          !addTextComposerOpen &&
                          !maskEditActive)
                        _buildShapeFloatingToolbar(
                          doc.layers,
                          selection,
                          viewport,
                        ),
                      // Quick actions pill — fallback structural actions
                      // for selected layer types that do not yet have a
                      // contextual toolbar More entry. Visibility is
                      // further gated inside the builder on inline-editing
                      // and active transform sessions so the bar never
                      // chases a moving selection.
                      if (selection.count == 1 &&
                          !_isProtectedSelection(doc, selection) &&
                          !addTextComposerOpen &&
                          !maskEditActive)
                        _buildQuickActionsOverlay(
                          doc.layers,
                          selection,
                          viewport,
                        ),
                      // Note: the legacy in-canvas image crop overlay
                      // was removed. Cropping now happens in the
                      // full-screen [CropModeOverlay] mounted by the
                      // [EditorScreen] above this canvas.
                      // Minimal multi-select mode indicator. Renders only
                      // when the user has explicitly entered the mode via
                      // long-press. A tiny chip in the top-left corner
                      // tells the user "you are in multi-select" + the
                      // current count, so toggling-on-tap behaviour is
                      // never invisible.
                      // Mask-edit chrome: region scrim/outline, drag
                      // handles, and the bottom strip. Mounted above
                      // every other chrome piece it replaces.
                      if (maskEditActive)
                        MaskEditOverlay(viewport: viewport),
                      const _MultiSelectModeChip(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// True when the current single-selection points at a layer that
  /// the document marks as a protected base photo (photo project +
  /// matching `basePhotoLayerId`). Used to suppress the chrome that
  /// implies movability (transform HUD, floating duplicate/delete
  /// bar, inline contextual toolbars). The selection FRAME itself
  /// is shown -- see the build order above. Centralised here so the
  /// rule lives in exactly one place.
  bool _isProtectedSelection(EditorDocument doc, SelectionState selection) {
    final id = selection.selectedId;
    if (id == null) return false;
    return doc.isProtectedBasePhoto(id);
  }

  /// Small screen-space "Base photo" pill anchored to the protected
  /// photo's top-left corner. Provides the explicit label the bare
  /// outline lacks, so the user understands why the bottom Image
  /// tools just appeared. Pure indicator -- IgnorePointer so it can
  /// never eat canvas gestures.
  Widget _buildProtectedBaseBadge(
    List<EditorLayer> layers,
    SelectionState selection,
    ViewportState viewport,
  ) {
    EditorLayer? layer;
    for (final l in layers) {
      if (l.id == selection.selectedId) {
        layer = l;
        break;
      }
    }
    if (layer == null) return const SizedBox.shrink();
    final t = layer.transform;
    final pos = t.position;
    final centerCanvas = t.center;
    final rot = t.rotation;
    final cos = math.cos(rot);
    final sin = math.sin(rot);
    final dx = pos.dx - centerCanvas.dx;
    final dy = pos.dy - centerCanvas.dy;
    final tlCanvas = Offset(
      centerCanvas.dx + dx * cos - dy * sin,
      centerCanvas.dy + dx * sin + dy * cos,
    );
    final tl = tlCanvas * viewport.scale + viewport.translation;
    return Positioned(
      left: tl.dx,
      top: tl.dy - 28,
      child: const IgnorePointer(child: _ProtectedBaseBadge()),
    );
  }

  Widget _buildSelectionOverlay(
    List<EditorLayer> layers,
    SelectionState selection,
    ViewportState viewport,
  ) {
    EditorLayer? layer;
    for (final l in layers) {
      if (l.id == selection.selectedId) {
        layer = l;
        break;
      }
    }
    if (layer == null) return const SizedBox.shrink();
    final selectedLayer = layer;
    return Consumer(
      builder: (context, ref, _) {
        final isEditing = ref.watch(
          editingControllerProvider.select((id) => id == selectedLayer.id),
        );
        if (isEditing) return const SizedBox.shrink();
        final live = ref.watch(
          interactionControllerProvider.select(
            (s) =>
                s.session?.layerId == selectedLayer.id ? s.liveTransform : null,
          ),
        );
        final activeHandle = ref.watch(
          interactionControllerProvider.select(
            (s) => s.session?.layerId == selectedLayer.id
                ? s.session?.handle
                : null,
          ),
        );
        final isRotSnapped = ref.watch(
          interactionControllerProvider.select(
            (s) =>
                s.session?.layerId == selectedLayer.id && s.isRotationSnapped,
          ),
        );
        final transform = live ?? selectedLayer.transform;
        return LayerSelectionOverlay(
          transform: transform,
          viewport: viewport,
          activeHandle: activeHandle,
          isSnapped: isRotSnapped,
          // Locked layers (notably the photo-mode base photo) get a
          // selection frame so users still see "this is what's
          // selected", but no transform handles -- handles imply
          // grab-and-resize, which would silently no-op against the
          // locked layer and feel broken.
          showHandles: !selectedLayer.locked,
          // Active-transform-surface model: while a layer is selected,
          // the entire canvas behaves as a transform surface for that
          // selection. The body recogniser claims any first pointer
          // (regardless of whether it lands on the layer's rotated
          // bbox), so:
          //
          //   * 1 finger anywhere → translates the selected layer
          //   * 2 fingers anywhere → pinch + rotate the selected layer
          //     (the gesture's focal becomes the pivot, exactly like
          //     Procreate / Photoshop's "free transform" mode)
          //   * a true tap (no movement past slop) is forwarded via
          //     [onBodyTap] → `_handleTap`, which routes to selection
          //     switching: tap on a different (eligible, higher)
          //     layer selects it; tap on empty canvas clears selection.
          //
          // Side-effect: the viewport's pan/pinch is suppressed while
          // any layer is selected — to pan/zoom the canvas, the user
          // taps empty space first to deselect. This matches the
          // mental model of pro mobile editors and is what makes the
          // single-finger-anywhere drag feel "right".
          //
          // First-finger-wins backstop: if a viewport pan/pinch was
          // already in flight when the selection appeared (rare race),
          // refuse new pointers so a half-finished viewport gesture
          // can complete cleanly.
          shouldClaimBody: (_) {
            if (_gestureStartViewport != null) return false;
            // Crop Mode owns the entire viewport via the
            // full-screen [CropModeOverlay]; the selection body
            // surface must yield so the canvas underneath stays
            // inert.
            final cropActive = ref.read(cropControllerProvider).active;
            if (cropActive) return false;
            // Mask-edit mode: the overlay owns the region + handles;
            // yielding lets outside-region pointers fall through to
            // viewport pan/zoom.
            if (ref.read(maskEditControllerProvider).active) return false;
            return true;
          },
          // Defer-start gate: when the first pointer lands OUTSIDE
          // the selected layer's rotated bbox (i.e. on empty canvas
          // or on a different, deeper layer) we claim the arena but
          // hold off on emitting [DragPhase.start] until movement
          // past slop or a second finger. This preserves the three
          // sub-slop intents the user can express on empty canvas
          // while a layer is selected:
          //
          //   * pure tap        → unselect / cycle selection
          //   * pure long-press → enter multi-select with that layer
          //   * pause-then-drag → translate the selected layer
          //
          // When the first pointer lands ON the selected layer's
          // bbox we keep the eager claim-and-start behaviour — drag
          // is the obvious intent and off-canvas recovery depends
          // on the layer responding from the very first frame.
          shouldDeferStartBody: (globalPosition) {
            final local = _toCanvas(globalPosition);
            return !_pointInLayerBbox(selectedLayer, local);
          },
          // Body surface eagerly claims the gesture arena on pointer-
          // down to guarantee drag priority over the viewport, which
          // also means it eats plain taps that the canvas-level tap
          // detector would otherwise route through `_handleTap`. This
          // callback re-injects those taps so overlapping-layer
          // cycling continues to work when the topmost layer is the
          // currently selected one.
          onBodyTap: (globalPosition) => _handleTap(globalPosition, layers),
          // Long-press intent re-injection. The body surface claims
          // every pointer-down whenever a layer is selected, so the
          // canvas-level `GestureDetector.onLongPressStart` is dead
          // while a selection exists. Without this hook, the
          // documented "long-press another layer to enter
          // multi-select with both layers" gesture would be silently
          // broken: the body surface would eat the held pointer and
          // long-press would never fire. Routing through
          // `_handleLongPress` runs the exact same code path as a
          // long-press on empty canvas, so behaviour is uniform
          // regardless of selection state.
          onBodyLongPress: (globalPosition) =>
              _handleLongPress(globalPosition, layers),
          onBody: selectedLayer.locked || !selectedLayer.capabilities.movable
              ? null
              : (update) {
                  final controller = ref.read(
                    interactionControllerProvider.notifier,
                  );
                  final focalCanvas = _toCanvas(update.focalGlobal);
                  switch (update.phase) {
                    case DragPhase.start:
                      // Single-layer body drag. Multi-select group
                      // drags are routed through the group selection
                      // overlay, which calls `startGroupGesture` and
                      // friends directly — this per-layer overlay is
                      // only wired up when `selection.count == 1`.
                      controller.startGesture(
                        layer: selectedLayer,
                        focalPoint: focalCanvas,
                      );
                    case DragPhase.update:
                      controller.updateGesture(
                        focalPoint: focalCanvas,
                        scale: update.scale,
                        rotation: update.rotation,
                        pointerCount: update.pointerCount,
                      );
                    case DragPhase.end:
                      controller.end();
                  }
                },
          onHandle: (handle, globalPointer, phase) {
            final controller = ref.read(interactionControllerProvider.notifier);
            switch (phase) {
              case DragPhase.start:
                final pointer = _toCanvas(globalPointer);
                if (handle == InteractionHandle.rotate) {
                  controller.startRotate(
                    layer: selectedLayer,
                    pointer: pointer,
                  );
                } else {
                  controller.startResize(
                    layer: selectedLayer,
                    handle: handle,
                    pointer: pointer,
                  );
                }
              case DragPhase.update:
                controller.update(_toCanvas(globalPointer));
              case DragPhase.end:
                controller.end();
            }
          },
        );
      },
    );
  }

  /// Build the group selection chrome (shared bounding box + handles)
  /// for the current multi-selection. Routes pointer events to the
  /// `startGroup{Move|Resize|Rotate|Gesture}` family on the
  /// interaction controller, so a single composite command commits
  /// the entire transform on release.
  Widget _buildGroupSelectionOverlay(
    List<EditorLayer> layers,
    SelectionState selection,
    ViewportState viewport,
  ) {
    final selectedSet = selection.selectedIds.toSet();
    final selectedLayers = <EditorLayer>[
      for (final l in layers)
        if (selectedSet.contains(l.id)) l,
    ];
    if (selectedLayers.length < 2) return const SizedBox.shrink();

    return Consumer(
      builder: (context, ref, _) {
        // Live group bounds. When a session is active, read the
        // controller's `groupLive` map (each entry already reflects
        // the in-flight transform). Otherwise compute from the
        // current document transforms.
        final ui = ref.watch(interactionControllerProvider);
        final Rect bounds;
        if (ui.groupSession != null) {
          bounds = ui.groupLiveBounds ?? Rect.zero;
        } else {
          bounds = const GroupEngine().computeBounds(
            selectedLayers.map((l) => l.transform),
          );
        }
        final activeHandle = ui.groupSession?.handle;
        return GroupSelectionOverlay(
          bounds: bounds,
          frameQuad: ui.groupLiveQuad,
          viewport: viewport,
          activeHandle: activeHandle,
          onBodyTap: (globalPosition) => _handleTap(globalPosition, layers),
          // Long-press intent re-injection (see single-layer overlay
          // for full rationale). While in multi-select with the
          // group active, long-pressing another layer must still
          // route to `_handleLongPress` so its toggle/extend
          // semantics fire. The eager arena claim hides it from
          // the canvas-level long-press recogniser otherwise.
          onBodyLongPress: (globalPosition) =>
              _handleLongPress(globalPosition, layers),
          // Active-transform-surface model for multi-select. See the
          // single-layer overlay above for the full rationale. Any
          // first pointer anywhere on the canvas drives the group's
          // rigid-body translate; a second finger anywhere drives
          // pinch + rotate around the gesture focal. A true tap with
          // no movement is forwarded via [onBodyTap] for selection
          // routing (toggle-in / toggle-out / mode exit).
          shouldClaimBody: (_) {
            if (_gestureStartViewport != null) return false;
            final cropActive = ref.read(cropControllerProvider).active;
            if (cropActive) return false;
            // Mask-edit mode: the overlay owns the region + handles;
            // yielding lets outside-region pointers fall through to
            // viewport pan/zoom.
            if (ref.read(maskEditControllerProvider).active) return false;
            return true;
          },
          // Defer-start gate: pointers landing OUTSIDE the group's
          // axis-aligned bbox claim the arena but defer the session
          // start until movement past slop or a second finger. Same
          // rationale as the single-layer overlay — preserves tap
          // (mode exit), long-press (extend / re-enter multi mode)
          // and pause-then-drag intents on empty canvas.
          shouldDeferStartBody: (globalPosition) {
            final local = _toCanvas(globalPosition);
            return !bounds.contains(local);
          },
          onBody: (update) {
            final controller = ref.read(interactionControllerProvider.notifier);
            final focalCanvas = _toCanvas(update.focalGlobal);
            switch (update.phase) {
              case DragPhase.start:
                controller.startGroupGesture(
                  layers: selectedLayers,
                  focalPoint: focalCanvas,
                );
              case DragPhase.update:
                controller.updateGroupGesture(
                  focalPoint: focalCanvas,
                  scale: update.scale,
                  rotation: update.rotation,
                  pointerCount: update.pointerCount,
                );
              case DragPhase.end:
                controller.end();
            }
          },
          onHandle: (handle, globalPointer, phase) {
            final controller = ref.read(interactionControllerProvider.notifier);
            final pointer = _toCanvas(globalPointer);
            switch (phase) {
              case DragPhase.start:
                if (handle == InteractionHandle.rotate) {
                  controller.startGroupRotate(
                    layers: selectedLayers,
                    pointer: pointer,
                  );
                } else {
                  controller.startGroupResize(
                    layers: selectedLayers,
                    handle: handle,
                    pointer: pointer,
                  );
                }
              case DragPhase.update:
                controller.updateGroup(pointer);
              case DragPhase.end:
                controller.end();
            }
          },
        );
      },
    );
  }

  Widget _buildHud(
    List<EditorLayer> layers,
    SelectionState selection,
    ViewportState viewport,
  ) {
    EditorLayer? layer;
    for (final l in layers) {
      if (l.id == selection.selectedId) {
        layer = l;
        break;
      }
    }
    if (layer == null) return const SizedBox.shrink();
    final selectedLayer = layer;
    return Consumer(
      builder: (context, ref, _) {
        final handle = ref.watch(
          interactionControllerProvider.select(
            (s) => s.session?.layerId == selectedLayer.id
                ? s.session?.handle
                : null,
          ),
        );
        if (handle == null) return const SizedBox.shrink();
        final live = ref.watch(
          interactionControllerProvider.select(
            (s) =>
                s.session?.layerId == selectedLayer.id ? s.liveTransform : null,
          ),
        );
        return TransformHud(
          transform: live ?? selectedLayer.transform,
          viewport: viewport,
          activeHandle: handle,
        );
      },
    );
  }

  /// Floating contextual toolbar for the selected text layer. Hidden
  /// while the layer is being inline-edited (the keyboard owns the
  /// screen) or while a transform gesture is in flight (we don't want
  /// the bar to chase the layer mid-drag).
  Widget _buildTextFloatingToolbar(
    List<EditorLayer> layers,
    SelectionState selection,
    ViewportState viewport,
  ) {
    EditorLayer? layer;
    for (final l in layers) {
      if (l.id == selection.selectedId) {
        layer = l;
        break;
      }
    }
    if (layer is! TextLayer) return const SizedBox.shrink();
    // Emoji stickers are stored as TextLayer but do NOT surface the
    // text-specific quick controls (Aa / size / bold). They get the
    // generic quick-actions pill instead, plus the dedicated
    // Sticker sub-tools in the bottom dock. Without this guard
    // both the text floating toolbar AND the quick-actions pill
    // would render simultaneously, stacking two bars on screen.
    if (layer.isSticker) return const SizedBox.shrink();
    final textLayer = layer;
    return Consumer(
      builder: (context, ref, _) {
        final isEditing = ref.watch(
          editingControllerProvider.select((id) => id == textLayer.id),
        );
        if (isEditing) return const SizedBox.shrink();
        final inSession = ref.watch(
          interactionControllerProvider.select(
            (s) => s.session?.layerId == textLayer.id,
          ),
        );
        if (inSession) return const SizedBox.shrink();
        // Hide while any bottom-dock sub-tool sheet is open — the
        // sheet is the source of truth for that property and the
        // floating bar would only stack on top of the sheet handle
        // on small phones.
        final sheetOpen = ref.watch(
          textToolControllerProvider.select((s) => s.openSheet != null),
        );
        final contextPanelOpen = ref.watch(
          contextToolbarControllerProvider.select((panel) => panel != null),
        );
        if (sheetOpen || contextPanelOpen) return const SizedBox.shrink();
        return TextFloatingToolbar(layer: textLayer, viewport: viewport);
      },
    );
  }

  /// Floating contextual toolbar for the selected paint layer. Hidden
  /// while a transform gesture is in flight (we don't want the bar to
  /// chase the layer mid-drag). Mutually exclusive with the text
  /// floating toolbar — type-checks the selected layer is a
  /// [PaintLayer] and returns nothing otherwise.
  Widget _buildPaintFloatingToolbar(
    List<EditorLayer> layers,
    SelectionState selection,
    ViewportState viewport,
  ) {
    EditorLayer? layer;
    for (final l in layers) {
      if (l.id == selection.selectedId) {
        layer = l;
        break;
      }
    }
    if (layer is! PaintLayer) return const SizedBox.shrink();
    final paintLayer = layer;
    return Consumer(
      builder: (context, ref, _) {
        final inSession = ref.watch(
          interactionControllerProvider.select(
            (s) => s.session?.layerId == paintLayer.id,
          ),
        );
        if (inSession) return const SizedBox.shrink();
        // Mirror the text-mode guard: hide while any paint dock
        // sub-tool sheet is open so the floating bar never stacks
        // on top of the sheet handle (and never duplicates the
        // controls the sheet already exposes).
        final sheetOpen = ref.watch(
          paintToolControllerProvider.select((s) => s.openSlot != null),
        );
        if (sheetOpen) return const SizedBox.shrink();
        return PaintFloatingToolbar(layer: paintLayer, viewport: viewport);
      },
    );
  }

  /// Floating contextual toolbar for the selected shape layer.
  /// Hidden while a transform gesture is in flight (so the bar
  /// never chases the layer mid-drag) and while the shape dock's
  /// sub-tool sheet (Style / Border / Shadow) is open (so the bar
  /// never stacks on top of the sheet handle). Type-checks the
  /// selected layer is a [ShapeLayer] and returns nothing
  /// otherwise — mirrors `_buildPaintFloatingToolbar`.
  Widget _buildShapeFloatingToolbar(
    List<EditorLayer> layers,
    SelectionState selection,
    ViewportState viewport,
  ) {
    EditorLayer? layer;
    for (final l in layers) {
      if (l.id == selection.selectedId) {
        layer = l;
        break;
      }
    }
    if (layer is! ShapeLayer) return const SizedBox.shrink();
    final shapeLayer = layer;
    return Consumer(
      builder: (context, ref, _) {
        final inSession = ref.watch(
          interactionControllerProvider.select(
            (s) => s.session?.layerId == shapeLayer.id,
          ),
        );
        if (inSession) return const SizedBox.shrink();
        final sheetOpen = ref.watch(
          shapeToolControllerProvider.select((s) => s.openSlot != null),
        );
        final contextPanelOpen = ref.watch(
          contextToolbarControllerProvider.select((panel) => panel != null),
        );
        if (sheetOpen || contextPanelOpen) return const SizedBox.shrink();
        return ShapeFloatingToolbar(layer: shapeLayer, viewport: viewport);
      },
    );
  }

  /// Quick actions pill (duplicate / bring-forward / delete) for
  /// layer types that do NOT bring their own contextual More entry.
  /// Text, image, paint, and shape layers route structural actions
  /// through their contextual toolbars so the canvas never shows two
  /// stacked action bars at once.
  ///
  /// Hidden during inline-edit and during a transform gesture so the
  /// bar never chases a moving selection.
  Widget _buildQuickActionsOverlay(
    List<EditorLayer> layers,
    SelectionState selection,
    ViewportState viewport,
  ) {
    EditorLayer? layer;
    for (final l in layers) {
      if (l.id == selection.selectedId) {
        layer = l;
        break;
      }
    }
    // Normal text + image + paint + shape suppress the generic
    // quick-actions overlay because their contextual toolbars own
    // that space and expose structural actions through More. Emoji
    // stickers, although stored as TextLayer, do NOT surface the
    // text toolbar — so they need the generic quick actions to stay
    // reachable (delete, duplicate, transform).
    if ((layer is TextLayer && !layer.isSticker) ||
        layer is ImageLayer ||
        layer is PaintLayer ||
        layer is ShapeLayer) {
      return const SizedBox.shrink();
    }
    if (layer == null) return const SizedBox.shrink();
    final selectedLayer = layer;
    return Consumer(
      builder: (context, ref, _) {
        final isEditing = ref.watch(
          editingControllerProvider.select((id) => id == selectedLayer.id),
        );
        if (isEditing) return const SizedBox.shrink();
        final inSession = ref.watch(
          interactionControllerProvider.select(
            (s) => s.session?.layerId == selectedLayer.id,
          ),
        );
        if (inSession) return const SizedBox.shrink();
        // Hide while an Image sub-tool panel is open above the
        // dock — the dock is taller and the floating pill would
        // sit on top of (or fight for vertical room with) the
        // selection controls. Mirrors how text/paint suppress
        // their floating bars while their sheet is open.
        final imagePanelOpen = ref.watch(
          imageToolControllerProvider.select((s) => s.openSlot != null),
        );
        if (imagePanelOpen) return const SizedBox.shrink();
        // Mirror the image-mode guard for the Sticker sub-tools so
        // the floating pill never stacks on top of the Style /
        // Size / Replace panel that owns the bottom of the screen.
        final stickerPanelOpen = ref.watch(
          stickerToolControllerProvider.select((s) => s.openSlot != null),
        );
        if (stickerPanelOpen) return const SizedBox.shrink();
        // Mirror for the Shape sub-tools — same reason: Style /
        // Border / Shadow / Replace panels would otherwise have
        // a floating pill stacking on top of them on small phones.
        final shapePanelOpen = ref.watch(
          shapeToolControllerProvider.select((s) => s.openSlot != null),
        );
        if (shapePanelOpen) return const SizedBox.shrink();
        return QuickActionsOverlay(layer: selectedLayer, viewport: viewport);
      },
    );
  }

  /// Removed: legacy `_buildImageCropOverlay`. Cropping is now
  /// handled by the full-screen [CropModeOverlay] mounted at the
  /// editor-screen level. Kept this comment as a breadcrumb so
  /// `git log` is enough to find the previous implementation.

  /// Returns the top-most layer whose rotated bounding box contains
  /// [point] (in logical canvas coordinates). Hidden and locked layers
  /// are skipped. Thin wrapper over [_hitTestAll] for call sites that
  /// only care about the topmost.
  EditorLayer? _hitTest(List<EditorLayer> layers, Offset point) {
    final hits = _hitTestAll(layers, point);
    return hits.isEmpty ? null : hits.first;
  }

  /// Returns ALL eligible layers under [point] in canvas coordinates,
  /// ordered top-most first (matching paint z-order: later in the
  /// layer list = visually on top). Hidden and locked layers are
  /// skipped. Drives [_handleTap]'s overlapping-layer cycling.
  List<EditorLayer> _hitTestAll(List<EditorLayer> layers, Offset point) {
    final hits = <EditorLayer>[];
    for (var i = layers.length - 1; i >= 0; i--) {
      final l = layers[i];
      if (!l.visible || l.locked) continue;
      if (_pointInLayerBbox(l, point)) hits.add(l);
    }
    return hits;
  }

  /// True iff [point] (canvas-space) is inside [layer]'s rotated
  /// bounding box. Pure geometry — does not consider visibility,
  /// lock state, or selection.
  bool _pointInLayerBbox(EditorLayer layer, Offset point) {
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

  /// Selection-routing for a plain tap on the canvas.
  ///
  /// Behaviour:
  ///
  ///   * Multi-select mode is active:
  ///       - hit → toggle that layer in/out of the selection;
  ///       - no hit → exit multi-select mode AND clear the selection.
  ///       Cycling is suppressed in this mode (it would conflict with
  ///       toggle semantics).
  ///   * Single mode (default):
  ///       - No eligible hit → clear selection and reset the cycle.
  ///       - One eligible hit → select it (cycle is irrelevant; reset).
  ///       - ≥2 eligible hits → first tap selects the topmost; a
  ///         follow-up tap landing within [_tapCycleTolerancePx] of
  ///         the previous tap advances to the next layer in z-order,
  ///         wrapping at the bottom. Any tap outside that radius, or
  ///         any tap whose hit set differs from the previous one
  ///         (layer added / removed / reordered), resets the cycle to
  ///         the topmost.
  ///
  /// Shared empty-tap dismiss path lives in [dismissActiveEditing]
  /// (`editor_lifecycle.dart`) so every future tool gets the same
  /// behaviour by adding one line there — not by re-discovering
  /// the same bug per tool.
  void _handleTap(Offset globalPosition, List<EditorLayer> layers) {
    final selectionCtl = ref.read(selectionControllerProvider.notifier);
    final mode = ref.read(selectionModeProvider);
    final local = _toCanvas(globalPosition);
    final hits = _hitTestAll(layers, local);

    if (mode == SelectionMode.multi) {
      // Multi-select mode tap routing — cycling is intentionally
      // disabled because it would compete with toggle semantics
      // (a 2nd tap on the same spot would both cycle AND toggle).
      _resetTapCycle();
      if (hits.isEmpty) {
        dismissActiveEditing(ref);
        return;
      }
      // Toggle the topmost eligible hit. We deliberately do NOT cycle
      // here — picking the topmost is the predictable behaviour when
      // the user is curating a multi-selection.
      selectionCtl.toggle(hits.first.id);
      return;
    }

    // Single mode (legacy / default behaviour).
    if (hits.isEmpty) {
      // Centralised dismiss: clears selection + collapses every
      // tool's transient sheet/panel + drops keyboard focus.
      // Saved layer data is untouched.
      dismissActiveEditing(ref);
      _resetTapCycle();
      return;
    }

    final hitIds = <String>[for (final l in hits) l.id];

    final lastGlobal = _lastTapGlobal;
    final lastIds = _lastTapHitIds;
    final isSameSpot =
        lastGlobal != null &&
        (globalPosition - lastGlobal).distance <= _tapCycleTolerancePx;
    final isSameHits = lastIds != null && _listsEqual(lastIds, hitIds);

    final int index;
    if (hits.length == 1 || !isSameSpot || !isSameHits) {
      index = 0;
    } else {
      index = (_tapCycleIndex + 1) % hits.length;
    }

    selectionCtl.select(hits[index].id);
    _lastTapGlobal = globalPosition;
    _lastTapHitIds = hitIds;
    _tapCycleIndex = index;
  }

  /// Long-press: the dedicated mobile entry to multi-select mode.
  ///
  /// Rules:
  ///   * Already in multi mode → no-op (long-pressing again should
  ///     not toggle the mode off; tap-on-empty does that).
  ///   * Hit a layer → enter multi mode AND ensure that layer is in
  ///     the selection (additive, becomes primary).
  ///   * Empty canvas → enter multi mode and clear, ready for the
  ///     user to start picking layers with taps.
  ///
  /// Always fires a short selection haptic so the mode change is felt
  /// even without looking — important on mobile where the visual chip
  /// might be partially occluded by the user's hand.
  void _handleLongPress(Offset globalPosition, List<EditorLayer> layers) {
    final mode = ref.read(selectionModeProvider);
    if (mode == SelectionMode.multi) return;

    final selectionCtl = ref.read(selectionControllerProvider.notifier);
    final modeCtl = ref.read(selectionModeProvider.notifier);
    final local = _toCanvas(globalPosition);
    final hit = _hitTest(layers, local);

    _resetTapCycle();
    modeCtl.enterMulti();
    if (hit != null) {
      // Use `add` (not `select`) so any existing single selection is
      // preserved and the long-pressed layer becomes the primary —
      // matches the mental model "I'm starting a multi-select that
      // includes whatever I had + this one".
      selectionCtl.add(hit.id);
    } else {
      selectionCtl.clear();
    }
    HapticFeedback.selectionClick().catchError((_) {});
  }

  void _resetTapCycle() {
    _lastTapGlobal = null;
    _lastTapHitIds = null;
    _tapCycleIndex = 0;
  }

  static bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// One pointer being tracked by the multi-finger tap heuristic. Only
/// stores what we need to disambiguate tap vs drag — no need to keep
/// the live position because we re-derive movement against the down
/// position on every move event.
class _MultiTapPointer {
  _MultiTapPointer(this.downPosition);
  final Offset downPosition;
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

/// Minimal mobile-only indicator that the canvas is in multi-select
/// mode. Renders nothing at all in single mode so the canvas chrome
/// stays untouched. Sits inside the screen-space chrome stack so it
/// never scales with viewport zoom.
///
/// Deliberately small + corner-pinned: this is an awareness affordance,
/// not a control surface. Mode entry/exit happens via long-press and
/// tap-on-empty respectively (see `_handleLongPress` / `_handleTap`).
class _MultiSelectModeChip extends ConsumerWidget {
  const _MultiSelectModeChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(selectionModeProvider);
    if (mode != SelectionMode.multi) return const SizedBox.shrink();
    final count = ref.watch(selectionControllerProvider.select((s) => s.count));
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      top: 12,
      left: 12,
      child: IgnorePointer(
        // Pure indicator — must never absorb taps that the canvas
        // gesture detectors are entitled to.
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 14,
                color: scheme.onPrimary,
              ),
              const SizedBox(width: 6),
              Text(
                context.l10n.multiSelectCount(count),
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact "Base photo" pill that labels the protected base-photo
/// selection. Positioning is the host's job (see
/// `_buildProtectedBaseBadge`); this widget only renders the visual.
/// Stateless + theme-driven so it follows light/dark automatically.
class _ProtectedBaseBadge extends StatelessWidget {
  const _ProtectedBaseBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 6,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 12, color: scheme.onPrimary),
          const SizedBox(width: 4),
          Text(
            context.l10n.basePhotoLabel,
            style: TextStyle(
              color: scheme.onPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
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
    final color = Theme.of(context).colorScheme.primary;
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
