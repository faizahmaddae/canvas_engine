import 'dart:convert';

import 'package:canvas_engine/app/app.dart';
import 'package:canvas_engine/features/home/presentation/home_screen.dart';
import 'package:canvas_engine/features/onboarding/presentation/onboarding_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('first launch mounts onboarding instead of Home', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CanvasEngineApp()));

    expect(find.byType(OnboardingFlow), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('second launch after onboarding mounts Home directly', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding.complete': true});

    await tester.pumpWidget(const ProviderScope(child: CanvasEngineApp()));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(OnboardingFlow), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationDestination), findsNothing);
  });

  testWidgets('uses persisted theme mode once settings load', (tester) async {
    SharedPreferences.setMockInitialValues({
      'onboarding.complete': true,
      'app.settings.v1': jsonEncode({'themeMode': 'dark'}),
    });

    await tester.pumpWidget(const ProviderScope(child: CanvasEngineApp()));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });

  testWidgets('uses persisted locale preference once settings load', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboarding.complete': true,
      'app.settings.v1': jsonEncode({'localePreference': 'persian'}),
    });

    await tester.pumpWidget(const ProviderScope(child: CanvasEngineApp()));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.locale, const Locale('fa'));
    expect(find.text('کانواس'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(HomeScreen))),
      TextDirection.rtl,
    );
  });
}
