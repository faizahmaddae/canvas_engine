import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/ui/app_filter_chip.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import 'templates_section.dart';

/// Home-only template recommendation filter (همه / فارسی / انگلیسی /
/// ترکیبی), restyled onto [AppFilterChip] (v2: selected = ink-filled
/// cream text, unselected = paper + hairline).
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
          return AppFilterChip(
            key: ValueKey('home-template-filter-${value.name}'),
            label: _labelFor(l10n, value),
            selected: selected == value,
            onTap: () => onChanged(value),
          );
        },
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
