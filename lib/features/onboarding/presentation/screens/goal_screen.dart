import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/ui/app_primary_button.dart';
import '../../../../app/ui/skip_text_button.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import '../../../templates/domain/template.dart';
import '../../application/onboarding_controller.dart';
import '../../../../app/theme/app_icons.dart';

/// The six onboarding goals map onto existing template categories.
///
/// Design rationale: phrased as creator jobs (story, ad, poetry,
/// thumbnail, text-on-photo, blank canvas) rather than internal
/// taxonomy. The persisted category still uses the existing settings
/// model, so onboarding remains a UI-layer concern.
///
/// v2 (docs/design-direction-v2-calligraphy-2026-07.md): each goal is
/// a calm outline icon + name — not a busy template preview. The
/// calligraphy welcome is the star; this screen stays quiet.
const List<_GoalSpec> _goals = [
  _GoalSpec(
    category: TemplateCategory.instagramStory,
    icon: AppIcons.categoryStory,
  ),
  _GoalSpec(
    category: TemplateCategory.promotionalPoster,
    icon: AppIcons.categoryPoster,
  ),
  _GoalSpec(
    category: TemplateCategory.poetryPost,
    icon: AppIcons.categoryPoetry,
  ),
  _GoalSpec(
    category: TemplateCategory.youtubeThumbnail,
    icon: AppIcons.videoPreset,
  ),
  _GoalSpec(category: TemplateCategory.quote, icon: AppIcons.goalQuote),
  _GoalSpec(category: TemplateCategory.social, icon: AppIcons.categorySocial),
];

class _GoalSpec {
  const _GoalSpec({required this.category, required this.icon});

  final TemplateCategory category;
  final IconData icon;
}

/// Goal picker — v2 aesthetic. Paper/ink canvas, Persian-sans title
/// and subtitle, a 2-column grid of quiet surface cards (outline
/// icon + name; selection = saffron ring + check), and the ink/cream
/// CTA near the bottom. Fully token-driven.
class GoalScreen extends ConsumerWidget {
  const GoalScreen({super.key, required this.onContinue, required this.onSkip});

  final VoidCallback onContinue;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choices = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);
    final l10n = context.l10n;
    final tokens = AppTokens.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return ColoredBox(
      color: tokens.pageBg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pageGutter,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.onboardingGoalTitle,
                textAlign: TextAlign.center,
                style: AppTypeScale.titleLg.copyWith(color: tokens.textPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Text(
                    l10n.onboardingGoalSubtitle,
                    textAlign: TextAlign.center,
                    style: AppTypeScale.caption.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: GridView.count(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  crossAxisCount: 2,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisSpacing: AppSpacing.md,
                  childAspectRatio: 1.45,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    for (final spec in _goals)
                      _GoalCard(
                        key: ValueKey('onboarding-goal-${spec.category.name}'),
                        icon: spec.icon,
                        label: _goalLabel(l10n, spec.category),
                        selected: choices.selectedCategories.contains(
                          spec.category,
                        ),
                        onTap: () => controller.toggleCategory(spec.category),
                      ),
                  ],
                ),
              ),
              AppPrimaryButton(
                key: const ValueKey('onboarding-goal-continue'),
                label: l10n.onboardingContinue,
                onPressed: onContinue,
              ),
              Center(
                child: SkipTextButton(
                  key: const ValueKey('onboarding-goal-skip'),
                  label: l10n.onboardingSkip,
                  onPressed: onSkip,
                ),
              ),
              SizedBox(height: bottomInset + AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}

String _goalLabel(AppLocalizations l10n, TemplateCategory category) =>
    switch (category) {
      TemplateCategory.instagramStory => l10n.onboardingGoalInstagram,
      TemplateCategory.promotionalPoster => l10n.onboardingGoalPoster,
      TemplateCategory.poetryPost => l10n.onboardingGoalPoetry,
      TemplateCategory.youtubeThumbnail => l10n.onboardingGoalYoutube,
      TemplateCategory.quote => l10n.onboardingGoalTextOnPhoto,
      // The card enables the SOCIAL template category, so it says so.
      // It used to read «بوم خالی» / "Blank canvas" — a goal that
      // implies enabling nothing — while silently persisting social
      // (ux-audit P3-15).
      TemplateCategory.social => l10n.categorySocial,
      _ => l10n.categorySocial,
    };

/// One quiet goal card: surface fill, radius 16, hairline border;
/// selected = 2px saffron ring + a small saffron check badge in the
/// top-start corner. Icon and label sit centred.
class _GoalCard extends StatelessWidget {
  const _GoalCard({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: AppMotion.standard,
          curve: AppMotion.curve,
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? tokens.accent : tokens.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 26,
                      color: selected ? tokens.accent : tokens.textSecondary,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AppTypeScale.caption.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                PositionedDirectional(
                  top: AppSpacing.sm,
                  start: AppSpacing.sm,
                  child: Icon(
                    AppIcons.selectedCheck,
                    size: 16,
                    color: tokens.accent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
