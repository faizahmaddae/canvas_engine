import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:canvas_engine/features/onboarding/presentation/screens/welcome_screen.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Design direction v2: WelcomeScreen calligraphy-hero widget test —
/// renders (nastaliq hero + flourish + subtitle), CTA + skip
/// dispatch, RTL, dark mode. No template repository involved
/// anymore: the v1 card showcase is gone.
void main() {
  Widget host({
    required VoidCallback onGetStarted,
    required VoidCallback onSkip,
    Brightness brightness = Brightness.light,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    return MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Directionality(
        textDirection: textDirection,
        child: Scaffold(
          body: WelcomeScreen(onGetStarted: onGetStarted, onSkip: onSkip),
        ),
      ),
    );
  }

  Future<void> pump(WidgetTester tester, Widget widget) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(widget);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  }

  testWidgets('renders the nastaliq hero, subtitle, CTA and skip', (
    tester,
  ) async {
    await pump(tester, host(onGetStarted: () {}, onSkip: () {}));

    final hero = tester.widget<Text>(find.text(WelcomeScreen.heroWord));
    expect(hero.style?.fontFamily, 'IranNastaliq');
    expect(
      find.byKey(const ValueKey('onboarding-get-started')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('onboarding-welcome-skip')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('hero uses textPrimary and the flourish uses accent', (
    tester,
  ) async {
    await pump(tester, host(onGetStarted: () {}, onSkip: () {}));

    final hero = tester.widget<Text>(find.text(WelcomeScreen.heroWord));
    expect(hero.style?.color, AppTokens.light.textPrimary);

    final flourish = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.color == AppTokens.light.accent);
    expect(flourish, isNotEmpty, reason: 'saffron flourish under the hero');
  });

  testWidgets('Get Started dispatches onGetStarted', (tester) async {
    var tapped = false;
    await pump(tester, host(onGetStarted: () => tapped = true, onSkip: () {}));

    await tester.tap(
      find.byKey(const ValueKey('onboarding-get-started')),
      warnIfMissed: false,
    );
    expect(tapped, isTrue);
  });

  testWidgets('Skip dispatches onSkip', (tester) async {
    var skipped = false;
    await pump(tester, host(onGetStarted: () {}, onSkip: () => skipped = true));

    await tester.tap(find.byKey(const ValueKey('onboarding-welcome-skip')));
    expect(skipped, isTrue);
  });

  testWidgets('renders without throwing under RTL', (tester) async {
    await pump(
      tester,
      host(
        onGetStarted: () {},
        onSkip: () {},
        textDirection: TextDirection.rtl,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text(WelcomeScreen.heroWord), findsOneWidget);
    expect(
      find.byKey(const ValueKey('onboarding-get-started')),
      findsOneWidget,
    );
  });

  testWidgets('dark mode flips hero to cream on ink', (tester) async {
    await pump(
      tester,
      host(onGetStarted: () {}, onSkip: () {}, brightness: Brightness.dark),
    );

    expect(tester.takeException(), isNull);
    final hero = tester.widget<Text>(find.text(WelcomeScreen.heroWord));
    expect(hero.style?.color, AppTokens.dark.textPrimary);
  });
}
