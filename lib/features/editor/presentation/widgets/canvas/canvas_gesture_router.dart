import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../settings/application/settings_controller.dart';
import '../../../application/editing_controller.dart';
import '../../../application/document_controller.dart';
import '../../../application/editor_lifecycle.dart';
import '../../../application/interaction_controller.dart';
import '../../../application/mask_edit_controller.dart';
import '../../../application/selection_controller.dart';
import '../../../application/viewport_controller.dart';
import '../../../crop/application/crop_controller.dart';
import '../../../engine/core/editor_layer.dart';
import '../../../engine/core/viewport_state.dart';
import '../../../engine/modules/text/text_layer.dart';
import '../../../paint/application/paint_tool_controller.dart';
import '../../../text/application/add_text_composer_state.dart';
import '../../../text/presentation/text_edit_flow.dart';
import '../selection_overlay.dart';
import 'canvas_hit_testing.dart' as geom;

/// Routes raw canvas pointers to the right owner.
///
/// Everything that decides *who* a touch belongs to lives here: the
/// raw-sequence bookkeeping the claim predicates read, the tap /
/// double-tap / long-press window, the chrome-quad and stem-capsule
/// hit tests, the select-and-move claim surface, and the two-finger
/// viewport pan/pinch path. The canvas widget owns the wiring (the
/// outer `Listener` and background `GestureDetector`); the chrome
/// overlays consult this object for their own claim predicates so all
/// three surfaces answer from one set of facts.
///
/// State is deliberately plain fields on a long-lived object rather
/// than providers: these are per-gesture facts read synchronously
/// inside claim predicates, where a provider round-trip would be both
/// slower and observable by unrelated rebuilds.
class CanvasGestureRouter {
  CanvasGestureRouter({
    required WidgetRef ref,
    required GlobalKey boardKey,
    required BuildContext Function() hostContext,
  }) : _ref = ref,
       _boardKey = boardKey,
       _hostContext = hostContext;

  final WidgetRef _ref;

  /// Key on the inner document board. A `RenderBox.globalToLocal` on
  /// that box automatically walks the viewport transform, which is
  /// what [toCanvas] relies on.
  final GlobalKey _boardKey;

  /// The canvas widget's own `BuildContext` — deliberately the host's,
  /// not whichever `Consumer` happens to invoke a callback, so the
  /// text-edit flow always opens against the same element.
  final BuildContext Function() _hostContext;

  /// Captured at the start of a background pan/pinch so the controller can
  /// solve for the correct translation that keeps the focal point fixed.
  ViewportState? _gestureStartViewport;
  Offset? _gestureStartFocal;

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

  /// Claim candidate for the select-and-move surface: either the
  /// eligible, movable, un-selected layer the pointer went down on
  /// (row 5) or — when the pointer landed on empty canvas while a
  /// movable single selection exists — the selected layer itself
  /// (row 7's drag-anywhere amendment). Stashed by the
  /// [SelectAndMoveSurface] claim predicate at pointer-down and
  /// consumed exactly once at [DragPhase.start] (the slop claim),
  /// which is the moment the layer becomes selected (a no-op for the
  /// row-7 case) and its translate session begins. A sub-slop release
  /// never consumes it — the pointer is handed back to the canvas tap
  /// recognisers and the stale value is simply overwritten by the
  /// next claim.
  EditorLayer? _selectAndMoveCandidate;

  /// True while the live interaction session was started by the
  /// select-and-move surface. Disambiguates the `isActive` claim
  /// branches: a new finger landing during a row-5 session must fall
  /// THROUGH the selection overlay's body surface (which now belongs
  /// to the same, freshly selected layer) so it joins the recogniser
  /// that actually owns the in-flight pointers, one Stack level
  /// below. Reset on session end and on OS pointer-cancel.
  bool _selectAndMoveOwnsSession = false;

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
  /// Stored on the router so the cycling is presentation-only; no
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
  // bookkeeping inside [handleTap] — a second tap landing within
  // [_doubleTapWindow] of the previous tap, within [kDoubleTapSlop]
  // of its position, on the SAME layer the previous tap selected, is
  // a double-tap. Because both tap entry paths (the canvas detector
  // AND the selection overlay's re-injected [onBodyTap]) route
  // through [handleTap], double-tap works identically on selected
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

