import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../templates/domain/template.dart';
import 'section_header.dart';
import 'template_card.dart';

/// One horizontal row representing a [TemplateCategory] (Quote,
/// Sale, Story, …). Header on top, peek-edge horizontal list below.
///
/// The trailing edge fades via a [ShaderMask] so a partially
/// visible last tile reads as "scroll for more" rather than as a
/// clipped layout bug.
class CategoryRow extends StatelessWidget {
  const CategoryRow({
    super.key,
    required this.title,
    required this.templates,
    required this.onOpen,
    this.onSeeAll,
    this.cardHeight = 160,
    this.thumbnailAspectRatio,
  });

  final String title;
  final List<Template> templates;
  final void Function(Template) onOpen;
  final VoidCallback? onSeeAll;
  final double cardHeight;

  /// When set, every thumbnail in the row is forced to this aspect
  /// ratio so a row of mixed-format templates (square + portrait)
  /// still reads as a uniform rhythm. The template's real aspect
  /// still applies once the user lands in the editor.
  final double? thumbnailAspectRatio;

  @override
  Widget build(BuildContext context) {
    if (templates.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppSpacing.pageGutter,
            end: AppSpacing.pageGutter,
          ),
          child: SectionHeader(
            title: title,
            actionLabel: onSeeAll == null ? null : 'See all',
            onAction: onSeeAll,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          // Card height + label row + slack for accessibility scale.
          height: cardHeight + 36,
          child: ShaderMask(
            // The shader callback runs outside the widget tree, so
            // there's no ambient `Directionality` for it to resolve
            // an `AlignmentDirectional` against. We capture the
            // direction here and pass it explicitly to
            // `createShader` so the fade always lands on the
            // trailing edge under both LTR and RTL.
            shaderCallback: (rect) => const LinearGradient(
              begin: AlignmentDirectional.centerStart,
              end: AlignmentDirectional.centerEnd,
              stops: [0.0, 0.92, 1.0],
              colors: [
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
            ).createShader(rect, textDirection: Directionality.of(context)),
            blendMode: BlendMode.dstIn,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsetsDirectional.only(
                start: AppSpacing.pageGutter,
                // Trailing pad pushes the last card slightly past
                // the right edge so the peek affordance survives
                // even when the row exactly fits the viewport.
                end: AppSpacing.xxl,
              ),
              itemCount: templates.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: AppSpacing.md),
              itemBuilder: (context, i) => TemplateCard(
                key: ValueKey(templates[i].id),
                template: templates[i],
                height: cardHeight,
                aspectRatioOverride: thumbnailAspectRatio,
                onTap: () => onOpen(templates[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
