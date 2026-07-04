import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/warm_palette.dart';
import '../../../templates/domain/template.dart';
import '../../../templates/presentation/template_preview.dart';

/// Visual interest picker card used on the Goal screen.
///
/// Design rationale: resting cards should feel like polished magazine
/// tiles, not settings toggles. Selection adds the purple accent,
/// checkmark, and lifted surface so the moment of choosing feels clear
/// without making the whole screen loud.
class OnboardingInterestCard extends StatefulWidget {
  const OnboardingInterestCard({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.template,
    this.preview,
    this.aspectRatio = 1,
  }) : assert(template != null || preview != null);

  final String title;
  final bool selected;
  final VoidCallback onTap;
  final Template? template;
  final Widget? preview;
  final double aspectRatio;

  @override
  State<OnboardingInterestCard> createState() => _OnboardingInterestCardState();
}

class _OnboardingInterestCardState extends State<OnboardingInterestCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final palette = WarmPalette.of(context);
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.985 : (selected ? 1.004 : 1),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      palette.surface,
                      palette.accentSoft.withValues(alpha: 0.46),
                    ],
                  )
                : null,
            color: selected ? null : palette.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected
                  ? palette.accent.withValues(alpha: 0.18)
                  : palette.hairline,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: selected
                    ? palette.accent.withValues(alpha: 0.12)
                    : palette.shadow.withValues(alpha: 0.055),
                blurRadius: selected ? 24 : 13,
                offset: Offset(0, selected ? 11 : 7),
              ),
            ],
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _InterestPreview(widget: widget)),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected
                            ? palette.ink
                            : palette.muted,
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w900
                            : FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              PositionedDirectional(
                top: AppSpacing.md,
                end: AppSpacing.md,
                child: AnimatedOpacity(
                  opacity: selected ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: AnimatedScale(
                    scale: selected ? 1 : 0.82,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: palette.accent.withValues(
                              alpha: 0.26,
                            ),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const SizedBox(
                        width: 18,
                        height: 18,
                        child: Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InterestPreview extends StatelessWidget {
  const _InterestPreview({required this.widget});

  final OnboardingInterestCard widget;

  @override
  Widget build(BuildContext context) {
    final palette = WarmPalette.of(context);
    return Center(
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.canvasPaper,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: palette.hairline.withValues(alpha: 0.78),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child:
                  widget.preview ??
                  TemplatePreview(
                    template: widget.template!,
                    borderRadius: 12,
                    fit: BoxFit.contain,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class BlankCanvasPreview extends StatelessWidget {
  const BlankCanvasPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = WarmPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [palette.surface, palette.accentSoft],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.surface.withValues(alpha: 0.64),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: palette.hairline.withValues(alpha: 0.72),
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              top: AppSpacing.sm,
              start: AppSpacing.sm,
              end: AppSpacing.sm,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showDots = constraints.maxWidth >= 28;
                  return Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: FractionallySizedBox(
                            widthFactor: 0.7,
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: palette.hairline.withValues(
                                  alpha: 0.9,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppRadii.pill,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (showDots) ...[
                        const SizedBox(width: AppSpacing.xs),
                        for (final color in [
                          palette.rose,
                          palette.saffron,
                          palette.accent,
                        ]) ...[
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.74),
                              shape: BoxShape.circle,
                            ),
                          ),
                          if (color != palette.accent)
                            const SizedBox(width: 2),
                        ],
                      ],
                    ],
                  );
                },
              ),
            ),
            PositionedDirectional(
              top: 28,
              end: AppSpacing.sm,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.add_rounded,
                  color: palette.accent,
                  size: 20,
                ),
              ),
            ),
            PositionedDirectional(
              top: 38,
              start: AppSpacing.md,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: palette.accentSoft.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: palette.accent.withValues(alpha: 0.12),
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              start: AppSpacing.md,
              bottom: AppSpacing.md,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 58,
                    height: 7,
                    decoration: BoxDecoration(
                      color: palette.ink.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    width: 38,
                    height: 7,
                    decoration: BoxDecoration(
                      color: palette.saffron.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TextOnPhotoPreview extends StatelessWidget {
  const TextOnPhotoPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = WarmPalette.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFFFD8C8), Color(0xFF7865FF)],
        ),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            top: AppSpacing.md,
            start: AppSpacing.md,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
            ),
          ),
          PositionedDirectional(
            end: AppSpacing.sm,
            bottom: AppSpacing.sm,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: palette.ink.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          PositionedDirectional(
            start: AppSpacing.md,
            end: AppSpacing.md,
            bottom: AppSpacing.md,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.surface.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadow.withValues(alpha: 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 7,
                      decoration: BoxDecoration(
                        color: palette.ink.withValues(alpha: 0.86),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 6,
                          decoration: BoxDecoration(
                            color: palette.accent.withValues(
                              alpha: 0.64,
                            ),
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: palette.hairline.withValues(
                                alpha: 0.86,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppRadii.pill,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
