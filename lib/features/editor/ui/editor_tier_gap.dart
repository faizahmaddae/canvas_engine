import 'package:flutter/material.dart';

/// Visual gap dividing tool-strip tiers (e.g. the primary-vs-
/// secondary cluster in the paint and text dock strips).
///
/// Unifies the byte-identical `_TierGap` (text) / `_PaintTierGap`
/// (paint) copies: a 13 px gutter centred on a 1×28 hairline at
/// `outlineVariant` 45% alpha. `SlotStrip`'s own `_TierDivider`
/// (data-driven from `SlotTier` boundaries) is a distinct,
/// intentionally-kept variant — migrating the text/paint strips onto
/// `SlotStrip` itself is parked (Phase 4 plan §1 non-goals); this
/// widget only removes the two hand-rolled duplicates of the same
/// static gap.
class EditorTierGap extends StatelessWidget {
  const EditorTierGap({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 13,
      alignment: Alignment.center,
      child: Container(
        width: 1,
        height: 28,
        decoration: BoxDecoration(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(0.5),
        ),
      ),
    );
  }
}
