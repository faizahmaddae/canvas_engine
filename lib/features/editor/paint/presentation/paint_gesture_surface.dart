import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/engine_constants.dart';
import '../../../settings/application/settings_controller.dart';
import '../../application/document_controller.dart';
import '../../application/live_overlay_controller.dart';
import '../../application/selection_controller.dart';
import '../../application/viewport_controller.dart';
import '../../engine/commands/transform_commands.dart';
import '../../engine/core/canvas_sizing.dart';
import '../../engine/core/editor_layer.dart';
import '../../engine/core/layer_transform.dart';
import '../../engine/core/viewport_state.dart';
import '../../engine/modules/paint/paint_layer.dart';
import '../application/paint_draft.dart';
import '../application/paint_tool_controller.dart';
import '../domain/paint_tool_type.dart';

const _uuid = Uuid();

/// Full-bleed transparent surface that turns canvas gestures into
/// [PaintLayer]s — contract §5 rows 2/3 (tb3 4/7).
///
/// Lives **inside** the viewport transform so stroke points arrive in
/// canvas-local coordinates without manual mapping. Mounted only when
/// paint mode has an active tool, so in normal editing the surface
/// doesn't exist and the viewport's pan/pinch + selection chrome
/// behave exactly as before.
///
/// Pointer routing is a raw-pointer state machine, not pan/tap
/// recognisers. The old `GestureDetector.onPan*` wiring could never
/// express the row-2 rescue — a pointer accepted by the pan arena
/// cannot be re-routed to the viewport — so [_PaintPointerRecognizer]
/// claims every pointer on down (row 3: one finger on the canvas IS a
/// stroke) and the surface tracks pointer count itself:
///
///   * 1 finger — buffered for [EngineConstants.paintDraftBufferLatency]
///     / until slop, then drafts (or sweeps, for the eraser);
///   * a 2nd finger — CANCELS an in-flight draft (a draft is not an
///     overlay preview; discarding is §7-correct) or COMMITS an
///     in-flight eraser sweep (that IS an overlay preview; §7 says
///     commit-on-interrupt), then drives the viewport pinch directly
///     via [ViewportController.gestureUpdate] — palm/zoom rescue;
///   * a sub-slop single-finger release — freestyle commits a DOT,
///     the eraser erases a hit (a miss is a silent no-op), every
///     other kind is a no-op. Taps NEVER exit the mode any more;
///     exit is the Done pill + the pasteboard tap (the background
///     detector's paint branch — pointers on the pasteboard never
///     reach this surface, which only covers the document board).
///
/// Every committed drawing flows through [DocumentController.execute]
/// → [AddLayerCommand] / [RemoveLayerCommand], producing exactly one
/// undo step per finished gesture.
class PaintGestureSurface extends ConsumerStatefulWidget {
  const PaintGestureSurface({
    super.key,
    required this.docSize,
    this.viewportBodyKey,
  });

  final Size docSize;

  /// Key of the render box the viewport transform is laid out in (the
  /// canvas widget's ClipRect). The two-finger rescue must feed
  /// [ViewportController.gestureUpdate] focals in THAT box's local
  /// space — the same space `viewport.translation` is defined in;
  /// global coordinates would drift the zoom anchor by the AppBar /
  /// status-bar offset (see the background handler's focal comment in
  /// editor_canvas.dart). Optional: headless test harnesses that
  /// mount the surface alone may omit it, falling back to global
  /// coordinates (identical up to a constant offset — exact for pan,
  /// anchor-shifted for zoom, irrelevant without a real viewport).
  final GlobalKey? viewportBodyKey;

  @override
  ConsumerState<PaintGestureSurface> createState() =>
      _PaintGestureSurfaceState();
}

/// Per-sequence phase of the paint pointer state machine. A sequence
/// spans from the first pointer down until the last pointer lifts.
enum _PaintSequenceMode {
  /// No pointers down.
  idle,

  /// One finger down, its point buffered — no draft yet. Exits to
  /// [drafting]/[sweeping] (slop or latency), [navigating] (second
  /// finger) or [idle] (release → tap semantics).
  buffered,

  /// Stroke draft in flight (non-eraser tools).
  drafting,

  /// Eraser sweep in flight (removals staged on the overlay).
  sweeping,

  /// Two-finger (or more) viewport navigation; sticky until the last
  /// finger lifts — a finger lifting mid-pinch rebases to a pan
  /// instead of resuming a stroke with a stale coordinate frame.
  navigating,
}

