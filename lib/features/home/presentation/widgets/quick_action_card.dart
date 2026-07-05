import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/theme/app_typography.dart';

/// One of Home's two create cards (home redesign doc §3): equal
/// siblings in a row, split by emphasis —
///
///  * [filled] — the main action: `brand` (ink/cream) fill, `onBrand`
///    label, saffron icon.
///  * outline (default) — `surface` card, hairline border, ink label
///    and icon.
///
/// Token-driven and dark-aware by construction; "calm chrome" means
/// no gradients, no shadows — emphasis comes from the ink fill alone.
class QuickActionCard extends StatelessWidget {
  const QuickActionCard({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final fill = filled ? tokens.brand : tokens.surface;
    final fg = filled ? tokens.onBrand : tokens.textPrimary;
    final iconColor = filled ? tokens.accent : tokens.textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Ink(
          height: 96,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: filled ? null : Border.all(color: tokens.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 22, color: iconColor),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypeScale.body.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
