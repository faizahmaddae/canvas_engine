import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';

/// Visual gap dividing tool-strip tiers (e.g. the primary-vs-
/// secondary cluster in the paint and text dock strips).
///
/// Unifies the byte-identical `_TierGap` (text) / `_PaintTierGap`
/// (paint) copies: a 20 px gutter centred on a clearly visible
/// 1×30 hairline (`AppTokens.border` @ 70%) — an INTENTIONAL group
/// divider, not an accidental hole between tiles (the old 13 px /
/// 45% version read as a spacing bug). `SlotStrip`'s own
/// `_TierDivider` (data-driven from `SlotTier` boundaries) mirrors
/// the same metrics — keep them in sync; migrating the text/paint
/// strips onto `SlotStrip` itself is parked (Phase 4 plan §1
/// non-goals).
class EditorTierGap extends StatelessWidget {
  const EditorTierGap({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      alignment: Alignment.center,
      child: Container(
        width: 1,
        height: 30,
        decoration: BoxDecoration(
          color: AppTokens.of(context).border.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(0.5),
        ),
      ),
    );
  }
}
