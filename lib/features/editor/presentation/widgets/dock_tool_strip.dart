import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';

/// Horizontally scrollable tool strip with **edge-fade gradients**
/// that appear only when there is more content to scroll to in
/// that direction.
///
/// Used by both [TextModeToolbar] and [PaintModeToolbar] so the
/// dock visually telegraphs "scroll for more" the moment a strip
/// overflows. Fade is 24-dp wide and uses a `BlendMode.dstOut` mask
/// so it works against any dock surface colour.
///
/// The strip itself is a `ListView` driven by [controller] so the
/// hosting widget can programmatically scroll the active tile into
/// view without losing the fade affordance.
class DockToolStrip extends StatefulWidget {
  const DockToolStrip({
    super.key,
    required this.controller,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 10),
    this.height = 80,
    this.centerWhenFits = false,
    this.fitAlignment = MainAxisAlignment.center,
  });

  final ScrollController controller;
  final List<Widget> children;
  final EdgeInsets padding;
  final double height;

  /// When true, if all [children] fit within the viewport the row
  /// is aligned per [fitAlignment]; otherwise the strip falls back
  /// to the normal left-aligned scrollable layout. Off by default
  /// so existing call sites (Text toolbar) are unaffected.
  final bool centerWhenFits;

  /// Alignment used by the [centerWhenFits] path. Defaults to
  /// [MainAxisAlignment.center]; pass [MainAxisAlignment.end] for a
  /// right-handed dock so tools sit closest to the right thumb.
  /// Item order is **never** reversed — only placement changes.
  final MainAxisAlignment fitAlignment;

  @override
  State<DockToolStrip> createState() => _DockToolStripState();
}

class _DockToolStripState extends State<DockToolStrip> {
  // Scroll-space flags: "back" = toward minScrollExtent (the content
  // START), "ahead" = toward maxScrollExtent (more content). Which
  // PHYSICAL edge each one fades is resolved in build() from the
  // ambient Directionality — under RTL the content starts at the
  // physical right, so the clipped "ahead" side is the physical
  // LEFT (tb1 17/17; pinned by rtl_strip_pins_test).
  bool _canScrollBack = false;
  bool _canScrollAhead = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_recompute);
    // Initial state needs to wait for layout.
    WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());
  }

  @override
  void didUpdateWidget(covariant DockToolStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_recompute);
      widget.controller.addListener(_recompute);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_recompute);
    super.dispose();
  }

  void _recompute() {
    if (!mounted || !widget.controller.hasClients) return;
    final pos = widget.controller.position;
    // 1-px tolerance so floating-point rounding never flickers the
    // fade on/off at the extreme ends.
    final back = pos.pixels > pos.minScrollExtent + 1;
    final ahead = pos.pixels < pos.maxScrollExtent - 1;
    if (back != _canScrollBack || ahead != _canScrollAhead) {
      setState(() {
        _canScrollBack = back;
        _canScrollAhead = ahead;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Edge fades must match the dock's ACTUAL surface (the elevated
    // chrome colour), not the workspace tone, or the fade reads as a
    // dirty smudge on the lighter bar.
    final fade = AppTokens.of(context).surface;
    // Map scroll-space flags → physical edges. The list view lays
    // out from the directional start, so under RTL "back toward the
    // content start" clips at the physical RIGHT and "more ahead"
    // clips at the physical LEFT — exactly mirrored from LTR. The
    // fade must sit on the clipped side it telegraphs.
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final showLeftFade = isRtl ? _canScrollAhead : _canScrollBack;
    final showRightFade = isRtl ? _canScrollBack : _canScrollAhead;
    return SizedBox(
      height: widget.height,
      child: NotificationListener<ScrollMetricsNotification>(
        // Catches viewport-size changes (rotation, dock resize)
        // that don't fire ScrollController listeners.
        onNotification: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());
          return false;
        },
        child: Stack(
          children: [
            if (widget.centerWhenFits)
              LayoutBuilder(
                builder: (context, constraints) {
                  // Reserve the strip's horizontal padding inside the
                  // ConstrainedBox so the centered Row aligns to the
                  // visible content area, not the raw viewport edge.
                  final minWidth =
                      (constraints.maxWidth - widget.padding.horizontal).clamp(
                        0.0,
                        double.infinity,
                      );
                  return SingleChildScrollView(
                    controller: widget.controller,
                    scrollDirection: Axis.horizontal,
                    padding: widget.padding,
                    physics: const BouncingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: minWidth),
                      child: Row(
                        mainAxisAlignment: widget.fitAlignment,
                        mainAxisSize: MainAxisSize.max,
                        children: widget.children,
                      ),
                    ),
                  );
                },
              )
            else
              ListView(
                controller: widget.controller,
                scrollDirection: Axis.horizontal,
                padding: widget.padding,
                physics: const BouncingScrollPhysics(),
                children: widget.children,
              ),
            if (showLeftFade)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 24,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [fade, fade.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
              ),
            if (showRightFade)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 24,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [fade, fade.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
