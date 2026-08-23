import 'package:flutter/material.dart';

import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_tokens.dart';
import 'editor_breakpoints.dart';

/// Bottom dock that swaps between **modes** (main / paint / text …)
/// without ever stacking surfaces on top of the canvas.
///
/// The dock has two stacked zones, both rendered inside the
/// `Scaffold.bottomNavigationBar`, so the canvas naturally shrinks
/// when the dock grows — no overlay, no blocking sheet:
///
/// ```
///  ┌───────────────────────────────┐
///  │  [expanded] (optional, 0..N)  │  ← animates open/close
///  ├───────────────────────────────┤
///  │  [child] chip strip (fixed)   │  ← always visible
///  └───────────────────────────────┘
/// ```
///
/// * [child] — compact, fixed-height chip strip (categories /
///   tools). Slides + cross-fades when [modeKey] changes.
/// * [expanded] — optional taller panel rendered ABOVE the chip
///   strip. Its presence/absence is animated via [AnimatedSize]
///   so the canvas reflows smoothly as the panel opens / closes.
///
/// The dock guarantees a minimum [height] for the chip strip so
/// switching modes never reflows the chip area; only the
/// [expanded] zone changes the dock's overall height.
class EditorToolDock extends StatelessWidget {
  const EditorToolDock({
    super.key,
    required this.modeKey,
    required this.child,
    this.expanded,
    this.expandedKey,
    this.height,
  });

  /// Stable key identifying the current mode. The chip strip
  /// animates its content swap whenever this changes.
  final String modeKey;

  /// Fixed-height chip strip content for the current mode.
  final Widget child;

  /// Optional content shown above the chip strip. When `null`, the
  /// expanded zone collapses to zero height. The widget is
  /// responsible for its own internal layout / scrolling — the dock
  /// only animates the height transition.
  final Widget? expanded;

  /// Identity for the expanded panel content. Used as the switch
  /// key so transitioning between two different expanded panels
  /// (e.g. text-mode "Style" → text-mode "Background") cross-fades
  /// without rebuilding from scratch.
  final Object? expandedKey;

  /// Minimum height of the chip strip (excluding bottom safe-area).
  /// When null, adapts to compact mode (small / landscape phones get
  /// 64dp; default 80dp).
  final double? height;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final stripHeight = height ?? EditorBreakpoints.stripHeight(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Elevated chrome: the dock sits on tokens.surface (a step
    // lighter than the tokens.workspace behind the canvas), separated
    // from it by a top hairline and a soft upward shadow, so bar +
    // expanded panel read as ONE surface under the workspace.
    //
    // SQUARE, deliberately. This departs from the rising-sheet
    // grammar the app uses for surfaces that arrive over content, and
    // the reason is that the dock does not arrive: it is pinned chrome
    // filling the full width down to the bottom of the display. A
    // rounded top left two wedges of workspace sitting in the corners
    // above a bar that visibly touches every other edge — the shape
    // claimed a card, the position said otherwise. Squaring it lets
    // the hairline read as the seam it is. (No `side` on the shape
    // either: a BorderSide strokes the WHOLE outline, so the dock was
    // also drawing a line down both edges and across the bottom,
    // against the display bezel, where it traced the screen's own
    // corner. The hairline it actually wants is one child below.)
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: tokens.surface,
        shape: const RoundedRectangleBorder(),
        shadows: [
          BoxShadow(
            color: Theme.of(
              context,
            ).colorScheme.shadow.withValues(alpha: isDark ? 0.4 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ClipRect(
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The separating hairline, and only on the one edge
                // that meets the workspace.
                Container(height: 1, color: tokens.border),
                // ── Expanded zone ──────────────────────────────────
                // AnimatedSize collapses to 0 when [expanded] is
                // null and grows to the panel's intrinsic height
                // otherwise. AnimatedSwitcher inside cross-fades
                // between different panels (e.g. category change).
                // `easeOutQuint` gives a premium "settle" feel —
                // fast initial expansion, soft tail — that reads as
                // intentional motion rather than mechanical resize.
                ClipRect(
                  child: AnimatedSize(
                    duration: AppMotion.surface,
                    curve: AppMotion.curve,
                    alignment: Alignment.bottomCenter,
                    child: AnimatedSwitcher(
                      duration: AppMotion.surface,
                      switchInCurve: AppMotion.curve,
                      switchOutCurve: AppMotion.curveOut,
                      transitionBuilder: (child, animation) {
                        // Subtle upward slide (4% of height) +
                        // fade — the panel "rises" into place
                        // instead of flat-fading. Matches the
                        // bottom-sheet motion users expect from
                        // premium iOS / Material 3 surfaces.
                        final slide = Tween<Offset>(
                          begin: const Offset(0, 0.04),
                          end: Offset.zero,
                        ).animate(animation);
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(position: slide, child: child),
                        );
                      },
                      layoutBuilder: (currentChild, previousChildren) {
                        return Stack(
                          alignment: Alignment.bottomCenter,
                          children: [...previousChildren, ?currentChild],
                        );
                      },
                      child: expanded == null
                          ? const SizedBox(width: double.infinity, height: 0)
                          : KeyedSubtree(
                              key: ValueKey(
                                expandedKey ?? expanded.runtimeType,
                              ),
                              child: SizedBox(
                                width: double.infinity,
                                child: expanded,
                              ),
                            ),
                    ),
                  ),
                ),
                // ── Chip strip ────────────────────────────────────
                // Fixed-height row that mirrors the previous dock
                // surface. Mode swaps slide + cross-fade in here.
                //
                // ANIMATED height: the strip's height differs per
                // mode (idle strip 80/64, the paint/text/image
                // benches 124/108), and a bare SizedBox snapped
                // between them — the canvas above reflowed in one
                // frame and visibly jumped the moment a photo, text
                // or stroke was selected. The box glides over the
                // same 220ms as the content cross-fade, while the
                // OverflowBox keeps the CONTENT laid out at the
                // target height for the whole flight — squeezing the
                // strip through intermediate heights overflowed
                // DockToolTile's fixed column (and the transition
                // also fires when a viewport change moves the
                // compact breakpoint). Bottom-anchored, the content
                // holds still against the display edge and the top
                // edge rises like a curtain.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: AppMotion.curve,
                  height: stripHeight,
                  child: ClipRect(
                    child: OverflowBox(
                      minHeight: stripHeight,
                      maxHeight: stripHeight,
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        height: stripHeight,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: AppMotion.curve,
                          switchOutCurve: AppMotion.curveOut,
                          transitionBuilder: (child, animation) {
                            final slide = Tween<Offset>(
                              begin: const Offset(0.06, 0),
                              end: Offset.zero,
                            ).animate(animation);
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: slide,
                                child: child,
                              ),
                            );
                          },
                          layoutBuilder: (currentChild, previousChildren) {
                            return Stack(
                              alignment: Alignment.center,
                              children: [...previousChildren, ?currentChild],
                            );
                          },
                          child: KeyedSubtree(
                            key: ValueKey(modeKey),
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
