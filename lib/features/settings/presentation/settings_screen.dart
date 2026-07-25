import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n.dart';
import '../../editor/application/export_quality.dart';
import '../../onboarding/application/onboarding_complete_provider.dart';
import '../../templates/domain/template.dart';
import '../application/settings_controller.dart';
import '../../../app/theme/app_icons.dart';

/// User-facing preferences screen.
///
/// Layout follows native Material 3 settings conventions: grouped
/// sections, switch tiles for toggles, and a dialog for the radio
/// selection of export quality (mirrors the user's preference for
/// dialog-based pickers over inline chips).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader(l10n.appearanceSection),
          _NavTile(
            icon: AppIcons.themeMode,
            title: l10n.themeTitle,
            subtitle: _themeModeLabel(l10n, settings.themeMode),
            onTap: () => _openThemePicker(context, ref, settings),
          ),
          _NavTile(
            icon: AppIcons.appLanguage,
            title: l10n.languageTitle,
            subtitle: _localePreferenceLabel(l10n, settings.localePreference),
            onTap: () => _openLanguagePicker(context, ref, settings),
          ),
          _NavTile(
            icon: AppIcons.contentLanguages,
            title: l10n.settingsContentLanguagesTitle,
            subtitle: _contentLanguagesLabel(l10n, settings.contentLanguages),
            onTap: () => _openContentLanguagesPicker(context, ref, settings),
          ),
          _NavTile(
            icon: AppIcons.enabledCategories,
            title: l10n.settingsEnabledCategoriesTitle,
            subtitle: _enabledCategoriesLabel(l10n, settings.enabledCategories),
            onTap: () => _openEnabledCategoriesPicker(context, ref, settings),
          ),
          const SizedBox(height: 8),
          _SectionHeader(l10n.canvasInteractionSection),
          _SwitchTile(
            icon: AppIcons.canvasPan,
            title: l10n.enableCanvasPanTitle,
            subtitle: l10n.enableCanvasPanSubtitle,
            value: settings.canvasPanEnabled,
            onChanged: controller.setCanvasPanEnabled,
          ),
          _SwitchTile(
            icon: AppIcons.zoom,
            title: l10n.enableCanvasZoomTitle,
            subtitle: l10n.enableCanvasZoomSubtitle,
            value: settings.canvasZoomEnabled,
            onChanged: controller.setCanvasZoomEnabled,
          ),
          _SwitchTile(
            icon: AppIcons.canvasRotation,
            title: l10n.enableCanvasRotationTitle,
            subtitle: l10n.enableCanvasRotationSubtitle,
            value: settings.canvasRotationEnabled,
            onChanged: controller.setCanvasRotationEnabled,
          ),
          const SizedBox(height: 8),
          _SectionHeader(l10n.exportSection),
          _NavTile(
            icon: AppIcons.exportQuality,
            title: l10n.defaultExportQualityTitle,
            subtitle:
                '${_exportQualityLabel(l10n, settings.defaultExportQuality)} '
                '· ${settings.defaultExportQuality.multiplier}',
            onTap: () => _openQualityPicker(context, ref, settings),
          ),
          const SizedBox(height: 8),
          _SectionHeader(l10n.editorSection),
          _SwitchTile(
            icon: AppIcons.snapToGuides,
            title: l10n.snapToGuidesTitle,
            subtitle: l10n.snapToGuidesSubtitle,
            value: settings.snapToGuides,
            onChanged: controller.setSnapToGuides,
          ),
          _SwitchTile(
            icon: AppIcons.distributeHorizontal,
            title: l10n.showSpacingGuidesTitle,
            subtitle: l10n.showSpacingGuidesSubtitle,
            value: settings.showSpacingGuides,
            onChanged: controller.setShowSpacingGuides,
          ),
          _SwitchTile(
            icon: AppIcons.touchGesture,
            title: l10n.multiFingerUndoRedoTitle,
            subtitle: l10n.multiFingerUndoRedoSubtitle,
            value: settings.multiFingerUndoRedoEnabled,
            onChanged: controller.setMultiFingerUndoRedoEnabled,
          ),
          _SwitchTile(
            icon: AppIcons.rightHandedToolbar,
            title: l10n.rightHandedToolbarTitle,
            subtitle: l10n.rightHandedToolbarSubtitle,
            value: settings.rightHandedToolbar,
            onChanged: controller.setRightHandedToolbar,
          ),
          const SizedBox(height: 24),
          Center(
            child: TextButton(
              onPressed: () =>
                  ref.read(onboardingCompleteProvider.notifier).reset(),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                textStyle: Theme.of(context).textTheme.labelSmall,
              ),
              child: Text(l10n.settingsResetOnboarding),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Future<void> _openThemePicker(
    BuildContext context,
    WidgetRef ref,
    AppSettings current,
  ) async {
    final picked = await showDialog<ThemeMode>(
      context: context,
      builder: (_) => _ThemePickerDialog(initial: current.themeMode),
    );
    if (picked == null) return;
    await ref.read(settingsControllerProvider.notifier).setThemeMode(picked);
  }

  Future<void> _openLanguagePicker(
    BuildContext context,
    WidgetRef ref,
    AppSettings current,
  ) async {
    final picked = await showDialog<LocalePreference>(
      context: context,
      builder: (_) => _LanguagePickerDialog(initial: current.localePreference),
    );
    if (picked == null) return;
    await ref
        .read(settingsControllerProvider.notifier)
        .setLocalePreference(picked);
  }

  Future<void> _openContentLanguagesPicker(
    BuildContext context,
    WidgetRef ref,
    AppSettings current,
  ) async {
    final picked = await showDialog<Set<TemplateLanguage>>(
      context: context,
      builder: (_) =>
          _ContentLanguagesDialog(initial: current.contentLanguages),
    );
    if (picked == null) return;
    await ref
        .read(settingsControllerProvider.notifier)
        .setContentLanguages(picked);
  }

  Future<void> _openEnabledCategoriesPicker(
    BuildContext context,
    WidgetRef ref,
    AppSettings current,
  ) async {
    final picked = await showDialog<Set<TemplateCategory>>(
      context: context,
      builder: (_) =>
          _EnabledCategoriesDialog(initial: current.enabledCategories),
    );
    if (picked == null) return;
    await ref
        .read(settingsControllerProvider.notifier)
        .setEnabledCategories(picked);
  }

  Future<void> _openQualityPicker(
    BuildContext context,
    WidgetRef ref,
    AppSettings current,
  ) async {
    final picked = await showDialog<ExportQuality>(
      context: context,
      builder: (_) =>
          _QualityPickerDialog(initial: current.defaultExportQuality),
    );
    if (picked == null) return;
    await ref
        .read(settingsControllerProvider.notifier)
        .setDefaultExportQuality(picked);
  }
}

