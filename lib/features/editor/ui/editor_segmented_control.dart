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
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tokens.surfaceMuted.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final segment in segments)
            _SegmentTile(
              key: segment.itemKey,
              label: segment.label,
              selected: segment.value == value,
              onTap: () => onChanged(segment.value),
              tokens: tokens,
            ),
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
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.state),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected
                ? tokens.accent.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
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
      ),
    );
  }
}
