import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';

/// Shared section header used across Home: title on the leading
/// side, optional text action on the trailing side. Uses
/// [TextDirection]-aware widgets throughout so it flips cleanly
/// under RTL.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canAct = actionLabel != null && onAction != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.start,
            style: theme.textTheme.titleMedium,
          ),
        ),
        const Spacer(),
        if (canAct)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: scheme.primary,
              padding: const EdgeInsetsDirectional.only(
                start: AppSpacing.md,
                end: AppSpacing.sm,
              ),
              // Meet the M3/Material accessibility minimum tap
              // target of 48dp on the cross axis.
              minimumSize: const Size(0, 48),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 2),
                // `chevron_right_rounded` auto-mirrors under RTL
                // because Flutter ships it as a directional icon.
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}
