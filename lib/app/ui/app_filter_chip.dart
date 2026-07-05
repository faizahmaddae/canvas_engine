import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

/// v2 filter chip (home redesign doc §5): selected = ink-filled with
/// cream text, unselected = paper + hairline. Quiet by design — the
/// chip row is chrome, not content.
///
/// Named AppFilterChip to avoid colliding with Material's
/// [FilterChip].
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Smaller footprint for SECONDARY filter rows (e.g. the browse
  /// screen's «زبان» row) so they read as subordinate to the primary
  /// chip row above them.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: compact ? 26 : 34,
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: compact ? AppSpacing.md : AppSpacing.lg,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? tokens.brand : tokens.surface,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: selected ? null : Border.all(color: tokens.border),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypeScale.caption.copyWith(
              fontSize: compact ? 11 : 13,
              color: selected ? tokens.onBrand : tokens.textSecondary,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
