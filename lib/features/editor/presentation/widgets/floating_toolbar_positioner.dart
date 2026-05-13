import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/widgets.dart' show EdgeInsets, Orientation;

import '../../engine/core/viewport_state.dart';

/// Where the floating toolbar landed relative to the selected layer.
enum FloatingToolbarPlacement {
  /// Toolbar sits above the layer's rotated bounding rect.
  above,

  /// Toolbar sits below the layer's rotated bounding rect.
  below,

  /// Toolbar should not be rendered (no safe slot, or caller forced
  /// hide e.g. while a sub-tool panel is open or in crop mode).
  hidden,
}

/// Resolved screen-space coordinates for a floating toolbar.
///
/// `left`/`top` are meaningless when [placement] is
/// [FloatingToolbarPlacement.hidden]; callers should treat the anchor
/// as a "do not render" signal in that case.
class FloatingToolbarAnchor {
  const FloatingToolbarAnchor({
    required this.left,
    required this.top,
    required this.placement,
  });

  /// Convenience constructor for the hidden state.
  const FloatingToolbarAnchor.hidden()
    : left = 0,
      top = 0,
      placement = FloatingToolbarPlacement.hidden;

  final double left;
  final double top;
  final FloatingToolbarPlacement placement;

  bool get isHidden => placement == FloatingToolbarPlacement.hidden;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FloatingToolbarAnchor &&
          other.left == left &&
          other.top == top &&
          other.placement == placement;

  @override
  int get hashCode => Object.hash(left, top, placement);

  @override
  String toString() => isHidden
      ? 'FloatingToolbarAnchor.hidden'
      : 'FloatingToolbarAnchor(left: $left, top: $top, placement: $placement)';
}

/// Pure positioning helper for the editor's floating quick-action
/// toolbars (text, paint, generic quick actions).
///
/// Centralises the math so every floating bar follows the exact same
/// placement rules:
///
/// 1. Map the layer's rotated bounding rect into screen space using the
///    viewport scale + translation.
/// 2. Prefer **above** the layer with [gap] of clearance.
/// 3. Fall back to **below** when above would clip the top safe area.
/// 4. Refuse to render (return [FloatingToolbarAnchor.hidden]) when
///    neither placement fits — e.g. the layer fills the whole screen
///    or the bottom panel is so tall there is no breathing room.
/// 5. Center horizontally over the layer, then clamp inside
///    `[horizontalMargin .. screenWidth - barWidth - horizontalMargin]`
///    so the bar never escapes the viewport on the sides.
/// 6. Treat [bottomReserved] as a forbidden zone (panel + dock height +
///    bottom safe-area inset). The bar will never overlap it.
/// 7. Treat the top app-bar / status notch via [safePadding] +
///    [topReserved] in the same way.
///
/// The helper is **pure**: takes plain values and returns a plain
/// value, so it is unit-testable without a widget tree, MediaQuery, or
/// Riverpod container.
class FloatingToolbarPositioner {
  FloatingToolbarPositioner._();

  /// Resolve the screen-space anchor for a floating toolbar of size
  /// `[barWidth] x [barHeight]` attached to a layer with the given
  /// transform.
  ///
  /// Set [forceHidden] to short-circuit to
  /// [FloatingToolbarAnchor.hidden] (e.g. crop mode active or a tool
  /// panel is open and the host wants to suppress floating chrome).
  static FloatingToolbarAnchor resolve({
    required Offset layerPosition,
    required Size layerSize,
    required Offset layerCenter,
    required double layerRotation,
    required ViewportState viewport,
    required Size screenSize,
    required EdgeInsets safePadding,
    required double barWidth,
    required double barHeight,
    double gap = 12,
    double horizontalMargin = 12,
    double topReserved = 0,
    double bottomReserved = 0,
    bool forceHidden = false,
  }) {
    if (forceHidden) return const FloatingToolbarAnchor.hidden();

    // ─── Step 1: rotated screen-space bounds of the layer ──────────────
    final corners = <Offset>[
      _rotate(layerPosition, layerCenter, layerRotation),
      _rotate(
        layerPosition + Offset(layerSize.width, 0),
        layerCenter,
        layerRotation,
      ),
      _rotate(
        layerPosition + Offset(0, layerSize.height),
        layerCenter,
        layerRotation,
      ),
      _rotate(
        layerPosition + Offset(layerSize.width, layerSize.height),
        layerCenter,
        layerRotation,
      ),
    ];
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final c in corners) {
      final s = c * viewport.scale + viewport.translation;
      if (s.dx < minX) minX = s.dx;
      if (s.dx > maxX) maxX = s.dx;
      if (s.dy < minY) minY = s.dy;
      if (s.dy > maxY) maxY = s.dy;
    }

