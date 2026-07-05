import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/onboarding/presentation/screens/welcome_screen.dart';
import 'package:canvas_engine/features/templates/application/template_repository_provider.dart';
import 'package:canvas_engine/features/templates/domain/template.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Workstream B, Commit 3: WelcomeScreen widget test (design doc §5/
/// §7) -- renders, CTA + skip dispatch, RTL, dark mode.
void main() {
  Template fakeTemplate(String id, TemplateCategory category) {
    return Template(
      id: id,
      name: id,
      category: category,
      language: TemplateLanguage.english,
      build: () => EditorDocument(
        width: 200,
        height: 200,
        layers: const [],
        backgroundColor: const Color(0xFFF5EFE6),
      ),
    );
  }

  final fakeTemplates = [
    fakeTemplate('fa_story_warm_pastel', TemplateCategory.story),
    fakeTemplate('fa_story_cafe_mood', TemplateCategory.instagramStory),
    fakeTemplate('fa_story_fashion_drop', TemplateCategory.instagramStory),
  ];

  Widget host({
    required VoidCallback onGetStarted,
    required VoidCallback onSkip,
    Brightness brightness = Brightness.light,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    return ProviderScope(
      overrides: [
        effectiveTemplatesProvider.overrideWith((ref, locale) => fakeTemplates),
      ],
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
            body: WelcomeScreen(onGetStarted: onGetStarted, onSkip: onSkip),
          ),
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

  testWidgets('renders the CTA and skip controls', (tester) async {
    await pump(tester, host(onGetStarted: () {}, onSkip: () {}));

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
    expect(
      find.byKey(const ValueKey('onboarding-get-started')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('onboarding-welcome-skip')),
      findsOneWidget,
    );
  });

  testWidgets('renders without throwing in dark mode', (tester) async {
    await pump(
      tester,
      host(onGetStarted: () {}, onSkip: () {}, brightness: Brightness.dark),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('onboarding-get-started')),
      findsOneWidget,
    );
  });
}
