import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../editor/application/export_quality.dart';
import '../../templates/domain/template.dart';

const Set<TemplateLanguage> kDefaultContentLanguages = {
  TemplateLanguage.english,
  TemplateLanguage.persian,
};

// Every category a goal card can persist MUST be listed here: this
// list drives the Settings picker, and a category missing from it is
// an invisible preference the user can neither see nor remove
// (ux-audit P2-18 — the quote/social goals used to persist exactly
// that way).
const List<TemplateCategory> kHomeTemplateGoalCategories = [
  TemplateCategory.instagramStory,
  TemplateCategory.youtubeThumbnail,
  TemplateCategory.poetryPost,
  TemplateCategory.promotionalPoster,
  TemplateCategory.quote,
  TemplateCategory.social,
];

const Set<TemplateCategory> kDefaultEnabledTemplateCategories = {
  TemplateCategory.instagramStory,
  TemplateCategory.youtubeThumbnail,
  TemplateCategory.poetryPost,
  TemplateCategory.promotionalPoster,
};

enum LocalePreference {
  system,
  english,
  persian;

  Locale? get appLocale => switch (this) {
    LocalePreference.system => null,
    LocalePreference.english => const Locale('en'),
    LocalePreference.persian => const Locale('fa'),
  };
}

/// Plain-data snapshot of every user-tunable preference in the app.
///
/// Lives outside any widget so it can be hashed for equality, serialised
/// to JSON, and watched reactively by both Home and Editor surfaces.
class AppSettings {
  const AppSettings({
    this.canvasPanEnabled = true,
    this.canvasZoomEnabled = true,
    this.canvasRotationEnabled = true,
    this.themeMode = ThemeMode.system,
    // Default UI locale is Persian: the app ships Persian-first and the
    // onboarding flow no longer asks for a language. Users can switch to
    // English (or System) from Settings → Language.
    this.localePreference = LocalePreference.persian,
    this.contentLanguages = kDefaultContentLanguages,
    this.enabledCategories = kDefaultEnabledTemplateCategories,
    this.defaultExportQuality = ExportQuality.original,
    this.snapToGuides = true,
    this.showSpacingGuides = true,
    this.multiFingerUndoRedoEnabled = false,
    this.rightHandedToolbar = false,
  });

  /// Sentinel used while preferences load from disk.
  static const AppSettings defaults = AppSettings();

  final bool canvasPanEnabled;
  final bool canvasZoomEnabled;
  final bool canvasRotationEnabled;
  final ThemeMode themeMode;
  final LocalePreference localePreference;
  final Set<TemplateLanguage> contentLanguages;
  final Set<TemplateCategory> enabledCategories;
  final ExportQuality defaultExportQuality;
  final bool snapToGuides;
  final bool showSpacingGuides;

  /// Opt-in Procreate-style tap shortcuts:
  ///   * 2-finger tap on the canvas → undo
  ///   * 3-finger tap on the canvas → redo
  ///
  /// Disabled by default because the gesture competes with legitimate
  /// 2-/3-finger interactions (pinch-to-zoom on empty canvas,
  /// multi-touch on a selection) and some users find it triggers
  /// unintentionally. Power users can enable it from Settings.
  final bool multiFingerUndoRedoEnabled;

  /// When true the bottom tool strip aligns to the **right** edge
  /// (when its tools fit in the viewport) so the row sits closest
  /// to the right thumb. **Tool order is never reversed** —
  /// primary tools (Font, Styles, Color, …) always appear in the
  /// same sequence regardless of handedness; only the row's
  /// alignment / placement changes. Default false (left/center).
  final bool rightHandedToolbar;

  AppSettings copyWith({
    bool? canvasPanEnabled,
    bool? canvasZoomEnabled,
    bool? canvasRotationEnabled,
    ThemeMode? themeMode,
    LocalePreference? localePreference,
    Set<TemplateLanguage>? contentLanguages,
    Set<TemplateCategory>? enabledCategories,
    ExportQuality? defaultExportQuality,
    bool? snapToGuides,
    bool? showSpacingGuides,
    bool? multiFingerUndoRedoEnabled,
    bool? rightHandedToolbar,
  }) {
    return AppSettings(
      canvasPanEnabled: canvasPanEnabled ?? this.canvasPanEnabled,
      canvasZoomEnabled: canvasZoomEnabled ?? this.canvasZoomEnabled,
      canvasRotationEnabled:
          canvasRotationEnabled ?? this.canvasRotationEnabled,
      themeMode: themeMode ?? this.themeMode,
      localePreference: localePreference ?? this.localePreference,
      contentLanguages: contentLanguages ?? this.contentLanguages,
      enabledCategories: enabledCategories ?? this.enabledCategories,
      defaultExportQuality: defaultExportQuality ?? this.defaultExportQuality,
      snapToGuides: snapToGuides ?? this.snapToGuides,
      showSpacingGuides: showSpacingGuides ?? this.showSpacingGuides,
      multiFingerUndoRedoEnabled:
          multiFingerUndoRedoEnabled ?? this.multiFingerUndoRedoEnabled,
      rightHandedToolbar: rightHandedToolbar ?? this.rightHandedToolbar,
    );
  }

