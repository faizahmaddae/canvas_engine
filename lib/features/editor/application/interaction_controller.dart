import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/engine_constants.dart';
import '../engine/commands/editor_command.dart';
import '../engine/commands/transform_commands.dart';
import '../engine/core/editor_document.dart';
import '../engine/core/editor_layer.dart';
import '../engine/core/layer_capabilities.dart';
import '../engine/core/layer_transform.dart';
import '../engine/core/selection_state.dart';
import '../engine/interaction/group_engine.dart';
import '../engine/interaction/interaction_engine.dart';
import '../engine/interaction/interaction_session.dart';
import '../engine/interaction/motion_smoother.dart';
import '../engine/interaction/snap_engine.dart';
import 'document_controller.dart';
import 'viewport_controller.dart';

/// Ephemeral per-gesture state. When a session is active, the canvas shows
/// the live transform; when it ends, the controller commits a single
/// undoable command.
/// Active group-gesture session.
///
/// A group session is independent of (and mutually exclusive with) a
/// single-layer [InteractionSession]. It captures the geometry needed
/// to drive *every* selected layer through a single gesture:
///
///   * [initials] — reference transforms used by the math engine to
///     compute deltas, keyed by layer id. IMPORTANT: this is NOT
///     guaranteed to be the transforms at gesture start. For
///     multi-touch group gestures, [updateGroupGesture] rebases this
///     map on every pointer-count transition (1↔≥2) to the current
///     live transforms, so a second finger landing mid-drag does not
///     cause a visible jump. Do NOT use `initials` for the commit
///     diff — compare live against the document's transforms
///     instead (see `_endGroup`);
///   * [initialBounds] — the axis-aligned union of every participant's
///     rotated rect at session start; the UI draws this rectangle
///     and the engine measures resize / rotate against it;
///   * [anchor] — the fixed point a transform pivots around (opposite
///     corner for resize, bounds centre for rotate / pinch);
///   * [pointerStart] — the gesture's starting pointer / focal in
///     canvas space;
///   * [pointerStartAngle] — the starting pointer angle around [anchor]
///     for rotate sessions; ignored otherwise.
///
/// Group sessions are translate-rigid: every layer travels by the same
/// delta during a move, scales uniformly around the same anchor during
/// a resize / pinch, and rotates by the same angle around the same
/// centre. Relative layout is therefore mathematically preserved — the
/// participants behave as one rigid body.
@immutable
class GroupGestureSession {
  const GroupGestureSession({
    required this.handle,
    required this.initials,
    required this.initialBounds,
    required this.anchor,
    required this.pointerStart,
    this.pointerStartAngle = 0,
  });

  final InteractionHandle handle;
  final Map<String, LayerTransform> initials;
  final Rect initialBounds;
  final Offset anchor;
  final Offset pointerStart;
  final double pointerStartAngle;

  GroupGestureSession copyWith({
    Offset? pointerStart,
    double? pointerStartAngle,
    Map<String, LayerTransform>? initials,
    Rect? initialBounds,
    Offset? anchor,
  }) {
    return GroupGestureSession(
      handle: handle,
      initials: initials ?? this.initials,
      initialBounds: initialBounds ?? this.initialBounds,
      anchor: anchor ?? this.anchor,
      pointerStart: pointerStart ?? this.pointerStart,
      pointerStartAngle: pointerStartAngle ?? this.pointerStartAngle,
    );
  }
}

/// Ephemeral per-gesture state. When a session is active, the canvas shows
/// the live transform; when it ends, the controller commits a single
/// undoable command.
@immutable
class InteractionUiState {
  const InteractionUiState({
    this.session,
    this.liveTransform,
    this.isRotationSnapped = false,
    this.snapGuides = const <SnapGuide>[],
    this.spacingGuides = const <SpacingGuide>[],
    this.groupSession,
    this.groupLive = const <String, LayerTransform>{},
    this.groupLiveBounds,
    this.groupLiveQuad,
  });

  /// Single-layer interaction session. Mutually exclusive with
  /// [groupSession] — at most one of them is non-null.
  final InteractionSession? session;

  /// Live (un-committed) transform applied on top of document state for the
  /// active single-layer session.
  final LayerTransform? liveTransform;

  /// True when the current rotation lies inside the snap threshold of a
  /// cardinal angle (0 / 45 / 90 / …). Drives subtle overlay feedback.
  final bool isRotationSnapped;

  /// Alignment guides currently active for the ongoing gesture. Empty when
  /// the layer is not aligned to any canvas / peer edge or center.
  final List<SnapGuide> snapGuides;

  /// Equal-spacing guides currently active for the ongoing gesture.
  /// Empty when the moved layer has not landed in an equal-gap slot
  /// between two peers. Independent of [snapGuides] — both can be
  /// active at once on different axes.
  final List<SpacingGuide> spacingGuides;

  /// Active group session, if any.
  final GroupGestureSession? groupSession;

  /// Live transforms for every group participant (including identity
  /// entries for layers that haven't moved yet). Read by every
  /// `_LayerGestureWrapper` so participants render their dragged
  /// pose without a document mutation.
  final Map<String, LayerTransform> groupLive;

  /// Cached bounds of [groupLive]. Computed once when the map is set
  /// (in [copyWith]) — never on read. Without this cache, the bounds
  /// were recomputed on every widget rebuild that watched the state,
  /// which for a 100-layer selection at 120 Hz is ~50 k trig ops/sec.
  final Rect? groupLiveBounds;

  /// Live group **frame** as 4 canvas-space corners in TL → TR → BR →
  /// BL order. During a gesture this is the session's initial AABB
  /// transformed by the same affine being applied to participants
  /// (rotation around [GroupGestureSession.anchor], uniform scale,
  /// then translation), so the selection chrome rotates / scales /
  /// translates as one rigid frame WITH the content.
  ///
  /// Null when no gesture is active or for translate-only sessions
  /// where the rotated quad would equal the AABB anyway — callers
  /// should fall back to [groupLiveBounds] in that case.
  final List<Offset>? groupLiveQuad;

  bool get isActive => session != null || groupSession != null;
  bool get isGroup => groupSession != null;

  static Rect? _computeGroupBounds(Map<String, LayerTransform> live) {
    if (live.isEmpty) return null;
    return const GroupEngine().computeBounds(live.values);
  }

  InteractionUiState copyWith({
    InteractionSession? session,
    LayerTransform? liveTransform,
    bool? isRotationSnapped,
    List<SnapGuide>? snapGuides,
    List<SpacingGuide>? spacingGuides,
    GroupGestureSession? groupSession,
    Map<String, LayerTransform>? groupLive,
    Object? groupLiveQuad = _kSentinel,
    bool clear = false,
  }) {
    if (clear) return const InteractionUiState();
    final nextLive = groupLive ?? this.groupLive;
    return InteractionUiState(
      session: session ?? this.session,
      liveTransform: liveTransform ?? this.liveTransform,
      isRotationSnapped: isRotationSnapped ?? this.isRotationSnapped,
      snapGuides: snapGuides ?? this.snapGuides,
      spacingGuides: spacingGuides ?? this.spacingGuides,
      groupSession: groupSession ?? this.groupSession,
      groupLive: nextLive,
      // Recompute only when the live map identity changed.
      groupLiveBounds: identical(nextLive, this.groupLive)
          ? groupLiveBounds
          : _computeGroupBounds(nextLive),
      // Sentinel-based opt-out: callers can pass `null` to explicitly
      // clear the quad (translate-only frames, gesture end), pass a
      // value to set it, or omit to preserve the previous one.
      groupLiveQuad: identical(groupLiveQuad, _kSentinel)
          ? this.groupLiveQuad
          : groupLiveQuad as List<Offset>?,
    );
  }
}

/// Sentinel used by [InteractionUiState.copyWith] to distinguish
/// "explicit null" from "omitted" for nullable fields.
const Object _kSentinel = Object();

/// Central controller for all pointer-driven transforms (single-layer and
/// group). Owns ephemeral session state, feeds the math engines, and
/// commits a single undoable command on release.
///
/// ## Invariants — do not break
///
/// 1. **Mutual exclusion**: at most one of [InteractionUiState.session]
///    and [InteractionUiState.groupSession] is non-null. Gesture
///    recognisers never switch types mid-gesture; if a start-method
///    runs while another session is active, the old session is
///    silently replaced.
/// 2. **Zero document writes during a live gesture**: the controller
///    publishes `liveTransform` / `groupLive` on its own state and
///    never mutates the document until [end] / [_endGroup]. The
///    lifecycle listener in [build] relies on this to treat any
///    observed transform change on an active layer as an external
///    mutation and cancel the gesture.
/// 3. **State-before-execute in every commit path**: [end] and
///    [_endGroup] MUST clear [state] before calling
///    `documentControllerProvider.notifier.execute`. The listener in
///    [build] fires synchronously on the document update; if the
///    session were still active it would observe our own commit as
///    external and call [cancel] recursively.
/// 4. **Diff against document, not `initial*`**: multi-touch sessions
///    rebase `initialTransform` / `initials` on every pointer-count
///    transition, so diffing against those fields on release skips
///    the commit and produces the "release snaps back" bug. Compare
///    against the live document instead.
class InteractionController extends Notifier<InteractionUiState> {
  static const _engine = InteractionEngine();
  static const _snapEngine = SnapEngine();