class _PaintGestureSurfaceState extends ConsumerState<PaintGestureSurface> {
  PaintDraft? _draft;

  /// Eraser-sweep accumulator (contract §3: one gesture = one
  /// history entry). Hits stage on the overlay's removals channel
  /// for instant visual feedback and commit as ONE command on
  /// gesture end. Insertion-ordered so the composite removes in
  /// sweep order.
  final List<String> _sweepErasedIds = <String>[];

  _PaintSequenceMode _mode = _PaintSequenceMode.idle;

  /// Live pointers of the current sequence: pointer id → latest
  /// GLOBAL position (globals stay valid while the viewport moves
  /// underneath the fingers; canvas-local move coordinates use the
  /// transform captured at pointer-down and are only trusted while
  /// drafting/sweeping, when the viewport is guaranteed static).
  final Map<int, Offset> _pointersGlobal = <int, Offset>{};

  /// Buffered first-finger point (see
  /// [EngineConstants.paintDraftBufferLatency]).
  Offset? _bufferedLocal;
  Offset? _bufferedGlobal;
  Timer? _draftBufferTimer;

  /// Navigation session reference frame, captured when the second
  /// finger lands and re-based on every pointer-count change.
  ViewportState? _navStartViewport;
  Offset? _navStartFocal;
  double _navStartSpan = 0;

