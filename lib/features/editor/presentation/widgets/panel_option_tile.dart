import 'package:flutter/material.dart';

/// Shared selection tile used by every panel preset row — Adjust
/// presets (Original / Pop / Soft / Warm / Cool), Border thickness,
/// Shape mask, Shadow style, Background style, etc.
///
/// Single source of truth for the panel preset grammar — established
/// by the Adjust preset chip in
/// `lib/features/editor/image/presentation/image_adjust_body.dart`:
///
///   * resting fill: `surfaceContainerHighest @ 35%` (subtle dark
///     card surface — NOT transparent)
///   * hover: `onSurface @ 6%`
///   * pressed: `primary @ 10%`
///   * selected: `primary @ 12%` (deepens to `18%` while pressed)
///   * fg: active = `primary`, else `onSurfaceVariant`
///   * label weight: w600 → w700 when active
///   * radius 10
///   * AnimatedContainer 160ms easeOutCubic for the bg
///   * AnimatedScale 0.97 / 120ms while pressed
///   * vertical padding 8 (icon-on-top + label beneath layout)
///
/// Per-panel visual hacks (extra glow, ring borders, oversized
/// active boxes) are not allowed — extend this widget instead so
/// the whole panel surface keeps speaking one visual language.
class PanelOptionTile extends StatefulWidget {
  const PanelOptionTile({
    super.key,
    required this.selected,
    required this.onTap,
    this.icon,
    this.iconSize = 18,
    this.preview,
    this.label,
    this.width,
  }) : assert(
         icon == null || preview == null,
         'Provide either icon or preview, not both.',
       );

  /// Whether this tile represents the currently active option.
  final bool selected;

  /// Tap handler. Callsites are responsible for firing the
  /// appropriate [EditorHaptics] feedback (typically `toggle()`)
  /// — this widget does not fire any haptics itself, mirroring
  /// the Adjust preset chip it derives from.
  final VoidCallback onTap;

  /// Optional leading icon (rendered above the label). Mutually
  /// exclusive with [preview].
  final IconData? icon;

  /// Override the default 18dp icon size — e.g. border thickness
  /// presets render the same horizontal-rule glyph at 16/22/30 so
  /// the preview itself communicates Thin / Medium / Bold.
  final double iconSize;

  /// Optional custom artwork (e.g. a `CustomPaint` silhouette of a
  /// mask). Rendered in place of [icon] in the same icon slot.
  final Widget? preview;

  /// Optional label rendered beneath the icon / preview.
  final String? label;

  /// Fixed tile width. Leave `null` for chip rows where the parent
  /// stretches each child via `Expanded`.
  final double? width;

  @override
  State<PanelOptionTile> createState() => _PanelOptionTileState();
}

class _PanelOptionTileState extends State<PanelOptionTile> {
  bool _down = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;

    final fg = selected ? scheme.primary : scheme.onSurfaceVariant;

    Color bg;
    if (selected) {
      bg = scheme.primary.withValues(alpha: _down ? 0.18 : 0.12);
    } else if (_down) {
      bg = scheme.primary.withValues(alpha: 0.10);
    } else if (_hover) {
      bg = scheme.onSurface.withValues(alpha: 0.06);
    } else {
      bg = scheme.surfaceContainerHighest.withValues(alpha: 0.35);
    }

    final hasGlyph = widget.icon != null || widget.preview != null;
    final hasLabel = widget.label != null;

    Widget glyph;
    if (widget.preview != null) {
      glyph = IconTheme(
        data: IconThemeData(color: fg, size: widget.iconSize),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: fg),
          child: widget.preview!,
        ),
      );
    } else if (widget.icon != null) {
      glyph = Icon(widget.icon, size: widget.iconSize, color: fg);
    } else {
      glyph = const SizedBox.shrink();
    }

    Widget content;
    if (hasGlyph && hasLabel) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          glyph,
          const SizedBox(height: 4),
          _Label(text: widget.label!, color: fg, selected: selected),
        ],
      );
    } else if (hasGlyph) {
      content = Center(child: glyph);
    } else {
      content = Center(
        child: _Label(text: widget.label ?? '', color: fg, selected: selected),
      );
    }

    Widget tile = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          // Hover/press painted via AnimatedContainer's `bg` so
          // bounds always match the selected fill exactly.
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          focusColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: widget.width,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: content,
            ),
          ),
        ),
      ),
    );

    tile = AnimatedScale(
      scale: _down ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      child: tile,
    );

    return Semantics(
      label: widget.label,
      button: true,
      selected: selected,
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          child: tile,
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({
    required this.text,
    required this.color,
    required this.selected,
  });

  final String text;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 11,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        color: color,
        letterSpacing: 0,
      ),
    );
  }
}
