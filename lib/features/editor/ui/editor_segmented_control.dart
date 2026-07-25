import 'package:flutter/material.dart';

import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_tokens.dart';

/// One tab of an [EditorSegmentedControl].
class EditorSegment<T> {
  const EditorSegment({required this.value, required this.label, this.itemKey});

  final T value;
  final String label;

  /// Optional key placed on the tappable tile — widget tests pin
  /// segments by key rather than by localized label.
  final Key? itemKey;
}

/// The dock's segmented selector: a rounded track with one tinted
/// active tile (tb4 2/14).
///
/// Extracted from the canvas panel's private background-mode toggle
/// so the Solid/Gradient fill switch reads as the same control
/// rather than a look-alike. Pixels are unchanged from the original.
class EditorSegmentedControl<T> extends StatelessWidget {
  const EditorSegmentedControl({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
  });

  final T value;
  final List<EditorSegment<T>> segments;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // A row of pills at the READING-START edge, not a full-width
    // track (tb7 4/7). The prototype's Solid/Gradient switch is two
    // small pills, the same object as every other choice chip in the
    // panel; a full-bleed track made a two-way choice look like the
    // panel's primary control, which it is not — the fill body
    // underneath is. Start-aligned so the pills hang under the
    // section label that introduces them.
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final segment in segments) ...[
            if (segment != segments.first) const SizedBox(width: 8),
            _SegmentTile(
              key: segment.itemKey,
              label: segment.label,
              selected: segment.value == value,
              onTap: () => onChanged(segment.value),
              tokens: tokens,
            ),
          ],
        ],
      ),
    );
  }
}

class _SegmentTile extends StatelessWidget {
  const _SegmentTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.tokens,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.state),
        curve: Curves.easeOut,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected
              ? tokens.accent.withValues(alpha: 0.16)
              : Colors.transparent,
          // Same fully-round pill as PresetChip (tb7 3/7): one chip
          // vocabulary across the whole panel.
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected
                ? tokens.accent
                : tokens.border.withValues(alpha: 0.9),
            width: selected ? 1.5 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: selected ? tokens.accentDeep : tokens.textSecondary,
          ),
        ),
      ),
    );
  }
}
