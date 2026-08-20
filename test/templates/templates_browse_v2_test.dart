import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:canvas_engine/app/ui/app_filter_chip.dart';
import 'package:canvas_engine/app/ui/template_thumb.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/settings/application/settings_controller.dart';
import 'package:canvas_engine/features/templates/domain/template.dart';
import 'package:canvas_engine/features/templates/presentation/templates_browse_screen.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Navigation doc commit 3: the Templates tab (browse screen) on v2
/// tokens — search field, category + language AppFilterChips, lazy
/// 2-col TemplateThumb grid. Filter logic pinned via chip taps.
void main() {
  Template template({
    required String id,
    required TemplateCategory category,
    TemplateLanguage language = TemplateLanguage.persian,
  }) {
    return Template(
      id: id,
      name: id,
      category: category,
      language: language,
      build: () => EditorDocument(
        width: 200,
        height: 200,
        layers: const [],
        backgroundColor: const Color(0xFFF5EFE6),
      ),
    );
  }

  final catalog = [
    template(id: 'story-fa', category: TemplateCategory.instagramStory),
    template(
      id: 'story-en',
      category: TemplateCategory.instagramStory,
      language: TemplateLanguage.english,
    ),
    template(id: 'poetry-fa', category: TemplateCategory.poetryPost),
  ];

  Future<void> pump(
    WidgetTester tester, {
    List<Template>? templates,
    TemplateLanguage? initialLanguage = TemplateLanguage.persian,
    void Function(Template)? onOpen,
    Brightness brightness = Brightness.light,
    Set<TemplateLanguage>? contentLanguages,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (contentLanguages != null)
            contentLanguagesProvider.overrideWithValue(contentLanguages),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TemplatesBrowseScreen(
            onOpen: onOpen ?? (_) {},
            initialLanguage: initialLanguage,
            templates: templates ?? catalog,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders search, chip rows, and the thumb grid on pageBg', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(const ValueKey('browse-category-all')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('browse-language-persian')),
      findsOneWidget,
    );
    // initialLanguage persian → only fa templates in the grid.
    expect(
      find.byKey(const ValueKey('browse-template-tile-story-fa')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('browse-template-tile-story-en')),
      findsNothing,
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppTokens.light.pageBg);
  });

  testWidgets('language chip switches the pool; category chip narrows it', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('browse-language-english')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('browse-template-tile-story-en')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('browse-template-tile-story-fa')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('browse-language-all')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('browse-category-poetryPost')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('browse-template-tile-poetry-fa')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('browse-template-tile-story-fa')),
      findsNothing,
    );
  });

  testWidgets('search narrows the grid and empty state appears on no match', (
    tester,
  ) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'poetry');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('browse-template-tile-poetry-fa')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('browse-template-tile-story-fa')),
      findsNothing,
    );

    await tester.enterText(find.byType(TextField), 'zzz-no-match');
    await tester.pump();
    expect(find.byType(TemplateThumb), findsNothing);
    expect(find.text('No templates found'), findsOneWidget);
  });

  testWidgets('tapping a tile opens the template', (tester) async {
    Template? opened;
    await pump(tester, onOpen: (t) => opened = t);

    await tester.tap(
      find.byKey(const ValueKey('browse-template-tile-story-fa')),
    );
    expect(opened?.id, 'story-fa');
  });

  testWidgets('story categories collapse onto ONE chip that filters both', (
    tester,
  ) async {
    final withBothStories = [
      ...catalog,
      template(id: 'plain-story', category: TemplateCategory.story),
    ];
    await pump(tester, templates: withBothStories);

    // One canonical chip: instagramStory hosts the shared «استوری»
    // label; no separate chip for the plain story category.
    expect(
      find.byKey(const ValueKey('browse-category-instagramStory')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('browse-category-story')), findsNothing);

    // Selecting it shows templates from BOTH story categories.
    await tester.tap(
      find.byKey(const ValueKey('browse-category-instagramStory')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('browse-template-tile-story-fa')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('browse-template-tile-plain-story')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('browse-template-tile-poetry-fa')),
      findsNothing,
    );
  });

  testWidgets('language row is the compact secondary control with a label', (
    tester,
  ) async {
    await pump(tester);

    // The «زبان:» prefix disambiguates the row from the category
    // chips; language chips render in the compact size.
    expect(find.text('Language:'), findsOneWidget);
    final languageChip = tester.getSize(
      find.byKey(const ValueKey('browse-language-all')),
    );
    final categoryChip = tester.getSize(
      find.byKey(const ValueKey('browse-category-all')),
    );
    expect(languageChip.height, lessThan(categoryChip.height));
  });

  testWidgets('dark mode: ink canvas, cream selected chip', (tester) async {
    await pump(tester, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppTokens.dark.pageBg);

    final selectedChip = tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byKey(const ValueKey('browse-language-persian')),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .first;
    expect(
      (selectedChip.decoration! as BoxDecoration).color,
      AppTokens.dark.brand,
    );
    expect(find.byType(AppFilterChip), findsAtLeastNWidgets(4));
  });

  // ── default language derivation (ux-audit P2-14) ──
  //
  // "See all" must be a superset of the Home rail: with no explicit
  // initialLanguage the browser follows the Content-languages setting
  // instead of hard-defaulting to Persian.

  testWidgets('default mount with both content languages starts on All — '
      'every template visible', (tester) async {
    await pump(tester, initialLanguage: null);

    expect(
      find.byKey(const ValueKey('browse-template-tile-story-fa')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('browse-template-tile-story-en')),
      findsOneWidget,
      reason: 'English content must not start hidden behind a filter',
    );
  });

  testWidgets('an English-only content preference preselects the English '
      'chip', (tester) async {
    await pump(
      tester,
      initialLanguage: null,
      contentLanguages: {TemplateLanguage.english},
    );

    expect(
      find.byKey(const ValueKey('browse-template-tile-story-en')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('browse-template-tile-story-fa')),
      findsNothing,
      reason: 'a single enabled language becomes the starting filter',
    );
  });
}
