// Shared control kit (Phase 2A §1): extracted verbatim from the
// text_mode_toolbar library (text_layout_panel.dart) so every tool's
// panels can reuse it. Rename-only promotion; no behaviour change.

import 'package:flutter/material.dart';

import '../../../../../app/theme/app_tokens.dart';
import '../../../../../core/utils/haptics.dart';

/// Compact 3-button segmented control. Used as the inner row of
/// `_AlignmentSegmentedControl` (Layout panel). Each segment is a
/// 36×32 pill with an accent-tint selected state.
///
/// **Editor toggle rule (paint + text):**
///   * Single on/off feature → `_CompactRow` + trailing
///     `Switch.adaptive` (paint Fill, text Background, Border,
///     Shadow).
///   * Tightly-grouped triple of related toggles → group
///     `ToggleSegment`s inside a tinted pill (alignment).
/// Same rule across both modes. Picking the affordance based on
/// "single vs grouped" is what makes the chrome predictable.
class ToggleSegment extends StatelessWidget {
  const ToggleSegment({
    super.key,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected
            ? tokens.accent.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected
              ? tokens.accent.withValues(alpha: 0.45)
              : Colors.transparent,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            EditorHaptics.toggle();
            onTap();
          },
          child: SizedBox(
            width: 36,
            height: 32,
            child: Center(
              child: Icon(
                icon,
                size: 18,
                color: selected ? tokens.accent : tokens.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
