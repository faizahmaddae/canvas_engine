import 'package:flutter/material.dart';

import '../domain/template.dart';
import '../domain/template_catalog.dart';
import 'template_preview.dart';

/// Full-screen browse experience reached from the "See all" button
/// on the Home templates strip.
///
/// Layout:
/// 1. Top tab bar — switches the language section (English / Persian).
/// 2. Category filter chips — refines within the active language.
/// 3. 2-column grid of templates honouring each design's native
///    aspect ratio.
///
/// Splitting by language at the highest level matches how users
/// shop for designs — they almost always know up front which script
/// they want to publish in, and mixing both into a single feed
/// cuts the perceived catalog in half for either audience.
class TemplatesBrowseScreen extends StatefulWidget {
  const TemplatesBrowseScreen({
    super.key,
    required this.onOpen,
    this.initialLanguage = TemplateLanguage.english,
  });

  final void Function(Template) onOpen;

  /// Pre-selected language tab. Lets callers (e.g. the Home strip's
  /// "See all") carry the user's current language choice into the
  /// full browse experience instead of resetting to English.
  final TemplateLanguage initialLanguage;

  @override
  State<TemplatesBrowseScreen> createState() => _TemplatesBrowseScreenState();
}

class _TemplatesBrowseScreenState extends State<TemplatesBrowseScreen> {
  late TemplateLanguage _language = widget.initialLanguage;

  /// `null` = "All".
  TemplateCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pool = TemplateCatalog.byLanguage(_language);
    final visible = _filter == null
        ? pool
        : pool.where((t) => t.category == _filter).toList(growable: false);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Templates'),
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _LanguageTabs(
              selected: _language,
              onChanged: (l) => setState(() {
                _language = l;
                // Reset category when switching language so the user
                // doesn't land on an empty grid if the new language
                // happens to lack the previously-selected category.
                _filter = null;
              }),
            ),
            _CategoryChips(
              language: _language,
              selected: _filter,
              onChanged: (c) => setState(() => _filter = c),
            ),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        'No templates in this category yet.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      physics: const BouncingScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.7,
                      ),
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final t = visible[i];
                        return _BrowseTile(
                          template: t,
                          onTap: () {
                            // Pop the browse screen first so the
                            // editor pushes onto Home, not onto
                            // browse. Keeps the back stack clean.
                            Navigator.of(context).pop();
                            widget.onOpen(t);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageTabs extends StatelessWidget {
  const _LanguageTabs({required this.selected, required this.onChanged});

  final TemplateLanguage selected;
  final ValueChanged<TemplateLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            for (final lang in TemplateLanguage.values)
              Expanded(
                child: _LanguagePill(
                  label: lang.label,
                  selected: selected == lang,
                  onTap: () => onChanged(lang),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LanguagePill extends StatelessWidget {
  const _LanguagePill({
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
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: selected ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected ? scheme.onPrimary : scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.language,
    required this.selected,
    required this.onChanged,
  });

  final TemplateLanguage language;
  final TemplateCategory? selected;
  final ValueChanged<TemplateCategory?> onChanged;

  @override
  Widget build(BuildContext context) {
    // Only surface chips for categories that actually have at least
    // one template in the active language — keeps the chip strip
    // honest as the catalog grows unevenly.
    final pool = TemplateCatalog.byLanguage(language);
    final present = <TemplateCategory>{for (final t in pool) t.category};
    final categories = TemplateCategory.values
        .where(present.contains)
        .toList(growable: false);
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _Chip(
            label: 'All',
            selected: selected == null,
            onTap: () => onChanged(null),
          ),
          for (final c in categories) ...[
            const SizedBox(width: 8),
            _Chip(
              label: c.label,
              selected: selected == c,
              onTap: () => onChanged(c),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: scheme.primary,
      labelStyle: TextStyle(
        color: selected ? scheme.onPrimary : scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(
        color: selected
            ? scheme.primary
            : scheme.outlineVariant.withValues(alpha: 0.6),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _BrowseTile extends StatelessWidget {
  const _BrowseTile({required this.template, required this.onTap});

  final Template template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                  color: scheme.surfaceContainer,
                ),
                clipBehavior: Clip.antiAlias,
                child: TemplatePreview(template: template),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              template.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
            Text(
              template.category.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
