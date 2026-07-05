import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/ui/template_thumb.dart';
import '../../../../l10n/l10n.dart';
import '../../../templates/domain/template.dart';
import '../../../templates/presentation/template_presentation_order.dart';
import '../../../templates/presentation/templates_browse_screen.dart';

enum HomeTemplateLanguageFilter { all, persian, english, mixed }

/// Templates block on Home, v2 (home redesign doc §5): a header row
/// — «قالب‌ها» + a «مشاهده همه» accent link — the language filter
/// chips, and ONE curated 2-column grid of colourful [TemplateThumb]
/// previews. The category strips are gone; the grid carries the
/// colour, the chrome stays quiet.
///
/// Filter LOGIC is unchanged from the strip era: the local language
/// filter intersects the user's content-language settings, and only
/// templates from enabled categories appear.
class TemplatesSection extends StatelessWidget {
  const TemplatesSection({
    super.key,
    required this.onOpen,
    required List<Template> templates,
    this.contentLanguages,
    this.enabledCategories,
    this.languageFilter = HomeTemplateLanguageFilter.all,
    this.filter,
  }) : _templates = templates;

  /// Maximum thumbnails on Home — the grid is a curated teaser, the
  /// full catalog lives behind «مشاهده همه». Also a build-cost cap:
  /// the grid is inside a box sliver (shrinkWrap), so every cell
  /// builds eagerly.
  static const int previewLimit = 10;

  /// Curation order for the grid — same priority the old
  /// "recommended" strip used, so the teaser stays hand-picked.
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

  final Set<TemplateLanguage>? contentLanguages;
  final HomeTemplateLanguageFilter languageFilter;

  /// The language filter chip row, rendered under the header so it
  /// reads as part of this section.
  final Widget? filter;

  final Set<TemplateCategory>? enabledCategories;

  /// Repository-backed source supplied by Home; tests inject a small
  /// catalog here so the grid/filter logic stays deterministic.
  final List<Template> _templates;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = AppTokens.of(context);
    final allowedLanguages = _allowedLanguages(
      languageFilter,
      contentLanguages,
    );
    final pool = _templates
        .where(
          (t) =>
              enabledCategories == null ||
              enabledCategories!.contains(t.category),
        )
        .where((t) => allowedLanguages.contains(t.language))
        .toList(growable: false);
    final ordered = orderTemplatesForHome(
      templates: pool,
      preferredIds: kHomeRecommendedTemplateIds,
      categoryPriority: _categoryPriority,
    );
    final shown = ordered.length > previewLimit
        ? ordered.sublist(0, previewLimit)
        : ordered;

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
                  l10n.templatesTitle,
                  style: AppTypeScale.title.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('home-templates-see-all'),
                onPressed: () => _openBrowse(context),
                style: TextButton.styleFrom(
                  foregroundColor: tokens.accent,
                  textStyle: AppTypeScale.caption.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(l10n.seeAllAction),
              ),
            ],
          ),
        ),
        if (filter != null) ...[const SizedBox(height: AppSpacing.xs), filter!],
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.pageGutter,
          ),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            childAspectRatio: 0.78,
            children: [
              for (final template in shown)
                GestureDetector(
                  key: ValueKey('home-template-${template.id}'),
                  onTap: () => onOpen(template),
                  child: TemplateThumb(template: template, borderRadius: 16),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _openBrowse(BuildContext context) {
    final allowedLanguages = _allowedLanguages(
      languageFilter,
      contentLanguages,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TemplatesBrowseScreen(
          onOpen: onOpen,
          initialLanguage: allowedLanguages.contains(TemplateLanguage.persian)
              ? TemplateLanguage.persian
              : TemplateLanguage.english,
          templates: _templates,
        ),
      ),
    );
  }
}

Set<TemplateLanguage> _allowedLanguages(
  HomeTemplateLanguageFilter filter,
  Set<TemplateLanguage>? settingsLanguages,
) => switch (filter) {
  HomeTemplateLanguageFilter.all =>
    settingsLanguages ?? {TemplateLanguage.english, TemplateLanguage.persian},
  HomeTemplateLanguageFilter.persian => {TemplateLanguage.persian},
  HomeTemplateLanguageFilter.english => {TemplateLanguage.english},
  HomeTemplateLanguageFilter.mixed => {
    TemplateLanguage.english,
    TemplateLanguage.persian,
  },
};
