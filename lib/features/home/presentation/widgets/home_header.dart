import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../settings/presentation/settings_screen.dart';

/// Home page top bar: app icon + name on the leading side, settings
/// trigger on the trailing side. Uses [Row] (which already respects
/// `Directionality`) and `EdgeInsetsDirectional`, so the layout
/// flips cleanly when the app's locale switches to RTL.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  static const String appName = 'Canvas';
  static const String settingsTooltip = 'Settings';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.pageGutter,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.button),
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [
                  scheme.primary,
                  Color.alphaBlend(
                    scheme.tertiary.withValues(alpha: 0.85),
                    scheme.primary,
                  ),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.auto_awesome_mosaic_rounded,
              color: scheme.onPrimary,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              appName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.start,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
          ),
          IconButton(
            tooltip: settingsTooltip,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen(),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
            // Material 3 IconButton ships with a 48dp tap target —
            // satisfies WCAG/AAA target sizing without extra work.
          ),
        ],
      ),
    );
  }
}