  Map<String, Object?> toJson() => {
    'canvasPanEnabled': canvasPanEnabled,
    'canvasZoomEnabled': canvasZoomEnabled,
    'canvasRotationEnabled': canvasRotationEnabled,
    'themeMode': themeMode.name,
    'localePreference': localePreference.name,
    'contentLanguages': contentLanguages.map((l) => l.name).toList(),
    'enabledCategories': enabledCategories.map((c) => c.name).toList(),
    'defaultExportQuality': defaultExportQuality.name,
    'snapToGuides': snapToGuides,
    'showSpacingGuides': showSpacingGuides,
    'multiFingerUndoRedoEnabled': multiFingerUndoRedoEnabled,
    'rightHandedToolbar': rightHandedToolbar,
  };

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final themeModeName = json['themeMode'] as String?;
    final themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == themeModeName,
      orElse: () => ThemeMode.system,
    );
    final localePreferenceName = json['localePreference'] as String?;
    final localePreference = LocalePreference.values.firstWhere(
      (p) => p.name == localePreferenceName,
      orElse: () => LocalePreference.system,
    );
    final contentLanguages = _enumSetFromJson(
      json['contentLanguages'],
      TemplateLanguage.values,
      kDefaultContentLanguages,
    );
    final enabledCategories = _enumSetFromJson(
      json['enabledCategories'],
      TemplateCategory.values,
      kDefaultEnabledTemplateCategories,
    );
    final qualityName = json['defaultExportQuality'] as String?;
    final quality = ExportQuality.values.firstWhere(
      (q) => q.name == qualityName,
      orElse: () => ExportQuality.original,
    );
    return AppSettings(
      canvasPanEnabled: json['canvasPanEnabled'] as bool? ?? true,
      canvasZoomEnabled: json['canvasZoomEnabled'] as bool? ?? true,
      canvasRotationEnabled: json['canvasRotationEnabled'] as bool? ?? true,
      themeMode: themeMode,
      localePreference: localePreference,
      contentLanguages: contentLanguages,
      enabledCategories: enabledCategories,
      defaultExportQuality: quality,
      snapToGuides: json['snapToGuides'] as bool? ?? true,
      showSpacingGuides: json['showSpacingGuides'] as bool? ?? true,
      // Default false: existing users who never touched the setting
      // get the safer behaviour without surprise regressions.
      multiFingerUndoRedoEnabled:
          json['multiFingerUndoRedoEnabled'] as bool? ?? false,
      rightHandedToolbar: json['rightHandedToolbar'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.canvasPanEnabled == canvasPanEnabled &&
      other.canvasZoomEnabled == canvasZoomEnabled &&
      other.canvasRotationEnabled == canvasRotationEnabled &&
      other.themeMode == themeMode &&
      other.localePreference == localePreference &&
      setEquals(other.contentLanguages, contentLanguages) &&
      setEquals(other.enabledCategories, enabledCategories) &&
      other.defaultExportQuality == defaultExportQuality &&
      other.snapToGuides == snapToGuides &&
      other.showSpacingGuides == showSpacingGuides &&
      other.multiFingerUndoRedoEnabled == multiFingerUndoRedoEnabled &&
      other.rightHandedToolbar == rightHandedToolbar;

  @override
  int get hashCode => Object.hash(
    canvasPanEnabled,
    canvasZoomEnabled,
    canvasRotationEnabled,
    themeMode,
    localePreference,
    Object.hashAllUnordered(contentLanguages),
    Object.hashAllUnordered(enabledCategories),
    defaultExportQuality,
    snapToGuides,
    showSpacingGuides,
    multiFingerUndoRedoEnabled,
    rightHandedToolbar,
  );
}

/// Reactive settings store backed by [SharedPreferences].
///
/// Stored as one JSON blob with standalone mirrors for onboarding-owned
/// preference keys. Fields default sensibly when missing from disk.
class SettingsController extends AsyncNotifier<AppSettings> {
  static const String _storageKey = 'app.settings.v1';
  static const String localeStorageKey = 'settings.locale';
  static const String contentLanguagesStorageKey = 'settings.content_languages';
  static const String enabledCategoriesStorageKey =
      'settings.enabled_categories';

  late SharedPreferences _prefs;

  @override
  Future<AppSettings> build() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return _applyStandaloneOverrides(AppSettings.defaults);
    }
    try {
      final settings = AppSettings.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
      return _applyStandaloneOverrides(settings);
    } catch (_) {
      return _applyStandaloneOverrides(AppSettings.defaults);
    }
  }

  Future<void> _persist(AppSettings next) async {
    state = AsyncData(next);
    final saved = await Future.wait<bool>([
      _prefs.setString(_storageKey, jsonEncode(next.toJson())),
      _prefs.setString(localeStorageKey, next.localePreference.name),
      _prefs.setStringList(
        contentLanguagesStorageKey,
        _enumNames(next.contentLanguages),
      ),
      _prefs.setStringList(
        enabledCategoriesStorageKey,
        _enumNames(next.enabledCategories),
      ),
    ]);
    if (saved.any((ok) => !ok)) {
      throw StateError('SharedPreferences refused to persist settings');
    }
  }

  Future<void> _mutate(
    AppSettings Function(AppSettings current) mutator, {
    bool forcePersist = false,
  }) async {
    final current = state.value ?? await future;
    final next = mutator(current);
    if (next == current && !forcePersist) return;
    await _persist(next);
  }

  Future<void> setCanvasPanEnabled(bool value) =>
      _mutate((s) => s.copyWith(canvasPanEnabled: value));

  Future<void> setCanvasZoomEnabled(bool value) =>
      _mutate((s) => s.copyWith(canvasZoomEnabled: value));

  Future<void> setCanvasRotationEnabled(bool value) =>
      _mutate((s) => s.copyWith(canvasRotationEnabled: value));

  Future<void> setThemeMode(ThemeMode value) =>
      _mutate((s) => s.copyWith(themeMode: value));

  Future<void> setLocalePreference(LocalePreference value) =>
      _mutate((s) => s.copyWith(localePreference: value), forcePersist: true);

  Future<void> setContentLanguages(Set<TemplateLanguage> value) => _mutate(
    (s) => s.copyWith(
      contentLanguages: _normalizeSet(value, kDefaultContentLanguages),
    ),
    forcePersist: true,
  );

  Future<void> setEnabledCategories(Set<TemplateCategory> value) => _mutate(
    (s) => s.copyWith(
      enabledCategories: _normalizeSet(
        value,
        kDefaultEnabledTemplateCategories,
      ),
    ),
    forcePersist: true,
  );

  Future<void> setDefaultExportQuality(ExportQuality value) =>
      _mutate((s) => s.copyWith(defaultExportQuality: value));

  Future<void> setSnapToGuides(bool value) =>
      _mutate((s) => s.copyWith(snapToGuides: value));

  Future<void> setShowSpacingGuides(bool value) =>
      _mutate((s) => s.copyWith(showSpacingGuides: value));

  Future<void> setMultiFingerUndoRedoEnabled(bool value) =>
      _mutate((s) => s.copyWith(multiFingerUndoRedoEnabled: value));

  Future<void> setRightHandedToolbar(bool value) =>
      _mutate((s) => s.copyWith(rightHandedToolbar: value));

  AppSettings _applyStandaloneOverrides(AppSettings settings) {
    return settings.copyWith(
      localePreference:
          _enumFromName(
            _prefs.getString(localeStorageKey),
            LocalePreference.values,
          ) ??
          settings.localePreference,
      contentLanguages: _enumSetFromNames(
        _prefs.getStringList(contentLanguagesStorageKey),
        TemplateLanguage.values,
        settings.contentLanguages,
      ),
      enabledCategories: _enumSetFromNames(
        _prefs.getStringList(enabledCategoriesStorageKey),
        TemplateCategory.values,
        settings.enabledCategories,
      ),
    );
  }
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
      SettingsController.new,
    );

