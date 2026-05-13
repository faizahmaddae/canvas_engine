import 'dart:convert';

import 'package:canvas_engine/app/app.dart';
import 'package:canvas_engine/features/settings/application/settings_controller.dart';
import 'package:canvas_engine/features/settings/presentation/settings_screen.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('theme tile offers system, light, and dark choices', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('System'), findsAtLeastNWidgets(1));

    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(RadioListTile<ThemeMode>, 'System'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(RadioListTile<ThemeMode>, 'Light'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(RadioListTile<ThemeMode>, 'Dark'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(RadioListTile<ThemeMode>, 'Dark'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Dark'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('app.settings.v1');
    expect(raw, isNotNull);
    final json = Map<String, Object?>.from(jsonDecode(raw!) as Map);
    expect(json['themeMode'], 'dark');
  });

  testWidgets('language tile switches UI immediately and persists', (
    tester,
  ) async {
    // App default locale is now Persian. Pre-seed an English
    // override so this test exercises the English → Persian switch.
    SharedPreferences.setMockInitialValues({
      'onboarding.complete': true,
      'settings.locale': 'english',
    });

    await tester.pumpWidget(const ProviderScope(child: CanvasEngineApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Language'), findsOneWidget);
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(RadioListTile<LocalePreference>, 'فارسی'),
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('تنظیمات'), findsOneWidget);
    expect(find.text('زبان'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('app.settings.v1');
    expect(raw, isNotNull);
    final json = Map<String, Object?>.from(jsonDecode(raw!) as Map);
    expect(json['localePreference'], 'persian');
  });
}
