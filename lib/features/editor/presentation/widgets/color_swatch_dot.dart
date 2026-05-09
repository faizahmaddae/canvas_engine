import 'package:flutter/material.dart';

/// Shared circular color swatch used by both Paint and Text color
/// panels so the two surfaces speak one visual language.
///
/// Visual grammar (single source of truth):
/// - 36×36 circle filled with [color]
/// - Resting: faint outline (`outlineVariant @ 60%`, 1px)
/// - Selected: 2.5px `primary` ring + brightness-aware checkmark
/// - Press: subtle scale-down (94%) for tactile feedback
/// - Selection swap is animated (scale + fade) for a calm reveal
///
/// This widget is purely visual — it owns no color, recents, or
/// alpha logic. Callers remain responsible for state, haptics on
/// commit, and any wrapping (e.g. custom-color rainbow tile).
class ColorSwatchDot extends StatefulWidget {
  const ColorSwatchDot({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.size = 36,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final double size;

  @override
  State<ColorSwatchDot> createState() => _ColorSwatchDotState();
}

class _ColorSwatchDotState extends State<ColorSwatchDot> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final color = widget.color;
    // Brightness-aware checkmark: dark colours get a white tick,
    // light colours get a black tick — guarantees contrast across
    // the whole palette without per-swatch overrides.
    final checkColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : Colors.black;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(
                  color: selected
                      ? scheme.primary
                      : scheme.outlineVariant.withValues(alpha: 0.6),
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (c, a) => ScaleTransition(
                  scale: a,
                  child: FadeTransition(opacity: a, child: c),
                ),
                child: selected
                    ? Icon(
                        Icons.check_rounded,
                        key: const ValueKey(true),
                        size: widget.size * 0.5,
                        color: checkColor,
                      )
                    : const SizedBox.shrink(key: ValueKey(false)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
