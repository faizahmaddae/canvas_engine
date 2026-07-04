import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/warm_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n.dart';
import '../../home/presentation/widgets/home_style.dart';
import '../application/template_repository_provider.dart';
import '../domain/template.dart';
import 'template_preview.dart';
import 'template_presentation_order.dart';

/// Full-screen browse experience reached from the "See all" button
/// on the Home templates strip.
class TemplatesBrowseScreen extends ConsumerStatefulWidget {
  const TemplatesBrowseScreen({
    super.key,
    required this.onOpen,
    this.initialLanguage = TemplateLanguage.english,
    this.initialCategory,
    this.templates,
  });

  final void Function(Template) onOpen;

  /// Pre-selected content language. This only filters templates; it
  /// never changes the app locale.
  final TemplateLanguage initialLanguage;

  /// Optional pre-selected category. Used by Home's per-category
  /// "See all" affordance so the browse screen opens with the
  /// matching chip already active. Null preserves legacy "All"
  /// behaviour for existing callers.
  final TemplateCategory? initialCategory;

  /// Optional fixed source for tests and routes that already resolved
  /// templates. Production browse entry points normally read the
  /// repository-backed provider instead.
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
    final title = _categoryFilter == null
        ? l10n.templatesTitle
        : _browseCategoryTitle(l10n, _categoryFilter!);
    final subtitle = _categoryFilter == null
        ? l10n.templatesBrowseSubtitle
        : l10n.templatesBrowseCategorySubtitle;

