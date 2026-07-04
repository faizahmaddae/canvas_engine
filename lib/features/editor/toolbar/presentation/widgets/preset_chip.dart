import 'package:flutter/material.dart';

import '../../../../../core/utils/haptics.dart';

/// Selected/unselected preset chip used above sliders and inside
/// any sub-tool that exposes a curated set of values
/// (paint size, blur, opacity, text size, line-height, …).
///
/// **Phase-2 polish (2026-04):**
///   * 44dp minimum height — Apple HIG / Material thumb target.
///   * Selected = solid `primary` fill + `onPrimary` label + 12dp
///     primary shadow. Reads under sunlight; matches the active
///     `DockToolTile` grammar so chips and tiles feel like one
///     family.
///   * Press-scale (0.96) on tap-down — gives every chip the
///     "tactile bead" feel that high-end editors lean on.
///   * Tabular figures so digits don't jiggle width as the value
///     changes (3 → 30 → 100).
class PresetChip extends StatefulWidget {
  const PresetChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.minWidth = 56,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Minimum chip width. The horizontal scroller in
  /// [PresetSliderControl] passes a value here so all chips share
  /// the same width — the eye doesn't have to track variable widths
  /// while scrubbing through presets.
  final double minWidth;

  @override
  State<PresetChip> createState() => _PresetChipState();
}

class _PresetChipState extends State<PresetChip> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final fill = selected
        ? scheme.primary
        : scheme.surfaceContainerHighest.withValues(alpha: 0.55);
    final fg = selected ? scheme.onPrimary : scheme.onSurface;
    final shadow = selected
        ? [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.28),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ]
        : const <BoxShadow>[];
    void handleTap() {
      EditorHaptics.snap();
      widget.onTap();
    }

    return Semantics(
      label: widget.label,
      button: true,
      selected: selected,
      onTap: handleTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: handleTap,
          child: AnimatedScale(
            scale: _down ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              constraints: BoxConstraints(minWidth: widget.minWidth),
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(14),
                boxShadow: shadow,
              ),
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: fg,
                  letterSpacing: -0.1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
