import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../templates/domain/template.dart';
import 'section_header.dart';
import 'template_card.dart';

/// One horizontal row representing a [TemplateCategory] (Quote,
/// Sale, Story, …). Header on top, peek-edge horizontal list below.
///
/// Directional padding keeps the first card cleanly aligned under
/// both LTR and RTL.
class CategoryRow extends StatelessWidget {
  const CategoryRow({
    super.key,
    required this.title,
    required this.templates,
    required this.onOpen,
    this.onSeeAll,
    this.actionLabel = 'See all',
    this.cardHeight = 160,
    this.thumbnailAspectRatio,
    this.cardMinWidth = 110,
    this.cardMaxWidth = 180,
  });

  final String title;
  final List<Template> templates;
  final void Function(Template) onOpen;
  final VoidCallback? onSeeAll;
  final String actionLabel;
  final double cardHeight;

  /// When set, every thumbnail in the row is forced to this aspect
  /// ratio so a row of mixed-format templates (square + portrait)
  /// still reads as a uniform rhythm. The template's real aspect
  /// still applies once the user lands in the editor.
  final double? thumbnailAspectRatio;

  /// Width clamps forwarded to [TemplateCard]. Focused Home rows set
  /// these to the same exact width so category-specific aspect ratios
  /// are preserved; legacy callers keep the flexible defaults.
  final double cardMinWidth;
  final double cardMaxWidth;

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
            actionLabel: onSeeAll == null ? null : actionLabel,
            onAction: onSeeAll,
            compact: true,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          // Card height + label row + slack for accessibility scale.
          height: cardHeight + 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsetsDirectional.only(
              start: AppSpacing.pageGutter,
              end: AppSpacing.pageGutter,
            ),
            itemCount: templates.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, i) => TemplateCard(
              key: ValueKey(templates[i].id),
              template: templates[i],
              height: cardHeight,
              minWidth: cardMinWidth,
              maxWidth: cardMaxWidth,
              aspectRatioOverride: thumbnailAspectRatio,
              onTap: () => onOpen(templates[i]),
            ),
          ),
        ),
      ],
    );
  }
}
