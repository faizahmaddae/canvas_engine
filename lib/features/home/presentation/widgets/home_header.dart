import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/ui/saffron_diamond.dart';
import '../../../../l10n/l10n.dart';
import '../../../settings/presentation/settings_screen.dart';
import '../../../../app/theme/app_icons.dart';

/// Home chrome (home redesign doc §1–2): wordmark «کانواس» + the
/// saffron-diamond mark at the start, a settings icon in a quiet
/// paper circle at the end, then the greeting headline + subtitle.
///
/// Calm chrome — paper/ink/saffron only, no gradients or shadows;
/// the colour on Home comes from the content below.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.pageGutter,
        AppSpacing.md,
        AppSpacing.pageGutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SaffronDiamond(),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  l10n.homeBrandTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypeScale.title.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.settingsTooltip,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
                icon: const Icon(AppIcons.settings, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: tokens.surface,
                  foregroundColor: tokens.textSecondary,
                  shape: const CircleBorder(),
                  side: BorderSide(color: tokens.border),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            l10n.homeWelcomeTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.4,
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.homeWelcomeSubtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypeScale.caption.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}