  /// Per-gesture smoother. Created at session start, dropped at session
  /// end. Absent (null) when no gesture is active, so no code path ever
  /// smooths committed document state.
  MotionSmoother? _smoother;
  /// Monotonic clock used to compute frame [dt] for the time-based
  /// smoother. Started at session begin, stopped on end. Using a
  /// [Stopwatch] (rather than wall-clock) keeps the smoother immune to
  /// system clock changes.
  final Stopwatch _clock = Stopwatch();
  Duration _lastTick = Duration.zero;

  /// Snap-edge tracking for haptics. We fire a single light tap when the
  /// gesture *enters* a snap zone (rotation or alignment), not on every
  /// frame the snap is held — that would buzz the device continuously.
  bool _wasRotationSnapped = false;
  bool _wasVerticallySnapped = false;
  bool _wasHorizontallySnapped = false;
  /// Pointer count observed on the previous multi-touch update. Used to
  /// detect 1\u2194n transitions so the session can be rebased without
  /// a visible jump when a second finger lands mid-drag.
  int _lastPointerCount = 0;

  @override
  InteractionUiState build() {
    // Lifecycle-safety: cancel any in-flight gesture the moment its
    // target layer disappears, becomes hidden, becomes locked, OR has
    // its transform changed from outside the gesture. This covers
    // undo crossing the gesture boundary, a layer being deleted /
    // toggled from the layers panel mid-drag, a drive-by document
    // import, or any other code path that mutates a layer we are
    // actively manipulating.
    //
    // Transform-change detection is safe here because this controller
    // NEVER mutates the document during an active pointer gesture —
    // it only publishes `liveTransform` / `groupLive` on its own
    // state, and commits to the document once in `end()` / `_endGroup`.
    // So any observed transform change must originate from elsewhere
    // and is therefore a signal to bail. Without this, an undo
    // landing mid-drag would leave the gesture's rebased reference
    // pointing at a ghost state, and the commit on release would
    // silently overwrite the undo.
    ref.listen<EditorDocument>(documentControllerProvider, (prev, next) {
      final s = state.session;
      if (s != null) {
        final layer = next.layerById(s.layerId);
        if (layer == null || !layer.visible || layer.locked) {
          cancel();
          return;
        }
        final prevLayer = prev?.layerById(s.layerId);
        if (prevLayer != null && prevLayer.transform != layer.transform) {
          cancel();
        }
        return;
      }
      final g = state.groupSession;
      if (g != null) {
        // Cancel the group session if any participant becomes
        // ineligible (deleted, hidden, locked) OR has its transform
        // changed from outside the gesture. Bail on the whole group
        // rather than dropping the bad layer to keep the rigid-body
        // invariant: every visible group bound and per-layer outline
        // matches the math driving them.
        for (final id in g.initials.keys) {
          final layer = next.layerById(id);
          if (layer == null || !layer.visible || layer.locked) {
            cancel();
            return;
          }
          final prevLayer = prev?.layerById(id);
          if (prevLayer != null &&
              prevLayer.transform != layer.transform) {
            cancel();
            return;
          }
        }
      }
    });
    // Lifecycle-safety #2: also bail on app-level focus loss
    // (paused / inactive / hidden / detached). EditorCanvas wires
    // the same hook from its widget observer, but that hook is
    // bound to the canvas widget being mounted. Registering here
    // as well guarantees the cancel still fires if the gesture
    // somehow outlives the canvas (e.g. an emergency rebuild that
    // unmounts the canvas while a pointer is still down). Both
    // observers race to call the same idempotent `cancel()`; the
    // second is a cheap no-op.
    final lifecycle = AppLifecycleListener(
      onStateChange: (AppLifecycleState s) {
        if (s != AppLifecycleState.resumed) cancel();
      },
    );
    ref.onDispose(lifecycle.dispose);
    return const InteractionUiState();
  }

  // ----- start -----

  void startMove({required EditorLayer layer, required Offset pointer}) {
    if (layer.locked || !layer.capabilities.movable) return;
    final session = _engine.startMove(
      layerId: layer.id,
      transform: layer.transform,
      pointer: pointer,
    );
    _beginSmoothing(layer.transform);
    state = InteractionUiState(
      session: session,
      liveTransform: layer.transform,
    );
  }

  void startResize({
    required EditorLayer layer,
    required InteractionHandle handle,
    required Offset pointer,
  }) {
    if (layer.locked || !layer.capabilities.resizable) return;
    final session = _engine.startResize(
      layerId: layer.id,
      transform: layer.transform,
      corner: handle,
      pointer: pointer,
    );
    _beginSmoothing(layer.transform);
    state = InteractionUiState(
      session: session,
      liveTransform: layer.transform,
    );
  }

  void startRotate({required EditorLayer layer, required Offset pointer}) {
    if (layer.locked || !layer.capabilities.rotatable) return;
    final session = _engine.startRotate(
      layerId: layer.id,
      transform: layer.transform,
      pointer: pointer,
    );
    _beginSmoothing(layer.transform);
    state = InteractionUiState(
      session: session,
      liveTransform: layer.transform,
    );
  }

  /// Start a multi-touch gesture session on a single layer. [focalPoint]
  /// is the midpoint of the pointers in canvas space. Requires at least
  /// one of [movable], [resizable], or [rotatable] — otherwise there is
  /// nothing the gesture could do and it is refused.
  ///
  /// Group multi-touch is handled by [startGroupGesture] / [updateGroupGesture];
  /// this method is single-layer only.
  void startGesture({
    required EditorLayer layer,
    required Offset focalPoint,
  }) {
    if (layer.locked) return;
    final caps = layer.capabilities;
    if (!caps.movable && !caps.resizable && !caps.rotatable) return;
    final session = _engine.startGesture(
      layerId: layer.id,
      transform: layer.transform,
      focalPoint: focalPoint,
    );
    _beginSmoothing(layer.transform);
    _lastPointerCount = 0;
    state = InteractionUiState(
      session: session,
      liveTransform: layer.transform,
    );
  }

  // ----- update -----

  void update(Offset pointer) {
    final s = state.session;
    if (s == null) return;

    LayerTransform next;
    var snapped = state.isRotationSnapped;
    var guides = const <SnapGuide>[];
    var spacingGuides = const <SpacingGuide>[];
    switch (s.handle) {
      case InteractionHandle.body:
        final moved = _engine.updateMove(s, pointer);
        final snapResult = _snapMove(moved, s.layerId);
        next = moved.copyWith(position: snapResult.position);
        guides = snapResult.guides;
        spacingGuides = snapResult.spacingGuides;
      case InteractionHandle.rotate:
        next = _engine.updateRotate(s, pointer);
        // Recompute the raw rotation to decide whether we are in the
        // snap-magnet zone, without re-implementing the math.
        final rawCurrent = math.atan2(
          pointer.dy - s.initialTransform.center.dy,
          pointer.dx - s.initialTransform.center.dx,
        );
        final rawRotation = s.initialTransform.rotation +
            (rawCurrent - s.pointerStartAngle);
        snapped = _engine.isNearSnap(rawRotation);
      case InteractionHandle.topLeft:
      case InteractionHandle.bottomLeft:
      case InteractionHandle.bottomRight:
        final layer =
            ref.read(documentControllerProvider).layerById(s.layerId);
        next = _engine.updateResize(
          s,
          pointer,
          capabilities: layer?.capabilities ?? const LayerCapabilities(),
        );
        // Snap the *grabbed corner* (the two moving edges incident to
        // it) against peer / canvas alignment targets, keeping the
        // opposite (anchor) corner fixed. Only for unrotated layers —
        // matches the rest of the snap subsystem which works on
        // [LayerTransform.unrotatedRect].
        if (next.rotation == 0 &&
            (layer?.capabilities.resizable ?? true)) {
          final snapResult = _snapResize(
            next,
            s.layerId,
            s.handle,
            keepAspect: layer?.capabilities.keepsAspectRatio ?? false,
          );
          next = snapResult.transform;
          guides = snapResult.guides;
        }
      case InteractionHandle.gesture:
        // A single-pointer update on a gesture session degrades to pure
        // translate.
        next = s.initialTransform.copyWith(
          position: s.initialTransform.position + (pointer - s.pointerStart),
        );
    }
    state = state.copyWith(
      liveTransform: _smooth(next),
      isRotationSnapped: snapped,
      snapGuides: guides,
      spacingGuides: spacingGuides,
    );
    _maybeFireSnapHaptic(rotationSnapped: snapped, guides: guides);
  }

