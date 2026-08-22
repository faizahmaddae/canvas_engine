import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/ui/template_thumb.dart';
import '../../../../l10n/l10n.dart';
import '../../../templates/domain/template.dart';
import '../../../templates/presentation/template_presentation_order.dart';

/// «پیشنهادِ امروز» on the Home launcher: a single HORIZONTAL rail of
/// curated [TemplateThumb]s with «مشاهده همه» jumping to the
/// Templates tab. The launcher shows a fixed-height teaser no matter
/// how big the catalog grows; browsing lives in the tab.
///
/// Living, not static: the rail draws a date-seeded selection from
/// the top of the curated order ([dailyTemplateShelf]), so the shelf
/// is stable within a day and different tomorrow — the screen keeps
/// the promise its own headline makes. Filter logic is unchanged:
/// only templates from enabled categories and the user's content
/// languages ever enter the pool.
class SuggestedTemplatesRail extends StatelessWidget {
  const SuggestedTemplatesRail({
    super.key,
    required this.onOpen,
    required this.onSeeAll,
    required List<Template> templates,
    this.contentLanguages,
    this.enabledCategories,
    this.today,
  }) : _templates = templates;

  /// Maximum thumbs on the rail — a curated teaser, not a catalog.
  static const int previewLimit = 10;

  /// Same curation priority the old recommended grid used.
  static const List<TemplateCategory> _categoryPriority = [
    TemplateCategory.instagramStory,
    TemplateCategory.promotionalPoster,
    TemplateCategory.poetryPost,
    TemplateCategory.youtubeThumbnail,
    TemplateCategory.quote,
    TemplateCategory.story,
    TemplateCategory.social,
    TemplateCategory.sale,
    TemplateCategory.business,
    TemplateCategory.food,
    TemplateCategory.event,
  ];

  final void Function(Template) onOpen;
  final VoidCallback onSeeAll;
  final Set<TemplateLanguage>? contentLanguages;
  final Set<TemplateCategory>? enabledCategories;
  final List<Template> _templates;

  /// The day the shelf is seeded with. Null means the device's today;
  /// tests inject a fixed date so the selection is deterministic.
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = AppTokens.of(context);
    final languages =
        contentLanguages ??
        {TemplateLanguage.english, TemplateLanguage.persian};
    final pool = _templates
        .where(
          (t) =>
              enabledCategories == null ||
              enabledCategories!.contains(t.category),
        )
        .where((t) => languages.contains(t.language))
        .toList(growable: false);
    final ordered = orderTemplatesForHome(
      templates: pool,
      preferredIds: kHomeRecommendedTemplateIds,
      categoryPriority: _categoryPriority,
    );
    final shown = dailyTemplateShelf(
      ordered: ordered,
      date: today ?? DateTime.now(),
      count: previewLimit,
    );

    if (shown.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppSpacing.pageGutter,
            end: AppSpacing.pageGutter,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.homeSuggestedTitle,
                  style: AppTypeScale.title.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('home-templates-see-all'),
                onPressed: onSeeAll,
                style: TextButton.styleFrom(
                  foregroundColor: tokens.accentText,
                  textStyle: AppTypeScale.caption.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(l10n.seeAllAction),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.pageGutter,
            ),
            itemCount: shown.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) {
              final template = shown[index];
              return GestureDetector(
                key: ValueKey('home-template-${template.id}'),
                onTap: () => onOpen(template),
                child: TemplateThumb(
                  template: template,
                  width: 110,
                  height: 150,
                  borderRadius: 16,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
