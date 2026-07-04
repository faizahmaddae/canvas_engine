import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/warm_palette.dart';
import '../../../../l10n/l10n.dart';
import '../../../templates/domain/template.dart';
import '../../../templates/presentation/template_preview.dart';

/// Lightweight Flutter-built illustration for onboarding.
///
/// Design rationale: the onboarding should show the product category
/// immediately without heavy assets. Layered template cards, localized
/// type specimens, and small editor-like chips communicate multilingual
/// design while staying cheap to paint and easy to maintain.
class OnboardingTemplateCollage extends StatelessWidget {
  const OnboardingTemplateCollage({
    super.key,
    required this.templates,
    this.height = 300,
    this.emphasizeTypography = false,
    this.showWorkspace = false,
  });

  final List<Template> templates;
  final double height;
  final bool emphasizeTypography;
  final bool showWorkspace;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final mainWidth = math.min(168.0, width * 0.45);
          final sideWidth = math.min(132.0, width * 0.35);
          final chipWidth = math.min(138.0, width * 0.36);
          final firstTemplate = templates.isNotEmpty ? templates[0] : null;
          final secondTemplate = templates.length > 1 ? templates[1] : null;
          final thirdTemplate = templates.length > 2 ? templates[2] : null;
          final palette = WarmPalette.of(context);

          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (showWorkspace)
                PositionedDirectional(
                  top: height * 0.13,
                  start: width * 0.04,
                  end: width * 0.04,
                  bottom: height * 0.08,
                  child: const _WorkspaceSurface(),
                ),
              PositionedDirectional(
                top: height * 0.03,
                start: width * 0.08,
                child: _TypeChip(
                  width: chipWidth,
                  title: l10n.onboardingArtTypography,
                  subtitle: l10n.onboardingArtPersian,
                  color: palette.saffron,
                ),
              ),
              PositionedDirectional(
                top: height * 0.05,
                end: width * 0.05,
                child: _PaletteCard(width: math.min(96, width * 0.25)),
              ),
              PositionedDirectional(
                top: height * 0.2,
                start: width * 0.05,
                child: Transform.rotate(
                  angle: -0.12,
                  child: _TemplateArtCard(
                    width: sideWidth,
                    height: height * 0.48,
                    template: secondTemplate,
                    label: l10n.onboardingArtStory,
                  ),
                ),
              ),
              PositionedDirectional(
                top: height * 0.11,
                child: Transform.rotate(
                  angle: 0.035,
                  child: _TemplateArtCard(
                    width: mainWidth,
                    height: height * 0.64,
                    template: firstTemplate,
                    label: l10n.appName,
                    elevated: true,
                  ),
                ),
              ),
              PositionedDirectional(
                end: width * 0.06,
                bottom: height * 0.08,
                child: Transform.rotate(
                  angle: 0.11,
                  child: _TemplateArtCard(
                    width: sideWidth,
                    height: height * 0.42,
                    template: thirdTemplate,
                    label: l10n.onboardingArtTemplate,
                  ),
                ),
              ),
              PositionedDirectional(
                start: width * 0.18,
                bottom: height * 0.02,
                child: _EditorPill(
                  icon: Icons.text_fields_rounded,
                  text: emphasizeTypography
                      ? l10n.onboardingArtPersianLetters
                      : l10n.onboardingArtReadyText,
                ),
              ),
              PositionedDirectional(
                end: width * 0.21,
                top: height * 0.74,
                child: _EditorPill(
                  icon: Icons.layers_rounded,
                  text: l10n.onboardingArtLayers,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TemplateArtCard extends StatelessWidget {
  const _TemplateArtCard({
    required this.width,
    required this.height,
    required this.template,
    required this.label,
    this.elevated = false,
  });

  final double width;
  final double height;
  final Template? template;
  final String label;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final palette = WarmPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: palette.hairline.withValues(alpha: 0.58),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(
              alpha: elevated ? 0.18 : 0.1,
            ),
            blurRadius: elevated ? 40 : 24,
            offset: Offset(0, elevated ? 22 : 13),
          ),
        ],
      ),
      child: SizedBox(
        width: width,
        height: height,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: template == null
                      ? const _PersianTypeSpecimen()
                      : TemplatePreview(
                          template: template!,
                          borderRadius: 22,
                          fit: BoxFit.contain,
                        ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersianTypeSpecimen extends StatelessWidget {
  const _PersianTypeSpecimen();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = WarmPalette.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFFFF6EA), Color(0xFFECE7FF)],
        ),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            top: 18,
            end: 18,
            child: Text(
              l10n.onboardingArtAlphabet,
              style: TextStyle(
                color: palette.accent.withValues(alpha: 0.9),
                fontFamily: 'BTitrBd',
                fontSize: 30,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
          PositionedDirectional(
            bottom: 18,
            start: 18,
            child: Text(
              l10n.onboardingArtBeautiful,
              style: TextStyle(
                color: palette.ink.withValues(alpha: 0.9),
                fontFamily: 'IranNastaliq',
                fontSize: 28,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.width,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final double width;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = WarmPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.hairline),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 4,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceSurface extends StatelessWidget {
  const _WorkspaceSurface();

  @override
  Widget build(BuildContext context) {
    final palette = WarmPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceMuted.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: palette.hairline.withValues(alpha: 0.68),
        ),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            top: AppSpacing.md,
            start: AppSpacing.lg,
            end: AppSpacing.lg,
            child: Row(
              children: [
                for (final color in [
                  palette.rose,
                  palette.saffron,
                  palette.accent,
                ]) ...[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.72),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                const Spacer(),
                Container(
                  width: 54,
                  height: 7,
                  decoration: BoxDecoration(
                    color: palette.hairline.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                ),
              ],
            ),
          ),
          PositionedDirectional(
            top: 38,
            start: AppSpacing.md,
            end: AppSpacing.md,
            bottom: AppSpacing.md,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.canvasPaper.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: palette.hairline.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaletteCard extends StatelessWidget {
  const _PaletteCard({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final palette = WarmPalette.of(context);
    final colors = [
      palette.accent,
      palette.rose,
      palette.saffron,
      palette.ink,
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.hairline),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final color in colors) ...[
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                if (color != colors.last) const SizedBox(width: AppSpacing.xs),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorPill extends StatelessWidget {
  const _EditorPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = WarmPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.ink,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: Colors.white),
            const SizedBox(width: AppSpacing.xs),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
