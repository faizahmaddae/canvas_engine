import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/constants/engine_constants.dart';
import '../../engine/core/layer_transform.dart';
import '../../engine/core/selection_state.dart';
import '../../engine/core/viewport_state.dart';
import '../../engine/interaction/layer_space_mapper.dart';
import 'handle_drag_detector.dart';
import '../../../../app/theme/app_icons.dart';

enum DragPhase { start, update, end }

/// Push the four corners of a (possibly rotated) screen-space quad
/// outward by [d] dp along the quad's local right and down axes.
///
/// Used by both [LayerSelectionOverlay] and [GroupSelectionOverlay] to
/// add a uniform visual gap between the layer's rendered bounds and
/// the selection chrome (frame stroke + handles). Rotation is
/// preserved because the outset is expressed in the quad's local
/// frame, not in screen axes.
///
/// Returns `[tl, tr, bl, br]` (same order as inputs). Falls back to
/// the input quad when [d] is zero or when an edge has degenerate
/// length (e.g. a brand-new layer being placed) so the chrome never
/// jumps to NaN coordinates.
@visibleForTesting
List<Offset> outsetSelectionQuad(
  Offset tl,
  Offset tr,
  Offset bl,
  Offset br,
  double d,
) {
  if (d == 0) return [tl, tr, bl, br];
  final rightVec = tr - tl;
  final downVec = bl - tl;
  final rightLen = rightVec.distance;
  final downLen = downVec.distance;
  if (rightLen < 1e-6 || downLen < 1e-6) return [tl, tr, bl, br];
  final right = rightVec / rightLen;
  final down = downVec / downLen;
  final dx = right * d;
  final dy = down * d;
  return [tl - dx - dy, tr + dx - dy, bl - dx + dy, br + dx + dy];
}

/// Snapshot of an in-flight body gesture, emitted by
/// [_BodyMultiTouchRecognizer] every pointer event.
///
/// Carries everything the [interactionControllerProvider] needs to drive
/// a multi-touch transform: focal in *global* coordinates (the consumer
/// converts to canvas space), cumulative scale + rotation since the
/// last rebase, and the live pointer count so the controller can
/// rebase its session on 1↔n transitions without the layer jumping.
class BodyGestureUpdate {
  const BodyGestureUpdate({
    required this.phase,
    required this.focalGlobal,
    required this.scale,
    required this.rotation,
    required this.pointerCount,
  });

  final DragPhase phase;
  final Offset focalGlobal;
  final double scale;
  final double rotation;
  final int pointerCount;
}

typedef BodyGestureCallback = void Function(BodyGestureUpdate update);

typedef HandleDragCallback =
    void Function(
      InteractionHandle handle,
      Offset globalPointerCanvas,
      DragPhase phase,
    );

/// Selection chrome rendered in **screen space**, above the viewport
/// transform.
///
/// Why not in canvas space? When the document is large (e.g. 2048\u00d72048)
/// the viewport must scale down significantly to fit the screen, and any
/// chrome drawn inside that transform shrinks with it \u2014 producing
/// 3-pixel-wide handles that nobody can grab. Drawing the frame and
/// handles outside the transform keeps their visual + touch sizes
/// constant in dp regardless of document size or zoom.
///
/// Position math: this widget receives the layer's [LayerTransform] in
/// canvas-space and the current [ViewportState], computes each corner in
/// canvas-space (rotated around the layer centre), then maps each point
/// through `p \u00d7 scale + translation` to obtain screen-space
/// coordinates the handles are positioned at. Rotation is preserved
/// because the viewport applies uniform scale + translation only.
class LayerSelectionOverlay extends StatelessWidget {
  const LayerSelectionOverlay({
    super.key,
    required this.transform,
    required this.viewport,
    required this.onHandle,
    this.onBody,
    this.onBodyTap,
    this.onBodyLongPress,
    this.shouldClaimBody,
    this.shouldDeferStartBody,
    this.activeHandle,
    this.isSnapped = false,
    this.showHandles = true,
  });

  final LayerTransform transform;
  final ViewportState viewport;
  final HandleDragCallback onHandle;

  /// Predicate consulted by the body drag surface on every pointer-down
  /// to decide whether to claim the gesture arena. When `null` the
  /// surface always claims (legacy behaviour).
  ///
  /// Used by the editor to forward taps that land on a visually-higher
  /// overlapping layer through to the canvas tap detector — without
  /// this, the selected layer's body surface (which covers the whole
  /// rotated bounding rect) would eat the tap and the user would have
  /// to manually deselect before they could pick the top object.
  ///
  /// Returning `false` causes the recogniser to ignore the pointer
  /// entirely (no tracking, no arena resolution), so it falls through
  /// to whatever recogniser sits below in hit-test order — exactly the
  /// behaviour we want for selection switching.
  final bool Function(Offset globalPosition)? shouldClaimBody;

  /// Optional predicate consulted on the FIRST pointer-down to decide
  /// whether to defer emitting [DragPhase.start] until movement past
  /// [kTouchSlop] or a second finger arrives.
  ///
  /// The host wires this so that pointers landing on the selected
  /// layer's rotated bbox start the session immediately (drag is the
  /// most likely intent and off-canvas recovery needs zero-frame
  /// responsiveness), while pointers landing on empty canvas defer
  /// — keeping tap, long-press and pause-then-drag intents intact.
  /// See [_BodyMultiTouchRecognizer.shouldDeferStart].
  final bool Function(Offset globalPosition)? shouldDeferStartBody;

  /// Called when the user drags inside the layer body via the screen-space
  /// drag surface. The surface lives at the same z-order as the handles
  /// (above the viewport gesture detector) and uses a custom multi-touch
  /// recogniser that claims **every** pointer that lands on it on
  /// pointer-down. This guarantees that:
  ///
  ///   * the layer always wins the gesture arena over the background
  ///     pan/pinch — even when partially or fully outside the canvas;
  ///   * a second finger landing on the body cannot fall through to the
  ///     viewport's `ScaleGestureRecognizer` (the previous bug, where
  ///     pinching a selected object also panned/zoomed the canvas).
  ///
  /// When null, no body surface is rendered (e.g. for non-movable
  /// layers).
  final BodyGestureCallback? onBody;

  /// Fired when the body surface receives a tap (pointer-down → up
  /// without exceeding [kTouchSlop]). The selection-overlay's body
  /// surface eagerly claims the gesture arena on pointer-down to
  /// guarantee drag priority, which means the canvas-level tap
  /// detector never sees taps that land on the selected layer. This
  /// callback is the escape hatch: it lets the canvas re-run its tap
  /// routing (selection switching, overlapping-layer cycling) for
  /// taps that turn out to be plain taps and not drags.
  final void Function(Offset globalPosition)? onBodyTap;