  @override
  void dispose() {
    _draftBufferTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(paintToolControllerProvider);
    if (session.activeTool == null) return const SizedBox.shrink();

    return Positioned.fill(
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          _PaintPointerRecognizer:
              GestureRecognizerFactoryWithHandlers<_PaintPointerRecognizer>(
                () => _PaintPointerRecognizer(),
                (instance) => instance
                  ..onDown = _onPointerDown
                  ..onMove = _onPointerMove
                  ..onUp = _onPointerUp
                  ..onCancelPointer = _onPointerCancel,
              ),
        },
        child: _draft == null
            ? const SizedBox.expand()
            : _DraftPreview(draft: _draft!),
      ),
    );
  }

  // ----------------------------------------------------- pointer machine

  void _onPointerDown(int pointer, Offset global, Offset local) {
    _pointersGlobal[pointer] = global;
    final count = _pointersGlobal.length;
    if (count == 1) {
      _mode = _PaintSequenceMode.buffered;
      _bufferedLocal = local;
      _bufferedGlobal = global;
      _draftBufferTimer?.cancel();
      _draftBufferTimer = Timer(
        EngineConstants.paintDraftBufferLatency,
        _onDraftBufferElapsed,
      );
      return;
    }
    if (count == 2) {
      // Row 2 rescue: the second finger turns the sequence into
      // viewport navigation, whatever it was doing.
      _cancelDraftBufferTimer();
      switch (_mode) {
        case _PaintSequenceMode.drafting:
          // Discard, don't commit: a draft is not an overlay preview
          // (§7 covers previews of EXISTING layers; a half stroke the
          // user is bailing out of must not become a layer).
          setState(() => _draft = null);
        case _PaintSequenceMode.sweeping:
          // The sweep IS an overlay preview: commit on interruption,
          // never discard — the layers the user watched disappear
          // must stay gone (§7).
          _commitEraserSweep();
        case _PaintSequenceMode.buffered:
        case _PaintSequenceMode.navigating:
        case _PaintSequenceMode.idle:
          break;
      }
      _mode = _PaintSequenceMode.navigating;
      _navRebase();
      return;
    }
    // Third+ finger while navigating: fold it in by re-basing.
    if (_mode == _PaintSequenceMode.navigating) _navRebase();
  }

  void _onPointerMove(int pointer, Offset global, Offset local) {
    if (!_pointersGlobal.containsKey(pointer)) return;
    _pointersGlobal[pointer] = global;
    switch (_mode) {
      case _PaintSequenceMode.buffered:
        final origin = _bufferedGlobal;
        if (origin == null || (global - origin).distance <= kTouchSlop) {
          return;
        }
        _cancelDraftBufferTimer();
        final tool = ref.read(paintToolControllerProvider).activeTool;
        if (tool == null) return;
        if (tool == PaintToolType.eraser) {
          _mode = _PaintSequenceMode.sweeping;
          _sweepErasedIds.clear();
          _sweepEraseAt(_bufferedLocal ?? local);
          _sweepEraseAt(local);
        } else {
          _startDraft(tool, _bufferedLocal ?? local);
          _mode = _PaintSequenceMode.drafting;
          _draftAppend(local);
        }
      case _PaintSequenceMode.drafting:
        _draftAppend(local);
      case _PaintSequenceMode.sweeping:
        _sweepEraseAt(local);
      case _PaintSequenceMode.navigating:
        _navUpdate();
      case _PaintSequenceMode.idle:
        break;
    }
  }

  void _onPointerUp(int pointer, Offset global) {
    if (_pointersGlobal.remove(pointer) == null) return;
    switch (_mode) {
      case _PaintSequenceMode.buffered:
        // Sub-slop single-finger release: tap semantics per tool.
        _cancelDraftBufferTimer();
        _mode = _PaintSequenceMode.idle;
        _handleTapRelease();
      case _PaintSequenceMode.drafting:
        if (_pointersGlobal.isEmpty) {
          _mode = _PaintSequenceMode.idle;
          _commitDraft();
        }
      case _PaintSequenceMode.sweeping:
        if (_pointersGlobal.isEmpty) {
          _mode = _PaintSequenceMode.idle;
          _commitEraserSweep();
        }
      case _PaintSequenceMode.navigating:
        if (_pointersGlobal.isEmpty) {
          _mode = _PaintSequenceMode.idle;
          _navStartViewport = null;
          _navStartFocal = null;
          _navStartSpan = 0;
        } else {
          // 2→1 (or 3→2): continue as a pan/pinch from a fresh
          // reference — never resume a stroke mid-sequence, the
          // canvas has moved under the finger.
          _navRebase();
        }
      case _PaintSequenceMode.idle:
        break;
    }
  }

  void _onPointerCancel(int pointer) {
    if (_pointersGlobal.remove(pointer) == null) return;
    if (_pointersGlobal.isNotEmpty) {
      if (_mode == _PaintSequenceMode.navigating) _navRebase();
      return;
    }
    _cancelDraftBufferTimer();
    switch (_mode) {
      case _PaintSequenceMode.sweeping:
        // Overlay previews commit on interruption, never discard (§7).
        _commitEraserSweep();
      case _PaintSequenceMode.drafting:
        setState(() => _draft = null);
      case _PaintSequenceMode.buffered:
      case _PaintSequenceMode.navigating:
      case _PaintSequenceMode.idle:
        break;
    }
    _mode = _PaintSequenceMode.idle;
    _navStartViewport = null;
    _navStartFocal = null;
    _navStartSpan = 0;
  }

  // ------------------------------------------------------------ buffering

  void _cancelDraftBufferTimer() {
    _draftBufferTimer?.cancel();
    _draftBufferTimer = null;
  }

  /// The buffer latency elapsed with the finger still resting
  /// sub-slop: flush the buffered point into a visible draft so a
  /// press-and-hold shows its dot preview. Eraser holds stay
  /// buffered — a sweep is meaningless without movement, and the
  /// sub-slop release must stay a discrete tap-erase.
  void _onDraftBufferElapsed() {
    if (_mode != _PaintSequenceMode.buffered) return;
    final tool = ref.read(paintToolControllerProvider).activeTool;
    final local = _bufferedLocal;
    if (tool == null || tool == PaintToolType.eraser || local == null) return;
    _startDraft(tool, local);
    _mode = _PaintSequenceMode.drafting;
  }

  /// Sub-slop single-finger release (a tap on the canvas):
  ///
  ///   * freestyle → commit a DOT through the normal draft pipeline
  ///     (PaintDraft.toLayer accepts a 1-point freestyle; the painter
  ///     draws the circle) — one AddLayer entry like any stroke;
  ///   * eraser → erase a hit; a MISS is a silent no-op;
  ///   * every other kind needs two distinct points — no-op.
  ///
  /// Deliberately NO exit path here: stray taps used to dismiss paint
  /// mode (any-tap-exits) which made the mode feel booby-trapped.
  /// Exit is the Done pill and the pasteboard tap only.
  void _handleTapRelease() {
    final tool = ref.read(paintToolControllerProvider).activeTool;
    final local = _bufferedLocal;
    _bufferedLocal = null;
    _bufferedGlobal = null;
    if (tool == null || local == null) return;
    if (tool == PaintToolType.eraser) {
      _eraseAt(local);
      return;
    }
    if (tool != PaintToolType.freestyle) return;
    final session = ref.read(paintToolControllerProvider);
    final doc = ref.read(documentControllerProvider);
    final dot = PaintDraft(
      kind: PaintKind.freestyle,
      strokeColor: session.strokeColor,
      strokeWidth: session.strokeWidth,
      fillColor: session.fillColor,
      sides: session.polygonSides,
      blurSigma: CanvasSizing.scaleDimension(session.blurRadius, doc),
      points: [local],
    );
    final layer = dot.toLayer(id: _uuid.v4(), docSize: widget.docSize);
    if (layer == null) return;
    ref
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(layer));
  }

  // -------------------------------------------------------------- drafting

  void _startDraft(PaintToolType tool, Offset local) {
    final session = ref.read(paintToolControllerProvider);
    setState(() {
      // The blur slider stores its value as *reference px* (designed
      // against the 1080-square canvas) — same model as the text
      // controller's font-size slider. Scaling at draft-creation
      // time via `CanvasSizing.scaleDimension` means a "16" pick
      // reads at the same visual softness on a 100×100 sticker as
      // on a 12000×12000 poster, instead of vanishing on the big
      // canvas and erasing the layer on the small one. Stroke
      // width / fill / sides are user-picked geometry, so they
      // pass through unchanged.
      final doc = ref.read(documentControllerProvider);
      _draft = PaintDraft(
        kind: _kindFor(tool),
        strokeColor: session.strokeColor,
        strokeWidth: session.strokeWidth,
        fillColor: session.fillColor,
        sides: session.polygonSides,
        blurSigma: CanvasSizing.scaleDimension(session.blurRadius, doc),
        points: [local],
      );
    });
  }

  void _draftAppend(Offset local) {
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      if (draft.kind == PaintKind.freestyle) {
        draft.points.add(local);
      } else {
        // Two-point geometry: replace the trailing endpoint each tick.
        if (draft.points.length == 1) {
          draft.points.add(local);
        } else {
          draft.points[draft.points.length - 1] = local;
        }
      }
    });
  }

  void _commitDraft() {
    final draft = _draft;
    if (draft == null) return;
    final layer = draft.toLayer(id: _uuid.v4(), docSize: widget.docSize);
    setState(() => _draft = null);
    if (layer == null) return; // degenerate (zero-area) gesture
    ref
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(layer));
  }

  // ------------------------------------------------------------ navigation

  /// Capture (or re-capture) the navigation reference frame from the
  /// CURRENT viewport + pointer geometry. Called when the second
  /// finger lands and on every later pointer-count change, mirroring
  /// the rebase model of the selection body recogniser: after a
  /// rebase the next update reports `scale = 1` relative to the new
  /// finger configuration, so the canvas never jumps.
  void _navRebase() {
    _navStartViewport = ref.read(viewportControllerProvider);
    _navStartFocal = _navFocal();
    _navStartSpan = _navSpan();
  }

  void _navUpdate() {
    final start = _navStartViewport;
    final startFocal = _navStartFocal;
    if (start == null || startFocal == null) return;
    // Honour the user's pan/zoom gesture toggles exactly like the
    // background viewport handler: disabling pan freezes the focal,
    // disabling zoom forces unit scale.
    final settings = ref.read(appSettingsProvider);
    if (!settings.canvasPanEnabled && !settings.canvasZoomEnabled) return;
    final currentFocal = settings.canvasPanEnabled ? _navFocal() : startFocal;
    final ratio = _navStartSpan <= 0 ? 1.0 : _navSpan() / _navStartSpan;
    final effectiveScale = settings.canvasZoomEnabled ? ratio : 1.0;
    ref
        .read(viewportControllerProvider.notifier)
        .gestureUpdate(
          startState: start,
          startFocal: startFocal,
          currentFocal: currentFocal,
          scale: effectiveScale,
        );
  }

  /// Centroid of the live pointers in the viewport body's local space
  /// (see [PaintGestureSurface.viewportBodyKey]).
  Offset _navFocal() {
    var sum = Offset.zero;
    for (final p in _pointersGlobal.values) {
      sum += p;
    }
    final centroid = sum / _pointersGlobal.length.toDouble();
    final box = widget.viewportBodyKey?.currentContext?.findRenderObject();
    if (box is RenderBox) return box.globalToLocal(centroid);
    return centroid;
  }

  /// Distance between the first two live pointers (insertion order),
  /// the scale reference for the pinch. `0` = pan-only (one pointer).
  double _navSpan() {
    if (_pointersGlobal.length < 2) return 0;
    final ps = _pointersGlobal.values.toList(growable: false);
    return (ps[0] - ps[1]).distance;
  }

  // ---------------------------------------------------------------- eraser

  /// Phase-1 eraser hit test: the topmost paint layer whose oriented
  /// bounding box contains [local], skipping [exclude] (layers
  /// already staged for removal by the in-flight sweep — the
  /// committed doc still contains them mid-gesture). Other layer
  /// kinds (text/shape/image) are deliberately skipped — the eraser
  /// is "paint only" by spec to keep behaviour predictable.
  EditorLayer? _hitPaintLayer(Offset local, {Set<String> exclude = const {}}) {
    final doc = ref.read(documentControllerProvider);
    for (var i = doc.layers.length - 1; i >= 0; i--) {
      final layer = doc.layers[i];
      if (!layer.visible || layer.locked) continue;
      if (layer is! PaintLayer) continue;
      if (exclude.contains(layer.id)) continue;
      if (_containsLocal(layer.transform, local)) return layer;
    }
    return null;
  }

  /// Discrete eraser TAP: one hit = one [RemoveLayerCommand] — a
  /// tap is its own history entry (§3), unchanged from before the
  /// sweep batching. Returns whether a layer was actually erased.
  bool _eraseAt(Offset local) {
    final hit = _hitPaintLayer(local);
    if (hit == null) return false;
    ref
        .read(documentControllerProvider.notifier)
        .execute(RemoveLayerCommand(hit.id));
    // If the erased paint layer happened to be selected (e.g. user
    // tapped it to select it and then entered paint/eraser mode),
    // clear selection so no dangling id remains in SelectionState.
    if (ref.read(selectionControllerProvider).contains(hit.id)) {
      ref.read(selectionControllerProvider.notifier).clear();
    }
    return true;
  }

  /// Sweep tick: stage a hit on the overlay's removals channel so
  /// the layer disappears instantly WITHOUT touching the committed
  /// document — the whole sweep commits once in
  /// [_commitEraserSweep] (§2/§3).
  void _sweepEraseAt(Offset local) {
    final hit = _hitPaintLayer(local, exclude: _sweepErasedIds.toSet());
    if (hit == null) return;
    _sweepErasedIds.add(hit.id);
    ref.read(liveOverlayProvider.notifier).removeLayer(hit.id);
  }

  /// Seal the sweep: clear the overlay and execute ONE command for
  /// every accumulated hit (clear-then-execute in one synchronous
  /// run, so the erased layers never flash back). A single-hit
  /// sweep stays a bare [RemoveLayerCommand]; multi-hit sweeps
  /// composite under the same 'Remove layer' label so undo reads
  /// identically either way — and one undo restores every layer
  /// the sweep took.
  void _commitEraserSweep() {
    final ids = List<String>.of(_sweepErasedIds);
    _sweepErasedIds.clear();
    if (ids.isEmpty) return;
    ref.read(liveOverlayProvider.notifier).clear();
    final commands = <RemoveLayerCommand>[
      for (final id in ids) RemoveLayerCommand(id),
    ];
    ref
        .read(documentControllerProvider.notifier)
        .execute(
          commands.length == 1
              ? commands.single
              : CompositeCommand(commands, labelOverride: 'Remove layer'),
        );
    final selection = ref.read(selectionControllerProvider);
    if (ids.any(selection.contains)) {
      ref.read(selectionControllerProvider.notifier).clear();
    }
  }

  /// Oriented bounding-box hit test — transforms [local] into the
  /// layer's local space using the inverse rotation about its centre.
  bool _containsLocal(LayerTransform t, Offset local) {
    final cx = t.position.dx + t.size.width / 2;
    final cy = t.position.dy + t.size.height / 2;
    final dx = local.dx - cx;
    final dy = local.dy - cy;
    final c = math.cos(-t.rotation);
    final s = math.sin(-t.rotation);
    final lx = dx * c - dy * s + t.size.width / 2;
    final ly = dx * s + dy * c + t.size.height / 2;
    return lx >= 0 && ly >= 0 && lx <= t.size.width && ly <= t.size.height;
  }

  PaintKind _kindFor(PaintToolType tool) {
    switch (tool) {
      case PaintToolType.freestyle:
        return PaintKind.freestyle;
      case PaintToolType.line:
        return PaintKind.line;
      case PaintToolType.arrow:
        return PaintKind.arrow;
      case PaintToolType.rectangle:
        return PaintKind.rectangle;
      case PaintToolType.circle:
        return PaintKind.circle;
      case PaintToolType.dashLine:
        return PaintKind.dashLine;
      case PaintToolType.dashDotLine:
        return PaintKind.dashDotLine;
      case PaintToolType.hexagon:
        return PaintKind.hexagon;
      case PaintToolType.polygon:
        return PaintKind.polygon;
      case PaintToolType.blur:
        return PaintKind.blur;
      case PaintToolType.eraser:
        // Eraser handled separately; never reaches the draft pipeline.
        return PaintKind.freestyle;
    }
  }
}