/// Convenience: synchronous snapshot. Falls back to [AppSettings.defaults]
/// while the preferences file is loading so callers never need to handle
/// the loading state themselves — settings are global, always available.
final appSettingsProvider = Provider<AppSettings>((ref) {
  final async = ref.watch(settingsControllerProvider);
  return async.value ?? AppSettings.defaults;
});

/// Theme mode used by [MaterialApp]. Defaults to the system setting
/// while preferences load, then updates immediately when Settings
/// writes a user override.
final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(appSettingsProvider).themeMode;
});

final localePreferenceProvider = Provider<LocalePreference>((ref) {
  return ref.watch(appSettingsProvider).localePreference;
});

final contentLanguagesProvider = Provider<Set<TemplateLanguage>>((ref) {
  return ref.watch(appSettingsProvider).contentLanguages;
});

final enabledCategoriesProvider = Provider<Set<TemplateCategory>>((ref) {
  return ref.watch(appSettingsProvider).enabledCategories;
});

final appLocaleProvider = Provider<Locale?>((ref) {
  return ref.watch(localePreferenceProvider).appLocale;
});

Set<T> _enumSetFromJson<T extends Enum>(
  Object? value,
  List<T> values,
  Set<T> fallback,
) {
  if (value is! List) return fallback;
  return _enumSetFromNames(
    value.whereType<String>().toList(),
    values,
    fallback,
  );
}

Set<T> _enumSetFromNames<T extends Enum>(
  List<String>? names,
  List<T> values,
  Set<T> fallback,
) {
  if (names == null || names.isEmpty) return fallback;
  final parsed = <T>{};
  for (final name in names) {
    final value = _enumFromName(name, values);
    if (value != null) parsed.add(value);
  }
  return parsed.isEmpty ? fallback : Set.unmodifiable(parsed);
}

T? _enumFromName<T extends Enum>(String? name, List<T> values) {
  if (name == null) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

Set<T> _normalizeSet<T>(Set<T> values, Set<T> fallback) {
  return values.isEmpty ? fallback : Set.unmodifiable(values);
}

List<String> _enumNames(Iterable<Enum> values) =>
    values.map((value) => value.name).toList(growable: false);
