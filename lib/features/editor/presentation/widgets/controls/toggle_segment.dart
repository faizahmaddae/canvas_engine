// Shared control kit (Phase 2A §1): extracted verbatim from the
// text_mode_toolbar library (text_layout_panel.dart) so every tool's
// panels can reuse it. Rename-only promotion; no behaviour change.

import 'package:flutter/material.dart';

import '../../../../../app/theme/app_motion.dart';
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
      duration: AppMotion.of(context, AppMotion.reveal),
      curve: AppMotion.curve,
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
                // Glyph stop: this icon is the selected segment's ONLY
                // content, and `accent` on its own tint measured 2.55:1.
                color: selected ? tokens.accentText : tokens.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tinted pill that groups a tightly-related set of [ToggleSegment]s
/// (the "grouped triple" case from the toggle rule above). Extracted
/// from the Layout panel's alignment control so every segmented pill
/// in the editor shares one wrapper instead of re-rolling the
/// Container styling per panel.
class ToggleSegmentGroup extends StatelessWidget {
  const ToggleSegmentGroup({
    super.key,
    required this.children,
    this.spatial = false,
  });

  final List<Widget> children;

  /// True when the segments' ORDER encodes a physical direction — the
  /// align triad, whose left/centre/right buttons mean the screen's
  /// left, centre and right.
  ///
  /// Such a group must not mirror. `AppIcons.textAlignLeft/Right` are
  /// already pinned `matchTextDirection: false` so the glyphs tell the
  /// truth, but the Row around them still laid out right-to-left under
  /// RTL, so the button that applied LEFT alignment sat on the RIGHT —
  /// icons saying one thing and position saying the opposite. Bold /
  /// italic / underline carry no spatial meaning and stay directional,
  /// hence the opt-in rather than a blanket LTR.
  final bool spatial;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    Widget row = Row(mainAxisSize: MainAxisSize.min, children: children);
    if (spatial) {
      row = Directionality(textDirection: TextDirection.ltr, child: row);
    }
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tokens.surfaceMuted.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: row,
    );
  }
}
