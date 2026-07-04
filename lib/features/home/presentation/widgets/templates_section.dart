import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/warm_palette.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import '../../../templates/domain/template.dart';
import '../../../templates/presentation/template_presentation_order.dart';
import '../../../templates/presentation/templates_browse_screen.dart';
import 'category_row.dart';

enum HomeTemplateLanguageFilter { all, persian, english, mixed }

/// Templates block on Home: curated, product-facing strips instead
/// of a raw catalog dump. The language filter is local to Home and
/// never changes the app locale.
class TemplatesSection extends StatelessWidget {
  const TemplatesSection({
    super.key,
    required this.onOpen,
    this.language,
    required List<Template> templates,
    this.contentLanguages,
    this.enabledCategories,
    this.languageFilter = HomeTemplateLanguageFilter.all,
    this.filter,
    this.onSeeAllCategory,
  }) : _templates = templates;

  static const List<_HomeTemplateSectionSpec> _sections = [
    _HomeTemplateSectionSpec(
      kind: _HomeTemplateSectionKind.recommended,
      categories: {
        TemplateCategory.instagramStory,
        TemplateCategory.story,
        TemplateCategory.social,
        TemplateCategory.business,
        TemplateCategory.food,
        TemplateCategory.event,
        TemplateCategory.sale,
        TemplateCategory.youtubeThumbnail,
        TemplateCategory.poetryPost,
        TemplateCategory.promotionalPoster,
        TemplateCategory.quote,
      },
      height: 172,
      aspectRatio: 4 / 5,
      categoryPriority: [
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
      ],
      preferredIds: kHomeRecommendedTemplateIds,
    ),
    _HomeTemplateSectionSpec(
      kind: _HomeTemplateSectionKind.instagramStories,
      categories: {TemplateCategory.instagramStory},
      category: TemplateCategory.instagramStory,
      height: 168,
      aspectRatio: 9 / 16,
      preferredIds: kHomeStoryTemplateIds,
    ),
    _HomeTemplateSectionSpec(
      kind: _HomeTemplateSectionKind.textTypography,
      categories: {TemplateCategory.quote},
      category: TemplateCategory.quote,
      height: 138,
      aspectRatio: 1,
      preferredIds: kHomeTextTemplateIds,
    ),
    _HomeTemplateSectionSpec(
      kind: _HomeTemplateSectionKind.advertisingPosts,
      categories: {TemplateCategory.promotionalPoster, TemplateCategory.sale},
      category: TemplateCategory.promotionalPoster,
      height: 164,
      aspectRatio: 4 / 5,
      preferredIds: kHomeAdvertisingTemplateIds,
    ),
    _HomeTemplateSectionSpec(
      kind: _HomeTemplateSectionKind.youtubeThumbnails,
      categories: {TemplateCategory.youtubeThumbnail},
      category: TemplateCategory.youtubeThumbnail,
      height: 110,
      aspectRatio: 16 / 9,
      preferredIds: kHomeYoutubeTemplateIds,
    ),
    _HomeTemplateSectionSpec(
      kind: _HomeTemplateSectionKind.quotesPoems,
      categories: {TemplateCategory.poetryPost},
      category: TemplateCategory.poetryPost,
      height: 138,
      aspectRatio: 1,
      preferredIds: kHomePoetryTemplateIds,
    ),
  ];

  final void Function(Template) onOpen;

  /// Kept for older callers/tests that still pass a language, but Home
  /// now shows every template in a focused category regardless of the
  /// UI locale or template content language.
  final TemplateLanguage? language;

  final Set<TemplateLanguage>? contentLanguages;

  final HomeTemplateLanguageFilter languageFilter;

  /// Optional compact control rendered directly under the Templates
  /// title. Home passes the local language filter here so the filter
  /// reads as part of recommendations instead of a separate section.
  final Widget? filter;

  final Set<TemplateCategory>? enabledCategories;

  /// Repository-backed source supplied by Home; tests inject a small
  /// catalog here so the row/filter logic stays deterministic.
  final List<Template> _templates;