  /// Fired when the user holds a single pointer on the body surface
  /// without moving past [kTouchSlop] for [kLongPressTimeout]. Same
  /// rationale as [onBodyTap]: the eager arena claim prevents the
  /// canvas-level `LongPressGestureRecognizer` from ever firing
  /// while a layer is selected. Without this hook, the documented
  /// long-press gesture (enter multi-select mode, add long-pressed
  /// layer to the selection) would be silently dead.
  final void Function(Offset globalPosition)? onBodyLongPress;

  /// Handle currently being dragged, if any. Drives the active glyph
  /// styling so users can see which control they are driving.
  final InteractionHandle? activeHandle;

  /// When true the selection stroke thickens slightly to signal that the
  /// current rotation is inside the magnetic snap zone.
  final bool isSnapped;

  /// When false the four corner / rotate handles are not rendered.
  /// Used to give locked layers (notably the photo-mode base photo)
  /// a frame that signals selection without implying that the user
  /// can transform it. The body drag surface is independently gated
  /// by [onBody] -- the host already passes `null` for locked
  /// layers, so handles + drag are switched off together.
  final bool showHandles;

  @override
  Widget build(BuildContext context) {
    // v2 selection chrome: saffron accent (was seed violet).
    final color = AppTokens.of(context).accent;
    final size = transform.size;
    final mapper = LayerSpaceMapper(transform: transform, viewport: viewport);

    // Layer corners, layer-local → screen in one step (rotation about
    // the layer centre + viewport scale/translation).
    final tlRaw = mapper.layerToScreen(Offset.zero);
    final trRaw = mapper.layerToScreen(Offset(size.width, 0));
    final blRaw = mapper.layerToScreen(Offset(0, size.height));
    final brRaw = mapper.layerToScreen(Offset(size.width, size.height));

    // Push the chrome quad outward by [EngineConstants.selectionOutset]
    // dp along the rotated rect's local axes so the frame + handles sit
    // slightly outside the layer content. Resize/rotate are unaffected
    // — handles report raw global pointer positions to [onHandle] and
    // the InteractionEngine drives the *real* transform via pointer
    // deltas, not handle-to-corner geometry.
    final outset = outsetSelectionQuad(
      tlRaw,
      trRaw,
      blRaw,
      brRaw,
      EngineConstants.selectionOutset,
    );
    final tl = outset[0];
    final tr = outset[1];
    final bl = outset[2];
    final br = outset[3];

    // Rotation knob geometry (tb3 6/7, D-a): the knob sits
    // [EngineConstants.rotateHandleOffset] screen-dp beyond the
    // frame's top-edge midpoint along the rotated up-axis — same
    // screen-space grammar as the corner outset, so stem length is
    // constant in dp at any zoom and the whole construction rotates
    // rigidly with the layer. RTL-indifferent: pure canvas/screen
    // geometry, no directionality.
    final topMid = Offset((tl.dx + tr.dx) / 2, (tl.dy + tr.dy) / 2);
    final downVec = bl - tl;
    final downLen = downVec.distance;
    final up = downLen < 1e-6
        ? const Offset(0, -1)
        : Offset(-downVec.dx / downLen, -downVec.dy / downLen);
    final rotateKnob = topMid + up * EngineConstants.rotateHandleOffset;

    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Screen-space body drag surface. Sits BELOW the frame stroke
          // and handles in the Stack so corner / rotate handles always
          // win the hit test, but ABOVE the viewport's pan/pinch
          // gesture detector — guaranteeing that touches on the
          // selected layer drive the layer, not the canvas.
          //
          // The surface fills the entire screen (translucent
          // hit-test) rather than tracing the layer's rotated
          // rectangle. The reason is multi-touch on small objects:
          // when the first finger has landed on the layer and a
          // body gesture session is in flight, the SECOND finger
          // often lands on empty canvas (Canva / CapCut behaviour).
          // A geometry-bounded surface would never see that second
          // pointer — it would leak through to the viewport's
          // ScaleGestureRecognizer and the canvas would pan/zoom
          // instead of the layer scaling. Full-screen + translucent
          // means any pointer reaches the body recogniser, which
          // then decides per-pointer whether to claim:
          //
          //   * First pointer of a sequence — gated by
          //     [shouldClaimBody] (which checks rotated-bbox hit
          //     test). Out-of-layer pointers fall through to the
          //     canvas tap detector for selection switching.
          //   * Subsequent pointers while a session is active —
          //     accepted unconditionally so the gesture owns every
          //     finger that lands during it, no matter where.
          //
          // The surface is always rendered while a selection exists
          // (even when the layer is entirely off-canvas), which is
          // what enables off-canvas recovery: as long as you can see
          // the selection chrome, you can grab the body and drag it
          // anywhere — including back inside the canvas.
          if (onBody != null)
            _BodyDragSurface(
              onDrag: onBody!,
              onTap: onBodyTap,
              onLongPress: onBodyLongPress,
              shouldClaim: shouldClaimBody,
              shouldDeferStart: shouldDeferStartBody,
            ),

          // Connecting frame stroke \u2014 constant width regardless of zoom.
          IgnorePointer(
            child: CustomPaint(
              size: Size.infinite,
              painter: _SelectionFramePainter(
                topLeft: tl,
                topRight: tr,
                bottomLeft: bl,
                bottomRight: br,
                color: color,
                strokeWidth: isSnapped
                    ? EngineConstants.selectionStroke + 1
                    : EngineConstants.selectionStroke,
              ),
            ),
          ),

          if (showHandles) ...[
            // Stem connecting the frame's top edge to the rotation
            // knob — painted below the handles so the knob glyph
            // sits on top of it.
            IgnorePointer(
              child: CustomPaint(
                size: Size.infinite,
                painter: _RotateStemPainter(
                  from: topMid,
                  to: rotateKnob,
                  color: color,
                  strokeWidth: EngineConstants.selectionStroke,
                ),
              ),
            ),
            _PositionedHandle(
              center: tl,
              debugLabel: 'topLeft',
              onDrag: (p, phase) =>
                  onHandle(InteractionHandle.topLeft, p, phase),
              child: _CornerGlyph(
                color: color,
                active: activeHandle == InteractionHandle.topLeft,
              ),
            ),
            _PositionedHandle(
              center: tr,
              debugLabel: 'topRight',
              onDrag: (p, phase) =>
                  onHandle(InteractionHandle.topRight, p, phase),
              child: _CornerGlyph(
                color: color,
                active: activeHandle == InteractionHandle.topRight,
              ),
            ),
            _PositionedHandle(
              center: bl,
              debugLabel: 'bottomLeft',
              onDrag: (p, phase) =>
                  onHandle(InteractionHandle.bottomLeft, p, phase),
              child: _CornerGlyph(
                color: color,
                active: activeHandle == InteractionHandle.bottomLeft,
              ),
            ),
            _PositionedHandle(
              center: br,
              debugLabel: 'bottomRight',
              onDrag: (p, phase) =>
                  onHandle(InteractionHandle.bottomRight, p, phase),
              child: _CornerGlyph(
                color: color,
                active: activeHandle == InteractionHandle.bottomRight,
              ),
            ),
            // Dedicated rotation knob (D-a): stemmed handle above the
            // top-centre. Same glyph, same 48dp touch box, same
            // constant-dp sizing as before — only the position moved
            // (rotation math is position-agnostic: start angle is
            // captured from the pointer, updates are pure deltas).
            _PositionedHandle(
              center: rotateKnob,
              debugLabel: 'rotateKnob',
              onDrag: (p, phase) =>
                  onHandle(InteractionHandle.rotate, p, phase),
              child: _RotateGlyph(
                color: color,
                active: activeHandle == InteractionHandle.rotate,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Paints the selection rectangle as four straight segments connecting
/// the screen-space corners. Stroke width is in *screen* pixels so it
/// stays crisp at any document size or zoom level.
class _SelectionFramePainter extends CustomPainter {
  _SelectionFramePainter({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
    required this.color,
    required this.strokeWidth,
  });

  final Offset topLeft;
  final Offset topRight;
  final Offset bottomLeft;
  final Offset bottomRight;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;
    final path = Path()
      ..moveTo(topLeft.dx, topLeft.dy)
      ..lineTo(topRight.dx, topRight.dy)
      ..lineTo(bottomRight.dx, bottomRight.dy)
      ..lineTo(bottomLeft.dx, bottomLeft.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SelectionFramePainter old) =>
      old.topLeft != topLeft ||
      old.topRight != topRight ||
      old.bottomLeft != bottomLeft ||
      old.bottomRight != bottomRight ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

/// A Positioned 48\u00d748 hit box whose geometric centre equals [center].
/// Centre is in **screen pixels** \u2014 this widget is hosted by a
/// `Positioned.fill` placed above the viewport transform.
/// Hairline stem connecting the selection frame's top edge to the
/// dedicated rotation knob (tb3 6/7). Painted in screen space with
/// the same stroke weight as the frame so the construction reads as
/// one piece of chrome.
class _RotateStemPainter extends CustomPainter {
  const _RotateStemPainter({
    required this.from,
    required this.to,
    required this.color,
    required this.strokeWidth,
  });

  final Offset from;
  final Offset to;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(from, to, paint);
  }

  @override
  bool shouldRepaint(covariant _RotateStemPainter old) =>
      old.from != from ||
      old.to != to ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

class _PositionedHandle extends StatelessWidget {
  const _PositionedHandle({
    required this.center,
    required this.child,
    required this.onDrag,
    required this.debugLabel,
  });

  final Offset center;
  final Widget child;
  final String debugLabel;
  final void Function(Offset globalPointer, DragPhase phase) onDrag;

  @override
  Widget build(BuildContext context) {
    const touch = EngineConstants.handleTouchSize;
    return Positioned(
      left: center.dx - touch / 2,
      top: center.dy - touch / 2,
      width: touch,
      height: touch,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: HandleDragDetector(
          onDrag: onDrag,
          child: _HitBoxVisual(debugLabel: debugLabel, child: child),
        ),
      ),
    );
  }
}

class _HitBoxVisual extends StatelessWidget {
  const _HitBoxVisual({required this.child, required this.debugLabel});
  final Widget child;
  final String debugLabel;

  @override
  Widget build(BuildContext context) {
    Widget inner = Center(child: child);
    if (EngineConstants.debugPaintHitBoxes) {
      inner = DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x22FF00FF),
          border: Border.all(color: const Color(0xFFFF00FF), width: 1),
        ),
        child: _LogGlobalBounds(label: debugLabel, child: inner),
      );
    }
    return inner;
  }
}

class _LogGlobalBounds extends StatelessWidget {
  const _LogGlobalBounds({required this.child, required this.label});
  final Widget child;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (ctx) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!kDebugMode) return;
          final ro = ctx.findRenderObject() as RenderBox?;
          if (ro == null || !ro.attached) return;
          final tl = ro.localToGlobal(Offset.zero);
          final br = ro.localToGlobal(ro.size.bottomRight(Offset.zero));
          final c = Offset((tl.dx + br.dx) / 2, (tl.dy + br.dy) / 2);
          debugPrint(
            '[handle:$label] hitbox=${tl.dx.toStringAsFixed(1)},'
            '${tl.dy.toStringAsFixed(1)}\u2192${br.dx.toStringAsFixed(1)},'
            '${br.dy.toStringAsFixed(1)}  center=${c.dx.toStringAsFixed(1)},'
            '${c.dy.toStringAsFixed(1)}',
          );
        });
        return child;
      },
    );
  }
}

