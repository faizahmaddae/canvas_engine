import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../templates/domain/template.dart';
import '../../../templates/domain/template_catalog.dart';
import '../../../templates/presentation/templates_browse_screen.dart';
import 'category_row.dart';

/// Templates block on Home: a focused preview of the top
/// [maxCategories] categories followed by a single "Browse all
/// templates" tile.
///
/// Each category row carries its own header — there is no parent
/// "Templates" title above them, since the bottom-nav already has a
/// dedicated Templates tab and a stacked title would just repeat
/// the first row's header.
///
/// English-only for now — the Persian catalog will be re-introduced
/// once the localization phase lands.
///
/// While the catalog is still small, each category row is padded
/// with display-only repeats of the same templates (under a
/// distinct `key`) so the rows look populated. These repeats route
/// the same `onOpen` so behaviour is identical.
class TemplatesSection extends StatelessWidget {
  const TemplatesSection({
    super.key,
    required this.onOpen,
    this.language = TemplateLanguage.english,
    this.minPerRow = 6,
    this.maxCategories = 3,
  });

  static const String browseAllLabel = 'Browse all templates';

  final void Function(Template) onOpen;
  final TemplateLanguage language;

  /// Minimum number of cards per category row. Padding repeats from
  /// the category's own pool only — never borrows across categories.
  final int? minPerRow;

  /// Number of categories surfaced on Home. The full catalog stays
  /// reachable via the trailing "Browse all templates" tile and the
  /// dedicated Templates tab.
  final int maxCategories;

  @override
  Widget build(BuildContext context) {
    final pool = TemplateCatalog.byLanguage(language);
    if (pool.isEmpty) return const SizedBox.shrink();

    // Group + preserve catalog order — first appearance of each
    // category dictates the row order on Home.
    final byCategory = <TemplateCategory, List<Template>>{};
    for (final t in pool) {
      byCategory.putIfAbsent(t.category, () => <Template>[]).add(t);
    }

    final categories = byCategory.entries.take(maxCategories).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in categories) ...[
          CategoryRow(
            title: entry.key.label,
            templates: _padded(entry.value),
            onOpen: onOpen,
            onSeeAll: () => _openBrowse(context),
            // Force a uniform 1:1 thumbnail in the home preview so
            // the row rhythm doesn't break when stories (9:16) sit
            // next to squares (1:1). Real aspect ratios still
            // apply once the user lands in the editor.
            thumbnailAspectRatio: 1,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppSpacing.pageGutter,
            end: AppSpacing.pageGutter,
          ),
          child: _BrowseAllTile(onTap: () => _openBrowse(context)),
        ),
      ],
    );
  }

  List<Template> _padded(List<Template> source) {
    final min = minPerRow ?? 0;
    if (source.isEmpty || source.length >= min) return source;
    final out = <Template>[...source];
    var i = 0;
    while (out.length < min) {
      final base = source[i % source.length];
      out.add(Template(
        // Distinct id so Flutter's `ValueKey(template.id)` in the
        // row treats this as a separate widget instance.
        id: '${base.id}__pad${out.length}',
        name: base.name,
        category: base.category,
        language: base.language,
        build: base.build,
      ));
      i++;
    }
    return out;
  }

  void _openBrowse(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TemplatesBrowseScreen(
          onOpen: onOpen,
          initialLanguage: language,
        ),
      ),
    );
  }
}

/// Full-width tile that surfaces the rest of the catalog without
/// crowding the home view. Outlined, primary-tinted, with a
/// directional chevron that auto-mirrors under RTL.
class _BrowseAllTile extends StatelessWidget {
  const _BrowseAllTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = scheme.primary;

    return Semantics(
      button: true,
      label: TemplatesSection.browseAllLabel,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Ink(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(
              color: accent.withValues(alpha: 0.45),
              width: 1.5,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.card),
            onTap: onTap,
            splashColor: accent.withValues(alpha: 0.18),
            highlightColor: accent.withValues(alpha: 0.10),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AppSpacing.lg,
                end: AppSpacing.lg,
                top: AppSpacing.md,
                bottom: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(AppRadii.button),
                    ),
                    child: Icon(
                      Icons.grid_view_rounded,
                      color: accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      TemplatesSection.browseAllLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.start,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: accent,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