  /// Multi-touch update. [pointerCount] < 2 collapses to a pure translate
  /// so a one-finger drag is indistinguishable from a handle-body drag.
  void updateGesture({
    required Offset focalPoint,
    required double scale,
    required double rotation,
    required int pointerCount,
  }) {
    var s = state.session;
    if (s == null) return;
    if (s.handle != InteractionHandle.gesture) return;

    // Rebase on pointer-count transitions (1↔≥2). Without rebasing,
    // when a second finger lands the focal moves to the pointers'
    // midpoint while [scale] restarts near 1.0 — our stored
    // [pointerStart] / [initialTransform] are now stale and the layer
    // jumps. Rebasing sets a fresh origin at the current live state so
    // the gesture continues seamlessly.
    //
    // Two trigger conditions:
    //
    //   1. _lastPointerCount > 0 and the count changed (1→2, 2→1, etc.)
    //   2. _lastPointerCount == 0 (first update of the session) AND the
    //      count is already ≥2. This is the "user dropped two fingers
    //      without moving the first" case — extremely common when
    //      pinching. Without this clause, focal0 stays at the first
    //      finger's landing position while focalPoint becomes the
    //      midpoint, producing a sideways jump of (P2-P1)/2 the moment
    //      the second finger touches.
    //
    // The first-update pc==1 case must NOT rebase: the session was just
    // created with the correct pointerStart, and rebasing would discard
    // the first frame of finger motion.
    final firstUpdate = _lastPointerCount == 0;
    final shouldRebase = firstUpdate
        ? pointerCount >= 2
        : _lastPointerCount != pointerCount;
    if (shouldRebase) {
      final currentLive = state.liveTransform ?? s.initialTransform;
      s = InteractionSession(
        layerId: s.layerId,
        handle: InteractionHandle.gesture,
        initialTransform: currentLive,
        pointerStart: focalPoint,
        pointerStartAngle: 0,
      );
      // Reset snap-haptic edge tracking too: after rebase the next
      // frame is effectively a fresh gesture, so a snap re-entry
      // should fire its tap rather than be swallowed by stale `true`
      // flags carried over from the pre-rebase state.
      _wasRotationSnapped = false;
      _wasVerticallySnapped = false;
      _wasHorizontallySnapped = false;
      state = state.copyWith(session: s);
    }
    _lastPointerCount = pointerCount;

    final layer =
        ref.read(documentControllerProvider).layerById(s.layerId);
    final caps = layer?.capabilities ?? const LayerCapabilities();

    if (pointerCount < 2) {
      // Single-finger drag on a gesture session degrades to pure
      // translate — same behaviour as a body-handle drag.
      if (!caps.movable) return;
      final delta = focalPoint - s.pointerStart;
      final moved = s.initialTransform.copyWith(
        position: s.initialTransform.position + delta,
      );
      final snapResult = _snapMove(moved, s.layerId);
      state = state.copyWith(
        liveTransform: _smooth(
          moved.copyWith(position: snapResult.position),
        ),
        isRotationSnapped: false,
        snapGuides: snapResult.guides,
        spacingGuides: snapResult.spacingGuides,
      );
      _maybeFireSnapHaptic(
        rotationSnapped: false,
        guides: snapResult.guides,
      );
      return;
    }

    // Zero-out disallowed components so a multi-touch gesture on a
    // partially-locked layer still works for the allowed axes.
    final effScale = caps.resizable ? scale : 1.0;
    final effRotation = caps.rotatable ? rotation : 0.0;
    final effFocal = caps.movable ? focalPoint : s.pointerStart;
    final result = _engine.updateGesture(
      s,
      focalPoint: effFocal,
      scale: effScale,
      rotation: effRotation,
      capabilities: caps,
    );
    // Multi-touch path bypasses the smoother. The engine's pinch math
    // anchors the canvas point that lived under the gesture focal at
    // session-start to remain under the focal as fingers move; passing
    // the result through an EMA delays the position so the anchored
    // point visibly slides out from under the user's fingers on fast
    // pinches. Top-tier editors (Procreate, Figma) deliberately leave
    // pinch output raw for exactly this reason. Single-finger drag and
    // rotate paths remain smoothed (handled in [update]).
    //
    // We still seed the smoother with the raw target so that if a
    // finger lifts (pc 2 → 1) and the gesture degrades to single-
    // finger translate, the smoother resumes from the correct
    // current state instead of an EMA tail from many frames ago.
    _seedSmoother(result.transform);
    state = state.copyWith(
      liveTransform: result.transform,
      isRotationSnapped: result.snapped,
      snapGuides: const <SnapGuide>[],
      spacingGuides: const <SpacingGuide>[],
    );
    _maybeFireSnapHaptic(
      rotationSnapped: result.snapped,
      guides: const <SnapGuide>[],
    );
  }

  // ----- end -----

  void end() {
    if (state.groupSession != null) {
      _endGroup();
      return;
    }
    final s = state.session;
    final live = state.liveTransform;
    if (s == null || live == null) {
      _endSmoothing();
      if (state.session != null || state.liveTransform != null) {
        state = const InteractionUiState();
      }
      return;
    }
    // Lifecycle-safety: the active layer may have been removed / hidden
    // / locked between the last update frame and this commit (e.g. via
    // an undo or a layers-panel action). Verify before issuing a
    // command — a stale `SetLayerTransformCommand` would either no-op
    // silently or, worse, mutate a layer the user cannot see.
    final activeLayer =
        ref.read(documentControllerProvider).layerById(s.layerId);
    final stillEligible =
        activeLayer != null && activeLayer.visible && !activeLayer.locked;
    // Diff against the *document* transform, not `s.initialTransform`.
    // Multi-touch gesture sessions rebase themselves on every pointer-
    // count transition (see [updateGesture]), which replaces
    // `initialTransform` with the CURRENT live transform. Diffing
    // against a rebased initial would always match the final live
    // transform and skip the commit — producing the "release snaps
    // back" bug: the user pinches with two fingers, lifts one, the
    // rebase snapshots the scaled state as the new "initial", and on
    // release the commit path thinks nothing changed. The document's
    // transform is untouched by the gesture (we only publish on
    // commit), so it is the correct reference for "did anything
    // actually change?".
    // Epsilon compare against the document, not strict equality. The
    // smoother's EMA tail can leave `live` a fraction of a canvas
    // pixel off the document transform even after the user returns
    // their finger to the origin, and strict `!=` would commit that
    // invisible delta as a history entry the user cannot see.
    // Tolerances are tight enough that any deliberate nudge still
    // commits: 0.25 canvas px is sub-pixel on a 1x viewport and
    // still under 1 screen px at 4x zoom.
    if (stillEligible &&
        !_transformsApproxEqual(live, activeLayer.transform)) {
      // IMPORTANT: commit the *exact* transform that was last rendered on
      // screen. Any normalisation here (e.g. rounding to whole logical
      // pixels) would cause a sub-pixel snap between the last frame of
      // the live drag and the first frame after release — visible as a
      // tiny "flicker" on release, especially at high viewport zoom
      // where 0.5 logical px = several screen px.
      //
      // Clear session state BEFORE executing the command. `execute`
      // publishes a new document state synchronously, which fires our
      // lifecycle listener in `build()`. If the session were still
      // active at that moment, the listener's transform-change check
      // would observe our own commit as an external mutation and call
      // `cancel()` recursively. Clearing first makes the commit
      // atomic from the listener's perspective.
      final docCtl = ref.read(documentControllerProvider.notifier);
      final layerId = s.layerId;
      // Label a multi-touch gesture session that ended up translate-
      // only as "Move" rather than "Transform": single-finger drags
      // that degraded from a gesture session should read the same
      // as body-handle drags in the history panel.
      final effectiveHandle = (s.handle == InteractionHandle.gesture &&
              live.size == activeLayer.transform.size &&
              live.rotation == activeLayer.transform.rotation)
          ? InteractionHandle.body
          : s.handle;
      _endSmoothing();
      state = const InteractionUiState();
      docCtl.execute(
        SetLayerTransformCommand(
          layerId: layerId,
          transform: live,
          labelOverride: _labelFor(effectiveHandle),
        ),
      );
      return;
    }
    _endSmoothing();
    state = const InteractionUiState();
  }

