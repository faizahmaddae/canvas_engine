/// Reusable building blocks for the small **glass floating bars** that
/// hover above a single selected layer (Paint, Shape, …).
///
/// ## Why this exists
/// Paint and Shape both shipped near-verbatim copies of the same
/// `ClipRRect + BackdropFilter + Container` shell and the same
/// `_PillButton` / `_ColorDot` widgets. Every visual tweak (corner
/// radius, shadow, active-state tint) had to be done in two places.
///
/// ## What it is *not*
/// * Not a home for structural actions (duplicate / delete / order)
///   — those live in the layer overflow sheet, reached through the
///   quick-capsule's More pill.
/// * Not a "do everything" toolbar abstraction. Each tool still owns
///   its own pill content (which sheets to open, what label to show,
///   which command to dispatch). Only the *shell* and *button shape*
///   are shared.
/// * Not anchored — anchoring is `FloatingToolbarPositioner`'s job.
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_tokens.dart';
import 'editor_breakpoints.dart';

/// Standard height of a single-row floating glass bar. Kept in sync
/// with the value Paint and Shape pass to [FloatingToolbarPositioner].
///
/// This is [kMinHitTarget], deliberately. The bar was 40 and its
/// `ClipRRect` clips hit-testing, so every pill inside it topped out
/// at a 40dp tap area — under the floor the rest of the editor holds
/// itself to, and not fixable from inside the clip. tb2's a11y pass
/// recorded it as a structural ceiling and deferred it; raising the
/// shell is the structural change it was waiting for. The painted
/// pill row is unchanged at 32dp — only the glass capsule around it
/// grows, by 4dp.
const double kFloatingBarHeight = kMinHitTarget;

/// Standard horizontal margin from screen edges enforced by the
/// positioner. Constant so callers don't drift.
const double kFloatingBarHorizontalMargin = 12;

/// Standard vertical gap between the layer bounding box and the bar.
const double kFloatingBarGap = 16;

/// The blurred glass shell every floating bar shares. Pass any
/// row of pills as [child]; the shell handles padding, blur,
/// border, shadow and rounded-rect clip identically across tools so
/// the bars feel like one component family.
///
/// Caller is responsible for sizing — wrap in `SizedBox(height:
/// kFloatingBarHeight, child: FloatingGlassBar(child: …))` or let
/// `IntrinsicWidth` size it.
class FloatingGlassBar extends StatelessWidget {
  const FloatingGlassBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = tokens.border.withValues(alpha: 0.8);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          // The hairline rides on `foregroundDecoration`, not on the
          // fill: a `Border` in the box decoration INSETS the child by
          // its width on every side, and 0.6 on each edge is enough to
          // put a pill at 42.8dp — under the touch floor the bar was
          // just raised to meet. Painting it over the child keeps the
          // same pixel and gives the 1.2dp back to the pills.
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 0.6),
          ),
          decoration: BoxDecoration(
            color: tokens.surface.withValues(alpha: isDark ? 0.55 : 0.78),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          // Horizontal only (tb2 a11y pass): the vertical breathing
          // room lives INSIDE [FloatingPillButton] so the pills' tap
          // area spans the full bar height while the painted pill row
          // stays exactly where it was. The glass shell's own box is
          // sized by the caller via SizedBox(height:
          // kFloatingBarHeight).
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: child,
        ),
      ),
    );
  }
}

/// Single tappable cell inside a [FloatingGlassBar]. Idle is fully
/// transparent so a row of these reads as one connected pill; the
/// active state paints a primary-tinted fill — used by toggle pills
/// like Paint's resize-mode (Scale ↔ Free).
class FloatingPillButton extends StatelessWidget {
  const FloatingPillButton({
    super.key,
    required this.onTap,
    required this.child,
    required this.semanticLabel,
    this.active = false,
  });

  final VoidCallback onTap;
  final Widget child;

  /// When `true`, paints the primary-tinted fill that signals the
  /// pill represents the current selection (e.g. the Scale pill when
  /// the layer is in Scale mode).
  final bool active;

  /// Required so every floating pill is reachable to a screen reader.
  /// Should describe the action *and* current state when the pill
  /// represents a toggle (e.g. "Resize behavior: Scale (tap for Free)").
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // Hit area = the full bar height (tb2 a11y pass): the InkWell
    // wraps a transparent vertical halo around the painted 32dp pill,
    // so the painted pixels are independent of the tap area. The bar
    // is now kMinHitTarget tall, which puts the halo at 6dp and the
    // pills on the floor the rest of the editor holds itself to.
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          splashColor: tokens.accent.withValues(alpha: 0.10),
          highlightColor: tokens.accent.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: (kFloatingBarHeight - 32) / 2,
            ),
            child: AnimatedContainer(
              duration: AppMotion.of(context, AppMotion.state),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: active
                    ? tokens.accent.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Container(
                constraints: const BoxConstraints(minWidth: 40, minHeight: 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small bordered colour swatch used inside a pill (e.g. Paint's
/// stroke-colour swatch). Kept here so a future Shape "fill colour"
/// pill can reuse the exact same dot.
class FloatingColorDot extends StatelessWidget {
  const FloatingColorDot({super.key, required this.color, this.size = 18});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppTokens.of(context).border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}