/// Raw multi-pointer recogniser for the paint surface.
///
/// Claims EVERY pointer the moment it lands (contract §5 row 3: one
/// finger on the canvas is a stroke, so there is nothing to arbitrate
/// — and the eager claim keeps the background detector's tap
/// recogniser from ever seeing an on-canvas tap, which is what makes
/// "stray taps don't exit paint mode" hold). It runs no gesture
/// interpretation of its own: downs/moves/ups/cancels stream to the
/// host verbatim, and the host's state machine decides
/// stroke-vs-dot-vs-sweep-vs-viewport-pinch from pointer count and
/// movement. This is the piece the old `GestureDetector.onPan*`
/// wiring could not express: a pan-accepted pointer can never be
/// re-routed to the viewport, but a host that OWNS the raw pointers
/// can drive [ViewportController.gestureUpdate] with them directly.
class _PaintPointerRecognizer extends OneSequenceGestureRecognizer {
  void Function(int pointer, Offset global, Offset local)? onDown;
  void Function(int pointer, Offset global, Offset local)? onMove;
  void Function(int pointer, Offset global)? onUp;
  void Function(int pointer)? onCancelPointer;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);
    onDown?.call(event.pointer, event.position, event.localPosition);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      // NOTE: localPosition is computed with the transform captured
      // at pointer-down. The host only consumes it while drafting /
      // sweeping — phases in which the viewport is guaranteed static
      // — and uses the (always-valid) global position for navigation.
      onMove?.call(event.pointer, event.position, event.localPosition);
    } else if (event is PointerUpEvent) {
      onUp?.call(event.pointer, event.position);
      stopTrackingPointer(event.pointer);
    } else if (event is PointerCancelEvent) {
      onCancelPointer?.call(event.pointer);
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'paint pointer surface';
}

