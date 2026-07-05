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
/// §5): a colour hero (`brandStrong`, ~56% of the height) showcasing
/// three real templates, and a rising [AppContentSheet] below with
/// the pitch + primary CTA.
///
/// Design rationale: this screen should immediately read as
/// multilingual design software with strong Persian typography
/// support. The showcase is a curated, warm-toned trio so the hero
/// reads as one designed set, not three unrelated cards.
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
    final bottomInset = MediaQuery.of(context).padding.bottom;
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
            // Colour hero (~56%). Enlarged, fanned cards fill it so
            // there's no dead violet band above the sheet.
            Expanded(
              flex: 56,
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
            // Rising sheet (~44%). Title + tagline pinned to the top,
            // CTA pinned to the bottom (padding = safe-area + 20), the
            // slack between them absorbed by a Spacer — no white void
            // under the button.
            Expanded(
              flex: 44,
              child: AppContentSheet(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  compact ? AppSpacing.lg : AppSpacing.xl,
                  AppSpacing.xl,
                  bottomInset + 20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypeScale.body.copyWith(
                                color: tokens.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    AppPrimaryButton(
                      key: const ValueKey('onboarding-get-started'),
                      label: l10n.onboardingGetStarted,
                      onPressed: widget.onGetStarted,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Three real templates fanned like a hand of cards for energy
/// (design doc §5): side cards tilted ±8° and dropped slightly, the
/// centre card upright, raised, and drawn in front. The cards float
/// directly on the hero — no backing panel — each lifted by a soft
/// drop shadow.
///
/// Purely a welcome-screen composition; [TemplateThumb] itself stays
/// a plain flat card so it's reusable elsewhere (Home, Templates
/// browse) without carrying this arrangement or its shadows.
class _ThumbShowcase extends StatelessWidget {
  const _ThumbShowcase({required this.templates, required this.compact});

  final List<Template> templates;
  final bool compact;

  static const _sideShadow = [
    BoxShadow(
      color: Color(0x33000000), // black @ 0.20
      blurRadius: 26,
      offset: Offset(0, 10),
    ),
  ];
  static const _centerShadow = [
    BoxShadow(
      color: Color(0x3D000000), // black @ 0.24
      blurRadius: 32,
      offset: Offset(0, 14),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // Degrade gracefully if the curated ids ever go missing (e.g. a
    // locale with a trimmed catalog): just row whatever we have.
    if (templates.length < 3) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in templates)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: TemplateThumb(
                template: t,
                width: 100,
                height: 138,
                borderRadius: 16,
                boxShadow: _sideShadow,
              ),
            ),
        ],
      );
    }

    Widget card(
      Template template, {
      required double left,
      required double top,
      required double angleDeg,
      required bool centre,
    }) {
      return Positioned(
        left: left,
        top: top,
        child: Transform.rotate(
          angle: angleDeg * math.pi / 180,
          child: TemplateThumb(
            template: template,
            width: centre ? 112 : 106,
            height: centre ? 152 : 146,
            borderRadius: 16,
            boxShadow: centre ? _centerShadow : _sideShadow,
          ),
        ),
      );
    }

    return Transform.scale(
      scale: compact ? 0.86 : 1.0,
      child: SizedBox(
        width: 250,
        height: 196,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            card(templates[0], left: 6, top: 30, angleDeg: -8, centre: false),
            card(templates[2], left: 138, top: 30, angleDeg: 8, centre: false),
            // Centre last → painted in front of both side cards.
            card(templates[1], left: 69, top: 8, angleDeg: 0, centre: true),
          ],
        ),
      ),
    );
  }
}

List<Template> _welcomeTemplates(List<Template> source) {
  // A cohesive warm-toned trio (cream card on a warm gradient), so the
  // hero reads as one designed set. Centre id is the amber centrepiece.
  const ids = [
    'fa_story_warm_pastel', // peach/pink — left
    'fa_story_cafe_mood', // warm amber — centre (front)
    'fa_story_fashion_drop', // warm maroon — right
  ];
  return [
    for (final id in ids)
      for (final template in source)
        if (template.id == id) template,
  ];
}
