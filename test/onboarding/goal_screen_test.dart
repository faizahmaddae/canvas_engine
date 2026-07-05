import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:canvas_engine/features/onboarding/application/onboarding_controller.dart';
import 'package:canvas_engine/features/onboarding/presentation/screens/goal_screen.dart';
import 'package:canvas_engine/features/templates/domain/template.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Design direction v2: GoalScreen widget test — selection toggles
/// through the onboarding controller (saffron ring + check on the
/// selected card), continue/skip dispatch, RTL and dark render.
/// Category persistence to settings stays covered by
/// onboarding_flow_test.dart.
void main() {
  Widget host({
    required ProviderContainer container,
    VoidCallback? onContinue,
    VoidCallback? onSkip,
    Brightness brightness = Brightness.light,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
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
            body: GoalScreen(
              onContinue: onContinue ?? () {},
              onSkip: onSkip ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    VoidCallback? onContinue,
    VoidCallback? onSkip,
    Brightness brightness = Brightness.light,
    TextDirection textDirection = TextDirection.ltr,
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      host(
        container: container,
        onContinue: onContinue,
        onSkip: onSkip,
        brightness: brightness,
        textDirection: textDirection,
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('renders all six goal cards, CTA and skip', (tester) async {
    await pump(tester);

    for (final name in [
      'instagramStory',
      'promotionalPoster',
      'poetryPost',
      'youtubeThumbnail',
      'quote',
      'social',
    ]) {
      expect(
        find.byKey(ValueKey('onboarding-goal-$name')),
        findsOneWidget,
        reason: name,
      );
    }
    expect(
      find.byKey(const ValueKey('onboarding-goal-continue')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('onboarding-goal-skip')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a card toggles the category and shows the '
      'saffron ring + check', (tester) async {
    final container = await pump(tester);
    const cardKey = ValueKey('onboarding-goal-instagramStory');

    AnimatedContainer cardBox() => tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byKey(cardKey),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .first;

    // Unselected: hairline border, no check badge.
    var border = (cardBox().decoration! as BoxDecoration).border! as Border;
    expect(border.top.color, AppTokens.light.border);
    expect(border.top.width, 1);
    expect(
      find.descendant(
        of: find.byKey(cardKey),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(cardKey));
    await tester.pump(const Duration(milliseconds: 250));

    expect(container.read(onboardingControllerProvider).selectedCategories, {
      TemplateCategory.instagramStory,
    });
    border = (cardBox().decoration! as BoxDecoration).border! as Border;
    expect(border.top.color, AppTokens.light.accent);
    expect(border.top.width, 2);
    expect(
      find.descendant(
        of: find.byKey(cardKey),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );

    // Tapping again deselects.
    await tester.tap(find.byKey(cardKey));
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      container.read(onboardingControllerProvider).selectedCategories,
      isEmpty,
    );
  });

  testWidgets('continue and skip dispatch', (tester) async {
    var continued = false;
    var skipped = false;
    await pump(
      tester,
      onContinue: () => continued = true,
      onSkip: () => skipped = true,
    );

    await tester.tap(
      find.byKey(const ValueKey('onboarding-goal-continue')),
      warnIfMissed: false,
    );
    expect(continued, isTrue);

    await tester.tap(find.byKey(const ValueKey('onboarding-goal-skip')));
    expect(skipped, isTrue);
  });

  testWidgets('renders without throwing under RTL', (tester) async {
    await pump(tester, textDirection: TextDirection.rtl);
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('onboarding-goal-continue')),
      findsOneWidget,
    );
  });

  testWidgets('dark mode: cards flip to ink surface, selection ring '
      'uses the dark saffron', (tester) async {
    await pump(tester, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);

    const cardKey = ValueKey('onboarding-goal-quote');
    await tester.tap(find.byKey(cardKey));
    await tester.pump(const Duration(milliseconds: 250));

    final box = tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byKey(cardKey),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .first;
    final decoration = box.decoration! as BoxDecoration;
    expect(decoration.color, AppTokens.dark.surface);
    expect((decoration.border! as Border).top.color, AppTokens.dark.accent);
  });
}