class _CornerGlyph extends StatelessWidget {
  const _CornerGlyph({required this.color, this.active = false});
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final size =
        EngineConstants.handleVisualSize *
        (active ? EngineConstants.handleActiveScale : 1);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: active ? color : Colors.white,
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: active
                ? color.withValues(alpha: 0.35)
                : const Color(0x33000000),
            blurRadius: active ? 6 : 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}

class _RotateGlyph extends StatelessWidget {
  const _RotateGlyph({required this.color, this.active = false});
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final size = 22.0 * (active ? EngineConstants.handleActiveScale : 1);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: active ? color : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: active
                ? color.withValues(alpha: 0.35)
                : const Color(0x33000000),
            blurRadius: active ? 8 : 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Transform.rotate(
        angle: math.pi / 4,
        child: Icon(
          AppIcons.rotateHandle,
          size: 14,
          color: active ? Colors.white : color,
        ),
      ),
    );
  }
}

/// Chrome-less, full-screen claim surface for contract §5 rows 5 and
/// 7: a 1-finger drag STARTING on an eligible, un-selected layer's
/// bbox selects that layer and translates it in the same gesture
/// (row 5, select-and-move), and a 1-finger drag STARTING on empty
/// canvas or pasteboard while a movable single selection exists
/// translates that selection (row 7's drag-anywhere amendment).
///
/// This is the same multi-touch recogniser the selection overlay's
/// body surface uses, but in LAZY arena mode
/// ([_BodyMultiTouchRecognizer.claimOnDown] == false): the first
/// pointer is tracked without resolving the arena, and the claim
/// happens only at the [kTouchSlop] crossing. Sub-slop intents (tap,
/// double-tap, long-press) therefore resolve through the canvas-level
/// recognisers with their native timing, and a second finger landing
/// before the claim abandons the sequence to the viewport pinch
/// (row 6). After the slop claim the host selects the candidate layer
/// and drives a normal body session, so later fingers join the
/// transform exactly like on the selection overlay.
///
/// The host mounts this permanently (below the selection overlays in
/// the screen-space chrome Stack) so a mid-gesture selection change —
/// which remounts the selection overlay — never disposes the
/// recogniser that owns the in-flight pointers. All mode gating
/// (multi-select, crop, mask, paint, inline edit) lives in
/// [shouldClaimBody].
class SelectAndMoveSurface extends StatelessWidget {
  const SelectAndMoveSurface({
    super.key,
    required this.onBody,
    this.shouldClaimBody,
  });

