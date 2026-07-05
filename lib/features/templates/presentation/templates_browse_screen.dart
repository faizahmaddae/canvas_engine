import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/ui/app_filter_chip.dart';
import '../../../app/ui/template_thumb.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n.dart';
import '../application/template_repository_provider.dart';
import '../domain/template.dart';
import 'template_presentation_order.dart';

/// The Templates tab — the full catalog browser (navigation doc):
/// search + category chips + language chips + a LAZY 2-column
/// [TemplateThumb] grid. Scales to any catalog size; Home only shows
/// a teaser rail.
///
/// v2 restyle of the old strip/row browse: tokens only, no
/// WarmPalette. The filter LOGIC is carried over unchanged —
/// language pool → category pool → search match, then
/// [orderTemplatesForBrowse] ordering and [orderedTemplateCategories]
/// chip ordering.
///
/// Works both as a NavShell tab (nothing to pop, no back affordance)
/// and as a pushed route (pops itself before opening a template so
/// the editor never stacks on top of the browser).
class TemplatesBrowseScreen extends ConsumerStatefulWidget {
  const TemplatesBrowseScreen({
    super.key,
    required this.onOpen,
    this.initialLanguage = TemplateLanguage.persian,
    this.initialCategory,
    this.templates,
  });

  final void Function(Template) onOpen;

  /// Pre-selected content language. This only filters templates; it
  /// never changes the app locale.
  final TemplateLanguage initialLanguage;

  /// Optional pre-selected category (per-category entry points).
  final TemplateCategory? initialCategory;

  /// Optional fixed source for tests and routes that already resolved
  /// templates. Production normally reads the repository provider.
  final List<Template>? templates;

  @override
  ConsumerState<TemplatesBrowseScreen> createState() =>
      _TemplatesBrowseScreenState();
}

class _TemplatesBrowseScreenState extends ConsumerState<TemplatesBrowseScreen> {
  late _BrowseLanguageFilter _languageFilter = _initialLanguageFilter(
    widget.initialLanguage,
  );

  /// `null` = "All".
  late TemplateCategory? _categoryFilter = widget.initialCategory;

  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = AppTokens.of(context);
    final localeLanguage = _localeLanguage(
      Localizations.localeOf(context).languageCode,
    );
    final List<Template> source =
        widget.templates ??
        ref.watch(
          effectiveTemplatesProvider(
            Localizations.localeOf(context).languageCode,
          ),
        );
    final allowedLanguages = _allowedLanguages(_languageFilter);
    final languagePool = source
        .where((template) => allowedLanguages.contains(template.language))
        .toList(growable: false);
    final categoryPool = _categoryFilter == null
        ? languagePool
        : languagePool
              .where((template) => template.category == _categoryFilter)
              .toList(growable: false);
    final visible = orderTemplatesForBrowse(
      templates: _filterBySearch(categoryPool, _searchQuery, l10n),
      preferredLanguage: _preferredBrowseLanguage(
        localeLanguage,
        _languageFilter,
      ),
      selectedCategory: _categoryFilter,
    );
    final categories = orderedTemplateCategories(
      languagePool,
      selected: _categoryFilter,
    );

    return Scaffold(
      backgroundColor: tokens.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.pageGutter,
                AppSpacing.lg,
                AppSpacing.pageGutter,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.templatesTitle,
                    style: AppTypeScale.title.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l10n.templatesBrowseSubtitle,
                    style: AppTypeScale.caption.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.pageGutter,
              ),
              child: _SearchField(
                onChanged: (query) => setState(() => _searchQuery = query),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _CategoryChips(
              categories: categories,
              selected: _categoryFilter,
              onChanged: (category) =>
                  setState(() => _categoryFilter = category),
            ),
            const SizedBox(height: AppSpacing.xs),
            _LanguageChips(
              selected: _languageFilter,
              onChanged: (filter) => setState(() => _languageFilter = filter),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: visible.isEmpty
                  ? const _EmptyTemplatesState()
                  : _TemplatesGrid(
                      templates: visible,
                      onOpen: (template) {
                        // Pushed-route entry points pop the browser
                        // first; as a tab there is nothing to pop.
                        final navigator = Navigator.of(context);
                        if (navigator.canPop()) navigator.pop();
                        widget.onOpen(template);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return TextField(
      onChanged: onChanged,
      style: AppTypeScale.body.copyWith(color: tokens.textPrimary, height: 1.4),
      decoration: InputDecoration(
        hintText: context.l10n.templatesSearchHint,
        hintStyle: AppTypeScale.body.copyWith(
          color: tokens.textMuted,
          height: 1.4,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: tokens.textMuted,
        ),
        isDense: true,
        filled: true,
        fillColor: tokens.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          borderSide: BorderSide(color: tokens.accent),
        ),
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.selected,
    required this.onChanged,
  });

  final List<TemplateCategory> categories;
  final TemplateCategory? selected;
  final ValueChanged<TemplateCategory?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.pageGutter,
        ),
        itemCount: categories.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          if (index == 0) {
            return AppFilterChip(
              key: const ValueKey('browse-category-all'),
              label: l10n.allFilter,
              selected: selected == null,
              onTap: () => onChanged(null),
            );
          }
          final category = categories[index - 1];
          return AppFilterChip(
            key: ValueKey('browse-category-${category.name}'),
            label: _categoryChipLabel(l10n, category),
            selected: selected == category,
            onTap: () => onChanged(selected == category ? null : category),
          );
        },
      ),
    );
  }
}