  void dispose() {
    _doubleTapWindowTimer?.cancel();
  }

  // ------------------------------------------------------------------
  // Facts the chrome overlays' claim predicates read.
  // ------------------------------------------------------------------

  /// True while a background viewport pan/pinch owns the sequence —
  /// the first-finger-wins backstop every claim predicate opens with.
  bool get viewportGestureInFlight => _gestureStartViewport != null;

  /// True when another finger of the current physical sequence is
  /// already down (see [_rawPointersDown]).
  bool get hasRawPointersDown => _rawPointersDown.isNotEmpty;

  /// True while the live interaction session belongs to the
  /// select-and-move surface (see [_selectAndMoveOwnsSession]).
  bool get selectAndMoveOwnsSession => _selectAndMoveOwnsSession;

  /// Handles claim on pointer-down, so a handle session can supersede
  /// any prior owner; the overlays call this to make sure the
  /// select-and-move ownership flag never lingers.
  void clearSelectAndMoveOwnership() {
    _selectAndMoveOwnsSession = false;
  }

  Offset toCanvas(Offset global) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return global;
    return box.globalToLocal(global);
  }

  /// The selection chrome's screen-space outset in canvas units at the
  /// current zoom. Supplies `canvas_hit_testing`'s pure geometry with
  /// the one provider read it deliberately does not make itself.
  double chromeOutset() =>
      geom.chromeOutsetCanvas(_ref.read(viewportControllerProvider).scale);

  /// Contract §5 row 4 claim test — see `pointInChromeQuad` in
  /// `canvas_hit_testing.dart`.
  bool pointInChromeQuad(EditorLayer layer, Offset point) =>
      geom.pointInChromeQuad(
        layer,
        point,
        _ref.read(viewportControllerProvider).scale,
      );

  // ------------------------------------------------------------------
  // Raw pointer bookkeeping, driven by the canvas' outer [Listener].
  // ------------------------------------------------------------------

  /// Registers a pointer in [_rawPointersDown]. Must run before any
  /// other work the canvas' [Listener] does for the same event — see
  /// the call site's comment for why the ordering matters.
  void trackPointerDown(PointerDownEvent e) {
    _rawPointersDown.add(e.pointer);
  }

  void trackPointerUp(PointerUpEvent e) {
    _rawPointersDown.remove(e.pointer);
  }

  void trackPointerCancel(PointerCancelEvent e) {
    _rawPointersDown.remove(e.pointer);
  }

  /// Reaction to an OS-issued pointer cancellation, after the raw
  /// bookkeeping and the multi-tap window have both seen the event.
  void handleOsPointerCancel() {
    _ref.read(interactionControllerProvider.notifier).cancel();
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
  }

  // ------------------------------------------------------------------
  // Two-finger viewport path (background pan + pinch-to-zoom).
  // ------------------------------------------------------------------

  void onScaleStart(ScaleStartDetails d) {
    if (_ref.read(interactionControllerProvider).isActive) return;
    // Paint mode suppresses viewport pan/zoom — the gesture
    // belongs to the drawing surface above.
    if (_ref.read(paintToolControllerProvider).activeTool != null) {
      return;
    }
    final s = _ref.read(appSettingsProvider);
    if (!s.canvasPanEnabled && !s.canvasZoomEnabled) return;
    _gestureStartViewport = _ref.read(viewportControllerProvider);
    // Body-LOCAL, not global: the viewport `translation` this
    // focal is solved against is defined by `fit()` from the
    // LayoutBuilder's `constraints.biggest` (this GestureDetector's
    // own box). `d.focalPoint` is global, so mixing it with a
    // body-local translation drifts the anchored canvas point by
    // the AppBar/status-bar offset during zoom. `localFocalPoint`
    // shares translation's origin. (Pan is delta-based so the
    // offset cancels — only scale exposed the bug.)
    _gestureStartFocal = d.localFocalPoint;
  }

  void onScaleUpdate(ScaleUpdateDetails d) {
    if (_ref.read(interactionControllerProvider).isActive) return;
    if (_ref.read(paintToolControllerProvider).activeTool != null) {
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
    final settings = _ref.read(appSettingsProvider);
    // Body-local to match `_gestureStartFocal` and the viewport
    // translation space (see onScaleStart).
    final effectiveFocal = settings.canvasPanEnabled
        ? d.localFocalPoint
        : focal;
    final effectiveScale = settings.canvasZoomEnabled ? d.scale : 1.0;
    _ref
        .read(viewportControllerProvider.notifier)
        .gestureUpdate(
          startState: start,
          startFocal: focal,
          currentFocal: effectiveFocal,
          scale: effectiveScale,
        );
  }

  void onScaleEnd(ScaleEndDetails d) {
    _gestureStartViewport = null;
    _gestureStartFocal = null;
  }

  // ------------------------------------------------------------------
  // Background tap entry.
  // ------------------------------------------------------------------

  void onBackgroundTapUp(Offset globalPosition, List<EditorLayer> layers) {
    // Paint mode owns the canvas — the paint surface (mounted
    // inside the viewport transform) handles taps that land
    // on the canvas itself. Taps that land OUTSIDE the canvas
    // (pasteboard / black area) reach this background
    // detector and must dismiss paint mode through the same
    // central seam, so the user has a way out without having
    // to first navigate back to the canvas. Drawing is a pan
    // gesture and never routes through onTapUp, so this is
    // safe mid-session.
    if (_ref.read(paintToolControllerProvider).activeTool != null) {
      dismissActiveEditing(_ref);
      return;
    }
    _ref.read(editingControllerProvider.notifier).stop();
    handleTap(globalPosition, layers);
  }

  // ------------------------------------------------------------------
  // Select-and-move + drag-anywhere (contract §5 rows 5 and 7).
  // ------------------------------------------------------------------

  /// Build the always-mounted select-and-move surface (contract §5
  /// rows 5 and 7). Mounted UNCONDITIONALLY below the selection
  /// overlays so the mid-gesture selection switch (which remounts the
  /// overlay) never disposes the recogniser owning the in-flight
  /// pointers; every mode gate lives in the claim predicate instead.
  Widget buildSelectAndMoveSurface(List<EditorLayer> layers) {
    return SelectAndMoveSurface(
      shouldClaimBody: (globalPosition) =>
          _shouldClaimSelectAndMove(layers, globalPosition),
      onBody: (update) {
        final controller = _ref.read(interactionControllerProvider.notifier);
        final focalCanvas = toCanvas(update.focalGlobal);
        switch (update.phase) {
          case DragPhase.start:
            // The slop claim: select the candidate and begin its
            // translate session in the same gesture. Selection is a
            // provider write, not a document command, so the whole
            // select-and-move lands as ONE undo entry (the transform
            // commit). In the row-7 drag-anywhere case the candidate
            // IS the current selection and `select` is a no-op.
            final candidate = _selectAndMoveCandidate;
            _selectAndMoveCandidate = null;
            if (candidate == null) return;
            _selectAndMoveOwnsSession = true;
            _ref
                .read(selectionControllerProvider.notifier)
                .select(candidate.id);
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

  /// Claim predicate for the select-and-move surface. `true` for a
  /// first finger landing either
  ///
  ///   * on an eligible, movable, un-selected layer's RAW bbox
  ///     (row 5 — no outset: the outset ring is selection chrome and
  ///     belongs to the selected layer's overlay), or
  ///   * on EMPTY canvas / pasteboard while a movable single
  ///     selection exists (row 7's drag-anywhere amendment — the
  ///     drag translates the selection, so a small or
  ///     finger-occluded object can be repositioned without hitting
  ///     it precisely),
  ///
  /// while the editor is in plain single-select interaction state.
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
    if (_ref.read(interactionControllerProvider).isActive) return false;
    // Row 5 is a single-select gesture by definition. Multi mode
    // keeps today's behaviour exactly (group quad or viewport).
    if (_ref.read(selectionModeProvider) == SelectionMode.multi) return false;
    // Surface-ownership gates, mirroring the selection overlay's
    // claim predicate plus the modes that only matter because this
    // surface is mounted permanently (paint / inline edit / add-text
    // composer own the canvas while the overlays are unmounted).
    if (_ref.read(cropControllerProvider).active) return false;
    if (_ref.read(maskEditControllerProvider).active) return false;
    if (_ref.read(paintToolControllerProvider).activeTool != null) return false;
    if (_ref.read(editingControllerProvider) != null) return false;
    if (_ref.read(addTextComposerOpenProvider)) return false;

    final local = toCanvas(globalPosition);
    final selection = _ref.read(selectionControllerProvider);
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
    // mutually exclusive. A HIDDEN selection renders no overlay
    // (buildSelectionOverlay's gate, ux-audit P2-6), so there is no
    // quad to reserve: its area must read like any other point —
    // row 5 for an eligible layer underneath, else row 7 / viewport.
    if (selectedLayer != null &&
        selectedLayer.visible &&
        pointInChromeQuad(selectedLayer, local)) {
      return false;
    }
    final hits = geom.hitTestAllLayers(layers, local);
    if (hits.isEmpty) {
      // Row 7, amended (drag-anywhere): no pointer-eligible layer
      // under the finger — empty canvas, the pasteboard, or a
      // locked/hidden layer's area (pointer-INeligible, so its
      // surface reads as background; in a photo project that is the
      // whole base photo). While a movable single selection exists,
      // a drag here translates THAT selection instead of panning the
      // viewport: precise grabs fail exactly when the object is
      // small, under the finger, or the canvas is zoomed out, and
      // deselect-then-pan / two-finger navigation both remain one
      // gesture away. The claim is lazy (start defers to slop), so a
      // tap here still deselects (E3) and a hold still enters
      // multi-select — only real movement takes the pointer.
      //
      // The old active-transform-surface model died for three
      // reasons (toolbar-redesign-audit §gestures); none returns
      // here: zooming while selected stays possible (row 6 —
      // a pre-slop second finger abandons this claim to the
      // viewport pinch), dragging another layer still moves THAT
      // layer (row 5 outranks this fallback), and only the
      // remaining case — empty-space drags, where the viewport pan
      // was the sole competitor — trades pan for selection drag.
      // Locked (protected base photo) and hidden selections decline,
      // so photo navigation while the base is selected keeps
      // today's pan.
      final sel = selectedLayer;
      if (sel == null) return false;
      if (sel.locked || !sel.visible || !sel.capabilities.movable) {
        return false;
      }
      _selectAndMoveCandidate = sel;
      return true;
    }
    // Topmost eligible layer only — the same layer a tap here would
    // select. Deliberately NOT drilling further down: dragging must
    // never move a layer the equivalent tap would not have picked.
    // An eligible-but-unmovable top hit also declines the row-7
    // fallback for the same reason: the finger is on a real object a
    // tap would pick; moving a DIFFERENT layer under it would be a
    // surprise.
    final top = hits.first;
    if (top.id == selection.selectedId) return false;
    if (!top.capabilities.movable) return false;
    _selectAndMoveCandidate = top;
    return true;
  }

  // ------------------------------------------------------------------
  // Tap / double-tap / long-press routing.
  // ------------------------------------------------------------------

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
  void handleTap(Offset globalPosition, List<EditorLayer> layers) {
    final selectionCtl = _ref.read(selectionControllerProvider.notifier);
    final mode = _ref.read(selectionModeProvider);
    final local = toCanvas(globalPosition);
    final hits = geom.hitTestAllLayers(layers, local);

    if (mode == SelectionMode.multi) {
      // Multi-select mode tap routing — cycling is intentionally
      // disabled because it would compete with toggle semantics
      // (a 2nd tap on the same spot would both cycle AND toggle).
      // Double-tap has no meaning here either; rapid toggle taps
      // must never be swallowed by the window.
      _resetTapCycle();
      _disarmDoubleTapWindow();
      if (hits.isEmpty) {
        dismissActiveEditing(_ref);
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
      // Before treating this as empty canvas: a photo project's base
      // photo is imported LOCKED, so `hitTestAllLayers` skips it and a
      // tap on the user's own photo used to fall through to "dismiss"
      // — the first thing anyone tries after importing answered with
      // nothing at all. Selecting it here is the affordance the rest
      // of the code already assumes exists: `canvas_chrome` renders
      // the "Base photo" badge and the outline-only frame for exactly
      // this state, and the dock swaps to the Image tools, so Crop and
      // Look land on-screen instead of behind the strip's scroll.
      // Move/scale/rotate stay suppressed — `buildSelectionOverlay`
      // passes `showHandles: !locked` and `onBody: null` — so this
      // grants reachability, not mutability.
      final base = _protectedBaseHitAt(local, layers);
      if (base != null) {
        // Tapping it again deselects. A base photo usually fills the
        // whole viewport, so once it became selectable there was often
        // no empty canvas left to tap and no Done pill (the protected
        // selection suppresses the HUD) — the user could reach Image
        // mode and not get back out of it. The photo has no handles
        // and no body drag, so a second tap has nothing else to mean,
        // and this is the same "re-tap the active thing to close it"
        // grammar the dock tiles already use (contract §4, E1/E3).
        if (_ref.read(selectionControllerProvider).selectedId == base.id) {
          dismissActiveEditing(_ref);
          _resetTapCycle();
          _disarmDoubleTapWindow();
          return;
        }
        selectionCtl.select(base.id);
        _resetTapCycle();
        _armDoubleTapWindow(base.id, globalPosition);
        return;
      }
      // Centralised dismiss: clears selection + collapses every
      // tool's transient sheet/panel + drops keyboard focus.
      // Saved layer data is untouched.
      dismissActiveEditing(_ref);
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

  /// The document's protected base photo when [local] (canvas space)
  /// lands inside it, else `null`.
  ///
  /// Deliberately NOT folded into `hitTestAllLayers`: that function
  /// feeds the select-and-move claim surface and the tap-cycling set,
  /// where a locked layer must stay POINTER-ineligible (contract §5
  /// row 5). Target-eligibility is the other axis and does not
  /// exclude locked — §10.2 — which is why the base photo can be
  /// cropped while staying undraggable.
  /// Only the no-other-hit tap branch consults this, so the base photo
  /// is reachable without ever becoming draggable or entering the
  /// cycle ahead of a real layer above it.
  EditorLayer? _protectedBaseHitAt(Offset local, List<EditorLayer> layers) {
    final doc = _ref.read(documentControllerProvider);
    final baseId = doc.basePhotoLayerId;
    if (baseId == null || !doc.isProtectedBasePhoto(baseId)) return null;
    for (final l in layers) {
      if (l.id != baseId) continue;
      if (!l.visible) return null;
      return geom.pointInLayerBbox(l, local) ? l : null;
    }
    return null;
  }

  /// Second tap of a double (see the window check in [handleTap]).
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
      _ref.read(selectionControllerProvider.notifier).select(layer.id);
      unawaited(showEditTextLayerFlow(_hostContext(), _ref, layer));
      return;
    }
    _ref.read(selectionControllerProvider.notifier).select(layer.id);
    _ref.read(editingControllerProvider.notifier).start(layer.id);
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
  void handleLongPress(Offset globalPosition, List<EditorLayer> layers) {
    final mode = _ref.read(selectionModeProvider);
    if (mode == SelectionMode.multi) return;
    // An armed paint session and a staged add-text composer own their
    // gesture space (§5 rows 1-3): a long-press mid-session must not
    // hijack the editor into multi-select. The paint surface only
    // covers the document board, so pasteboard presses still reach
    // this handler while a tool is armed — the same reason rows
    // 279/298/346 gate on the armed tool.
    if (_ref.read(paintToolControllerProvider).activeTool != null) return;
    if (_ref.read(addTextComposerOpenProvider)) return;

    final selectionCtl = _ref.read(selectionControllerProvider.notifier);
    final modeCtl = _ref.read(selectionModeProvider.notifier);
    final local = toCanvas(globalPosition);
    final hit = geom.hitTestTopLayer(layers, local);

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