String _themeModeLabel(AppLocalizations l10n, ThemeMode mode) => switch (mode) {
  ThemeMode.system => l10n.themeSystem,
  ThemeMode.light => l10n.themeLight,
  ThemeMode.dark => l10n.themeDark,
};

String _localePreferenceLabel(
  AppLocalizations l10n,
  LocalePreference preference,
) => switch (preference) {
  LocalePreference.system => l10n.languageSystem,
  LocalePreference.english => l10n.languageEnglish,
  LocalePreference.persian => l10n.languagePersian,
};

String _contentLanguagesLabel(
  AppLocalizations l10n,
  Set<TemplateLanguage> languages,
) {
  final selected = languages.isEmpty ? kDefaultContentLanguages : languages;
  return [
    if (selected.contains(TemplateLanguage.english)) l10n.languageEnglish,
    if (selected.contains(TemplateLanguage.persian)) l10n.languagePersian,
  ].join(' · ');
}

String _enabledCategoriesLabel(
  AppLocalizations l10n,
  Set<TemplateCategory> categories,
) {
  final selected = categories.isEmpty
      ? kDefaultEnabledTemplateCategories
      : categories;
  return [
    for (final category in kHomeTemplateGoalCategories)
      if (selected.contains(category)) _categoryLabel(l10n, category),
  ].join(' · ');
}

String _categoryLabel(AppLocalizations l10n, TemplateCategory category) =>
    switch (category) {
      TemplateCategory.instagramStory => l10n.onboardingGoalInstagram,
      TemplateCategory.youtubeThumbnail => l10n.onboardingGoalYoutube,
      TemplateCategory.poetryPost => l10n.onboardingGoalPoetry,
      TemplateCategory.promotionalPoster => l10n.onboardingGoalPoster,
      _ => l10n.categorySocial,
    };

IconData _categoryIcon(TemplateCategory category) => switch (category) {
  TemplateCategory.instagramStory => AppIcons.categoryInstagramStory,
  TemplateCategory.youtubeThumbnail => AppIcons.categoryYoutubeThumbnail,
  TemplateCategory.poetryPost => AppIcons.categoryPoetryPost,
  TemplateCategory.promotionalPoster => AppIcons.categoryPoster,
  _ => AppIcons.stylePresets,
};

String _exportQualityLabel(AppLocalizations l10n, ExportQuality quality) =>
    switch (quality) {
      ExportQuality.original => l10n.exportQualityOriginal,
      ExportQuality.high => l10n.exportQualityHigh,
      ExportQuality.ultra => l10n.exportQualityUltra,
    };

class _ThemePickerDialog extends StatefulWidget {
  const _ThemePickerDialog({required this.initial});
  final ThemeMode initial;