class _LanguageChips extends StatelessWidget {
  const _LanguageChips({required this.selected, required this.onChanged});

  final _BrowseLanguageFilter selected;
  final ValueChanged<_BrowseLanguageFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.pageGutter,
        ),
        itemCount: _BrowseLanguageFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final value = _BrowseLanguageFilter.values[index];
          return AppFilterChip(
            key: ValueKey('browse-language-${value.name}'),
            label: _languageFilterLabel(l10n, value),
            selected: selected == value,
            onTap: () => onChanged(value),
          );
        },
      ),
    );
  }
}

class _TemplatesGrid extends StatelessWidget {
  const _TemplatesGrid({required this.templates, required this.onOpen});

  final List<Template> templates;
  final void Function(Template) onOpen;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    // Lazy builder grid: cells build on demand, so the browser
    // scales to any catalog size (navigation doc).
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSpacing.pageGutter,
        AppSpacing.xs,
        AppSpacing.pageGutter,
        AppSpacing.xxl + bottomPadding,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
        childAspectRatio: 0.78,
      ),
      itemCount: templates.length,
      itemBuilder: (context, index) {
        final template = templates[index];
        return GestureDetector(
          key: ValueKey('browse-template-tile-${template.id}'),
          onTap: () => onOpen(template),
          child: TemplateThumb(template: template, borderRadius: 16),
        );
      },
    );
  }
}

class _EmptyTemplatesState extends StatelessWidget {
  const _EmptyTemplatesState();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = AppTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 32, color: tokens.textMuted),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.noTemplatesFoundTitle,
              textAlign: TextAlign.center,
              style: AppTypeScale.body.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.noTemplatesFoundSubtitle,
              textAlign: TextAlign.center,
              style: AppTypeScale.caption.copyWith(color: tokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── filter logic (unchanged from the strip-era browser) ──────────

enum _BrowseLanguageFilter { all, persian, english, mixed }

_BrowseLanguageFilter _initialLanguageFilter(TemplateLanguage language) =>
    switch (language) {
      TemplateLanguage.english => _BrowseLanguageFilter.english,
      TemplateLanguage.persian => _BrowseLanguageFilter.persian,
    };

Set<TemplateLanguage> _allowedLanguages(_BrowseLanguageFilter filter) =>
    switch (filter) {
      _BrowseLanguageFilter.all => TemplateLanguage.values.toSet(),
      _BrowseLanguageFilter.persian => {TemplateLanguage.persian},
      _BrowseLanguageFilter.english => {TemplateLanguage.english},
      _BrowseLanguageFilter.mixed => {
        TemplateLanguage.english,
        TemplateLanguage.persian,
      },
    };

List<Template> _filterBySearch(
  List<Template> templates,
  String query,
  AppLocalizations l10n,
) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return templates;
  return templates
      .where((template) {
        final searchableText = [
          template.name,
          _browseCategoryTitle(l10n, template.category),
          _templateLanguageLabel(l10n, template.language),
          _templateSearchKeywords(template),
        ].join(' ').toLowerCase();
        return searchableText.contains(normalizedQuery);
      })
      .toList(growable: false);
}