  // ===== group =====

  static const _groupEngine = GroupEngine();

  /// Eligibility filter shared by every group-start path: drops any
  /// layer that is locked or fails the capability gate, then returns
  /// the surviving id→transform map. Returns an empty map when nothing
  /// is eligible — start methods short-circuit on that.
  Map<String, LayerTransform> _eligibleInitials(
    Iterable<EditorLayer> layers, {
    required bool requireMovable,
    required bool requireResizable,
    required bool requireRotatable,
  }) {
    final out = <String, LayerTransform>{};
    for (final l in layers) {
      if (l.locked) continue;
      final c = l.capabilities;
      if (requireMovable && !c.movable) continue;
      if (requireResizable && !c.resizable) continue;
      if (requireRotatable && !c.rotatable) continue;
      out[l.id] = l.transform;
    }
    return out;
  }

  /// Begin a translate-only group session driven by a body / single-finger
  /// drag on the shared bounding box. Drops layers that are locked or
  /// non-movable. No-op when nothing remains.
  void startGroupMove({
    required Iterable<EditorLayer> layers,
    required Offset pointer,
  }) {
    final initials = _eligibleInitials(
      layers,
      requireMovable: true,
      requireResizable: false,
      requireRotatable: false,
    );
    if (initials.isEmpty) return;
    final bounds = _groupEngine.computeBounds(initials.values);
    _dropSingleSmoother();
    _resetGroupHaptics();
    state = InteractionUiState(
      groupSession: GroupGestureSession(
        handle: InteractionHandle.body,
        initials: initials,
        initialBounds: bounds,
        anchor: bounds.center,
        pointerStart: pointer,
      ),
      groupLive: initials,
      groupLiveBounds: bounds,
    );
  }

  /// Begin a uniform-scale group resize from one of the four bounds
  /// corners. The opposite corner is the anchor. Requires every
  /// participant to be both movable AND resizable — a pure resize
  /// would shift positions, so movability is also required.
  ///
  /// Scale is uniform across the whole group, so every child's own
  /// aspect ratio is preserved mathematically regardless of each
  /// participant's [LayerCapabilities.keepsAspectRatio] flag — the
  /// per-layer aspect-lock is only relevant for asymmetric
  /// (single-handle) resize, which groups do not expose.
  void startGroupResize({
    required Iterable<EditorLayer> layers,
    required InteractionHandle handle,
    required Offset pointer,
  }) {
    assert(
      handle == InteractionHandle.topLeft ||
          handle == InteractionHandle.bottomLeft ||
          handle == InteractionHandle.bottomRight,
      'startGroupResize requires a corner handle',
    );
    final initials = _eligibleInitials(
      layers,
      requireMovable: true,
      requireResizable: true,
      requireRotatable: false,
    );
    if (initials.isEmpty) return;
    final bounds = _groupEngine.computeBounds(initials.values);
    final groupHandle = _toGroupHandle(handle);
    final anchor = groupHandle.anchorIn(bounds);
    _dropSingleSmoother();
    _resetGroupHaptics();
    state = InteractionUiState(
      groupSession: GroupGestureSession(
        handle: handle,
        initials: initials,
        initialBounds: bounds,
        anchor: anchor,
        pointerStart: pointer,
      ),
      groupLive: initials,
      groupLiveBounds: bounds,
    );
  }

  /// Begin a rigid group rotate around the bounds centre. Requires
  /// every participant to be movable AND rotatable — child centres
  /// orbit the bounds centre, so positions change in addition to
  /// rotations.
  void startGroupRotate({
    required Iterable<EditorLayer> layers,
    required Offset pointer,
  }) {
    final initials = _eligibleInitials(
      layers,
      requireMovable: true,
      requireResizable: false,
      requireRotatable: true,
    );
    if (initials.isEmpty) return;
    final bounds = _groupEngine.computeBounds(initials.values);
    final centre = bounds.center;
    _dropSingleSmoother();
    _resetGroupHaptics();
    state = InteractionUiState(
      groupSession: GroupGestureSession(
        handle: InteractionHandle.rotate,
        initials: initials,
        initialBounds: bounds,
        anchor: centre,
        pointerStart: pointer,
        pointerStartAngle:
            math.atan2(pointer.dy - centre.dy, pointer.dx - centre.dx),
      ),
      groupLive: initials,
      groupLiveBounds: bounds,
    );
  }

  /// Begin a multi-touch group gesture (translate + uniform scale +
  /// rotate). Capability filtering is conservative: every participant
  /// must be movable; resize / rotate are applied uniformly to all.
  /// Mixed-capability groups still drag.
  void startGroupGesture({
    required Iterable<EditorLayer> layers,
    required Offset focalPoint,
  }) {
    final initials = _eligibleInitials(
      layers,
      requireMovable: true,
      requireResizable: false,
      requireRotatable: false,
    );
    if (initials.isEmpty) return;
    final bounds = _groupEngine.computeBounds(initials.values);
    _lastPointerCount = 0;
    _dropSingleSmoother();
    _resetGroupHaptics();
    state = InteractionUiState(
      groupSession: GroupGestureSession(
        handle: InteractionHandle.gesture,
        initials: initials,
        initialBounds: bounds,
        anchor: bounds.center,
        pointerStart: focalPoint,
      ),
      groupLive: initials,
      groupLiveBounds: bounds,
    );
  }

  /// Update the active group session with the current pointer position.
  /// Routes by [GroupGestureSession.handle]:
  ///   * `body` → translate by `pointer - pointerStart`;
  ///   * one of the four corners → uniform scale around the opposite
  ///     corner. The scale factor is the pointer's signed projection
  ///     onto the original anchor→corner diagonal divided by the
  ///     diagonal length squared (so off-axis pointer motion does
  ///     not inflate the factor — gives the natural feel of dragging
  ///     the corner along its diagonal);
  ///   * `rotate` → rotate around bounds centre by the pointer's
  ///     angular delta.
  ///
  /// No-op when [InteractionUiState.groupSession] is null. Pointer-count
  /// gesture updates use [updateGroupGesture] instead.
  void updateGroup(Offset pointer) {
    final g = state.groupSession;
    if (g == null) return;
    Map<String, LayerTransform> next;
    var snapped = false;
    var alignGuides = const <SnapGuide>[];
    var spacingGuides = const <SpacingGuide>[];
    // Cumulative gesture transform applied to the *frame* (the
    // initial group AABB). Selection chrome is rendered by mapping
    // [GroupGestureSession.initialBounds] corners through this
    // transform, so the box rotates / scales / translates as one
    // rigid frame WITH the layers — mirroring single-layer chrome.
    var frameRotation = 0.0;
    var frameScale = 1.0;
    var frameTranslation = Offset.zero;
    switch (g.handle) {
      case InteractionHandle.body:
        next = _groupEngine.translate(g.initials, pointer - g.pointerStart);
        frameTranslation = pointer - g.pointerStart;
        // Snap the *group bounds* (not any single layer) against
        // non-group peers + canvas. Apply the resulting correction
        // as a uniform translation to every participant so the group
        // stays rigid. Hysteresis is provided by feeding last
        // frame's guides as `previous`.
        final snap = _snapGroupBounds(next, g.initials.keys.toSet());
        if (snap != null) {
          next = {
            for (final e in next.entries)
              e.key: e.value.copyWith(
                position: e.value.position.translate(snap.dx, snap.dy),
              ),
          };
          alignGuides = snap.guides;
          spacingGuides = snap.spacingGuides;
          frameTranslation = frameTranslation.translate(snap.dx, snap.dy);
        }
      case InteractionHandle.topLeft:
      case InteractionHandle.bottomLeft:
      case InteractionHandle.bottomRight:
        // Skip resize entirely if any participant is non-resizable.
        // This matches the per-layer capability gate single-layer
        // resize already applies (via `LayerCapabilities` clamps in
        // `InteractionEngine.updateResize`).
        if (!_groupCanResize(g)) {
          next = g.initials;
          break;
        }
        final groupHandle = _toGroupHandle(g.handle);
        final originalCorner = groupHandle.cornerIn(g.initialBounds);
        final diag = originalCorner - g.anchor;
        final pointerVec = pointer - g.anchor;
        final diagLen2 = diag.dx * diag.dx + diag.dy * diag.dy;
        if (diagLen2 < 1e-12) {
          next = g.initials;
          break;
        }
        var factor =
            (pointerVec.dx * diag.dx + pointerVec.dy * diag.dy) / diagLen2;
        // Reject NaN / non-finite (e.g. pointer == anchor exactly).
        if (!factor.isFinite) {
          next = g.initials;
          break;
        }
        // Clamp factor to a tiny positive minimum so the user cannot
        // drag the corner *through* the anchor and produce a flipped
        // (mirrored) layer set. Single-layer resize prevents this with
        // its rect-side clamp; group resize gets the same guard.
        if (factor < 0.01) factor = 0.01;
        next = _groupEngine.scale(
          g.initials,
          anchor: g.anchor,
          scale: factor,
          // Same per-session envelope as single-layer gestures. Without
          // these the engine's permissive API defaults (0.05..64) apply
          // and a group pinch can scale far past what a single-layer
          // pinch allows.
          minScale: EngineConstants.minGestureScale,
          maxScale: EngineConstants.maxGestureScale,
          minLayerSide: EngineConstants.minLayerSize,
          maxLayerSide: EngineConstants.maxLayerSize,
        );
        frameScale = factor;
      case InteractionHandle.rotate:
        if (!_groupCanRotate(g)) {
          next = g.initials;
          break;
        }
        final current = math.atan2(
          pointer.dy - g.anchor.dy,
          pointer.dx - g.anchor.dx,
        );
        // Shortest-arc delta — using `atan2(sin, cos)` collapses any
        // multiple-rotation ambiguity to (-pi, pi]. Without this,
        // when the pointer crosses the +/- pi branch cut the raw
        // subtraction jumps by 2*pi and the group spins a full turn.
        var delta = current - g.pointerStartAngle;
        delta = math.atan2(math.sin(delta), math.cos(delta));
        // Snap the gesture *delta* (not any single layer's absolute
        // angle): the group's AABB has no inherent rotation, and
        // members can start with different rotations of their own.
        // Snapping the delta means "rotate by ~90°" clicks at exactly
        // 90° regardless of where the children started.
        snapped = _engine.isNearSnap(delta);
        delta = _engine.snapRotation(delta);
        next = _groupEngine.rotate(
          g.initials,
          center: g.anchor,
          delta: delta,
        );
        frameRotation = delta;
      case InteractionHandle.gesture:
        // Single-pointer update on a gesture session: degrade to translate.
        next = _groupEngine.translate(g.initials, pointer - g.pointerStart);
        frameTranslation = pointer - g.pointerStart;
    }
    state = state.copyWith(
      groupLive: next,
      isRotationSnapped: snapped,
      snapGuides: alignGuides,
      spacingGuides: spacingGuides,
      groupLiveQuad: _frameCorners(
        g.initialBounds,
        g.anchor,
        frameRotation,
        frameScale,
        frameTranslation,
      ),
    );
    _maybeFireSnapHaptic(
      rotationSnapped: snapped,
      guides: alignGuides,
    );
  }