  @override
  State<_ThemePickerDialog> createState() => _ThemePickerDialogState();
}

class _ThemePickerDialogState extends State<_ThemePickerDialog> {
  late ThemeMode _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      // Scroll instead of overflowing when the tile/radio list is
      // taller than the dialog's max height (landscape / short screens).
      scrollable: true,
      title: Text(l10n.themeTitle),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: RadioGroup<ThemeMode>(
        groupValue: _selected,
        onChanged: (v) {
          if (v != null) setState(() => _selected = v);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in ThemeMode.values)
              RadioListTile<ThemeMode>(
                value: mode,
                title: Text(_themeModeLabel(l10n, mode)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: Text(l10n.saveAction),
        ),
      ],
    );
  }
}

class _LanguagePickerDialog extends StatefulWidget {
  const _LanguagePickerDialog({required this.initial});
  final LocalePreference initial;

  @override
  State<_LanguagePickerDialog> createState() => _LanguagePickerDialogState();
}

class _LanguagePickerDialogState extends State<_LanguagePickerDialog> {
  late LocalePreference _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      // Scroll instead of overflowing when the tile/radio list is
      // taller than the dialog's max height (landscape / short screens).
      scrollable: true,
      title: Text(l10n.languageTitle),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: RadioGroup<LocalePreference>(
        groupValue: _selected,
        onChanged: (v) {
          if (v != null) setState(() => _selected = v);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final preference in LocalePreference.values)
              RadioListTile<LocalePreference>(
                value: preference,
                title: Text(_localePreferenceLabel(l10n, preference)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: Text(l10n.saveAction),
        ),
      ],
    );
  }
}

class _ContentLanguagesDialog extends StatefulWidget {
  const _ContentLanguagesDialog({required this.initial});
  final Set<TemplateLanguage> initial;

  @override
  State<_ContentLanguagesDialog> createState() =>
      _ContentLanguagesDialogState();
}

class _ContentLanguagesDialogState extends State<_ContentLanguagesDialog> {
  late final Set<TemplateLanguage> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      // Scroll instead of overflowing when the tile/radio list is
      // taller than the dialog's max height (landscape / short screens).
      scrollable: true,
      title: Text(l10n.settingsContentLanguagesTitle),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final language in TemplateLanguage.values)
            CheckboxListTile(
              value: _selected.contains(language),
              title: Text(
                language == TemplateLanguage.english
                    ? l10n.languageEnglish
                    : l10n.languagePersian,
              ),
              onChanged: (_) => setState(() {
                if (!_selected.add(language)) _selected.remove(language);
              }),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, Set.unmodifiable(_selected)),
          child: Text(l10n.saveAction),
        ),
      ],
    );
  }
}

class _EnabledCategoriesDialog extends StatefulWidget {
  const _EnabledCategoriesDialog({required this.initial});
  final Set<TemplateCategory> initial;

  @override
  State<_EnabledCategoriesDialog> createState() =>
      _EnabledCategoriesDialogState();
}

class _EnabledCategoriesDialogState extends State<_EnabledCategoriesDialog> {
  late final Set<TemplateCategory> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      // Scroll instead of overflowing when the tile/radio list is
      // taller than the dialog's max height (landscape / short screens).
      scrollable: true,
      title: Text(l10n.settingsEnabledCategoriesTitle),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final category in kHomeTemplateGoalCategories)
            CheckboxListTile(
              value: _selected.contains(category),
              secondary: Icon(_categoryIcon(category)),
              title: Text(_categoryLabel(l10n, category)),
              onChanged: (_) => setState(() {
                if (!_selected.add(category)) _selected.remove(category);
              }),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, Set.unmodifiable(_selected)),
          child: Text(l10n.saveAction),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      secondary: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(AppIcons.drillIn),
      onTap: onTap,
    );
  }
}

class _QualityPickerDialog extends StatefulWidget {
  const _QualityPickerDialog({required this.initial});
  final ExportQuality initial;

  @override
  State<_QualityPickerDialog> createState() => _QualityPickerDialogState();
}

class _QualityPickerDialogState extends State<_QualityPickerDialog> {
  late ExportQuality _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return AlertDialog(
      // Scroll instead of overflowing when the tile/radio list is
      // taller than the dialog's max height (landscape / short screens).
      scrollable: true,
      title: Text(l10n.defaultExportQualityTitle),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioGroup<ExportQuality>(
            groupValue: _selected,
            onChanged: (v) {
              if (v != null) setState(() => _selected = v);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final q in ExportQuality.values)
                  RadioListTile<ExportQuality>(
                    value: q,
                    title: Text(_exportQualityLabel(l10n, q)),
                    secondary: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        q.multiplier,
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: Text(l10n.saveAction),
        ),
      ],
    );
  }
}
