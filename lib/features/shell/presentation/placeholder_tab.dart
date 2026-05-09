import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';

/// Quiet "coming soon" placeholder used by the Projects, Templates
/// and Profile tabs while only Home is implemented. Centred glyph
/// + headline + body, with no actions — keeps the bottom nav real
/// without faking unfinished functionality.
class PlaceholderTab extends StatelessWidget {
  const PlaceholderTab({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
          start: AppSpacing.xxl,
          end: AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadii.hero),
              ),
              child: Icon(icon, size: 32, color: scheme.primary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