String _languageFilterLabel(
  AppLocalizations l10n,
  _BrowseLanguageFilter filter,
) => switch (filter) {
  _BrowseLanguageFilter.all => l10n.homeTemplateLanguageAll,
  _BrowseLanguageFilter.persian => l10n.homeTemplateLanguagePersian,
  _BrowseLanguageFilter.english => l10n.homeTemplateLanguageEnglish,
  _BrowseLanguageFilter.mixed => l10n.homeTemplateLanguageMixed,
};

String _templateLanguageLabel(
  AppLocalizations l10n,
  TemplateLanguage language,
) => switch (language) {
  TemplateLanguage.english => l10n.templateLanguageEnglish,
  TemplateLanguage.persian => l10n.templateLanguagePersian,
};

String _categoryChipLabel(AppLocalizations l10n, TemplateCategory category) =>
    switch (category) {
      TemplateCategory.instagramStory ||
      TemplateCategory.story => l10n.templatesCategoryChipStories,
      TemplateCategory.social => l10n.categorySocial,
      TemplateCategory.promotionalPoster => l10n.templatesCategoryChipAds,
      TemplateCategory.sale => l10n.categorySale,
      TemplateCategory.business => l10n.categoryBusiness,
      TemplateCategory.food => l10n.categoryFood,
      TemplateCategory.event => l10n.categoryEvent,
      TemplateCategory.youtubeThumbnail => l10n.templatesCategoryChipThumbnails,
      TemplateCategory.poetryPost => l10n.templatesCategoryChipQuotes,
      TemplateCategory.quote => l10n.templatesCategoryChipText,
      _ => _browseCategoryTitle(l10n, category),
    };

TemplateLanguage _localeLanguage(String localeCode) {
  return localeCode.toLowerCase().startsWith('fa')
      ? TemplateLanguage.persian
      : TemplateLanguage.english;
}

TemplateLanguage? _preferredBrowseLanguage(
  TemplateLanguage localeLanguage,
  _BrowseLanguageFilter filter,
) {
  return switch (filter) {
    _BrowseLanguageFilter.all || _BrowseLanguageFilter.mixed => localeLanguage,
    _BrowseLanguageFilter.persian => TemplateLanguage.persian,
    _BrowseLanguageFilter.english => TemplateLanguage.english,
  };
}

String _templateSearchKeywords(Template template) {
  final idWords = template.id.replaceAll('_', ' ');
  final keywords = <String>[idWords];
  if (template.id.contains('_edu_') ||
      template.id.contains('course') ||
      template.id.contains('webinar') ||
      template.id.contains('workshop')) {
    keywords.add('education course class learning workshop webinar tutorial');
  }
  if (template.category == TemplateCategory.food ||
      template.id.contains('cafe') ||
      template.id.contains('restaurant')) {
    keywords.add('food menu cafe restaurant coffee');
  }
  if (template.category == TemplateCategory.business ||
      template.id.contains('hiring') ||
      template.id.contains('service')) {
    keywords.add('business service hiring agency announcement');
  }
  if (template.category == TemplateCategory.sale ||
      template.category == TemplateCategory.promotionalPoster) {
    keywords.add('sale promo offer campaign ad advertising');
  }
  if (template.category == TemplateCategory.poetryPost ||
      template.category == TemplateCategory.quote) {
    keywords.add('quote poetry text typography literary');
  }
  return keywords.join(' ');
}

String _browseCategoryTitle(AppLocalizations l10n, TemplateCategory category) =>
    switch (category) {
      TemplateCategory.instagramStory => l10n.homeTemplatesInstagramStories,
      TemplateCategory.youtubeThumbnail => l10n.homeTemplatesYoutubeThumbnails,
      TemplateCategory.poetryPost => l10n.homeTemplatesQuotesPoems,
      TemplateCategory.promotionalPoster => l10n.homeTemplatesAdvertisingPosts,
      TemplateCategory.quote => l10n.homeTemplatesTextTypography,
      TemplateCategory.social => l10n.categorySocial,
      TemplateCategory.story => l10n.categoryStory,
      TemplateCategory.sale => l10n.categorySale,
      TemplateCategory.greeting => l10n.categoryGreeting,
      TemplateCategory.business => l10n.categoryBusiness,
      TemplateCategory.event => l10n.categoryEvent,
      TemplateCategory.food => l10n.categoryFood,
      TemplateCategory.motivational => l10n.categoryMotivational,
    };
