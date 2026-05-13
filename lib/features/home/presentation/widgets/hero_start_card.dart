import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../l10n/l10n.dart';
import '../../../templates/domain/template.dart';
import '../../../templates/presentation/template_preview.dart';
import 'home_style.dart';

/// Premium start card for Home.
///
/// The card is decorative plus actionable: it introduces the template
/// workflow and keeps the visual language aligned with onboarding's
/// floating-card identity without changing any editor or template logic.
class HeroStartCard extends StatelessWidget {
  const HeroStartCard({
    super.key,
    required this.templates,
    required this.onChooseTemplate,
  });

  final List<Template> templates;
  final VoidCallback onChooseTemplate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.pageGutter,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final illustrationWidth = math.min(
            138.0,
            constraints.maxWidth * 0.34,
          );
          final content = _HeroCopy(onChooseTemplate: onChooseTemplate);
          final illustration = _HeroIllustration(
            templates: templates,
            width: illustrationWidth,
          );

          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [Color(0xFFFFFEFC), Color(0xFFF1ECFF)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: HomePalette.hairline.withValues(alpha: 0.72),
              ),
              boxShadow: [
                BoxShadow(
                  color: HomePalette.shadow.withValues(alpha: 0.11),
                  blurRadius: 26,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: content),
                  const SizedBox(width: AppSpacing.md),
                  illustration,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({required this.onChooseTemplate});

  final VoidCallback onChooseTemplate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.homeHeroTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.start,
          style: theme.textTheme.titleLarge?.copyWith(
            color: HomePalette.ink,
            fontWeight: FontWeight.w900,
            height: 1.14,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.homeHeroSubtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.start,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: HomePalette.muted,
            fontWeight: FontWeight.w600,
            height: 1.45,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.icon(
          onPressed: onChooseTemplate,
          icon: const Icon(Icons.auto_awesome_rounded, size: 16),
          label: Text(l10n.homeChooseTemplateAction),
          style: FilledButton.styleFrom(
            backgroundColor: HomePalette.accentSoft,
            foregroundColor: HomePalette.accent,
            elevation: 0,
            minimumSize: const Size(0, 38),
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroIllustration extends StatelessWidget {
  const _HeroIllustration({required this.templates, required this.width});

  final List<Template> templates;
  final double width;

  @override
  Widget build(BuildContext context) {
    final persianStory = _templateById(templates, 'fa_story_fashion_drop');
    final englishFeature = _templateById(templates, 'en_yt_tutorial_blueprint');
    final persianPoster = _templateById(templates, 'fa_promo_app_launch');
    return SizedBox(
      width: width,
      height: 146,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PositionedDirectional(
            top: 24,
            end: 4,
            child: Container(
              width: width * 0.7,
              height: 92,
              decoration: BoxDecoration(
                color: HomePalette.accentSoft.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: HomePalette.accent.withValues(alpha: 0.14),
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
            ),
          ),
          PositionedDirectional(
            top: 16,
            start: 4,
            end: 10,
            bottom: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: HomePalette.surfaceMuted.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: HomePalette.hairline.withValues(alpha: 0.62),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 0,
            start: 4,
            child: Transform.rotate(
              angle: -0.1,
              child: _MiniTemplateCard(
                template: englishFeature,
                width: width * 0.52,
                height: 68,
              ),
            ),
          ),
          PositionedDirectional(
            top: 34,
            end: 0,
            child: Transform.rotate(
              angle: 0.045,
              child: _MiniTemplateCard(
                template: persianStory,
                width: width * 0.58,
                height: 102,
                elevated: true,
              ),
            ),
          ),
          PositionedDirectional(
            start: 18,
            bottom: 0,
            child: Transform.rotate(
              angle: -0.055,
              child: _MiniTemplateCard(
                template: persianPoster,
                width: width * 0.48,
                height: 64,
              ),
            ),
          ),
          PositionedDirectional(
            start: 0,
            bottom: 22,
            child: _ToolPill(width: width * 0.46),
          ),
          PositionedDirectional(
            end: 12,
            top: 4,
            child: _TypeMark(width: math.min(64, width * 0.55)),
          ),
        ],
      ),
    );
  }
}

class _TypeMark extends StatelessWidget {
  const _TypeMark({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: HomePalette.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: HomePalette.hairline.withValues(alpha: 0.72)),
        boxShadow: [
          BoxShadow(
            color: HomePalette.shadow.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: SizedBox(
        width: width,
        height: 28,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text(
              'Aa',
              style: TextStyle(
                color: HomePalette.ink,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            SizedBox(width: 3),
            Text(
              'فا',
              style: TextStyle(
                color: HomePalette.accent,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniTemplateCard extends StatelessWidget {
  const _MiniTemplateCard({
    required this.template,
    required this.width,
    required this.height,
    this.elevated = false,
  });

  final Template? template;
  final double width;
  final double height;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: HomePalette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: HomePalette.hairline.withValues(alpha: 0.58)),
        boxShadow: [
          BoxShadow(
            color: HomePalette.shadow.withValues(alpha: elevated ? 0.16 : 0.08),
            blurRadius: elevated ? 22 : 14,
            offset: Offset(0, elevated ? 12 : 7),
          ),
        ],
      ),
      child: SizedBox(
        width: width,
        height: height,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: template == null
                ? const DecoratedBox(
                    decoration: BoxDecoration(color: HomePalette.canvasPaper),
                  )
                : TemplatePreview(
                    template: template!,
                    borderRadius: 14,
                    fit: BoxFit.contain,
                  ),
          ),
        ),
      ),
    );
  }
}

class _ToolPill extends StatelessWidget {
  const _ToolPill({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: HomePalette.ink,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        boxShadow: [
          BoxShadow(
            color: HomePalette.shadow.withValues(alpha: 0.16),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SizedBox(
        width: width,
        height: 26,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.text_fields_rounded, color: Colors.white, size: 14),
            SizedBox(width: AppSpacing.xs),
            Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 12),
          ],
        ),
      ),
    );
  }
}

Template? _templateById(List<Template> templates, String id) {
  for (final template in templates) {
    if (template.id == id) return template;
  }
  return null;
}
