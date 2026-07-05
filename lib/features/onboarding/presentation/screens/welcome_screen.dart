import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/ui/app_content_sheet.dart';
import '../../../../app/ui/app_primary_button.dart';
import '../../../../app/ui/brand_mark.dart';
import '../../../../app/ui/skip_text_button.dart';
import '../../../../app/ui/template_thumb.dart';
import '../../../../l10n/l10n.dart';
import '../../../templates/application/template_repository_provider.dart';
import '../../../templates/domain/template.dart';

/// First onboarding screen — design-system Direction C (design doc
/// §5): a colour hero (`brandStrong`, ~55% of the height) showcasing
/// three real templates, and a rising [AppContentSheet] below with
/// the pitch + primary CTA.
///
/// Design rationale: this screen should immediately read as
/// multilingual design software with strong Persian typography
/// support. The showcase mixes real English and Persian templates;
/// the copy stays short so the user feels welcomed, not pitched.
///
/// Fully token-driven — no `WarmPalette` usage (design doc §6). Goal
/// and Ready keep `WarmPalette`/`OnboardingPrimaryButton` until each
/// is rebuilt on tokens in its own commit.
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
    final tokens = AppTokens.of(context);
    final templates = _welcomeTemplates(
      ref.watch(
        effectiveTemplatesProvider(
          Localizations.localeOf(context).languageCode,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 650;
        return Column(
          children: [
            Expanded(
              flex: 55,
              child: ColoredBox(
                color: tokens.brandStrong,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.pageGutter,
                      vertical: AppSpacing.sm,
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const BrandMark(),
                            SkipTextButton(
                              key: const ValueKey('onboarding-welcome-skip'),
                              label: l10n.onboardingSkip,
                              onPressed: widget.onSkip,
                            ),
                          ],
                        ),
                        Expanded(
                          child: Center(
                            child: FadeTransition(
                              opacity: _entryOpacity,
                              child: SlideTransition(
                                position: _entryOffset,
                                child: _ThumbShowcase(
                                  templates: templates,
                                  compact: compact,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 45,
              child: AppContentSheet(
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FadeTransition(
                          opacity: _entryOpacity,
                          child: SlideTransition(
                            position: _entryOffset,
                            child: Column(
                              children: [
                                Text(
                                  l10n.onboardingWelcomeTitle,
                                  textAlign: TextAlign.center,
                                  style: AppTypeScale.titleLg.copyWith(
                                    color: tokens.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  l10n.onboardingWelcomeTagline,
                                  textAlign: TextAlign.center,
                                  style: AppTypeScale.body.copyWith(
                                    color: tokens.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                          height: compact ? AppSpacing.lg : AppSpacing.xl,
                        ),
                        AppPrimaryButton(
                          key: const ValueKey('onboarding-get-started'),
                          label: l10n.onboardingGetStarted,
                          onPressed: widget.onGetStarted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Three real templates fanned with slight alternating rotation for
/// energy (design doc §5). Purely a welcome-screen composition —
/// [TemplateThumb] itself stays a plain, unrotated card so it's
/// reusable elsewhere (Home, Templates browse) without carrying this
/// screen's specific arrangement.
class _ThumbShowcase extends StatelessWidget {
  const _ThumbShowcase({required this.templates, required this.compact});

  final List<Template> templates;
  final bool compact;

  static const _rotationDegrees = 6;

  @override
  Widget build(BuildContext context) {
    final width = compact ? 84.0 : 100.0;
    final height = compact ? 112.0 : 134.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final (index, template) in templates.indexed)
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: index == 0 ? 0 : AppSpacing.sm,
            ),
            child: Transform.rotate(
              angle: (index.isEven ? -1 : 1) * _rotationDegrees * math.pi / 180,
              child: TemplateThumb(
                template: template,
                width: width,
                height: height,
              ),
            ),
          ),
      ],
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
