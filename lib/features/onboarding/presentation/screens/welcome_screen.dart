import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../l10n/l10n.dart';
import '../../../templates/application/template_repository_provider.dart';
import '../../../templates/domain/template.dart';
import '../widgets/onboarding_art.dart';
import '../widgets/onboarding_buttons.dart';
import '../widgets/onboarding_style.dart';

/// First onboarding screen.
///
/// Design rationale: this screen should immediately read as multilingual
/// design software with strong Persian typography support. The illustration
/// mixes real English and Persian templates; the copy stays short so the
/// user feels welcomed, not pitched.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({
    super.key,
    required this.onGetStarted,
    required this.onSkip,
  });

  final VoidCallback onGetStarted;
  final VoidCallback onSkip;

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _entryOpacity;
  late final Animation<Offset> _entryOffset;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    final curve = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );
    _entryOpacity = curve;
    _entryOffset = Tween<Offset>(
      begin: const Offset(0, 0.025),
      end: Offset.zero,
    ).animate(curve);
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final templates = _welcomeTemplates(
      ref.watch(
        effectiveTemplatesProvider(
          Localizations.localeOf(context).languageCode,
        ),
      ),
    );
    return OnboardingPageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              key: const ValueKey('onboarding-welcome-skip'),
              onPressed: widget.onSkip,
              style: TextButton.styleFrom(
                foregroundColor: OnboardingPalette.muted,
              ),
              child: Text(l10n.onboardingSkip),
            ),
          ),
          Expanded(
            child: FadeTransition(
              opacity: _entryOpacity,
              child: SlideTransition(
                position: _entryOffset,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxHeight < 650;
                    final collageHeight = compact ? 276.0 : 310.0;
                    return SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Align(
                          alignment: Alignment(0, compact ? -0.18 : -0.34),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _BrandPill(label: l10n.appName),
                              const SizedBox(height: AppSpacing.md),
                              OnboardingTemplateCollage(
                                templates: templates,
                                height: collageHeight,
                                emphasizeTypography: true,
                              ),
                              SizedBox(
                                height: compact ? AppSpacing.lg : AppSpacing.xl,
                              ),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 360,
                                ),
                                child: Text(
                                  l10n.onboardingWelcomeTitle,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: OnboardingPalette.ink,
                                    fontSize: 34,
                                    fontWeight: FontWeight.w900,
                                    height: 1.28,
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 330,
                                ),
                                child: Text(
                                  l10n.onboardingWelcomeTagline,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: OnboardingPalette.muted,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    height: 1.75,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          OnboardingPrimaryButton(
            key: const ValueKey('onboarding-get-started'),
            label: l10n.onboardingGetStarted,
            onPressed: widget.onGetStarted,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

class _BrandPill extends StatelessWidget {
  const _BrandPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: OnboardingPalette.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: OnboardingPalette.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: OnboardingPalette.accent,
            fontSize: 15,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    );
  }
}

List<Template> _welcomeTemplates(List<Template> source) {
  const ids = [
    'fa_insta_story_v1',
    'en_quote_editorial_gradient',
    'fa_promo_v1',
  ];
  return [
    for (final id in ids)
      for (final template in source)
        if (template.id == id) template,
  ];
}
