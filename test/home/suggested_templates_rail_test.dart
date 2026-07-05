import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/ui/template_thumb.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/home/presentation/widgets/suggested_templates_rail.dart';
import 'package:canvas_engine/features/templates/domain/template.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Navigation doc commit 2: the launcher's «پیشنهادی» rail — one
/// horizontal, fixed-height teaser with «مشاهده همه» delegating to
/// the Templates tab. Filter logic (enabled categories x content
/// languages) carried over from the old grid and pinned here.
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
    Set<TemplateLanguage>? contentLanguages,
    void Function(Template)? onOpen,
    VoidCallback? onSeeAll,
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
            child: SuggestedTemplatesRail(
              templates: templates,
              enabledCategories: enabledCategories,
              contentLanguages: contentLanguages,
              onOpen: onOpen ?? (_) {},
              onSeeAll: onSeeAll ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders a single horizontal rail with the header', (
    tester,
  ) async {
    await pump(tester, templates: catalog);

    expect(find.text('Suggested'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-templates-see-all')),
      findsOneWidget,
    );
    expect(find.byType(TemplateThumb), findsNWidgets(4));

    // Horizontal: all thumbs share one row.
    final first = tester.getTopLeft(find.byType(TemplateThumb).at(0));
    final last = tester.getTopLeft(find.byType(TemplateThumb).at(3));
    expect(first.dy, last.dy);
  });

  testWidgets('tap opens the template; see-all fires the callback', (
    tester,
  ) async {
    Template? opened;
    var sawAll = false;
    await pump(
      tester,
      templates: catalog,
      onOpen: (t) => opened = t,
      onSeeAll: () => sawAll = true,
    );

    await tester.tap(find.byKey(const ValueKey('home-template-story-fa')));
    expect(opened?.id, 'story-fa');

    await tester.tap(find.byKey(const ValueKey('home-templates-see-all')));
    expect(sawAll, isTrue);
  });

  testWidgets('filters by content language and enabled categories', (
    tester,
  ) async {
    await pump(
      tester,
      templates: catalog,
      contentLanguages: {TemplateLanguage.english},
      enabledCategories: {TemplateCategory.instagramStory},
    );

    expect(
      find.byKey(const ValueKey('home-template-story-en')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-template-story-fa')), findsNothing);
    expect(find.byKey(const ValueKey('home-template-poetry-fa')), findsNothing);
  });

  testWidgets('caps at previewLimit and renders nothing when empty', (
    tester,
  ) async {
    final many = [
      for (var i = 0; i < SuggestedTemplatesRail.previewLimit + 5; i++)
        template(id: 's$i', category: TemplateCategory.instagramStory),
    ];
    await pump(tester, templates: many);
    // Lazy rail: assert the cut tail never exists.
    expect(
      find.byKey(
        ValueKey('home-template-s${SuggestedTemplatesRail.previewLimit}'),
        skipOffstage: false,
      ),
      findsNothing,
    );

    await pump(tester, templates: const []);
    expect(find.text('Suggested'), findsNothing);
  });

  testWidgets('dark mode renders without throwing', (tester) async {
    await pump(tester, templates: catalog, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
    expect(find.byType(TemplateThumb), findsNWidgets(4));
  });
}
