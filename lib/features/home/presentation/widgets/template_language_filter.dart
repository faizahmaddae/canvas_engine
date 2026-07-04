import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/warm_palette.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import 'templates_section.dart';

/// Home-only template recommendation filter.
///
/// This state is intentionally local to Home. It changes the current
/// recommendation feed only; it does not mutate the app locale or the
/// user's persisted content-language settings.
class TemplateLanguageFilter extends StatelessWidget {
  const TemplateLanguageFilter({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final HomeTemplateLanguageFilter selected;
  final ValueChanged<HomeTemplateLanguageFilter> onChanged;

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
        itemCount: HomeTemplateLanguageFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final value = HomeTemplateLanguageFilter.values[index];
          return _FilterPill(
            label: _labelFor(l10n, value),
            selected: selected == value,
            onTap: () => onChanged(value),
          );
        },
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
          ? palette.ink
          : palette.surface.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Container(
          height: 34,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(
              color: selected
                  ? palette.ink
                  : palette.hairline.withValues(alpha: 0.72),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: selected ? Colors.white : palette.muted,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

String _labelFor(AppLocalizations l10n, HomeTemplateLanguageFilter filter) =>
    switch (filter) {
      HomeTemplateLanguageFilter.all => l10n.homeTemplateLanguageAll,
      HomeTemplateLanguageFilter.persian => l10n.homeTemplateLanguagePersian,
      HomeTemplateLanguageFilter.english => l10n.homeTemplateLanguageEnglish,
      HomeTemplateLanguageFilter.mixed => l10n.homeTemplateLanguageMixed,
    };
