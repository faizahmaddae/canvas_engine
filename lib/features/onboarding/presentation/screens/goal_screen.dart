import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/warm_palette.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import '../../../templates/application/template_repository_provider.dart';
import '../../../templates/domain/template.dart';
import '../../application/onboarding_controller.dart';
import '../widgets/onboarding_buttons.dart';
import '../widgets/onboarding_interest_card.dart';
import '../widgets/onboarding_style.dart';

/// The six onboarding interests map onto existing template categories.
///
/// Design rationale: these are phrased as creator jobs (story, ad,
/// quote, thumbnail, text-on-photo, blank canvas) rather than internal
/// taxonomy. The persisted category still uses the existing settings
/// model, so onboarding remains a UI layer change.
const List<_GoalSpec> _goals = [
  _GoalSpec(
    category: TemplateCategory.instagramStory,
    templateId: 'fa_insta_story_v1',
    aspectRatio: 9 / 16,
  ),
  _GoalSpec(
    category: TemplateCategory.promotionalPoster,
    templateId: 'fa_promo_v1',
    aspectRatio: 4 / 5,
  ),
  _GoalSpec(
    category: TemplateCategory.poetryPost,
    templateId: 'fa_poetry_v1',
    aspectRatio: 1,
  ),
  _GoalSpec(
    category: TemplateCategory.youtubeThumbnail,
    templateId: 'en_yt_thumb_v1',
    aspectRatio: 16 / 9,
  ),
  _GoalSpec(
    category: TemplateCategory.quote,
    templateId: 'fa_poetry_overlay_v1',
    aspectRatio: 1,
  ),
  _GoalSpec(
    category: TemplateCategory.social,
    templateId: null,
    aspectRatio: 1,
  ),
];

class _GoalSpec {
  const _GoalSpec({
    required this.category,
    required this.templateId,
    required this.aspectRatio,
  });

  final TemplateCategory category;
  final String? templateId;
  final double aspectRatio;
}

/// Goal picker.
///
/// Design rationale: this page is where the product becomes personal.
/// The cards use real templates at a meaningful size, while selection
/// adds a soft purple overlay and checkmark so the chosen interests
/// feel alive without making the resting grid noisy.
class GoalScreen extends ConsumerWidget {
  const GoalScreen({super.key, required this.onContinue, required this.onSkip});

  final VoidCallback onContinue;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choices = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);
    final l10n = context.l10n;
    final templates = ref.watch(
      effectiveTemplatesProvider(Localizations.localeOf(context).languageCode),
    );
    final palette = WarmPalette.of(context);
    return OnboardingPageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.onboardingGoalTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.ink,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.22,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Text(
                l10n.onboardingGoalSubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.6,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.only(bottom: 96),
              crossAxisCount: 2,
              crossAxisSpacing: AppSpacing.md,
              mainAxisSpacing: AppSpacing.md,
              childAspectRatio: 1.2,
              physics: const BouncingScrollPhysics(),
              children: [
                for (final spec in _goals)
                  _goalCard(
                    l10n: l10n,
                    spec: spec,
                    templates: templates,
                    selected: choices.selectedCategories.contains(
                      spec.category,
                    ),
                    onTap: () => controller.toggleCategory(spec.category),
                  ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  palette.backgroundBottom.withValues(alpha: 0),
                  palette.backgroundBottom,
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  OnboardingPrimaryButton(
                    key: const ValueKey('onboarding-goal-continue'),
                    label: l10n.onboardingContinue,
                    onPressed: onContinue,
                  ),
                  OnboardingTextButton(
                    key: const ValueKey('onboarding-goal-skip'),
                    label: l10n.onboardingSkip,
                    onPressed: onSkip,
                  ),
                ],
              ),
            ),
          ),
        ],
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
      TemplateCategory.social => l10n.onboardingGoalBlankCanvas,
      _ => l10n.categorySocial,
    };

Widget? _previewFor(TemplateCategory category) => switch (category) {
  TemplateCategory.quote => const TextOnPhotoPreview(),
  TemplateCategory.social => const BlankCanvasPreview(),
  _ => null,
};

Widget _goalCard({
  required AppLocalizations l10n,
  required _GoalSpec spec,
  required List<Template> templates,
  required bool selected,
  required VoidCallback onTap,
}) {
  final template = _templateFor(templates, spec.templateId);
  return OnboardingInterestCard(
    key: ValueKey('onboarding-goal-${spec.category.name}'),
    title: _goalLabel(l10n, spec.category),
    template: template,
    preview:
        _previewFor(spec.category) ??
        (template == null ? const BlankCanvasPreview() : null),
    aspectRatio: spec.aspectRatio,
    selected: selected,
    onTap: onTap,
  );
}

Template? _templateFor(List<Template> source, String? id) {
  if (id == null) return null;
  for (final template in source) {
    if (template.id == id) return template;
  }
  return null;
}