  /// Session callback, identical contract to
  /// [LayerSelectionOverlay.onBody]. [DragPhase.start] fires at the
  /// slop claim — that is the moment the host selects the candidate
  /// and starts the translate session.
  final BodyGestureCallback onBody;

  /// Consulted on the first pointer-down; returning `false` leaves
  /// the pointer entirely alone (not even tracked). The host returns
  /// `true` only for pointers landing on an eligible, movable,
  /// un-selected layer's bbox (row 5) or on empty canvas while a
  /// movable single selection exists (row 7), while no other finger
  /// is down.
  final bool Function(Offset globalPosition)? shouldClaimBody;

  @override
  Widget build(BuildContext context) {
    return _BodyDragSurface(
      onDrag: onBody,
      shouldClaim: shouldClaimBody,
      claimOnDown: false,
    );
  }
}

/// Screen-space drag surface that mirrors the layer's rotated rectangle.
///
/// This is what gives the selected layer absolute priority over the
/// background viewport pan: it sits above the viewport's gesture
/// detector in the widget tree and uses [HandleDragDetector], whose
/// recogniser claims the gesture arena on pointer-down (zero slop).
/// Once the user touches anywhere inside the layer's selection rect,
/// the parent `GestureDetector`'s tap / scale recognisers are rejected
/// before they can fire — the touch belongs to the layer.
///
/// Critically, this surface is rendered in *screen* space, not canvas
/// space, so it remains reachable when the layer is partially or fully
/// outside the canvas. The user can always grab a visible selection
/// rectangle and drag the layer back inside.
class _BodyDragSurface extends StatelessWidget {
  const _BodyDragSurface({
    required this.onDrag,
    this.onTap,
    this.onLongPress,
    this.shouldClaim,
    this.shouldDeferStart,
    this.claimOnDown = true,
  });

  final BodyGestureCallback onDrag;

  /// See [_BodyMultiTouchRecognizer.claimOnDown]. `false` selects the
  /// lazy arena mode used by [SelectAndMoveSurface].
  final bool claimOnDown;

  /// Invoked when the gesture sequence ends without ever moving past
  /// [kTouchSlop] — i.e. a true tap rather than a drag. See
  /// [LayerSelectionOverlay.onBodyTap] for why this exists.
  final void Function(Offset globalPosition)? onTap;

  /// Invoked when the user holds a single pointer without movement
  /// past [kTouchSlop] for longer than [kLongPressTimeout]. Lets the
  /// host route long-press intents (e.g. enter multi-select mode)
  /// even though the recogniser claims the arena on pointer-down.
  /// See [_BodyMultiTouchRecognizer.onLongPress].
  final void Function(Offset globalPosition)? onLongPress;

  /// See [LayerSelectionOverlay.shouldClaimBody]. Gates the FIRST
  /// pointer of a sequence; subsequent pointers landing while the
  /// gesture is in flight are accepted unconditionally inside the
  /// recogniser so the layer owns every finger of the gesture.
  final bool Function(Offset globalPosition)? shouldClaim;

