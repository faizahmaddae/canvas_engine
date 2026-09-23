import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/ui/saffron_diamond.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import '../../../settings/presentation/settings_screen.dart';
import '../../../../app/theme/app_icons.dart';

/// Home chrome: wordmark «کانواس» + the saffron-diamond mark at the
/// start, a settings icon in a quiet paper circle at the end, then a
/// daypart greeting over the headline.
///
/// The greeting is the one line on Home that admits what time it is —
/// «صبح بخیر» on the morning open, «شب بخیر» at night — a small daily
/// truth on a screen visited every day. It replaced the old static
/// subtitle, which spent a line describing the two buttons directly
/// below it.
///
/// Calm chrome — paper/ink/saffron only, no gradients or shadows;
/// the colour on Home comes from the content below.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, this.now});

  /// Clock for the daypart greeting. Null means the device's now;
  /// tests inject a fixed time so the greeting is deterministic.
  final DateTime? now;

  /// Daypart boundaries (24h): [5, 11) morning, [11, 15) noon,
  /// [15, 20) evening, else night.
  static String _greeting(AppLocalizations l10n, int hour) {
    if (hour >= 5 && hour < 11) return l10n.greetingMorning;
    if (hour >= 11 && hour < 15) return l10n.greetingNoon;
    if (hour >= 15 && hour < 20) return l10n.greetingEvening;
    return l10n.greetingNight;
  }

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
            _greeting(l10n, (now ?? DateTime.now()).hour),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypeScale.caption.copyWith(
              color: tokens.accentText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
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
        ],
      ),
    );
  }
}
