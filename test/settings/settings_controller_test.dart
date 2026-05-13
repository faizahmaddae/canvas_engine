import 'dart:convert';

import 'package:canvas_engine/features/editor/application/export_quality.dart';
import 'package:canvas_engine/features/settings/application/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> makeContainer() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Force the controller to materialise its initial state.
    await container.read(settingsControllerProvider.future);
    return container;
  }

  test('defaults are pan/zoom on, original quality, snap on', () async {
    final container = await makeContainer();
    final s = container.read(appSettingsProvider);
    expect(s.canvasPanEnabled, isTrue);
    expect(s.canvasZoomEnabled, isTrue);
    expect(s.canvasRotationEnabled, isTrue);
    expect(s.themeMode, ThemeMode.system);
    expect(s.localePreference, LocalePreference.persian);
    expect(container.read(themeModeProvider), ThemeMode.system);
    expect(container.read(localePreferenceProvider), LocalePreference.persian);
    expect(container.read(appLocaleProvider), const Locale('fa'));
    expect(s.defaultExportQuality, ExportQuality.original);
    expect(s.snapToGuides, isTrue);
    expect(s.showSpacingGuides, isTrue);
    expect(
      s.multiFingerUndoRedoEnabled,
      isFalse,
      reason:
          'Multi-finger undo/redo is opt-in to avoid conflicts '
          'with pinch gestures.',
    );
  });

  test('toggling pan persists to SharedPreferences', () async {
    final container = await makeContainer();
    await container
        .read(settingsControllerProvider.notifier)
        .setCanvasPanEnabled(false);

    expect(container.read(appSettingsProvider).canvasPanEnabled, isFalse);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('app.settings.v1');
    expect(raw, isNotNull);
    final json = Map<String, Object?>.from(jsonDecode(raw!) as Map);
    expect(json['canvasPanEnabled'], isFalse);
  });

  test('theme mode persists and updates themeModeProvider', () async {
    final container = await makeContainer();
    await container
        .read(settingsControllerProvider.notifier)
        .setThemeMode(ThemeMode.dark);

    expect(container.read(appSettingsProvider).themeMode, ThemeMode.dark);
    expect(container.read(themeModeProvider), ThemeMode.dark);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('app.settings.v1');
    expect(raw, isNotNull);
    final json = Map<String, Object?>.from(jsonDecode(raw!) as Map);
    expect(json['themeMode'], 'dark');
  });

  test('locale preference persists and updates appLocaleProvider', () async {
    final container = await makeContainer();
    await container
        .read(settingsControllerProvider.notifier)
        .setLocalePreference(LocalePreference.persian);

    expect(
      container.read(appSettingsProvider).localePreference,
      LocalePreference.persian,
    );
    expect(container.read(localePreferenceProvider), LocalePreference.persian);
    expect(container.read(appLocaleProvider), const Locale('fa'));

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('app.settings.v1');
    expect(raw, isNotNull);
    final json = Map<String, Object?>.from(jsonDecode(raw!) as Map);
    expect(json['localePreference'], 'persian');
  });

  test('settings restore from disk on next launch', () async {
    SharedPreferences.setMockInitialValues({
      'app.settings.v1': jsonEncode({
        'canvasPanEnabled': false,
        'canvasZoomEnabled': false,
        'themeMode': 'light',
        'localePreference': 'english',
        'defaultExportQuality': 'high',
        'snapToGuides': false,
      }),
    });
    final container = await makeContainer();
    final s = container.read(appSettingsProvider);
    expect(s.canvasPanEnabled, isFalse);
    expect(s.canvasZoomEnabled, isFalse);
    expect(s.themeMode, ThemeMode.light);
    expect(s.localePreference, LocalePreference.english);
    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(container.read(appLocaleProvider), const Locale('en'));
    expect(s.defaultExportQuality, ExportQuality.high);
    expect(s.snapToGuides, isFalse);
    // Missing keys fall back to defaults.
    expect(s.canvasRotationEnabled, isTrue);
    expect(s.showSpacingGuides, isTrue);
  });

  test('corrupt blob falls back to defaults without throwing', () async {
    SharedPreferences.setMockInitialValues({'app.settings.v1': '{not-json'});
    final container = await makeContainer();
    expect(container.read(appSettingsProvider), AppSettings.defaults);
  });

  test('export quality round-trips through settings', () async {
    final container = await makeContainer();
    await container
        .read(settingsControllerProvider.notifier)
        .setDefaultExportQuality(ExportQuality.ultra);
    expect(
      container.read(appSettingsProvider).defaultExportQuality,
      ExportQuality.ultra,
    );
  });
}