  /// See [_BodyMultiTouchRecognizer.shouldDeferStart]. When `null`
  /// (default) the recogniser starts the session eagerly on the first
  /// pointer-down — preserving the on-body drag responsiveness that
  /// the off-canvas recovery flow depends on.
  final bool Function(Offset globalPosition)? shouldDeferStart;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: RawGestureDetector(
        // Translucent: pointers we don't claim fall through to the
        // canvas tap detector (selection switching, empty-canvas
        // taps, etc.). Opaque would block them.
        behavior: HitTestBehavior.translucent,
        gestures: <Type, GestureRecognizerFactory>{
          _BodyMultiTouchRecognizer:
              GestureRecognizerFactoryWithHandlers<_BodyMultiTouchRecognizer>(
                () => _BodyMultiTouchRecognizer(),
                (instance) => instance
                  ..onUpdate = onDrag
                  ..onTap = onTap
                  ..onLongPress = onLongPress
                  ..shouldClaim = shouldClaim
                  ..shouldDeferStart = shouldDeferStart
                  ..claimOnDown = claimOnDown,
              ),
        },
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Custom multi-touch recogniser used by the screen-space body drag
/// surface.
///
/// Why not [ScaleGestureRecognizer]?
///
///   * The built-in recogniser does not resolve the gesture arena until
///     the pointer has moved past `kTouchSlop` (and even then only when
///     scale or rotation crosses an internal threshold). On a selected
///     layer, that means a second finger landing on the body briefly
///     remains unclaimed — and a competing recogniser (here the
///     viewport's `ScaleGestureRecognizer`) can claim it instead. The
///     visible symptom was: the object pinched/rotated correctly, but
///     the canvas simultaneously panned/zoomed in the opposite
///     direction.
///
/// This recogniser:
///
///   1. Claims the arena for **every** pointer the moment it lands
///      (`resolve(GestureDisposition.accepted)` in `addAllowedPointer`),
///      so no pointer landing on the body can leak through to the
///      viewport's recogniser.
///   2. Tracks every pointer in a flat map and recomputes the focal
///      point + scale + rotation from scratch each frame.
///   3. On 1↔n pointer-count transitions, **rebases** its own scale /
///      rotation reference (so the next event reports `scale=1.0`,
///      `rotation=0` relative to the new finger configuration). The
///      consumer (interaction controller) does the same internally,
///      keeping the layer visually anchored across finger
///      additions/removals.
class _BodyMultiTouchRecognizer extends OneSequenceGestureRecognizer {
  BodyGestureCallback? onUpdate;

  /// Invoked exactly once per gesture sequence when the gesture turns
  /// out to be a tap (single pointer, never moved past [kTouchSlop]).
  /// See [LayerSelectionOverlay.onBodyTap].
  void Function(Offset globalPosition)? onTap;

  /// Invoked exactly once per gesture sequence when a single pointer
  /// has been held without moving past [kTouchSlop] for longer than
  /// [kLongPressTimeout]. The host treats this as a long-press intent
  /// (e.g. enter multi-select mode), exactly as if the canvas-level
  /// `GestureDetector.onLongPressStart` had fired.
  ///
  /// Why is this here? With the active-transform-surface model the
  /// recogniser claims the arena on pointer-down whenever a layer is
  /// selected, which prevents the canvas-level `LongPressGestureRecognizer`
  /// from ever winning. Without this re-injection, long-press would
  /// be silently dead while anything is selected — and long-press is
  /// the documented entry point to multi-select mode. We replicate
  /// the long-press timer locally so the intent survives the claim.
  ///
  /// Interaction with the deferred-start model (see [shouldDeferStart]):
  /// the timer only fires when `_sessionStarted == false` at timeout.
  /// For pointers that took the eager-start path (typically an
  /// on-bbox drag-arm), the session is already in flight and the
  /// timer's fire-time guard bails without invoking [onLongPress] —
  /// long-press is exclusively a deferred-path intent, so no phantom
  /// session ever needs to be torn down.
  void Function(Offset globalPosition)? onLongPress;

  /// Optional predicate consulted on every pointer-down. When it
  /// returns `false`, the recogniser silently ignores that pointer —
  /// it does not track it and does not resolve the arena, so the
  /// pointer is delivered to whatever recogniser sits below in hit-
  /// test order. This is what lets a tap meant for a visually-higher
  /// overlapping layer reach the canvas tap detector instead of being
  /// eaten by the selected layer's body surface.
  bool Function(Offset globalPosition)? shouldClaim;

  /// Optional predicate consulted on the FIRST pointer-down to decide
  /// whether the eager arena claim should also start a body session
  /// immediately, or wait for promotion (movement past [kTouchSlop]
  /// or a second pointer arriving).
  ///
  /// Returning `true` means "defer" — claim the arena (so viewport /
  /// long-press recognisers stay quiet) but do NOT emit
  /// [DragPhase.start] until the user's intent is unambiguous. This
  /// is what the editor uses for pointers landing on EMPTY CANVAS
  /// while a layer is selected: tapping there must remain a plain
  /// tap (so unselect-on-tap fires), holding there must remain a
  /// long-press (so multi-select-via-long-press fires), and only
  /// real movement promotes to a body drag.
  ///
  /// Returning `false` (or leaving it `null`) preserves the eager
  /// behaviour: pointer-down immediately starts a session. This is
  /// what the editor uses for pointers landing INSIDE the selected
  /// layer's rotated bounding box — the off-canvas recovery flow
  /// depends on the layer responding to the very first frame.
  bool Function(Offset globalPosition)? shouldDeferStart;

  /// Arena-claim policy. `true` (default) is the selection-overlay
  /// behaviour: resolve the arena in our favour the moment a pointer
  /// lands, so nothing below us can steal the gesture.
  ///
  /// `false` is the LAZY mode used by the select-and-move surface
  /// (contract §5 row 5): the first pointer is *tracked* but the
  /// arena is left open, and we claim it only when the pointer moves
  /// past [kTouchSlop]. Until then every competing recogniser below
  /// stays live, which is the whole point:
  ///
  ///   * a sub-slop release stays a plain tap — the canvas-level
  ///     tap / double-tap recognisers resolve NATURALLY (tap-select,
  ///     tap-cycling and double-tap-to-edit keep their exact timing,
  ///     including the double-tap window);
  ///   * a still hold stays a long-press — the canvas-level
  ///     long-press recogniser wins at timeout and we get rejected;
  ///   * a second finger arriving BEFORE the slop claim abandons the
  ///     sequence entirely (we resolve rejected) so the pair falls
  ///     through to the viewport pinch — row 6 stays strict even
  ///     when the first finger happened to land on a layer.
  ///
  /// The slop claim wins the race against the viewport's
  /// [ScaleGestureRecognizer] because scale resolves at pan-slop
  /// (2 × [kTouchSlop]) while we resolve at [kTouchSlop].
  bool claimOnDown = true;

  /// True once this sequence has resolved the arena in our favour.
  /// Always true immediately after the first pointer in eager mode;
  /// in lazy mode it flips at the slop claim. Reset per sequence.
  bool _arenaClaimed = false;

  /// Live pointer map: pointer id → latest global position.
  final Map<int, Offset> _pointers = <int, Offset>{};

  /// Reference distance + angle captured at session-start or after a
  /// pointer-count transition. Subsequent events report cumulative scale
  /// and rotation relative to these values.
  double _baseDistance = 1.0;
  double _baseAngle = 0.0;

  /// True once we've emitted [DragPhase.start] for this sequence.
  ///
  /// **Deferred-claim model**: pointer-down claims the gesture arena
  /// (so the viewport's `ScaleGestureRecognizer` can never steal it)
  /// but does NOT yet emit `DragPhase.start`. Promotion to a real
  /// session happens only when:
  ///
  ///   * a 2nd pointer arrives (pinch starts immediately, no slop
  ///     gate — Canva / CapCut behaviour), OR
  ///   * the single pointer moves past [kTouchSlop] (drag starts).
  ///
  /// This is what lets the deferred-claim long-press fire cleanly
  /// (no phantom session to tear down), lets a tap stay a tap (no
  /// `DragPhase.start` + `DragPhase.end` round-trip), and lets the
  /// framework's tap / long-press recognisers stay quiet during the
  /// pause without us emitting any visible state change.
  bool _sessionStarted = false;

  /// Tap-vs-drag tracking. The very first pointer-down position is
  /// recorded; if any subsequent move exceeds [kTouchSlop] from it, or
  /// a second pointer ever lands, the sequence is no longer a tap.
  Offset? _initialDownPosition;
  bool _movedPastSlop = false;
  int _maxConcurrentPointers = 0;

  /// Long-press timer. Armed on the FIRST pointer of a sequence,
  /// cancelled on movement past slop, on a second pointer arriving,
  /// or on pointer-up before timeout. When it fires we re-inject the
  /// long-press intent via [onLongPress] and short-circuit the rest
  /// of the sequence so neither tap nor drag fires.
  Timer? _longPressTimer;
  bool _longPressFired = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    // First-pointer gate: when no pointer is being tracked yet,
    // consult the optional [shouldClaim] predicate. Returning false
    // means "not for me" — pointer falls through to whatever
    // recogniser sits below (typically the canvas tap detector).
    //
    // Once at least one pointer is already tracked, accept every
    // additional pointer unconditionally — the gesture owns the
    // selected object regardless of where the second/third finger
    // lands. This is the Canva / CapCut behaviour: pinching a small
    // object never requires both fingers inside its bounding box.
    final isFirstPointer = _pointers.isEmpty;
    if (isFirstPointer &&
        shouldClaim != null &&
        !shouldClaim!(event.position)) {
      return;
    }
    // Lazy mode only: a second finger arriving BEFORE the slop claim
    // means the user is pinching, and contract §5 row 6 says a pinch
    // whose first finger never claimed belongs to the viewport.
    // Abandon the whole sequence — rejecting our (single) arena entry
    // hands the first pointer back to the recognisers below, and we
    // never track the new one.
    if (!isFirstPointer && !_arenaClaimed) {
      resolve(GestureDisposition.rejected);
      return;
    }
    _pointers[event.pointer] = event.position;
    if (_pointers.length > _maxConcurrentPointers) {
      _maxConcurrentPointers = _pointers.length;
    }
    _initialDownPosition ??= event.position;
    startTrackingPointer(event.pointer, event.transform);
    if (claimOnDown || !isFirstPointer) {
      // Eagerly claim the arena. This is the linchpin that prevents
      // the viewport's ScaleGestureRecognizer (and the framework's
      // long-press / tap recognisers) from ever seeing pointers we
      // accepted. Note: claiming does NOT start a session — see
      // [_sessionStarted] for the deferred-promotion model.
      resolve(GestureDisposition.accepted);
      _arenaClaimed = true;
    }
    _rebase();
    if (isFirstPointer) {
      if (!claimOnDown) {
        // Lazy arena mode: no long-press timer (the canvas-level
        // long-press recogniser below must win at timeout) and no
        // eager session — promotion AND the arena claim both happen
        // at the slop crossing in [handleEvent].
        return;
      }
      // Arm the long-press timer on the FIRST pointer only. Any
      // additional pointer cancels it (long-press is one-finger).
      _armLongPressTimer(event.position);
      // Eager-vs-deferred: when no [shouldDeferStart] predicate is
      // configured, OR it returns false for this position, start
      // the session immediately (matches the historical
      // claim-on-down-and-start behaviour that on-body drags depend
      // on). Otherwise wait for promotion via slop or a second
      // finger — see [shouldDeferStart] for rationale.
      final defer =
          shouldDeferStart != null && shouldDeferStart!(event.position);
      if (!defer) {
        _sessionStarted = true;
        _emit(DragPhase.start);
      }
    } else {
      // Second (or later) pointer arrived. Cancel any pending
      // long-press (long-press is strictly one-finger) and promote
      // the sequence into a real session immediately so pinch /
      // rotate can start without a slop delay.
      _cancelLongPressTimer();
      if (!_sessionStarted) {
        _sessionStarted = true;
        _emit(DragPhase.start);
      } else {
        // Already promoted (e.g. drag had crossed slop, then a
        // second finger landed). Notify so the consumer can rebase
        // its session against the new pointer geometry.
        _emit(DragPhase.update);
      }
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    // After a long-press fires we have already short-circuited the
    // sequence; remaining events for the same pointer should be
    // drained silently (otherwise a stray PointerUp could fire onTap
    // on top of onLongPress — two intents from one gesture).
    if (_longPressFired) {
      if (event is PointerUpEvent || event is PointerCancelEvent) {
        _pointers.remove(event.pointer);
        stopTrackingPointer(event.pointer);
        if (_pointers.isEmpty) _resetSequenceTracking();
      }
      return;
    }
    if (event is PointerMoveEvent) {
      _pointers[event.pointer] = event.position;
      if (!_movedPastSlop && _initialDownPosition != null) {
        if ((event.position - _initialDownPosition!).distance > kTouchSlop) {
          _movedPastSlop = true;
          // Movement disqualifies long-press — user is dragging,
          // not holding.
          _cancelLongPressTimer();
          if (!_arenaClaimed) {
            // Lazy mode: THIS is the arena-resolution moment for
            // select-and-move — the drag intent is now unambiguous.
            // We resolve at kTouchSlop, beating the viewport's scale
            // recogniser (which waits for pan-slop, 2×), so the tap /
            // double-tap / long-press recognisers below get rejected
            // only once a real drag has begun.
            resolve(GestureDisposition.accepted);
            _arenaClaimed = true;
          }
          // Promote the deferred claim into a real session on the
          // first slop crossing.
          if (!_sessionStarted) {
            _sessionStarted = true;
            _emit(DragPhase.start);
          }
        }
      }
      // Only stream updates once the session has started. Sub-slop
      // jitter while the long-press timer is still pending must not
      // drive the consumer.
      if (_sessionStarted) {
        _emit(DragPhase.update);
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointers.remove(event.pointer);
      stopTrackingPointer(event.pointer);
      if (_pointers.isEmpty) {
        _cancelLongPressTimer();
        if (!_arenaClaimed) {
          // Lazy sequence ended without ever claiming (sub-slop
          // release): bow out explicitly so the arena sweep hands
          // the pointer to the recognisers below — the canvas tap /
          // double-tap recognisers must win this arena, not us
          // (sweep favours the first-added member, which is us).
          resolve(GestureDisposition.rejected);
        }
        if (_sessionStarted) {
          _emit(DragPhase.end);
          _sessionStarted = false;
        }
        // Tap detection: a single-pointer sequence with no movement
        // past slop is a tap, not a drag. Forward the up-position to
        // the canvas so it can re-run its selection routing
        // (overlapping-layer cycling, etc.) for taps that landed on
        // the selected layer's body surface.
        final wasTap = !_movedPastSlop && _maxConcurrentPointers == 1;
        if (wasTap && event is PointerUpEvent) {
          onTap?.call(event.position);
        }
        _resetSequenceTracking();
      } else if (_sessionStarted) {
        // Rebase so the remaining fingers' next move reports
        // `scale=1, rotation=0` relative to their current geometry,
        // not relative to a stale reference that included the lifted
        // finger.
        _rebase();
        _emit(DragPhase.update);
      } else {
        // A pointer lifted before promotion (e.g. user briefly
        // tapped with two fingers and released one). Just rebase
        // the geometry; nothing to report yet.
        _rebase();
      }
    }
  }

  /// Arm the deferred long-press timer for the first-pointer-down at
  /// [position]. See [onLongPress] for the rationale.
  void _armLongPressTimer(Offset position) {
    _cancelLongPressTimer();
    if (onLongPress == null) return;
    _longPressTimer = Timer(kLongPressTimeout, () {
      // Re-validate state at fire time: still a single pointer, never
      // moved past slop, sequence still active. Any of these flipping
      // means the gesture became a drag/pinch and the timer should
      // have been cancelled — belt-and-braces guard.
      if (_pointers.length != 1 ||
          _movedPastSlop ||
          _sessionStarted ||
          _longPressFired) {
        return;
      }
      _longPressFired = true;
      // Deferred-claim model: no DragPhase.start was ever emitted
      // for this sequence (we promote on slop / second pointer, not
      // on pointer-down), so there is no phantom session to tear
      // down. Just call the host hook.
      onLongPress?.call(position);
    });
  }

  void _cancelLongPressTimer() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  /// Reset per-sequence tracking after the last pointer lifts. Kept
  /// in one place so [handleEvent] and the long-press post-fire
  /// drainage path stay in sync.
  void _resetSequenceTracking() {
    _initialDownPosition = null;
    _movedPastSlop = false;
    _maxConcurrentPointers = 0;
    _longPressFired = false;
    _arenaClaimed = false;
  }

  Offset _focal() {
    if (_pointers.isEmpty) return Offset.zero;
    var sx = 0.0, sy = 0.0;
    for (final p in _pointers.values) {
      sx += p.dx;
      sy += p.dy;
    }
    return Offset(sx / _pointers.length, sy / _pointers.length);
  }

  void _rebase() {
    if (_pointers.length >= 2) {
      final ps = _pointers.values.toList(growable: false);
      final dx = ps[1].dx - ps[0].dx;
      final dy = ps[1].dy - ps[0].dy;
      final d = math.sqrt(dx * dx + dy * dy);
      _baseDistance = d <= 0 ? 1.0 : d;
      _baseAngle = math.atan2(dy, dx);
    } else {
      _baseDistance = 1.0;
      _baseAngle = 0.0;
    }
  }

  void _emit(DragPhase phase) {
    var scale = 1.0;
    var rotation = 0.0;
    if (_pointers.length >= 2) {
      final ps = _pointers.values.toList(growable: false);
      final dx = ps[1].dx - ps[0].dx;
      final dy = ps[1].dy - ps[0].dy;
      final d = math.sqrt(dx * dx + dy * dy);
      scale = d / _baseDistance;
      rotation = math.atan2(dy, dx) - _baseAngle;
    }
    onUpdate?.call(
      BodyGestureUpdate(
        phase: phase,
        focalGlobal: _focal(),
        scale: scale,
        rotation: rotation,
        pointerCount: _pointers.length,
      ),
    );
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    // _sessionStarted is reset inside handleEvent when the last
    // pointer lifts; nothing to do here.
  }

  @override
  void rejectGesture(int pointer) {
    // Eager mode claims on pointer-down so the framework should never
    // reject us there (defensive: widget unmounted mid-gesture). In
    // LAZY mode ([claimOnDown] == false) rejection is a NORMAL exit:
    // the canvas-level long-press recogniser winning at timeout, a
    // handle claiming on down, or our own explicit abandon all route
    // through here. No session can have started while unclaimed, so
    // the cleanup below emits nothing in those paths.
    if (_pointers.remove(pointer) != null) {
      stopTrackingPointer(pointer);
      if (_pointers.isEmpty) {
        _cancelLongPressTimer();
        if (_sessionStarted) {
          _sessionStarted = false;
          onUpdate?.call(
            const BodyGestureUpdate(
              phase: DragPhase.end,
              focalGlobal: Offset.zero,
              scale: 1.0,
              rotation: 0.0,
              pointerCount: 0,
            ),
          );
        }
        _resetSequenceTracking();
      }
    }
    super.rejectGesture(pointer);
  }

  @override
  void dispose() {
    _cancelLongPressTimer();
    super.dispose();
  }

  @override
  String get debugDescription => 'body-multi-touch (claims-on-down)';
}

/// Selection chrome for a *group* of layers — the shared, axis-aligned
/// bounding box plus the four corner resize handles, the rotate handle,
/// and a body drag surface for translate / pinch.
///
/// Drawn in **screen space** for the same reason as
/// [LayerSelectionOverlay]: the chrome stays a constant size in dp
/// regardless of viewport zoom, so handles are always grabbable.
///
/// Group bounds are axis-aligned at rest (the AABB of every
/// participant's rotated rect at session start). DURING a rotate /
/// pinch gesture the overlay renders an oriented quad via [frameQuad]
/// instead, so the selection box rotates / scales WITH the content
/// — mirroring single-layer chrome. Without [frameQuad] the overlay
/// falls back to projecting [bounds] corners directly.
class GroupSelectionOverlay extends StatelessWidget {
  const GroupSelectionOverlay({
    super.key,
    required this.bounds,
    required this.viewport,
    required this.onBody,
    required this.onHandle,
    this.frameQuad,
    this.onBodyTap,
    this.onBodyLongPress,
    this.shouldClaimBody,
    this.shouldDeferStartBody,
    this.activeHandle,
  });

  /// Live group bounds in canvas space. Always axis-aligned. Used as
  /// the chrome geometry when [frameQuad] is null and as the
  /// hit-test region for [shouldDeferStartBody] regardless.
  final Rect bounds;

  /// Optional oriented frame in canvas space. Four corners in
  /// TL → TR → BR → BL order. When non-null, drives chrome and handle
  /// placement instead of [bounds] — the selection box then visually
  /// rotates / scales with the group during pinch / rotate gestures.
  final List<Offset>? frameQuad;
  final ViewportState viewport;

  /// Body / multi-touch driver. Same contract as
  /// [LayerSelectionOverlay.onBody] — translate when one finger is
  /// down, pinch + rotate when two are.
  final BodyGestureCallback onBody;

  /// Resize / rotate driver. The handle parameter is one of the four
  /// corners or [InteractionHandle.rotate] — group overlays do not
  /// expose edge handles (no top/right/bottom/left midpoint
  /// resize) because uniform group scale is the only well-defined
  /// resize for groups containing rotated children.
  final HandleDragCallback onHandle;

  /// Re-injection point for taps that landed inside the group body
  /// surface but turned out to be plain taps (no movement past
  /// [kTouchSlop]). Without this, the group's eager-claim recognizer
  /// would eat the tap and the canvas tap detector — which routes
  /// multi-select toggles, including the toggle-out behaviour — would
  /// never fire.
  final void Function(Offset globalPosition)? onBodyTap;

  /// Re-injection point for long-press intents on the group body
  /// surface. Same rationale as [LayerSelectionOverlay.onBodyLongPress]:
  /// the eager arena claim hides long-press from the canvas-level
  /// detector. Wired so the editor can still enter / extend
  /// multi-select via long-press while a group is active.
  final void Function(Offset globalPosition)? onBodyLongPress;

  /// Optional extra guard composed with the screen-space bbox check on
  /// the FIRST pointer of a sequence. Returning `false` keeps the
  /// pointer out of the body recogniser even when it lands inside the
  /// group's bounds — used by the editor to enforce the
  /// "first-finger-wins" rule (a viewport pinch already in flight
  /// must not be hijacked by a second finger landing on the group).
  final bool Function(Offset globalPosition)? shouldClaimBody;

  /// Defer-start predicate for the group body surface. Wired by the
  /// host so pointers landing ON the group's bounds start the
  /// session immediately (drag is the obvious intent), while
  /// pointers landing on empty canvas defer until promotion — keeping
  /// tap (mode-exit) and long-press intents fully responsive. See
  /// [_BodyMultiTouchRecognizer.shouldDeferStart].
  final bool Function(Offset globalPosition)? shouldDeferStartBody;

  final InteractionHandle? activeHandle;

  Offset _toScreen(Offset canvas) =>
      canvas * viewport.scale + viewport.translation;

  @override
  Widget build(BuildContext context) {
    // v2 selection chrome: saffron accent (was seed violet).
    final color = AppTokens.of(context).accent;
    // Pick the geometry: oriented quad (rotated frame during gesture)
    // when supplied, otherwise the axis-aligned bounds.
    final Offset tlCanvas;
    final Offset trCanvas;
    final Offset blCanvas;
    final Offset brCanvas;
    final q = frameQuad;
    if (q != null && q.length == 4) {
      tlCanvas = q[0];
      trCanvas = q[1];
      brCanvas = q[2];
      blCanvas = q[3];
    } else {
      tlCanvas = bounds.topLeft;
      trCanvas = bounds.topRight;
      blCanvas = bounds.bottomLeft;
      brCanvas = bounds.bottomRight;
    }

    final tlRaw = _toScreen(tlCanvas);
    final trRaw = _toScreen(trCanvas);
    final blRaw = _toScreen(blCanvas);
    final brRaw = _toScreen(brCanvas);

    // Same outset rule as single-layer chrome (see
    // [LayerSelectionOverlay.build]) so groups feel consistent with
    // individual selections.
    final outset = outsetSelectionQuad(
      tlRaw,
      trRaw,
      blRaw,
      brRaw,
      EngineConstants.selectionOutset,
    );
    final tl = outset[0];
    final tr = outset[1];
    final bl = outset[2];
    final br = outset[3];

    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Body drag surface for translate / pinch / rotate via
          // multi-touch. The surface is full-screen (see
          // [_BodyDragSurface]); the host wires [shouldClaimBody] to
          // the active-transform-surface policy — while a multi-
          // selection exists, a first pointer anywhere on the canvas
          // drives the group's rigid-body translate; a second finger
          // anywhere drives pinch + rotate around the gesture focal.
          // A true tap (no movement past slop) is forwarded via
          // [onBodyTap] so the canvas can route selection toggle /
          // mode-exit. The recogniser internally accepts every
          // additional pointer regardless of position so pinch on a
          // small group never requires both fingers inside its bounds.
          _BodyDragSurface(
            onDrag: onBody,
            onTap: onBodyTap,
            onLongPress: onBodyLongPress,
            shouldClaim: shouldClaimBody,
            shouldDeferStart: shouldDeferStartBody,
          ),

          IgnorePointer(
            child: CustomPaint(
              size: Size.infinite,
              painter: _SelectionFramePainter(
                topLeft: tl,
                topRight: tr,
                bottomLeft: bl,
                bottomRight: br,
                color: color,
                strokeWidth: EngineConstants.selectionStroke,
              ),
            ),
          ),

          _PositionedHandle(
            center: tl,
            debugLabel: 'group-topLeft',
            onDrag: (p, phase) => onHandle(InteractionHandle.topLeft, p, phase),
            child: _CornerGlyph(
              color: color,
              active: activeHandle == InteractionHandle.topLeft,
            ),
          ),
          _PositionedHandle(
            center: tr,
            debugLabel: 'group-topRightRotate',
            onDrag: (p, phase) => onHandle(InteractionHandle.rotate, p, phase),
            child: _RotateGlyph(
              color: color,
              active: activeHandle == InteractionHandle.rotate,
            ),
          ),
          _PositionedHandle(
            center: bl,
            debugLabel: 'group-bottomLeft',
            onDrag: (p, phase) =>
                onHandle(InteractionHandle.bottomLeft, p, phase),
            child: _CornerGlyph(
              color: color,
              active: activeHandle == InteractionHandle.bottomLeft,
            ),
          ),
          _PositionedHandle(
            center: br,
            debugLabel: 'group-bottomRight',
            onDrag: (p, phase) =>
                onHandle(InteractionHandle.bottomRight, p, phase),
            child: _CornerGlyph(
              color: color,
              active: activeHandle == InteractionHandle.bottomRight,
            ),
          ),
        ],
      ),
    );
  }
}

