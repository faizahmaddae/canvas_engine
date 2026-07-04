import 'package:flutter/material.dart';

import '../../../../core/utils/haptics.dart';

/// Shared primary tile used by the main toolbar and every
/// sub-toolbar (text / paint / shape / image / sticker).
///
/// 66-dp wide card (56 in compact) with:
///  * centered icon (or colour swatch when [swatchColor] is set)
///  * ellipsised label beneath
///  * unified active state — primary @ 12% fill, primary fg, label
///    bold; no border, no glow, no scale lift, so selected tiles
///    keep the same height + width as their neighbours
///  * subtle hover (onSurface @ 6%) and press (scale 0.97) tints
///    that never compete with the selection fill
///  * dimmed visuals + disabled ripple when [enabled] is false
///  * optional long-press "peek" gesture — holding the tile fires
///    [onPeekStart] (typically an undo) and releasing fires
///    [onPeekEnd] (redo), for instant A/B compare against the prior
///    state without leaving the dock.
///
/// This widget is the single source of truth for toolbar item
/// chrome. Per-toolbar visual hacks are not allowed — extend this
/// widget instead.
class DockToolTile extends StatefulWidget {
  const DockToolTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.active = false,
    this.swatchColor,
    this.fontFamily,
    this.valueText,
    this.onPeekStart,
    this.onPeekEnd,
    this.compact = false,
  });

  /// Compact layout for landscape / very small screens. Drops width
  /// 66→56, icon 28→24, hides label when [valueText] is null.
  final bool compact;

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool active;

  /// Long-press peek handlers. When both are supplied, a
  /// GestureDetector wraps the tile and routes press/release to
  /// these callbacks.
  final VoidCallback? onPeekStart;
  final VoidCallback? onPeekEnd;

  /// Optional live value ("24 pt", "Inter", "On"). When present we
  /// **replace** the static label with this value so the tile reads
  /// as state, not as a category label — information density wins
  /// on small screens. The static [label] is still used for
  /// accessibility / fallback when [valueText] is null.
  final String? valueText;

  /// When non-null, replaces the icon with a circular colour chip
  /// (used for the Color tile so the user reads the current colour
  /// at a glance).
  final Color? swatchColor;

  /// When non-null, the label renders in this typeface — used for
  /// the Font tile so the label previews the current family.
  final String? fontFamily;

  @override
  State<DockToolTile> createState() => _DockToolTileState();
}

class _DockToolTileState extends State<DockToolTile> {
  bool _down = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.enabled;
    final active = widget.active;
    final compact = widget.compact;
    // Unified toolbar item visual system (2026-05).
    //
    // Goals:
    //   * Active state must be clearly readable but never heavier
    //     than its siblings — same width, same height, same
    //     baseline. No scale lift, no border ring, no glow.
    //   * Hover (desktop/web) and pressed states are subtle
    //     surface tints; selection is a primary tint. The three
    //     states never compete.
    //   * Identical grammar across main toolbar + every
    //     sub-toolbar — single source of truth lives here.
    //
    // Active = primary @ 12% fill + primary fg + label w700.
    // Hover  = onSurface @ 6% fill (only when not active).
    // Press  = scale 0.97 (tactile feedback only — no lift).
    final fg = !enabled
        ? scheme.onSurface.withValues(alpha: 0.35)
        : (active ? scheme.primary : scheme.onSurface);
    final iconColor = !enabled
        ? scheme.onSurfaceVariant.withValues(alpha: 0.35)
        : (active ? scheme.primary : scheme.onSurfaceVariant);

    final tileWidth = compact ? 56.0 : 66.0;
    final iconSize = compact ? 24.0 : 28.0;
    final swatchSize = compact ? 26.0 : 30.0;
    final showLabel = !compact || widget.valueText != null;

    Color bg;
    if (active) {
      // Pressed-while-active deepens the selection slightly so the
      // user gets tap feedback without changing tile bounds.
      bg = scheme.primary.withValues(alpha: _down ? 0.18 : 0.12);
    } else if (_down && enabled) {
      bg = scheme.primary.withValues(alpha: 0.10);
    } else if (_hover && enabled) {
      bg = scheme.onSurface.withValues(alpha: 0.06);
    } else {
      bg = Colors.transparent;
    }

    Widget iconWidget;
    if (widget.swatchColor != null) {
      iconWidget = Container(
        width: swatchSize,
        height: swatchSize,
        decoration: BoxDecoration(
          color: widget.swatchColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: active
                ? scheme.primary.withValues(alpha: 0.85)
                : scheme.outlineVariant.withValues(alpha: 0.6),
            width: active ? 1.5 : 1.5,
          ),
        ),
      );
    } else {
      iconWidget = Icon(widget.icon, size: iconSize, color: iconColor);
    }

    final peekEnabled =
        enabled && widget.onPeekStart != null && widget.onPeekEnd != null;
    // Display label: live value if provided, else the static
    // category label.
    final displayLabel = widget.valueText ?? widget.label;
    // CRITICAL: spacing lives in an outer Padding, NOT as margin on
    // the AnimatedContainer. If the spacing were applied as
    // `margin` inside the InkWell, the ink ripple + hover overlay
    // would fill the full margin box (taller + wider than the
    // visible selected fill), producing a flicker where pressed /
    // hover bounds appear larger than the selected bounds. Keeping
    // Padding outside the InkWell guarantees all three states
    // (hover, press, selected) share identical visual bounds.
    Widget tile = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 1),
      child: MouseRegion(
        onEnter: enabled ? (_) => setState(() => _hover = true) : null,
        onExit: enabled ? (_) => setState(() => _hover = false) : null,
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: enabled
                ? () {
                    EditorHaptics.tap();
                    widget.onTap();
                  }
                : null,
            borderRadius: BorderRadius.circular(14),
            // Hover/press painted via AnimatedContainer's `bg` so
            // the bounds always match the selected fill exactly.
            // Suppress Material's own overlays (which paint on the
            // InkWell's *full* layout box, ignoring our radius
            // visually).
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            focusColor: Colors.transparent,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: tileWidth,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  iconWidget,
                  if (showLabel) ...[
                    SizedBox(height: compact ? 3 : 6),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: tileWidth - 6),
                      child: Text(
                        displayLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: widget.fontFamily,
                          fontSize: compact ? 10 : 11,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: fg,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // Press feedback only — no resting lift on active. Keeps every
    // tile the same height so the strip baseline stays flat.
    tile = AnimatedScale(
      scale: _down ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      child: tile,
    );

    if (peekEnabled) {
      tile = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onLongPressStart: (_) => widget.onPeekStart!(),
        onLongPressEnd: (_) => widget.onPeekEnd!(),
        child: tile,
      );
    } else {
      tile = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        child: tile,
      );
    }
    // The static category label doubles as the accessible name even
    // when valueText replaces it on screen ("Font Size" stays the
    // label, "24 pt" becomes the value) -- otherwise a screen reader
    // just hears the bare value with no idea what it refers to. The
    // peek long-press (undo/redo preview) has no AT equivalent and
    // is intentionally not exposed here; onTap (select this tool)
    // is the control's core function.
    return Semantics(
      label: widget.label,
      value: widget.valueText,
      button: true,
      enabled: enabled,
      selected: active,
      onTap: enabled ? widget.onTap : null,
      child: ExcludeSemantics(child: tile),
    );
  }
}
