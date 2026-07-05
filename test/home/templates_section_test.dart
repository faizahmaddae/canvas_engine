import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:canvas_engine/app/ui/app_filter_chip.dart';
import 'package:canvas_engine/app/ui/template_thumb.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/home/presentation/widgets/template_language_filter.dart';
import 'package:canvas_engine/features/home/presentation/widgets/templates_section.dart';
import 'package:canvas_engine/features/templates/domain/template.dart';
import 'package:canvas_engine/features/templates/presentation/templates_browse_screen.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Home redesign commit 2 (docs/home-screen-redesign-2026-07.md):
/// the templates section is one curated 2-col grid of TemplateThumbs
/// under a «قالب‌ها» + «مشاهده همه» header and AppFilterChip language
/// chips. Filter LOGIC (language x enabled categories) is unchanged
/// from the strip era and pinned here.
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
    template(id: 'promo-fa', category: TemplateCategory.promotionalPoster),
  ];

  Future<void> pump(
    WidgetTester tester, {
    required List<Template> templates,
    Set<TemplateCategory>? enabledCategories,
    HomeTemplateLanguageFilter languageFilter = HomeTemplateLanguageFilter.all,
    Widget? filter,
    void Function(Template)? onOpen,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: TemplatesSection(
              templates: templates,
              enabledCategories: enabledCategories,
              languageFilter: languageFilter,
              filter: filter,
              onOpen: onOpen ?? (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders a 2-col grid of TemplateThumbs with the header row', (
    tester,
  ) async {
    await pump(tester, templates: catalog);

    expect(find.text('Templates'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-templates-see-all')),
      findsOneWidget,
    );
    expect(find.byType(TemplateThumb), findsNWidgets(4));

    // 2 columns: first two thumbs share a row (same dy).
    final first = tester.getTopLeft(find.byType(TemplateThumb).at(0));
    final second = tester.getTopLeft(find.byType(TemplateThumb).at(1));
    final third = tester.getTopLeft(find.byType(TemplateThumb).at(2));
    expect(first.dy, second.dy);
    expect(third.dy, greaterThan(first.dy));
  });

  testWidgets('tapping a thumb opens that template', (tester) async {
    Template? opened;
    await pump(tester, templates: catalog, onOpen: (t) => opened = t);

    await tester.tap(find.byKey(const ValueKey('home-template-poetry-fa')));
    expect(opened?.id, 'poetry-fa');
  });

  testWidgets('language filter logic: english shows only english templates', (
    tester,
  ) async {
    await pump(
      tester,
      templates: catalog,
      languageFilter: HomeTemplateLanguageFilter.english,
    );

    expect(
      find.byKey(const ValueKey('home-template-story-en')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-template-story-fa')), findsNothing);
    expect(find.byKey(const ValueKey('home-template-poetry-fa')), findsNothing);
  });

  testWidgets('enabled-categories logic: disabled categories are absent', (
    tester,
  ) async {
    await pump(
      tester,
      templates: catalog,
      enabledCategories: {TemplateCategory.instagramStory},
    );

    expect(
      find.byKey(const ValueKey('home-template-story-fa')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-template-poetry-fa')), findsNothing);
    expect(find.byKey(const ValueKey('home-template-promo-fa')), findsNothing);
  });

  testWidgets('grid caps at previewLimit', (tester) async {
    final many = [
      for (var i = 0; i < TemplatesSection.previewLimit + 5; i++)
        template(id: 'story-$i', category: TemplateCategory.instagramStory),
    ];
    await pump(tester, templates: many);

    expect(
      find.byType(TemplateThumb),
      findsNWidgets(TemplatesSection.previewLimit),
    );
  });

  testWidgets('see-all opens the browse screen', (tester) async {
    await pump(tester, templates: catalog);

    await tester.tap(find.byKey(const ValueKey('home-templates-see-all')));
    await tester.pumpAndSettle();

    expect(find.byType(TemplatesBrowseScreen), findsOneWidget);
  });

  testWidgets('filter chips: selected is ink-filled, tap reports the value', (
    tester,
  ) async {
    HomeTemplateLanguageFilter? changed;
    await pump(
      tester,
      templates: catalog,
      filter: TemplateLanguageFilter(
        selected: HomeTemplateLanguageFilter.all,
        onChanged: (v) => changed = v,
      ),
    );

    AnimatedContainer chipBox(String name) => tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byKey(ValueKey('home-template-filter-$name')),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .first;

    final selected = chipBox('all').decoration! as BoxDecoration;
    expect(selected.color, AppTokens.light.brand);
    expect(selected.border, isNull);

    final unselected = chipBox('persian').decoration! as BoxDecoration;
    expect(unselected.color, AppTokens.light.surface);
    expect((unselected.border! as Border).top.color, AppTokens.light.border);

    await tester.tap(
      find.byKey(const ValueKey('home-template-filter-persian')),
    );
    expect(changed, HomeTemplateLanguageFilter.persian);
  });

  testWidgets('dark mode: selected chip flips to cream, grid renders', (
    tester,
  ) async {
    await pump(
      tester,
      templates: catalog,
      brightness: Brightness.dark,
      filter: TemplateLanguageFilter(
        selected: HomeTemplateLanguageFilter.all,
        onChanged: (_) {},
      ),
    );
    expect(tester.takeException(), isNull);

    final chip = tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byType(AppFilterChip).first,
            matching: find.byType(AnimatedContainer),
          ),
        )
        .first;
    expect((chip.decoration! as BoxDecoration).color, AppTokens.dark.brand);
    expect(find.byType(TemplateThumb), findsNWidgets(4));
  });
}
