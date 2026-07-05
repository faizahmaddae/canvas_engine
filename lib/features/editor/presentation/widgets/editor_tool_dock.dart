import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';

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
    final media = MediaQuery.of(context);
    final compact =
        media.size.shortestSide < 380 ||
        media.orientation == Orientation.landscape;
    final stripHeight = height ?? (compact ? 64.0 : 80.0);
    return Material(
      color: tokens.surfaceMuted,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: tokens.border.withValues(alpha: 0.5),
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.bottomCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
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
                            key: ValueKey(expandedKey ?? expanded.runtimeType),
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
              SizedBox(
                height: stripHeight,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final slide = Tween<Offset>(
                      begin: const Offset(0.06, 0),
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  layoutBuilder: (currentChild, previousChildren) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [...previousChildren, ?currentChild],
                    );
                  },
                  child: KeyedSubtree(key: ValueKey(modeKey), child: child),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