  /// True when every group participant is resizable. We require all
  /// to be resizable (rather than filtering) to keep the rigid-body
  /// invariant: a uniform scale that left some children un-scaled
  /// would visibly shear the group.
  bool _groupCanResize(GroupGestureSession g) {
    final doc = ref.read(documentControllerProvider);
    for (final id in g.initials.keys) {
      final l = doc.layerById(id);
      if (l == null || !l.capabilities.resizable) return false;
    }
    return true;
  }

  /// True when every group participant is rotatable. Same all-or-nothing
  /// rationale as [_groupCanResize].
  bool _groupCanRotate(GroupGestureSession g) {
    final doc = ref.read(documentControllerProvider);
    for (final id in g.initials.keys) {
      final l = doc.layerById(id);
      if (l == null || !l.capabilities.rotatable) return false;
    }
    return true;
  }

  /// Multi-touch update for a group gesture session. Combines pinch
  /// scale + rotate + focal translate in a single pass via
  /// [GroupEngine.pinch] to minimise compounded float error.
  void updateGroupGesture({
    required Offset focalPoint,
    required double scale,
    required double rotation,
    required int pointerCount,
  }) {
    var g = state.groupSession;
    if (g == null) return;
    if (g.handle != InteractionHandle.gesture) return;

    // Rebase on pointer-count transitions for the same reason as the
    // single-layer path: a second finger landing mid-drag moves the
    // focal to the midpoint and resets [scale] to 1, so the stored
    // [pointerStart] / [initials] become stale and the group jumps.
    final firstUpdate = _lastPointerCount == 0;
    final shouldRebase =
        firstUpdate ? pointerCount >= 2 : _lastPointerCount != pointerCount;
    if (shouldRebase) {
      final liveBounds = _groupEngine.computeBounds(state.groupLive.values);
      g = GroupGestureSession(
        handle: InteractionHandle.gesture,
        initials: Map.of(state.groupLive),
        initialBounds: liveBounds,
        anchor: liveBounds.center,
        pointerStart: focalPoint,
      );
      // Reset snap-haptic edge tracking: after rebase the next frame
      // is effectively a fresh gesture, so a snap re-entry should
      // fire its tap rather than be swallowed by stale `true` flags.
      // Mirrors the single-layer rebase in [updateGesture].
      _resetGroupHaptics();
      state = state.copyWith(groupSession: g);
    }
    _lastPointerCount = pointerCount;

    if (pointerCount < 2) {
      // Single-finger drag on a group session: pure translate WITH
      // alignment + equal-spacing snap on the group AABB. Mirrors
      // the dedicated `startGroupMove` / `updateGroup` body path \u2014
      // the real UI routes group body-drags through this gesture
      // session (the dedicated move path is currently only exercised
      // by unit tests), so without this branch a multi-select drag
      // would feel un-snappable in production.
      var next =
          _groupEngine.translate(g.initials, focalPoint - g.pointerStart);
      var alignGuides = const <SnapGuide>[];
      var spacingGuides = const <SpacingGuide>[];
      var translation = focalPoint - g.pointerStart;
      final snap = _snapGroupBounds(next, g.initials.keys.toSet());
      if (snap != null) {
        next = {
          for (final e in next.entries)
            e.key: e.value.copyWith(
              position: e.value.position.translate(snap.dx, snap.dy),
            ),
        };
        alignGuides = snap.guides;
        spacingGuides = snap.spacingGuides;
        translation = translation.translate(snap.dx, snap.dy);
      }
      state = state.copyWith(
        groupLive: next,
        snapGuides: alignGuides,
        spacingGuides: spacingGuides,
        groupLiveQuad: _frameCorners(
          g.initialBounds,
          g.anchor,
          0,
          1,
          translation,
        ),
      );
      _maybeFireSnapHaptic(
        rotationSnapped: false,
        guides: alignGuides,
      );
      return;
    }

    // Multi-touch pinch / rotate / translate: raw direct manipulation,
    // no snap. Matches Figma-mobile / CapCut / Procreate behaviour \u2014
    // freeform two-finger transforms should not fight magnetic targets.
    // Any guides left over from the single-finger phase are cleared
    // when we publish state below.
    //
    // Per-layer capability gating: if any participant cannot resize,
    // collapse scale to 1; if any cannot rotate, collapse rotation
    // to 0. Single-layer `updateGesture` does the equivalent \u2014 group
    // must match for consistency.
    final effScale = _groupCanResize(g) ? scale : 1.0;
    final effRotation = _groupCanRotate(g) ? rotation : 0.0;
    // Scale / rotate around the group's CENTRE (rebased to liveBounds
    // centre on every pointer-count transition in `shouldRebase`
    // above), not around the focal. Matches the single-layer engine's
    // scale-in-place policy — see the comment in
    // `InteractionEngine.updateGesture` for the full rationale. The
    // translation term is still the focal's delta so dragging fingers
    // drags the group 1:1.
    final next = _groupEngine.pinch(
      g.initials,
      anchor: g.anchor,
      scale: effScale,
      rotation: effRotation,
      translation: focalPoint - g.pointerStart,
      minLayerSide: EngineConstants.minLayerSize,
      maxLayerSide: EngineConstants.maxLayerSize,
    );
    state = state.copyWith(
      groupLive: next,
      snapGuides: const <SnapGuide>[],
      spacingGuides: const <SpacingGuide>[],
      groupLiveQuad: _frameCorners(
        g.initialBounds,
        g.anchor,
        effRotation,
        effScale,
        focalPoint - g.pointerStart,
      ),
    );
  }