  /// Optional observer used by widget tests to verify the category
  /// that will pre-filter the browse screen. Production leaves this
  /// null and still navigates normally.
  final void Function(TemplateCategory category)? onSeeAllCategory;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final source = _templates;
    final allowedLanguages = _allowedLanguages(
      languageFilter,
      contentLanguages,
    );
    final allowedCategories = enabledCategories;
    final rows = <_HomeTemplateSectionRow>[];
    for (final spec in _sections) {
      final categories = spec.categories.where(
        (category) =>
            allowedCategories == null || allowedCategories.contains(category),
      );
      if (categories.isEmpty) continue;

      final templates = _templatesFor(
        source: source,
        spec: spec,
        categories: categories.toSet(),
        allowedLanguages: allowedLanguages,
      );
      if (templates.isEmpty) continue;
      rows.add(_HomeTemplateSectionRow(spec: spec, templates: templates));
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppSpacing.pageGutter,
            end: AppSpacing.pageGutter,
          ),
          child: Text(
            l10n.templatesTitle,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: WarmPalette.of(context).ink,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (filter != null) ...[const SizedBox(height: AppSpacing.sm), filter!],
        const SizedBox(height: AppSpacing.md),
        for (var index = 0; index < rows.length; index++) ...[
          Builder(
            builder: (context) {
              final row = rows[index];
              final width = row.spec.height * row.spec.aspectRatio;
              return CategoryRow(
                title: _labelFor(l10n, row.spec.kind),
                templates: row.templates,
                onOpen: onOpen,
                onSeeAll: () => _openBrowse(
                  context,
                  row.spec.category ?? row.templates.first.category,
                  row.templates.first.language,
                ),
                actionLabel: l10n.seeAllAction,
                cardHeight: row.spec.height,
                thumbnailAspectRatio: row.spec.aspectRatio,
                cardMinWidth: width,
                cardMaxWidth: width,
              );
            },
          ),
          if (index != rows.length - 1) const SizedBox(height: AppSpacing.xxl),
        ],
      ],
    );
  }

  String _labelFor(AppLocalizations l10n, _HomeTemplateSectionKind kind) =>
      switch (kind) {
        _HomeTemplateSectionKind.recommended => l10n.homeTemplatesRecommended,
        _HomeTemplateSectionKind.instagramStories =>
          l10n.homeTemplatesInstagramStories,
        _HomeTemplateSectionKind.textTypography =>
          l10n.homeTemplatesTextTypography,
        _HomeTemplateSectionKind.advertisingPosts =>
          l10n.homeTemplatesAdvertisingPosts,
        _HomeTemplateSectionKind.youtubeThumbnails =>
          l10n.homeTemplatesYoutubeThumbnails,
        _HomeTemplateSectionKind.quotesPoems => l10n.homeTemplatesQuotesPoems,
      };

  void _openBrowse(
    BuildContext context,
    TemplateCategory category,
    TemplateLanguage browseLanguage,
  ) {
    onSeeAllCategory?.call(category);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TemplatesBrowseScreen(
          onOpen: onOpen,
          initialLanguage: browseLanguage,
          initialCategory: category,
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

List<Template> _templatesFor({
  required List<Template> source,
  required _HomeTemplateSectionSpec spec,
  required Set<TemplateCategory> categories,
  required Set<TemplateLanguage> allowedLanguages,
}) {
  final pool = source
      .where((t) => categories.contains(t.category))
      .where((t) => allowedLanguages.contains(t.language))
      .toList(growable: false);
  return orderTemplatesForHome(
    templates: pool,
    preferredIds: spec.preferredIds,
    categoryPriority: spec.categoryPriority,
  );
}

enum _HomeTemplateSectionKind {
  recommended,
  instagramStories,
  textTypography,
  advertisingPosts,
  youtubeThumbnails,
  quotesPoems,
}

class _HomeTemplateSectionSpec {
  const _HomeTemplateSectionSpec({
    required this.kind,
    required this.categories,
    required this.height,
    required this.aspectRatio,
    this.category,
    this.preferredIds = const [],
    this.categoryPriority = const [],
  });

  final _HomeTemplateSectionKind kind;
  final Set<TemplateCategory> categories;
  final TemplateCategory? category;
  final double height;
  final double aspectRatio;
  final List<String> preferredIds;
  final List<TemplateCategory> categoryPriority;
}

class _HomeTemplateSectionRow {
  const _HomeTemplateSectionRow({required this.spec, required this.templates});

  final _HomeTemplateSectionSpec spec;
  final List<Template> templates;
}
