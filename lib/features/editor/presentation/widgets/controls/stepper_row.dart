// Shared control kit (Phase 2A §1): extracted verbatim from the
// text_mode_toolbar library (text_size_panel.dart) so every tool's
// panels can reuse it. Rename-only promotion; no behaviour change.

import 'package:flutter/material.dart';

import '../../../../../app/theme/app_tokens.dart';
import '../../../../../core/utils/haptics.dart';

/// "A−" / "A+" double-button stepper used in the Size sub-tool. Each
/// tap nudges the live font size by a perceptual step so the user
/// gets visible change without having to drag a slider. Long-press
/// repeats. The buttons round-trip through the controller so undo
/// coalescing and box auto-fit behaviour stay identical to the
/// slider path.
class SizeStepperRow extends StatelessWidget {
  const SizeStepperRow({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChange,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChange;

  /// Perceptual step: ~10% of the current value (rounded), with a
  /// floor so very small sizes still nudge by at least 1 px.
  double get _step {
    final s = (value * 0.1).roundToDouble();
    return s < 1 ? 1 : s;
  }

  void _bump(int dir) {
    final next = (value + dir * _step).clamp(min, max).toDouble();
    if ((next - value).abs() < 0.01) return;
    EditorHaptics.tap();
    onChange(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    Widget btn({required IconData icon, required VoidCallback onTap}) {
      return Material(
        color: tokens.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 56,
            height: 44,
            child: Center(child: Icon(icon, size: 22, color: tokens.accent)),
          ),
        ),
      );
    }

    return Row(
      children: [
        btn(icon: Icons.text_decrease_rounded, onTap: () => _bump(-1)),
        // Live value pill in the middle — same vocabulary as the
        // Layout panel's value pill so the two panels feel like
        // one family. Tabular figures so 12 → 24 → 120 doesn't
        // shift the centred layout.
        Expanded(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: tokens.surfaceMuted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${value.round()} px',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
        btn(icon: Icons.text_increase_rounded, onTap: () => _bump(1)),
      ],
    );
  }
}