  /// Commit the group session as a single composite command. Drops
  /// participants that became ineligible mid-gesture and entries
  /// whose transform did not change.
  ///
  /// IMPORTANT — diff against the *document* transform, not
  /// [GroupGestureSession.initials]. Multi-touch gesture sessions
  /// rebase themselves on every pointer-count transition (see
  /// [updateGroupGesture]), which replaces `initials` with the
  /// CURRENT live transforms. Diffing against a rebased `initials`
  /// would always match the final live transform and skip the
  /// commit — producing the "release snaps back" bug: the user
  /// scales with two fingers, lifts one, the rebase snapshots the
  /// scaled state as the new "initial", and on release the commit
  /// path thinks nothing changed. The document's transform is
  /// untouched by the gesture (we only publish on commit), so it
  /// is the correct reference for "did anything actually change?".
  void _endGroup() {
    final g = state.groupSession;
    if (g == null) {
      state = const InteractionUiState();
      return;
    }
    final doc = ref.read(documentControllerProvider);
    final cmds = <EditorCommand>[];
    for (final entry in state.groupLive.entries) {
      final l = doc.layerById(entry.key);
      if (l == null || !l.visible || l.locked) continue;
      // Epsilon compare: a pinch that ended exactly where it began
      // can leave sub-pixel float noise across 50+ participants.
      // Strict equality would commit a 50-layer composite for a
      // visibly-still group; epsilon drops each untouched layer.
      if (_transformsApproxEqual(entry.value, l.transform)) continue;
      cmds.add(SetLayerTransformCommand(
        layerId: entry.key,
        transform: entry.value,
        labelOverride: _labelFor(g.handle),
      ));
    }
    if (cmds.isNotEmpty) {
      final docCtl = ref.read(documentControllerProvider.notifier);
      final handle = g.handle;
      final cmdCount = cmds.length;
      // Clear session state BEFORE executing the command — same
      // rationale as the single-layer `end()`: `execute` fires our
      // lifecycle listener, which would otherwise observe our own
      // commit as an external transform change and call `cancel()`
      // mid-commit. Clearing first makes the commit atomic.
      _lastPointerCount = 0;
      _resetGroupHaptics();
      state = const InteractionUiState();
      if (cmdCount == 1) {
        docCtl.execute(cmds.first);
      } else {
        docCtl.execute(CompositeCommand(
          cmds,
          labelOverride: '${_labelFor(handle)} $cmdCount layers',
        ));
      }
      return;
    }
    _lastPointerCount = 0;
    // Reset snap-haptic edge tracking so the next session
    // (single-layer or group) fires its first snap-entry tap rather
    // than carry stale `true` flags from this one. The single-layer
    // path resets via `_endSmoothing`; the group path has no
    // smoother, so reset explicitly.
    _resetGroupHaptics();
    state = const InteractionUiState();
  }

  /// Map an [InteractionHandle] corner to the matching [GroupHandle].
  GroupHandle _toGroupHandle(InteractionHandle h) {
    switch (h) {
      case InteractionHandle.topLeft:
        return GroupHandle.topLeft;
      case InteractionHandle.bottomLeft:
        return GroupHandle.bottomLeft;
      case InteractionHandle.bottomRight:
        return GroupHandle.bottomRight;
      // ignore: no_default_cases
      default:
        throw ArgumentError('Not a corner handle: $h');
    }
  }

  /// Reset snap-haptic edge tracking before a fresh group session
  /// begins. Single-layer paths reset via [_beginSmoothing]; group
  /// paths have no smoother, so this is the equivalent hook.
  void _resetGroupHaptics() {
    _wasRotationSnapped = false;
    _wasVerticallySnapped = false;
    _wasHorizontallySnapped = false;
  }

  /// Defensive: ensure no single-layer smoother leaks into a group
  /// session. Single-start paths call [_beginSmoothing], but group
  /// paths don't smooth — if a prior single-layer session was ever
  /// abandoned without passing through [end] / [cancel] (e.g. via a
  /// framework-swallowed pointer cancel followed immediately by a
  /// group-start), the stale smoother would lie unused until the
  /// next single-layer start. Reset it explicitly.
  void _dropSingleSmoother() {
    if (_smoother == null) return;
    _smoother = null;
    _clock.stop();
    _lastTick = Duration.zero;
  }

  /// Idempotent cancel — safe to call from any state, at any time.
  /// Drops the active session and any live transform without committing
  /// a command. Hooked up to: `PointerCancelEvent`, app
  /// `paused`/`inactive`/`hidden`, active layer
  /// removal/hide/lock, and `EditorCanvas.dispose`.
  void cancel() {
    if (state.session == null &&
        state.groupSession == null &&
        state.liveTransform == null &&
        state.snapGuides.isEmpty &&
        state.spacingGuides.isEmpty &&
        !state.isRotationSnapped) {
      // Nothing to do — keeps cancel safe to call from broad lifecycle
      // hooks without churning state on every event.
      return;
    }
    _endSmoothing();
    state = const InteractionUiState();
  }

  /// Seed a fresh smoother at session start.
  void _beginSmoothing(LayerTransform initial) {
    final sm = MotionSmoother()
      ..seed(
        position: initial.position,
        rotation: initial.rotation,
        size: initial.size,
      );
    _smoother = sm;
    _clock
      ..reset()
      ..start();
    _lastTick = Duration.zero;
    _wasRotationSnapped = false;
    _wasVerticallySnapped = false;
    _wasHorizontallySnapped = false;
  }

  /// Drop the active smoother and reset pointer-count tracking.
  void _endSmoothing() {
    _smoother = null;
    _lastPointerCount = 0;
    _clock.stop();
    _lastTick = Duration.zero;
    _wasRotationSnapped = false;
    _wasVerticallySnapped = false;
    _wasHorizontallySnapped = false;
  }

  /// Apply time-based smoothing to a freshly-computed target transform.
  /// No-op when no smoother is active (should not happen during a
  /// session, but keeps the path safe).
  LayerTransform _smooth(LayerTransform target) {
    final sm = _smoother;
    if (sm == null) return target;
    final now = _clock.elapsed;
    // Frame delta in seconds. Clamp to a sane upper bound so a paused
    // gesture (debugger break, app suspended) does not produce a giant dt
    // that would snap the smoother to target on resume.
    final rawDt = (now - _lastTick).inMicroseconds / 1e6;
    _lastTick = now;
    final dt = rawDt.isFinite ? rawDt.clamp(0.0, 0.05) : 0.0;
    return target.copyWith(
      position: sm.smoothPosition(target.position, dt: dt),
      rotation: sm.smoothRotation(target.rotation, dt: dt),
      size: sm.smoothSize(target.size, dt: dt),
    );
  }

  /// Re-seed the smoother to a known transform without applying EMA.
  /// Used by the multi-touch pinch path which deliberately renders raw
  /// (un-smoothed) frames so the gesture focal stays pixel-anchored to
  /// its initial canvas point. If the gesture later degrades back to a
  /// single-finger translate (pc 2 \u2192 1), the smoother resumes
  /// from the freshly-seeded state instead of an EMA tail captured
  /// before the pinch began.
  void _seedSmoother(LayerTransform target) {
    final sm = _smoother;
    if (sm == null) return;
    sm.seed(
      position: target.position,
      rotation: target.rotation,
      size: target.size,
    );
    _lastTick = _clock.elapsed;
  }