/// Subtle per-layer outline drawn inside the viewport transform for
/// every member of a multi-selection. No handles — the group overlay
/// owns transformation chrome. Purely an awareness affordance: tells
/// the user which layers are part of the group.
///
/// Drawn in **canvas space** (inside the viewport transform) so the
/// outlines hug the layer geometry pixel-accurately, including
/// per-layer rotation. Stroke width is divided by viewport scale so the
/// rendered stroke stays a constant number of screen pixels wide at
/// any zoom level.
class GroupMemberOutlinePainter extends CustomPainter {
  GroupMemberOutlinePainter({
    required Iterable<LayerTransform> transforms,
    required this.color,
    required this.viewportScale,
    this.strokeScreenPx = 1.0,
  }) : transforms = List<LayerTransform>.unmodifiable(transforms);

  final List<LayerTransform> transforms;
  final Color color;
  final double viewportScale;
  final double strokeScreenPx;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeScreenPx / viewportScale
      ..isAntiAlias = true;
    for (final t in transforms) {
      final centre = t.center;
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(t.rotation);
      canvas.translate(-centre.dx, -centre.dy);
      canvas.drawRect(
        Rect.fromLTWH(
          t.position.dx,
          t.position.dy,
          t.size.width,
          t.size.height,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(GroupMemberOutlinePainter old) =>
      // listEquals does an element-by-element compare. The previous
      // `!=` on `Iterable` was reference equality and almost always
      // returned true \u2014 forcing a repaint every frame even when
      // nothing visible had changed.
      !listEquals(old.transforms, transforms) ||
      old.color != color ||
      old.viewportScale != viewportScale ||
      old.strokeScreenPx != strokeScreenPx;
}