    // ─── Step 2: vertical placement (above preferred) ──────────────────
    // The "safe" vertical band is [topSafe .. bottomSafe], where
    // topSafe respects the system status bar + caller-supplied
    // app bar and bottomSafe respects the dock + active panel.
    final topSafe = safePadding.top + topReserved + 8;
    final bottomSafe =
        screenSize.height - safePadding.bottom - bottomReserved - 8;

    final topAbove = minY - gap - barHeight;
    final topBelow = maxY + gap;

    // 'above' must clear both the top safe area AND not extend into
    // the bottom reserved zone (relevant when the layer itself is
    // sitting low on screen behind a tall panel).
    final fitsAbove = topAbove >= topSafe && topAbove + barHeight <= bottomSafe;
    final fitsBelow = topBelow + barHeight <= bottomSafe;

    double top;
    FloatingToolbarPlacement placement;
    if (fitsAbove) {
      top = topAbove;
      placement = FloatingToolbarPlacement.above;
    } else if (fitsBelow) {
      top = topBelow;
      placement = FloatingToolbarPlacement.below;
    } else {
      // Neither placement fits cleanly. Hide rather than render
      // overlapping the dock / panel — that was the chief complaint
      // the centralised positioner is designed to fix.
      return const FloatingToolbarAnchor.hidden();
    }

    // ─── Step 3: horizontal centre + clamp inside viewport ─────────────
    final centerX = (minX + maxX) / 2;
    var left = centerX - barWidth / 2;
    final minLeft = horizontalMargin + safePadding.left;
    final maxLeft =
        screenSize.width - barWidth - horizontalMargin - safePadding.right;
    if (maxLeft < minLeft) {
      // Bar is wider than the viewport — flush left rather than
      // produce NaN from a backwards clamp.
      left = minLeft;
    } else {
      left = left.clamp(minLeft, maxLeft);
    }

    return FloatingToolbarAnchor(left: left, top: top, placement: placement);
  }

  /// Estimated bottom-dock height in logical pixels, matching the
  /// `EditorToolDock` adaptive sizing rule (compact = 64, regular =
  /// 80). Floating toolbars pass this as `bottomReserved` so they
  /// never overlap the dock's chip strip — a dock-open panel adds
  /// further reserved height on top of this baseline.
  ///
  /// Pure (no MediaQuery dependency) so it is unit-testable. Callers
  /// extract `screen` from `MediaQuery.of(context).size` and
  /// `orientation` from `MediaQuery.of(context).orientation`.
  static double dockHeight({
    required Size screen,
    required Orientation orientation,
  }) {
    final compact =
        screen.shortestSide < 380 || orientation == Orientation.landscape;
    return compact ? 64.0 : 80.0;
  }

  /// Rotate [p] around [pivot] by [a] radians. Exposed for tests and
  /// for any caller that needs the same rotated-bounding-rect math
  /// outside of a full anchor resolve.
  static Offset _rotate(Offset p, Offset pivot, double a) {
    final c = math.cos(a);
    final s = math.sin(a);
    final dx = p.dx - pivot.dx;
    final dy = p.dy - pivot.dy;
    return Offset(pivot.dx + dx * c - dy * s, pivot.dy + dx * s + dy * c);
  }
}