  /// Compute a snap-adjusted position for a moving layer. Reads the latest
  /// document state to build peer rects (excluding the moving layer) and
  /// uses the document dimensions as the canvas envelope. The engine
  /// remains pure — this controller method is the only coupling between
  /// snapping and document state.
  ///
  /// The base snap threshold is expressed in *screen* pixels and is
  /// converted to canvas pixels by dividing by the current viewport
  /// scale before being passed to the engine. That keeps the magnetic
  /// radius constant on the user's screen: at 0.25× zoom the engine
  /// sees 4× the canvas threshold; at 4× zoom it sees ¼ — same feel
  /// at any zoom level.
  ///
  /// Composes alignment snap + equal-spacing snap: alignment snap runs
  /// first (it's a stronger signal — "your edge / centre lines up with
  /// X"), then on each axis where alignment did *not* engage, a
  /// spacing snap is attempted. The result is the union of the two —
  /// alignment guides + spacing guides — never fighting for the same
  /// axis.
  _CombinedSnap _snapMove(LayerTransform moved, String movingId) {
    final doc = ref.read(documentControllerProvider);
    final peers = <Rect>[
      for (final l in doc.layers)
        if (l.id != movingId && l.visible) l.transform.unrotatedRect,
    ];
    final scale = ref.read(viewportControllerProvider).scale;
    final effectiveThreshold =
        scale > 0 ? _baseSnapThreshold / scale : _baseSnapThreshold;
    // Hysteresis: hand the engine last frame's guides as `previous`
    // so engaged targets retain their engagement at a wider release
    // tolerance. Eliminates the on/off flicker that appears when the
    // pointer hovers exactly at the threshold boundary.
    final prevAlign = state.snapGuides.isEmpty
        ? null
        : SnapResult(position: Offset.zero, guides: state.snapGuides);
    final align = _snapEngine.snapPosition(
      proposed: moved.position,
      size: moved.size,
      peerRects: peers,
      canvasSize: Size(doc.width, doc.height),
      threshold: effectiveThreshold,
      previous: prevAlign,
    );

    // Spacing snap composes on axes where alignment snap did NOT
    // engage. We feed it the *post-alignment* position so any X-snap
    // already applied keeps its strong-signal status while a Y
    // spacing snap (or vice versa) still has a chance to engage.
    final alignedHasV =
        align.guides.any((g) => g.axis == SnapAxis.vertical);
    final alignedHasH =
        align.guides.any((g) => g.axis == SnapAxis.horizontal);
    final spacingGuides = <SpacingGuide>[];
    var finalPos = align.position;
    if (peers.length >= 2 && (!alignedHasV || !alignedHasH)) {
      final prevSpacing = state.spacingGuides.isEmpty
          ? null
          : SpacingSnapResult(
              position: Offset.zero,
              guides: state.spacingGuides,
            );
      final spacing = _snapEngine.findSpacingSnap(
        proposed: align.position,
        size: moved.size,
        peerRects: peers,
        threshold: effectiveThreshold,
        previous: prevSpacing,
      );
      // Spacing guide on axis vertical → moves X. Discard guides on
      // axes that alignment already locked (would fight).
      var dx = 0.0;
      var dy = 0.0;
      for (final g in spacing.guides) {
        if (g.axis == SnapAxis.vertical && !alignedHasV) {
          dx = spacing.position.dx - align.position.dx;
          spacingGuides.add(g);
        } else if (g.axis == SnapAxis.horizontal && !alignedHasH) {
          dy = spacing.position.dy - align.position.dy;
          spacingGuides.add(g);
        }
      }
      finalPos = align.position.translate(dx, dy);
    }

    return _CombinedSnap(
      position: finalPos,
      guides: align.guides,
      spacingGuides: spacingGuides,
    );
  }

  /// Snap a resized layer's *grabbed corner* against alignment targets
  /// (peer edges/centres + canvas edges/centre), keeping the opposite
  /// (anchor) corner fixed. Only applies to unrotated layers; rotated
  /// resize falls through unchanged.
  ///
  /// Snap targets are evaluated for the two edges incident to the
  /// grabbed corner: a top-right grab snaps the top edge (Y) and the
  /// right edge (X). When [keepAspect] is true, only one axis is
  /// allowed to snap — whichever produces the smaller correction —
  /// and the other dimension is recomputed to preserve aspect ratio.
  _ResizeSnapResult _snapResize(
    LayerTransform t,
    String layerId,
    InteractionHandle handle,
    {required bool keepAspect}) {
    final doc = ref.read(documentControllerProvider);
    final peers = <Rect>[
      for (final l in doc.layers)
        if (l.id != layerId && l.visible) l.transform.unrotatedRect,
    ];
    final scale = ref.read(viewportControllerProvider).scale;
    final tol = scale > 0 ? _baseSnapThreshold / scale : _baseSnapThreshold;

    final rect = t.unrotatedRect;
    // Identify which edges move with this handle.
    final movesLeft = handle == InteractionHandle.topLeft ||
        handle == InteractionHandle.bottomLeft;
    final movesRight = handle == InteractionHandle.bottomRight;
    final movesTop = handle == InteractionHandle.topLeft;
    final movesBottom = handle == InteractionHandle.bottomLeft ||
        handle == InteractionHandle.bottomRight;

    // Anchor coords (the fixed corner).
    final anchorX = movesLeft ? rect.right : rect.left;
    final anchorY = movesTop ? rect.bottom : rect.top;

    // Build vertical-line targets (X coords) and horizontal-line
    // targets (Y coords) — peer edges + canvas edges.
    final vTargets = <double>[
      0, doc.width / 2, doc.width,
      for (final r in peers) ...[r.left, r.left + r.width / 2, r.right],
    ];
    final hTargets = <double>[
      0, doc.height / 2, doc.height,
      for (final r in peers) ...[r.top, r.top + r.height / 2, r.bottom],
    ];
    final prevVCoord = _firstCoord(state.snapGuides, SnapAxis.vertical);
    final prevHCoord = _firstCoord(state.snapGuides, SnapAxis.horizontal);

    final movingX = movesLeft ? rect.left : rect.right;
    final movingY = movesTop ? rect.top : rect.bottom;
    final xSnap = movesLeft || movesRight
        ? _bestEdgeSnap(movingX, vTargets, tol, prevVCoord)
        : null;
    final ySnap = movesTop || movesBottom
        ? _bestEdgeSnap(movingY, hTargets, tol, prevHCoord)
        : null;

    // No snap engaged on either axis → return as-is.
    if (xSnap == null && ySnap == null) {
      return _ResizeSnapResult(transform: t, guides: const []);
    }

    double newLeft = rect.left;
    double newRight = rect.right;
    double newTop = rect.top;
    double newBottom = rect.bottom;

    var pickX = xSnap != null;
    var pickY = ySnap != null;
    // Aspect lock: choose the axis with the smaller correction; the
    // other follows mathematically. Prevents fighting snaps on both
    // edges from stretching the rect off-aspect.
    if (keepAspect && pickX && pickY) {
      final dxMag = (xSnap.target - movingX).abs();
      final dyMag = (ySnap.target - movingY).abs();
      if (dxMag <= dyMag) {
        pickY = false;
      } else {
        pickX = false;
      }
    }

    final guides = <SnapGuide>[];
    if (pickX && xSnap != null) {
      if (movesLeft) {
        newLeft = xSnap.target;
      } else {
        newRight = xSnap.target;
      }
      guides.add(SnapGuide(
        axis: SnapAxis.vertical,
        coord: xSnap.target,
        start: math.min(rect.top, rect.bottom),
        end: math.max(rect.top, rect.bottom),
      ));
    }
    if (pickY && ySnap != null) {
      if (movesTop) {
        newTop = ySnap.target;
      } else {
        newBottom = ySnap.target;
      }
      guides.add(SnapGuide(
        axis: SnapAxis.horizontal,
        coord: ySnap.target,
        start: math.min(rect.left, rect.right),
        end: math.max(rect.left, rect.right),
      ));
    }

    // Aspect-ratio recomputation: with anchor fixed, the moving edge
    // on the unsnapped axis follows from the snapped axis' new size.
    if (keepAspect && rect.width > 0 && rect.height > 0) {
      final aspect = rect.width / rect.height;
      if (pickX && !pickY) {
        final newWidth = (newRight - newLeft).abs();
        final newHeight = newWidth / aspect;
        if (movesTop) {
          newTop = anchorY - newHeight;
        } else {
          newBottom = anchorY + newHeight;
        }
      } else if (pickY && !pickX) {
        final newHeight = (newBottom - newTop).abs();
        final newWidth = newHeight * aspect;
        if (movesLeft) {
          newLeft = anchorX - newWidth;
        } else {
          newRight = anchorX + newWidth;
        }
      }
    }

    final width = (newRight - newLeft).abs();
    final height = (newBottom - newTop).abs();
    // Reject snaps that would shrink past the minimum side. The
    // engine's [updateResize] already enforced minLayerSize for the
    // raw drag; if our snap would push *under* that, abandon the
    // snap rather than violate the floor.
    if (width < EngineConstants.minLayerSize ||
        height < EngineConstants.minLayerSize) {
      return _ResizeSnapResult(transform: t, guides: const []);
    }
    return _ResizeSnapResult(
      transform: t.copyWith(
        position: Offset(math.min(newLeft, newRight), math.min(newTop, newBottom)),
        size: Size(width, height),
      ),
      guides: guides,
    );
  }

  /// 1-D nearest-target snap with hysteresis, used by [_snapResize].
  /// Mirrors the per-target sticky-tolerance logic from
  /// [SnapEngine._bestMatch] but for a single moving coordinate.
  _EdgeSnap? _bestEdgeSnap(
    double moving,
    List<double> targets,
    double tol,
    double? sticky,
  ) {
    final release = tol * 1.6;
    _EdgeSnap? best;
    var bestDist = tol;
    for (final c in targets) {
      final d = (moving - c).abs();
      final isSticky = sticky != null && (c - sticky).abs() < 0.001;
      final t = isSticky ? release : tol;
      if (d > t) continue;
      if (best == null || d < bestDist) {
        bestDist = d;
        best = _EdgeSnap(target: c);
      }
    }
    return best;
  }

