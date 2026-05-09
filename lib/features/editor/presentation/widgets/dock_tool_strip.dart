import 'package:flutter/material.dart';

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
  bool _showLeft = false;
  bool _showRight = false;

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
    final left = pos.pixels > pos.minScrollExtent + 1;
    final right = pos.pixels < pos.maxScrollExtent - 1;
    if (left != _showLeft || right != _showRight) {
      setState(() {
        _showLeft = left;
        _showRight = right;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fade = scheme.surfaceContainer;
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
                      (constraints.maxWidth - widget.padding.horizontal)
                          .clamp(0.0, double.infinity);
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
            if (_showLeft)
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
            if (_showRight)
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