    return Scaffold(
      backgroundColor: WarmPalette.of(context).backgroundBottom,
      body: HomeBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _BrowseHeader(title: title, subtitle: subtitle),
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSpacing.pageGutter,
                ),
                child: _SearchField(
                  onChanged: (query) => setState(() => _searchQuery = query),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSpacing.pageGutter,
                ),
                child: _BrowseFilterBar(
                  languageFilter: _languageFilter,
                  categoryFilter: _categoryFilter,
                  categories: categories,
                  onLanguageChanged: (filter) => setState(() {
                    _languageFilter = filter;
                  }),
                  onCategoryChanged: (category) => setState(() {
                    _categoryFilter = category;
                  }),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                child: visible.isEmpty
                    ? const _EmptyTemplatesState()
                    : _TemplatesGrid(
                        templates: visible,
                        onOpen: (template) {
                          Navigator.of(context).pop();
                          widget.onOpen(template);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrowseHeader extends StatelessWidget {
  const _BrowseHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = WarmPalette.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.pageGutter,
        AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          BackButton(
            color: palette.ink,
            style: const ButtonStyle(
              padding: WidgetStatePropertyAll(EdgeInsets.zero),
              visualDensity: VisualDensity.compact,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: palette.ink,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.muted,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrowseFilterBar extends StatelessWidget {
  const _BrowseFilterBar({
    required this.languageFilter,
    required this.categoryFilter,
    required this.categories,
    required this.onLanguageChanged,
    required this.onCategoryChanged,
  });

  final _BrowseLanguageFilter languageFilter;
  final TemplateCategory? categoryFilter;
  final List<TemplateCategory> categories;
  final ValueChanged<_BrowseLanguageFilter> onLanguageChanged;
  final ValueChanged<TemplateCategory?> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          Expanded(
            child: _CategoryChips(
              categories: categories,
              selected: categoryFilter,
              onChanged: onCategoryChanged,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _LanguageFilterButton(
            selected: languageFilter,
            onChanged: onLanguageChanged,
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final palette = WarmPalette.of(context);
    return SizedBox(
      height: 38,
      child: TextField(
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: palette.ink,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        decoration: InputDecoration(
          hintText: l10n.templatesSearchHint,
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: palette.muted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: palette.muted,
            size: 18,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 36),
          isDense: true,
          filled: true,
          fillColor: palette.surface.withValues(alpha: 0.72),
          contentPadding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            borderSide: BorderSide(
              color: palette.hairline.withValues(alpha: 0.58),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            borderSide: BorderSide(
              color: palette.accent.withValues(alpha: 0.54),
            ),
          ),
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
    final chips = <Widget>[
      _FilterPill(
        label: l10n.allFilter,
        selected: selected == null,
        onTap: () => onChanged(null),
      ),
      for (final category in categories)
        _FilterPill(
          label: _categoryChipLabel(l10n, category),
          selected: selected == category,
          onTap: () => onChanged(category),
        ),
    ];

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsetsDirectional.only(end: AppSpacing.xl),
          itemCount: chips.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (context, index) => chips[index],
        ),
        const PositionedDirectional(
          top: 0,
          end: 0,
          bottom: 0,
          child: IgnorePointer(child: _ChipTrailingFade()),
        ),
      ],
    );
  }
}

class _LanguageFilterButton extends StatelessWidget {
  const _LanguageFilterButton({
    required this.selected,
    required this.onChanged,
  });

  final _BrowseLanguageFilter selected;
  final ValueChanged<_BrowseLanguageFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final palette = WarmPalette.of(context);
    return PopupMenuButton<_BrowseLanguageFilter>(
      tooltip: l10n.templatesLanguageFilterLabel,
      position: PopupMenuPosition.under,
      color: palette.backgroundTop,
      elevation: 4,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final filter in _BrowseLanguageFilter.values)
          PopupMenuItem<_BrowseLanguageFilter>(
            value: filter,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(child: Text(_languageFilterLabel(l10n, filter))),
                if (selected == filter)
                  Icon(
                    Icons.check_rounded,
                    color: palette.accent,
                    size: 18,
                  ),
              ],
            ),
          ),
      ],
      child: Material(
        color: palette.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Container(
          height: 30,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.sm + AppSpacing.xs / 2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(
              color: palette.hairline.withValues(alpha: 0.58),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${l10n.templatesLanguageFilterLabel}: '
                '${_languageFilterLabel(l10n, selected)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: palette.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: palette.muted,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipTrailingFade extends StatelessWidget {
  const _ChipTrailingFade();

  @override
  Widget build(BuildContext context) {
    final palette = WarmPalette.of(context);
    return SizedBox(
      width: AppSpacing.xl,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.centerEnd,
            end: AlignmentDirectional.centerStart,
            colors: [
              palette.backgroundBottom.withValues(alpha: 0.94),
              palette.backgroundBottom.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = WarmPalette.of(context);
    return Material(
      color: selected
          ? palette.accent
          : palette.surface.withValues(alpha: 0.58),
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        onTap: onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.sm + AppSpacing.xs / 2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(
              color: selected
                  ? palette.accent
                  : palette.hairline.withValues(alpha: 0.52),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: selected ? Colors.white : palette.muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
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
    final rows = _browseRowsFor(
      templates.map(_MeasuredTemplate.fromTemplate).toList(growable: false),
    );

    return ListView.separated(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSpacing.pageGutter,
        AppSpacing.sm,
        AppSpacing.pageGutter,
        AppSpacing.xxl + bottomPadding,
      ),
      physics: const BouncingScrollPhysics(),
      itemCount: rows.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) =>
          _BrowseTemplateRow(row: rows[index], onOpen: onOpen),
    );
  }
}

class _BrowseTemplateRow extends StatelessWidget {
  const _BrowseTemplateRow({required this.row, required this.onOpen});

  final _BrowseRow row;
  final void Function(Template) onOpen;

  @override
  Widget build(BuildContext context) {
    if (row.layout == _BrowseTileLayout.wideLandscape) {
      final entry = row.entries.single;
      return _BrowseTile(
        entry: entry,
        layout: _BrowseTileLayout.wideLandscape,
        onTap: () => onOpen(entry.template),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var column = 0; column < _compactBrowseColumnCount; column++) ...[
          if (column > 0) const SizedBox(width: AppSpacing.md),
          Expanded(
            child: column < row.entries.length
                ? _BrowseTile(
                    entry: row.entries[column],
                    layout: _BrowseTileLayout.compact,
                    onTap: () => onOpen(row.entries[column].template),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ],
    );
  }
}

class _BrowseTile extends StatelessWidget {
  const _BrowseTile({
    required this.entry,
    required this.layout,
    required this.onTap,
  });

  final _MeasuredTemplate entry;
  final _BrowseTileLayout layout;
  final VoidCallback onTap;

  Template get template => entry.template;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final palette = WarmPalette.of(context);
    return Material(
      key: ValueKey<String>('browse-template-tile-${template.id}'),
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              key: ValueKey<String>('browse-template-preview-${template.id}'),
              aspectRatio: _previewFrameAspectRatioFor(layout),
              child: _BrowsePreviewFrame(
                template: template,
                fit: _previewFitFor(entry, layout),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              template.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.start,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.ink,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                height: 1.15,
                letterSpacing: 0,
              ),
            ),
            Text(
              '${_templateLanguageLabel(l10n, template.language)} - '
              '${_browseCategoryTitle(l10n, template.category)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.start,
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.12,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowsePreviewFrame extends StatelessWidget {
  const _BrowsePreviewFrame({required this.template, required this.fit});

  final Template template;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final palette = WarmPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: palette.hairline.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.button),
          child: SizedBox.expand(
            child: TemplatePreview(
              template: template,
              borderRadius: AppRadii.button,
              fit: fit,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyTemplatesState extends StatelessWidget {
  const _EmptyTemplatesState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final palette = WarmPalette.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.all(AppSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: palette.accentSoft,
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: Icon(
                Icons.auto_awesome_outlined,
                color: palette.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.noTemplatesFoundTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: palette.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.noTemplatesFoundSubtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.muted,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _BrowseLanguageFilter { all, persian, english, mixed }

enum _BrowseTileLayout { compact, wideLandscape }

// Landscape templates need a materially different frame from the portrait-first
// grid; 1.2 keeps square and 4:5 social posts in compact rows while promoting
// 16:9 YouTube-style artboards to a wide card.
const _landscapeTemplateAspectThreshold = 1.2;

const _compactBrowseColumnCount = 2;
const _compactPreviewFrameAspectRatio = 0.74;
const _landscapePreviewFrameAspectRatio = 16 / 9;
const _portraitFitHeightAspectThreshold = 0.72;

class _MeasuredTemplate {
  const _MeasuredTemplate({required this.template, required this.aspectRatio});

  factory _MeasuredTemplate.fromTemplate(Template template) {
    final document = template.build();
    return _MeasuredTemplate(
      template: template,
      aspectRatio: document.width / document.height,
    );
  }

  final Template template;
  final double aspectRatio;

  bool get isLandscape => aspectRatio >= _landscapeTemplateAspectThreshold;
}

class _BrowseRow {
  const _BrowseRow({required this.entries, required this.layout});

  final List<_MeasuredTemplate> entries;
  final _BrowseTileLayout layout;
}

List<_BrowseRow> _browseRowsFor(List<_MeasuredTemplate> entries) {
  final rows = <_BrowseRow>[];
  final compactEntries = <_MeasuredTemplate>[];

  void flushCompactEntries() {
    while (compactEntries.isNotEmpty) {
      final takeCount = compactEntries.length >= _compactBrowseColumnCount
          ? _compactBrowseColumnCount
          : compactEntries.length;
      rows.add(
        _BrowseRow(
          entries: List.unmodifiable(compactEntries.take(takeCount)),
          layout: _BrowseTileLayout.compact,
        ),
      );
      compactEntries.removeRange(0, takeCount);
    }
  }

  for (final entry in entries) {
    if (entry.isLandscape) {
      flushCompactEntries();
      rows.add(
        _BrowseRow(
          entries: List.unmodifiable([entry]),
          layout: _BrowseTileLayout.wideLandscape,
        ),
      );
    } else {
      compactEntries.add(entry);
    }
  }

  flushCompactEntries();
  return rows;
}

double _previewFrameAspectRatioFor(_BrowseTileLayout layout) =>
    switch (layout) {
      _BrowseTileLayout.compact => _compactPreviewFrameAspectRatio,
      _BrowseTileLayout.wideLandscape => _landscapePreviewFrameAspectRatio,
    };

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
          _categoryChipLabel(l10n, template.category),
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

BoxFit _previewFitFor(_MeasuredTemplate entry, _BrowseTileLayout layout) {
  if (layout == _BrowseTileLayout.wideLandscape) return BoxFit.cover;
  if (entry.template.thumbnailPath != null) return BoxFit.cover;
  if (entry.aspectRatio < _portraitFitHeightAspectThreshold) {
    return BoxFit.fitHeight;
  }
  return BoxFit.contain;
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
