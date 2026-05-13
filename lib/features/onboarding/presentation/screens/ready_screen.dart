import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../l10n/l10n.dart';
import '../../../templates/application/template_repository_provider.dart';
import '../../../templates/domain/template.dart';
import '../../application/onboarding_controller.dart';
import '../widgets/onboarding_art.dart';
import '../widgets/onboarding_buttons.dart';
import '../widgets/onboarding_style.dart';

/// Final onboarding screen shown after the goal pick.
///
/// Design rationale: the user should feel that a curated studio is
/// ready for them. The layered preview composition uses only selected
/// categories, adds depth through shadows, and avoids empty slots so
/// the screen feels complete rather than like a wireframe.
class ReadyScreen extends ConsumerStatefulWidget {
  const ReadyScreen({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  ConsumerState<ReadyScreen> createState() => _ReadyScreenState();
}

class _ReadyScreenState extends ConsumerState<ReadyScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _entry;

  static const _templateByCategory = <TemplateCategory, String>{
    TemplateCategory.instagramStory: 'fa_insta_story_v1',
    TemplateCategory.promotionalPoster: 'fa_promo_v1',
    TemplateCategory.poetryPost: 'fa_poetry_v1',
    TemplateCategory.youtubeThumbnail: 'en_yt_thumb_v1',
    TemplateCategory.quote: 'fa_poetry_overlay_v1',
    TemplateCategory.social: 'fa_announcement',
  };

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..forward();
    _entry = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  List<Template> _resolveTemplates(
    List<Template> source,
    Set<TemplateCategory> selected,
  ) {
    final effective = selected.isEmpty
        ? _templateByCategory.keys.take(4).toSet()
        : selected;
    final ids = [
      for (final category in effective) _templateByCategory[category],
    ].whereType<String>();
    return [
      for (final id in ids)
        for (final template in source)
          if (template.id == id) template,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final choices = ref.watch(onboardingControllerProvider);
    final source = ref.watch(
      effectiveTemplatesProvider(Localizations.localeOf(context).languageCode),
    );
    final templates = _resolveTemplates(source, choices.selectedCategories);
    return OnboardingPageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xl),
          Text(
            l10n.onboardingReadyTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: OnboardingPalette.ink,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              height: 1.25,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Text(
                l10n.onboardingReadySubtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: OnboardingPalette.muted,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.7,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final collageHeight = math.min(
                  370.0,
                  constraints.maxHeight * 0.86,
                );
                return Align(
                  alignment: const Alignment(0, -0.3),
                  child: FadeTransition(
                    opacity: _entry,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.96, end: 1).animate(_entry),
                      child: OnboardingTemplateCollage(
                        templates: templates,
                        height: collageHeight,
                        emphasizeTypography: true,
                        showWorkspace: true,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          OnboardingPrimaryButton(
            key: const ValueKey('onboarding-ready-cta'),
            label: l10n.onboardingReadyCta,
            onPressed: widget.onStart,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
