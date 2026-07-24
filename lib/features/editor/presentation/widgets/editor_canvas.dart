import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/constants/engine_constants.dart';
import '../../../../l10n/l10n.dart';
import '../../../settings/application/settings_controller.dart';
import '../../application/canvas_capture.dart';
import '../../application/document_controller.dart';
import '../../application/canvas_chrome_visibility.dart';
import '../../application/edit_session_registry.dart';
import '../../application/editing_controller.dart';
import '../../application/editor_lifecycle.dart';
import '../../application/editor_session.dart';
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
import '../../engine/modules/text/text_layer.dart';
import '../../engine/rendering/background_fill_box.dart';
import '../../engine/rendering/layer_renderer.dart';
import '../../crop/application/crop_controller.dart';
import '../../canvas/presentation/widgets/canvas_checkerboard.dart';
import '../../paint/application/paint_tool_controller.dart';
import '../../paint/presentation/paint_gesture_surface.dart';
import '../../text/presentation/text_edit_flow.dart';
import '../../text/application/add_text_composer_state.dart';
import 'animated_guides_layer.dart';
import 'canvas_framing.dart';
import 'editor_breakpoints.dart';
import 'mask_edit_overlay.dart';
import 'quick_capsule.dart';
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

  /// Hardware pointers currently down anywhere on the canvas subtree,
  /// tracked at the outer [Listener]. Because pointer events dispatch
  /// leaf-first, a body recogniser's claim predicate runs BEFORE the
  /// pointer it is deciding on is added here — so a non-empty set
  /// means "another finger is already down in this physical sequence".
  ///
  /// Drives contract §5 row 6 (sequence continuation): when the body
  /// surface declined the first finger of a sequence (it landed off
  /// the selection's chrome quad), every later finger of that same
  /// sequence must also fall through, even if it lands ON the quad —
  /// the pair belongs to the viewport pinch, not the layer.
  final Set<int> _rawPointersDown = <int>{};

  /// Key on the ClipRect the viewport [Transform] is laid out in.
  /// Hands the paint surface the render box whose local space
  /// `viewport.translation` is defined in, so its two-finger rescue
  /// can feed [ViewportController.gestureUpdate] focals in the same
  /// space the background scale handler uses (`localFocalPoint`) —
  /// global focals would drift the zoom anchor by the AppBar /
  /// status-bar offset.
  final GlobalKey _viewportBodyKey = GlobalKey();

  /// Row-5 candidate: the eligible, movable, un-selected layer the
  /// current select-and-move pointer went down on. Stashed by the
  /// [SelectAndMoveSurface] claim predicate at pointer-down and
  /// consumed exactly once at [DragPhase.start] (the slop claim),
  /// which is the moment the layer becomes selected and its translate
  /// session begins. A sub-slop release never consumes it — the
  /// pointer is handed back to the canvas tap recognisers and the
  /// stale value is simply overwritten by the next claim.
  EditorLayer? _selectAndMoveCandidate;

  /// True while the live interaction session was started by the
  /// select-and-move surface. Disambiguates the `isActive` claim
  /// branches: a new finger landing during a row-5 session must fall
  /// THROUGH the selection overlay's body surface (which now belongs
  /// to the same, freshly selected layer) so it joins the recogniser
  /// that actually owns the in-flight pointers, one Stack level
  /// below. Reset on session end and on OS pointer-cancel.
  bool _selectAndMoveOwnsSession = false;

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

  // ------------------------------------------------------------------
  // Double-tap window (tb3 3/7).
  //
  // The canvas GestureDetector used to register `onDoubleTapDown`,
  // which put a DoubleTapGestureRecognizer in the arena and delayed
  // EVERY plain tap by the ~300ms double-tap timeout before the tap
  // recogniser could win. That recogniser is gone: taps now resolve
  // immediately, and the double-tap WINDOW lives here as plain
  // bookkeeping inside [_handleTap] — a second tap landing within
  // [_doubleTapWindow] of the previous tap, within [kDoubleTapSlop]
  // of its position, on the SAME layer the previous tap selected, is
  // a double-tap. Because both tap entry paths (the canvas detector
  // AND the selection overlay's re-injected [onBodyTap]) route
  // through [_handleTap], double-tap works identically on selected
  // and un-selected layers.
  //
  // Expiry is a [Timer] (not a wall-clock read) so widget tests can
  // age the window with `tester.pump(...)` exactly like they age the
  // long-press timeout.
  // ------------------------------------------------------------------

  /// Layer selected by the most recent single tap; a follow-up tap on
  /// it within the window is a double-tap. `null` = window disarmed.
  String? _doubleTapArmedLayerId;

  /// Global position of the arming tap, compared against the second
  /// tap with the framework's [kDoubleTapSlop] radius.
  Offset? _doubleTapArmedGlobal;

  Timer? _doubleTapWindowTimer;

  /// Matches the timing the repo's gesture tests already use to lapse
  /// tap sequences (they pump 400–500ms between taps).
  static const Duration _doubleTapWindow = Duration(milliseconds: 400);

  void _armDoubleTapWindow(String layerId, Offset globalPosition) {
    _doubleTapWindowTimer?.cancel();
    _doubleTapArmedLayerId = layerId;
    _doubleTapArmedGlobal = globalPosition;
    _doubleTapWindowTimer = Timer(_doubleTapWindow, _disarmDoubleTapWindow);
  }

  void _disarmDoubleTapWindow() {
    _doubleTapWindowTimer?.cancel();
    _doubleTapWindowTimer = null;
    _doubleTapArmedLayerId = null;
    _doubleTapArmedGlobal = null;
  }

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
        if (!mounted) return;
        _viewportStore.save(projectId, next, userAdjusted: next.userAdjusted);
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
    _doubleTapWindowTimer?.cancel();
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
    // A brand-new physical sequence must not inherit an abort
    // latched by a fully-gated previous one: the gates below abort
    // BEFORE registering the pointer, so [_finalizeMultiTap] (the
    // only reset point) never ran for that sequence and the flag
    // stayed true — silently swallowing the first legitimate tap
    // after e.g. a mask session ended (surfaced by the tb2 13/16
    // registry-gate pin).
    if (_multiTapPointers.isEmpty && _multiTapFirstDownAt == null) {
      _multiTapAborted = false;
    }
    // Feature flag: the 2-/3-finger tap shortcuts are opt-in. When
    // disabled (the default), we abort the window on every pointer-
    // down so no amount of subsequent lifts can trigger undo/redo.
    // The body / viewport recognisers are unaffected — they receive
    // the same pointers via their own listeners.
    if (!ref.read(appSettingsProvider).multiFingerUndoRedoEnabled) {
      _abortMultiTap();
      return;
    }
    // Surface-ownership gates: paint and inline-edit own the canvas
    // entirely; we must not consume their touches with an undo
    // shortcut. These are NOT draft sessions (paint is a live mode,
    // inline edit is the on-canvas caret) so they stay as their own
    // reads rather than folding into the registry below.
    if (ref.read(paintToolControllerProvider).activeTool != null) {
      _abortMultiTap();
      return;
    }
    if (ref.read(editingControllerProvider) != null) {
      _abortMultiTap();
      return;
    }
    // Session registry (contract §6): while ANY draft session is
    // open the shortcut is inert. Replaces the old mask-only read —
    // mask rides on the live canvas so it was the visible offender,
    // but crop / text compose / edit / export must be equally
    // protected (their modal barriers cover most of the screen, not
    // the edge cases where a pointer still lands on the canvas).
    if (ref.read(anyDraftSessionOpenProvider)) {
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

  /// Schedule a viewport-preserving reflow for the next frame — the
  /// counterpart to [_scheduleFit] taken when the canvas pane changes size
  /// (a tool panel opened/closed/switched) while the user has a manually
  /// adjusted zoom/pan. Keeps the user's scale, re-centres on the same
  /// canvas detail, and re-clamps translation to the new pane instead of
  /// re-fitting. Deferred to the post-frame callback for the same reason
  /// [_scheduleFit] is: the viewport provider must not be mutated during
  /// build. Only reached after [_fittedOnce], so no visibility gate is
  /// involved.
  void _schedulePreserveViewport(Size oldScreen, Size newScreen, Size docSize) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(viewportControllerProvider.notifier)
          .reflowPreservingZoom(
            oldScreen: oldScreen,
            newScreen: newScreen,
            canvasSize: docSize,
          );
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
    final maskEditActive = ref.watch(
      maskEditControllerProvider.select((s) => s.active),
    );
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
          final userAdjusted = ref
              .read(viewportControllerProvider.notifier)
              .userAdjusted;
          if (_fittedOnce &&
              userAdjusted &&
              !docChanged &&
              prevScreen != null) {
            _schedulePreserveViewport(prevScreen, screen, docSize);
          } else {
            _scheduleFit(screen, docSize);
          }
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
          onPointerDown: (e) {
            // Raw sequence bookkeeping FIRST (see [_rawPointersDown]).
            // This runs after every deeper recogniser has already seen
            // the down event, so claim predicates observed the set
            // WITHOUT the current pointer — exactly the "is another
            // finger already down?" question they need answered.
            _rawPointersDown.add(e.pointer);
            _onMultiTapPointerDown(e);
          },
          onPointerMove: _onMultiTapPointerMove,
          onPointerUp: (e) {
            _rawPointersDown.remove(e.pointer);
            _onMultiTapPointerUp(e);
          },
          onPointerCancel: (e) {
            _rawPointersDown.remove(e.pointer);
            _onMultiTapPointerCancel(e);
            ref.read(interactionControllerProvider.notifier).cancel();
            // The cancelled session may have been the select-and-move
            // surface's; clear the ownership flag so the selection
            // overlay's isActive claim branch is not permanently
            // fenced off.
            _selectAndMoveOwnsSession = false;
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
            // pointer that reaches this detector — taps on empty
            // canvas and on un-selected layers. Long-press over the
            // SELECTED layer never reaches here (its body surface
            // claims the arena on down); the body recogniser's own
            // long-press timer re-injects that intent via
            // [onBodyLongPress] → the same [_handleLongPress].
            //
            // NOTE: deliberately NO onDoubleTapDown here. Registering
            // it would put a DoubleTapGestureRecognizer in the arena,
            // which holds every plain tap hostage for the ~300ms
            // double-tap timeout before onTapUp can fire — the audit's
            // "first tap feels laggy" finding. Double-tap detection
            // lives in [_handleTap]'s window bookkeeping instead, so
            // single taps resolve instantly.
            onLongPressStart: (d) {
              _handleLongPress(d.globalPosition, doc.layers);
            },
            // Background pan + pinch-to-zoom for the viewport. Layer body
            // recognisers sit deeper in the tree and win the gesture arena
            // only when the first finger lands on the selection's chrome
            // quad (contract §5 row 4); touches off the quad — including
            // whole sequences while a selection exists — fall through to
            // this handler, which is what makes rows 6 (two-finger always
            // navigates) and 7 (off-layer drag pans) work.
            //
            // Exclusivity backstop (kept deliberately after the tb3 1/7
            // re-routing): skipping start/update while an interaction
            // session is active prevents the viewport from panning or
            // zooming "alongside" an object transform in split-ownership
            // races — e.g. finger A rests off-quad (unclaimed, sub-slop)
            // while finger B starts a body session on the quad; when A
            // finally moves, this recogniser wins A's arena and would
            // otherwise pan under the live transform. During a normal
            // off-quad pinch no session exists (`isActive` is false), so
            // this guard never blocks legitimate viewport navigation.
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
              // Body-LOCAL, not global: the viewport `translation` this
              // focal is solved against is defined by `fit()` from the
              // LayoutBuilder's `constraints.biggest` (this GestureDetector's
              // own box). `d.focalPoint` is global, so mixing it with a
              // body-local translation drifts the anchored canvas point by
              // the AppBar/status-bar offset during zoom. `localFocalPoint`
              // shares translation's origin. (Pan is delta-based so the
              // offset cancels — only scale exposed the bug.)
              _gestureStartFocal = d.localFocalPoint;
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
              // Body-local to match `_gestureStartFocal` and the viewport
              // translation space (see onScaleStart).
              final effectiveFocal = settings.canvasPanEnabled
                  ? d.localFocalPoint
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
            // v2 workspace: a step deeper than the chrome's surface
            // (warm in light, deep ink in dark — never pure black)
            // so the bars/panels visibly float above it and the
            // canvas floats on it.
            child: ColoredBox(
              color: AppTokens.of(context).workspace,
              child: ClipRect(
                // Keyed so the paint surface can map global pointer
                // positions into this box's local space — the space
                // `viewport.translation` lives in (see
                // [_viewportBodyKey]).
                key: _viewportBodyKey,
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
                            // Snapshot boundary for the colour
                            // picker's eyedropper: sits inside the
                            // viewport transform so a capture is
                            // 1 px per logical canvas unit at any
                            // zoom. The dim mask + border framing
                            // paint above (outside) it, so samples
                            // are the raw design colours.
                            child: RepaintBoundary(
                              key: ref.watch(canvasBoardBoundaryKeyProvider),
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
                                        : BackgroundFillBox(
                                            fill: doc.background,
                                          ),
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
                                    viewportBodyKey: _viewportBodyKey,
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
                      // Select-and-move claim surface (contract §5
                      // row 5) — BELOW the selection overlays so the
                      // selected layer's chrome quad, handles and
                      // group quad always outrank it, and mounted
                      // unconditionally so the mid-gesture selection
                      // switch never disposes its recogniser. Mode
                      // gating lives in its claim predicate.
                      _buildSelectAndMoveSurface(doc.layers),
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
                      // Floating text quick-capsule (re-added,
                      // redesigned): a lean edit/font/size/color/more
                      // pill over the selection. THE one floating
                      // quick-capsule (tb2 9/16): registry-derived
                      // per-type accelerators routing to the SAME
                      // surfaces the bottom bar opens — quick
                      // in-place access, not a second full bar. The
                      // protected base photo keeps its badge and
                      // gets NO capsule.
                      if (selection.count == 1 &&
                          !_isProtectedSelection(doc, selection) &&
                          !addTextComposerOpen &&
                          !maskEditActive)
                        _buildQuickCapsule(doc.layers, selection, viewport),
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
                      if (maskEditActive) MaskEditOverlay(viewport: viewport),
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

  /// Build the always-mounted select-and-move surface (contract §5
  /// row 5). Mounted UNCONDITIONALLY below the selection overlays so
  /// the mid-gesture selection switch (which remounts the overlay)
  /// never disposes the recogniser owning the in-flight pointers;
  /// every mode gate lives in the claim predicate instead.
  Widget _buildSelectAndMoveSurface(List<EditorLayer> layers) {
    return SelectAndMoveSurface(
      shouldClaimBody: (globalPosition) =>
          _shouldClaimSelectAndMove(layers, globalPosition),
      onBody: (update) {
        final controller = ref.read(interactionControllerProvider.notifier);
        final focalCanvas = _toCanvas(update.focalGlobal);
        switch (update.phase) {
          case DragPhase.start:
            // The slop claim: select the candidate and begin its
            // translate session in the same gesture. Selection is a
            // provider write, not a document command, so the whole
            // select-and-move lands as ONE undo entry (the transform
            // commit).
            final candidate = _selectAndMoveCandidate;
            _selectAndMoveCandidate = null;
            if (candidate == null) return;
            _selectAndMoveOwnsSession = true;
            ref.read(selectionControllerProvider.notifier).select(candidate.id);
            controller.startGesture(layer: candidate, focalPoint: focalCanvas);
          case DragPhase.update:
            controller.updateGesture(
              focalPoint: focalCanvas,
              scale: update.scale,
              rotation: update.rotation,
              pointerCount: update.pointerCount,
            );
          case DragPhase.end:
            controller.end();
            _selectAndMoveOwnsSession = false;
        }
      },
    );
  }

  /// Claim predicate for the select-and-move surface. `true` only for
  /// a first finger landing on an eligible, movable, un-selected
  /// layer's RAW bbox (no outset — the outset ring is selection
  /// chrome and belongs to the selected layer's overlay) while the
  /// editor is in plain single-select interaction state.
  bool _shouldClaimSelectAndMove(
    List<EditorLayer> layers,
    Offset globalPosition,
  ) {
    // First-finger-wins backstop + row 6: never join a sequence the
    // viewport (or anyone else) already owns a finger of.
    if (_gestureStartViewport != null) return false;
    if (_rawPointersDown.isNotEmpty) return false;
    // A live session is never ours to re-claim here: mid-session
    // fingers join through the recogniser's own unconditional-accept
    // path, and off-canvas recovery belongs to the selection overlay.
    if (ref.read(interactionControllerProvider).isActive) return false;
    // Row 5 is a single-select gesture by definition. Multi mode
    // keeps today's behaviour exactly (group quad or viewport).
    if (ref.read(selectionModeProvider) == SelectionMode.multi) return false;
    // Surface-ownership gates, mirroring the selection overlay's
    // claim predicate plus the modes that only matter because this
    // surface is mounted permanently (paint / inline edit / add-text
    // composer own the canvas while the overlays are unmounted).
    if (ref.read(cropControllerProvider).active) return false;
    if (ref.read(maskEditControllerProvider).active) return false;
    if (ref.read(paintToolControllerProvider).activeTool != null) return false;
    if (ref.read(editingControllerProvider) != null) return false;
    if (ref.read(addTextComposerOpenProvider)) return false;

    final local = _toCanvas(globalPosition);
    final selection = ref.read(selectionControllerProvider);
    EditorLayer? selectedLayer;
    if (selection.selectedId != null) {
      for (final l in layers) {
        if (l.id == selection.selectedId) {
          selectedLayer = l;
          break;
        }
      }
    }
    // The selected layer's chrome quad (bbox + outset ring) belongs
    // to the selection overlay above — including where another layer
    // overlaps it. Declining here keeps the two surfaces' claims
    // mutually exclusive.
    if (selectedLayer != null && _pointInChromeQuad(selectedLayer, local)) {
      return false;
    }
    final hits = _hitTestAll(layers, local);
    if (hits.isEmpty) return false;
    // Topmost eligible layer only — the same layer a tap here would
    // select. Deliberately NOT drilling further down: dragging must
    // never move a layer the equivalent tap would not have picked.
    final top = hits.first;
    if (top.id == selection.selectedId) return false;
    if (!top.capabilities.movable) return false;
    _selectAndMoveCandidate = top;
    return true;
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
          // Contract §5 rows 4/6/7 (chrome-quad claim model): the
          // body recogniser claims a FIRST finger only when it lands
          // on the selection's chrome quad — the rotated bbox plus
          // the drawn handle outset — or when a transform session is
          // already running. Everything else falls through to the
          // viewport, so:
          //
          //   * 1 finger ON the quad  → translates the selected layer
          //     (eager claim-and-start; off-canvas recovery depends
          //     on the layer responding from the very first frame)
          //   * 2 fingers, first ON the quad → pinch + rotate the
          //     layer (the second finger may land anywhere — pinching
          //     a small object never requires both fingers inside it)
          //   * 1 finger OFF the quad → viewport pan; the selection
          //     stays (row 7 — 3.2 adds select-and-move)
          //   * 2 fingers, first OFF the quad → viewport pinch, even
          //     with a selection (row 6 — two-finger gestures ALWAYS
          //     navigate)
          //   * a true tap ON the quad is forwarded via [onBodyTap]
          //     → `_handleTap` (overlapping-layer cycling); taps and
          //     long-presses OFF the quad reach the canvas-level
          //     recognisers natively now that nothing claims them.
          //
          // First-finger-wins backstop: if a viewport pan/pinch is
          // already in flight, refuse new pointers so a half-finished
          // viewport gesture can complete cleanly.
          shouldClaimBody: (globalPosition) {
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
            // Mid-session claim: a live transform keeps the surface
            // (off-canvas recovery — the finger may wander anywhere).
            // EXCEPT when the session belongs to the select-and-move
            // surface one Stack level below: new fingers must fall
            // through to the recogniser that owns the in-flight
            // pointers, or they would restart the session up here.
            if (ref.read(interactionControllerProvider).isActive) {
              return !_selectAndMoveOwnsSession;
            }
            // Sequence continuation (row 6): another finger is
            // already down and was NOT claimed by this recogniser
            // (else isActive would be true / _pointers non-empty and
            // this first-pointer gate would not run). The sequence
            // belongs to the viewport — later fingers must join the
            // pinch even if they land on the quad.
            if (_rawPointersDown.isNotEmpty) return false;
            return _pointInChromeQuad(selectedLayer, _toCanvas(globalPosition));
          },
          // Defer-start gate: EVERY claimed pointer defers the
          // session start until movement past slop or a second
          // finger (tb3 3/7 — the eager on-bbox start is gone).
          // Claiming and starting are different promises:
          //
          //   * the arena CLAIM still happens on pointer-down, so
          //     off-canvas recovery keeps its guarantee (nothing can
          //     steal the pointer) and a second finger still joins
          //     the layer pinch (small-object pinch);
          //   * the session START waits for slop — at most
          //     kTouchSlop of dead travel, the same standard as
          //     every other drag in the editor.
          //
          // Deferring on the bbox itself is what revives the
          // stationary intents ON the selected layer:
          //
          //   * pure tap        → [onBodyTap] → cycling / double-tap
          //                       window (edit for text)
          //   * pure long-press → the recogniser's timer fires (no
          //                       session started) → [onBodyLongPress]
          //                       → enter multi-select with the
          //                       selected layer — previously dead
          //                       because the eager start
          //                       short-circuited the timer.
          shouldDeferStartBody: (_) => true,
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
                // Handles claim on pointer-down, so a handle session
                // can supersede any prior owner; make sure the
                // select-and-move ownership flag never lingers.
                _selectAndMoveOwnsSession = false;
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
          // Chrome-quad claim model for multi-select (contract §5
          // rows 4/6/7 — see the single-layer overlay above for the
          // full rationale). The group's chrome quad is its
          // axis-aligned bounds inflated by the drawn handle outset:
          // a first pointer ON that quad drives the group's
          // rigid-body translate (a second finger anywhere then
          // drives pinch + rotate around the gesture focal); a first
          // pointer OFF it falls through to the viewport. A true tap
          // ON the quad is forwarded via [onBodyTap] for selection
          // routing (toggle-in / toggle-out / mode exit).
          shouldClaimBody: (globalPosition) {
            if (_gestureStartViewport != null) return false;
            final cropActive = ref.read(cropControllerProvider).active;
            if (cropActive) return false;
            // Mask-edit mode: the overlay owns the region + handles;
            // yielding lets outside-region pointers fall through to
            // viewport pan/zoom.
            if (ref.read(maskEditControllerProvider).active) return false;
            // Mid-session claim (off-canvas recovery), then the
            // row-6 sequence-continuation refusal — same order and
            // rationale as the single-layer overlay (including the
            // select-and-move ownership carve-out).
            if (ref.read(interactionControllerProvider).isActive) {
              return !_selectAndMoveOwnsSession;
            }
            if (_rawPointersDown.isNotEmpty) return false;
            return bounds
                .inflate(_chromeOutsetCanvas())
                .contains(_toCanvas(globalPosition));
          },
          // Defer-start gate: claimed pointers landing in the outset
          // ring (inside the chrome quad, outside the group's
          // axis-aligned bbox) defer the session start until movement
          // past slop or a second finger. Same rationale as the
          // single-layer overlay — preserves tap (toggle / mode exit)
          // and long-press (extend) intents on the frame edge.
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
                // See the single-layer overlay's onHandle: handles
                // claim on down and supersede any prior session owner.
                _selectAndMoveOwnsSession = false;
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

  /// Floating text quick-capsule for the selected (non-sticker) text
  /// layer. Hidden while a transform gesture is in flight, while the
  /// inline editor is active, and while any text dock sheet or
  /// context panel is open — it just opened that surface; stacking
  /// on top of it would be noise. Emoji stickers are excluded (they
  /// carry no text flow; the generic quick-actions pill serves them).
  /// THE one floating quick-capsule builder (tb2 9/16) — the five
  /// per-type builders collapsed to one. Per-type contents live in
  /// [QuickCapsule]'s registry; this builder owns only the guards
  /// every old builder shared:
  ///   * inline edit on the selected layer (text) hides it,
  ///   * an in-flight transform session hides it (never chase a
  ///     moving selection),
  ///   * the shared [canvasChromeSuppressedProvider] signal
  ///     (tb1 15/17) hides ALL floating chrome uniformly.
  Widget _buildQuickCapsule(
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
        final inSession = ref.watch(
          interactionControllerProvider.select(
            (s) => s.session?.layerId == selectedLayer.id,
          ),
        );
        if (inSession) return const SizedBox.shrink();
        if (ref.watch(canvasChromeSuppressedProvider)) {
          return const SizedBox.shrink();
        }
        return QuickCapsule(layer: selectedLayer, viewport: viewport);
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

  /// The selection chrome's screen-space outset converted into canvas
  /// units at the current zoom. The overlay outsets its frame quad by
  /// [EngineConstants.selectionOutset] SCREEN pixels along the rotated
  /// axes ([outsetSelectionQuad] in `selection_overlay.dart`); since
  /// the viewport map is conformal (uniform scale + translation, no
  /// rotation), the same quad expressed in canvas space is the layer
  /// rect inflated by `outset / viewport.scale`.
  double _chromeOutsetCanvas() {
    final scale = ref.read(viewportControllerProvider).scale;
    if (!scale.isFinite || scale <= 0) return EngineConstants.selectionOutset;
    return EngineConstants.selectionOutset / scale;
  }

  /// True iff [point] (canvas-space) lands on [layer]'s selection
  /// CHROME QUAD — the rotated bbox inflated by the handle outset the
  /// overlay actually draws. This is the contract §5 row 4 claim test:
  /// deliberately the drawn geometry, not the raw bbox, so grabbing
  /// the frame edge between two handles still counts as "on the
  /// selection". Pure canvas-space math (no widget bounds), so it
  /// extrapolates correctly for layers dragged partly or fully off
  /// the canvas — the off-canvas recovery grab keeps working.
  bool _pointInChromeQuad(EditorLayer layer, Offset point) {
    final t = layer.transform;
    final local = LayerSpaceMapper(
      transform: t,
      viewport: ViewportState.identity,
    ).canvasToLayer(point);
    final o = _chromeOutsetCanvas();
    return local.dx >= -o &&
        local.dy >= -o &&
        local.dx <= t.size.width + o &&
        local.dy <= t.size.height + o;
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
      // Double-tap has no meaning here either; rapid toggle taps
      // must never be swallowed by the window.
      _resetTapCycle();
      _disarmDoubleTapWindow();
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
      _disarmDoubleTapWindow();
      return;
    }

    // Double-tap check — BEFORE the cycling logic, deliberately.
    // A second tap inside the window, near the first tap, landing on
    // the layer that first tap selected is a double-tap: text opens
    // its editor, everything else is simply consumed. Consuming it
    // means tap-cycling through overlapping layers now requires the
    // 400ms window to expire between taps — that is the accepted
    // trade-off for making double-tap deterministic: without it the
    // second tap of a double could cycle the selection to the layer
    // BENEATH and the edit intent would hit the wrong layer.
    final armedId = _doubleTapArmedLayerId;
    final armedGlobal = _doubleTapArmedGlobal;
    if (armedId != null &&
        armedGlobal != null &&
        (globalPosition - armedGlobal).distance <= kDoubleTapSlop) {
      EditorLayer? armedLayer;
      for (final l in hits) {
        if (l.id == armedId) {
          armedLayer = l;
          break;
        }
      }
      if (armedLayer != null) {
        _disarmDoubleTapWindow();
        _handleDoubleTap(armedLayer);
        return;
      }
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
    // Every completed single tap arms the double-tap window on the
    // layer it just selected.
    _armDoubleTapWindow(hits[index].id, globalPosition);
  }

  /// Second tap of a double (see the window check in [_handleTap]).
  ///
  /// Double-tap IS the on-canvas edit affordance for text (text-tool
  /// redesign step 1): the floating pill that used to own "edit" is
  /// gone, so double-tapping a text layer opens the keyboard editor.
  /// Emoji stickers stay excluded — they're TextLayers but have no
  /// editable text flow. Non-editable layers: the double-tap is
  /// consumed with no effect beyond the selection the first tap
  /// already made (in particular it must NOT cycle underneath).
  void _handleDoubleTap(EditorLayer layer) {
    if (!layer.capabilities.editable) return;
    if (layer is TextLayer) {
      if (layer.isSticker) return;
      ref.read(selectionControllerProvider.notifier).select(layer.id);
      unawaited(showEditTextLayerFlow(context, ref, layer));
      return;
    }
    ref.read(selectionControllerProvider.notifier).select(layer.id);
    ref.read(editingControllerProvider.notifier).start(layer.id);
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

/// Multi-select mode chip: count readout + the mode's visible EXIT
/// (tb3 5/7 — the audit's "no visible way out"). Renders nothing at
/// all in single mode so the canvas chrome stays untouched. Sits
/// inside the screen-space chrome stack so it never scales with
/// viewport zoom; top-START (directional) so it mirrors under RTL.
///
/// The whole capsule is one tap target (44dp floor via a transparent
/// halo, ModeDoneButton's pattern) and the trailing ✕ is what makes
/// it read as dismissible. Exit keeps the PRIMARY selection and drops
/// to single mode — the same landing state the editor's own <2-member
/// prune rule produces. Long-press-to-enter and tap-on-empty-to-exit
/// keep working unchanged; this is the discoverable path.
class _MultiSelectModeChip extends ConsumerWidget {
  const _MultiSelectModeChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(selectionModeProvider);
    if (mode != SelectionMode.multi) return const SizedBox.shrink();
    final count = ref.watch(selectionControllerProvider.select((s) => s.count));
    final tokens = AppTokens.of(context);
    return PositionedDirectional(
      // The 44dp hit halo centres the painted ~26dp pill, so 4/8 here
      // lands the visible capsule near the old 12/12 spot.
      top: 4,
      start: 8,
      child: Semantics(
        button: true,
        label: context.l10n.multiSelectExit,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('multi-select-exit-chip'),
            borderRadius: BorderRadius.circular(999),
            onTap: () {
              HapticFeedback.selectionClick().catchError((_) {});
              // Keep the primary, drop the rest, leave the mode —
              // matching what the <2-member flows land on.
              final primary = ref.read(selectionControllerProvider).selectedId;
              ref.read(selectionModeProvider.notifier).exitMulti();
              if (primary != null) {
                ref.read(selectionControllerProvider.notifier).select(primary);
              }
            },
            child: Container(
              constraints: const BoxConstraints(
                minWidth: kMinHitTarget,
                minHeight: kMinHitTarget,
              ),
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: tokens.brand.withValues(alpha: 0.92),
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
                      color: tokens.onBrand,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.l10n.multiSelectCount(count),
                      style: TextStyle(
                        color: tokens.onBrand,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.close_rounded, size: 14, color: tokens.onBrand),
                  ],
                ),
              ),
            ),
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
    final tokens = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.brand.withValues(alpha: 0.92),
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
          Icon(Icons.lock_outline, size: 12, color: tokens.onBrand),
          const SizedBox(width: 4),
          Text(
            context.l10n.basePhotoLabel,
            style: TextStyle(
              color: tokens.onBrand,
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
