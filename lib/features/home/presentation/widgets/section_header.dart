import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import 'home_style.dart';

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
    this.compact = false,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canAct = actionLabel != null && onAction != null;
    final titleStyle = compact
        ? theme.textTheme.titleSmall
        : theme.textTheme.titleMedium;
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.start,
            style: titleStyle?.copyWith(
              color: HomePalette.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (canAct)
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: compact ? AppSpacing.sm : AppSpacing.md,
            ),
            child: TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: HomePalette.accent,
                padding: EdgeInsets.zero,
                minimumSize: Size(0, compact ? 28 : 48),
                tapTargetSize: compact
                    ? MaterialTapTargetSize.shrinkWrap
                    : MaterialTapTargetSize.padded,
                visualDensity: compact
                    ? VisualDensity.compact
                    : VisualDensity.standard,
              ),
              child: Text(
                actionLabel!,
                style: TextStyle(
                  fontSize: compact ? 12 : null,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );

    return compact ? SizedBox(height: 30, child: header) : header;
  }
}