/// Preview wrapper. Selects between a [CustomPaint] (for vector kinds)
/// and a real [BackdropFilter] (for blur) so the in-flight preview
/// always matches what the committed layer will look like.
class _DraftPreview extends StatelessWidget {
  const _DraftPreview({required this.draft});

  final PaintDraft draft;

  @override
  Widget build(BuildContext context) {
    if (draft.kind == PaintKind.blur) {
      final bounds = draft.previewBounds();
      if (bounds == null) return const SizedBox.expand();
      return Stack(
        children: [
          Positioned(
            left: bounds.left,
            top: bounds.top,
            width: bounds.width,
            height: bounds.height,
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: draft.blurSigma,
                  sigmaY: draft.blurSigma,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      );
    }
    return CustomPaint(
      size: Size.infinite,
      painter: _DraftPainter(draft),
      isComplex: true,
      willChange: true,
    );
  }
}

/// Painter for the in-flight draft. Reuses [PaintLayerPainter]'s
/// rendering so the preview pixels match the committed layer 1:1.
class _DraftPainter extends CustomPainter {
  _DraftPainter(this.draft);

  final PaintDraft draft;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = draft.previewBounds();
    if (bounds == null) return;
    canvas.save();
    canvas.translate(bounds.left, bounds.top);
    final inner = PaintLayerPainter(
      kind: draft.kind,
      normalizedPoints: draft.normalizedFor(bounds),
      strokeColor: draft.strokeColor,
      strokeWidth: draft.strokeWidth,
      sides: draft.kind == PaintKind.hexagon ? 6 : draft.sides,
      fillColor: _previewSupportsFill(draft.kind) ? draft.fillColor : null,
    );
    inner.paint(canvas, bounds.size);
    canvas.restore();
  }

  static bool _previewSupportsFill(PaintKind kind) =>
      kind == PaintKind.rectangle ||
      kind == PaintKind.circle ||
      kind == PaintKind.hexagon ||
      kind == PaintKind.polygon;

  @override
  bool shouldRepaint(covariant _DraftPainter old) => true;
}