  double? _firstCoord(List<SnapGuide> guides, SnapAxis axis) {
    for (final g in guides) {
      if (g.axis == axis) return g.coord;
    }
    return null;
  }

  /// Map the four corners of [initialBounds] through the gesture's
  /// affine: rotate by [rotation] and scale by [scale] around
  /// [anchor], then translate by [translation]. Returned in
  /// TL → TR → BR → BL order so the selection chrome can stroke a
  /// closed quad and place its four handles directly.
  ///
  /// This is the same affine the math engines apply to participant
  /// transforms, so the rendered frame stays pixel-aligned with the
  /// rotated / scaled / translated content.
  static List<Offset> _frameCorners(
    Rect initialBounds,
    Offset anchor,
    double rotation,
    double scale,
    Offset translation,
  ) {
    final cosR = math.cos(rotation);
    final sinR = math.sin(rotation);
    Offset map(Offset p) {
      final dx = (p.dx - anchor.dx) * scale;
      final dy = (p.dy - anchor.dy) * scale;
      final rx = cosR * dx - sinR * dy;
      final ry = sinR * dx + cosR * dy;
      return Offset(
        anchor.dx + rx + translation.dx,
        anchor.dy + ry + translation.dy,
      );
    }

    return <Offset>[
      map(initialBounds.topLeft),
      map(initialBounds.topRight),
      map(initialBounds.bottomRight),
      map(initialBounds.bottomLeft),
    ];
  }

  /// Snap a group's bounding rect during a rigid translate. The group
  /// AABB itself is used as the moved rect; peers are all *non-group*
  /// document layers (so members never snap against each other), and
  /// the engine sees its previous-frame guides for hysteresis.
  ///
  /// Returns null when no snap engaged. Callers apply `(dx, dy)` as
  /// a single uniform translation to every participant — preserving
  /// the rigid-body invariant the rest of [updateGroup] relies on.
  _GroupSnapResult? _snapGroupBounds(
    Map<String, LayerTransform> live,
    Set<String> groupIds,
  ) {
    if (live.isEmpty) return null;
    // Compute axis-aligned bounding box of all participants.
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final t in live.values) {
      final r = t.unrotatedRect;
      if (r.left < minX) minX = r.left;
      if (r.top < minY) minY = r.top;
      if (r.right > maxX) maxX = r.right;
      if (r.bottom > maxY) maxY = r.bottom;
    }
    if (!minX.isFinite || !minY.isFinite) return null;
    final bounds = Rect.fromLTRB(minX, minY, maxX, maxY);

    final doc = ref.read(documentControllerProvider);
    final peers = <Rect>[
      for (final l in doc.layers)
        if (!groupIds.contains(l.id) && l.visible)
          l.transform.unrotatedRect,
    ];
    final scale = ref.read(viewportControllerProvider).scale;
    final effectiveThreshold =
        scale > 0 ? _baseSnapThreshold / scale : _baseSnapThreshold;
    final prevAlign = state.snapGuides.isEmpty
        ? null
        : SnapResult(position: Offset.zero, guides: state.snapGuides);
    final align = _snapEngine.snapPosition(
      proposed: bounds.topLeft,
      size: bounds.size,
      peerRects: peers,
      canvasSize: Size(doc.width, doc.height),
      threshold: effectiveThreshold,
      previous: prevAlign,
    );

    final alignedHasV =
        align.guides.any((g) => g.axis == SnapAxis.vertical);
    final alignedHasH =
        align.guides.any((g) => g.axis == SnapAxis.horizontal);
    var dx = align.position.dx - bounds.left;
    var dy = align.position.dy - bounds.top;
    var spacingGuides = const <SpacingGuide>[];

    if (peers.length >= 2 && (!alignedHasV || !alignedHasH)) {
      final prevSpacing = state.spacingGuides.isEmpty
          ? null
          : SpacingSnapResult(
              position: Offset.zero,
              guides: state.spacingGuides,
            );
      final spacing = _snapEngine.findSpacingSnap(
        proposed: align.position,
        size: bounds.size,
        peerRects: peers,
        threshold: effectiveThreshold,
        previous: prevSpacing,
      );
      final kept = <SpacingGuide>[];
      for (final g in spacing.guides) {
        if (g.axis == SnapAxis.vertical && !alignedHasV) {
          dx += spacing.position.dx - align.position.dx;
          kept.add(g);
        } else if (g.axis == SnapAxis.horizontal && !alignedHasH) {
          dy += spacing.position.dy - align.position.dy;
          kept.add(g);
        }
      }
      spacingGuides = kept;
    }

    if (dx == 0 && dy == 0 && align.guides.isEmpty && spacingGuides.isEmpty) {
      return null;
    }
    return _GroupSnapResult(
      dx: dx,
      dy: dy,
      guides: align.guides,
      spacingGuides: spacingGuides,
    );
  }

  /// Base snap distance in *screen* pixels. Numerically matches the
  /// engine's default (6.0) so the at-1×-zoom behaviour is unchanged
  /// from before screen-space scaling was introduced.
  static const double _baseSnapThreshold = 6.0;

  /// True when two transforms differ by less than a perceptually-
  /// invisible amount. Used on commit to drop history entries for
  /// gestures that returned exactly to origin but leave behind
  /// sub-pixel smoother noise. Tolerances:
  ///   * position / size: 0.25 canvas px (< 1 screen px at 4x zoom)
  ///   * rotation: 1e-4 rad (~0.006°)
  static bool _transformsApproxEqual(LayerTransform a, LayerTransform b) {
    const posTol = 0.25;
    const sizeTol = 0.25;
    const rotTol = 1e-4;
    return (a.position.dx - b.position.dx).abs() < posTol &&
        (a.position.dy - b.position.dy).abs() < posTol &&
        (a.size.width - b.size.width).abs() < sizeTol &&
        (a.size.height - b.size.height).abs() < sizeTol &&
        (a.rotation - b.rotation).abs() < rotTol;
  }

  /// Fire a single light haptic on the rising edge of a snap engagement.
  /// Calling [HapticFeedback.selectionClick] every frame would vibrate
  /// the device continuously — we only want a single tactile "tick" the
  /// moment the gesture enters the magnetic zone.
  void _maybeFireSnapHaptic({
    required bool rotationSnapped,
    required List<SnapGuide> guides,
  }) {
    final vNow = guides.any((g) => g.axis == SnapAxis.vertical);
    final hNow = guides.any((g) => g.axis == SnapAxis.horizontal);
    final entered = (rotationSnapped && !_wasRotationSnapped) ||
        (vNow && !_wasVerticallySnapped) ||
        (hNow && !_wasHorizontallySnapped);
    _wasRotationSnapped = rotationSnapped;
    _wasVerticallySnapped = vNow;
    _wasHorizontallySnapped = hNow;
    if (entered) {
      // Selection click is the lightest, most appropriate tap on both
      // iOS and Android. Fire-and-forget; ignore platform errors so
      // tests / web / desktop don't choke.
      HapticFeedback.selectionClick().catchError((_) {});
    }
  }

  String _labelFor(InteractionHandle h) {
    switch (h) {
      case InteractionHandle.body:
        return 'Move';
      case InteractionHandle.rotate:
        return 'Rotate';
      case InteractionHandle.gesture:
        return 'Transform';
      default:
        return 'Resize';
    }
  }
}

final interactionControllerProvider =
    NotifierProvider<InteractionController, InteractionUiState>(
  InteractionController.new,
);

/// Internal carry-type for a single-call snap query result that
/// combines alignment guides, equal-spacing guides, and the final
/// snapped position.
@immutable
class _CombinedSnap {
  const _CombinedSnap({
    required this.position,
    required this.guides,
    required this.spacingGuides,
  });
  final Offset position;
  final List<SnapGuide> guides;
  final List<SpacingGuide> spacingGuides;
}

/// Carry-type for [InteractionController._snapGroupBounds]. Holds the
/// uniform translation and the guides to publish, decoupled from any
/// individual layer.
@immutable
class _GroupSnapResult {
  const _GroupSnapResult({
    required this.dx,
    required this.dy,
    required this.guides,
    required this.spacingGuides,
  });
  final double dx;
  final double dy;
  final List<SnapGuide> guides;
  final List<SpacingGuide> spacingGuides;
}

/// Carry-type for [InteractionController._snapResize].
@immutable
class _ResizeSnapResult {
  const _ResizeSnapResult({required this.transform, required this.guides});
  final LayerTransform transform;
  final List<SnapGuide> guides;
}

/// Carry-type for [InteractionController._bestEdgeSnap]: the snapped
/// target coordinate.
@immutable
class _EdgeSnap {
  const _EdgeSnap({required this.target});
  final double target;
}
