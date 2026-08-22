import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/ui/template_thumb.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/home/presentation/widgets/suggested_templates_rail.dart';
import 'package:canvas_engine/features/templates/domain/template.dart';
import 'package:canvas_engine/features/templates/presentation/template_presentation_order.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The launcher's «پیشنهادِ امروز» rail — one horizontal, fixed-height
/// teaser with «مشاهده همه» delegating to the Templates tab. Filter
/// logic (enabled categories x content languages) carried over from
/// the old grid and pinned here. New with the desk redesign: the
/// selection is date-seeded ([dailyTemplateShelf]) — stable within a
/// day, different across days — so every test pins the date.
void main() {
  final fixedToday = DateTime(2026, 8, 22);
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
    DateTime? today,
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
              today: today ?? fixedToday,
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

    expect(find.text("Today's picks"), findsOneWidget);
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
    // The selection is date-seeded, so WHICH ids are cut depends on
    // the pinned date — recompute the day's shelf with the same pure
    // function and assert the rail agrees with it exactly.
    final shelf = dailyTemplateShelf(
      ordered: orderTemplatesForHome(templates: many),
      date: fixedToday,
      count: SuggestedTemplatesRail.previewLimit,
    );
    expect(shelf.length, SuggestedTemplatesRail.previewLimit);
    final shownIds = shelf.map((t) => t.id).toSet();
    final cut = many.firstWhere((t) => !shownIds.contains(t.id));
    expect(
      find.byKey(ValueKey('home-template-${shelf.first.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('home-template-${cut.id}'), skipOffstage: false),
      findsNothing,
    );

    await pump(tester, templates: const []);
    expect(find.text("Today's picks"), findsNothing);
  });

  test('the shelf is stable within a day and changes across days', () {
    final many = [
      for (var i = 0; i < 15; i++)
        template(id: 's$i', category: TemplateCategory.instagramStory),
    ];
    final ordered = orderTemplatesForHome(templates: many);
    List<String> shelfIds(DateTime d) =>
        dailyTemplateShelf(ordered: ordered, date: d).map((t) => t.id).toList();

    // Same day → byte-identical selection: the shelf must not
    // reshuffle under the user's thumb on every rebuild.
    expect(shelfIds(fixedToday), shelfIds(fixedToday));

    // Across a week of days, at least two distinct orders — the
    // whole point of the seed. (Six independent shuffles of 15
    // items colliding into one order is not a real possibility.)
    final week = {
      for (var d = 0; d < 6; d++)
        shelfIds(fixedToday.add(Duration(days: d))).join(','),
    };
    expect(week.length, greaterThan(1));
  });

  testWidgets('dark mode renders without throwing', (tester) async {
    await pump(tester, templates: catalog, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
    expect(find.byType(TemplateThumb), findsNWidgets(4));
  });

  testWidgets('tiles take their format\'s shape: a story reads tall, a '
      'video cover reads wide', (tester) async {
    await pump(
      tester,
      templates: [
        template(id: 'a-story', category: TemplateCategory.instagramStory),
        template(id: 'a-quote', category: TemplateCategory.poetryPost),
        template(id: 'a-video', category: TemplateCategory.youtubeThumbnail),
      ],
    );

    double widthOf(String id) =>
        tester.getSize(find.byKey(ValueKey('home-template-$id'))).width;

    // 9:16 clamps at the narrow floor, 1:1 is square, 16:9 clamps at
    // the wide ceiling — three visibly different silhouettes.
    expect(widthOf('a-story'), moreOrLessEquals(150 * 0.62, epsilon: 0.01));
    expect(widthOf('a-quote'), moreOrLessEquals(150, epsilon: 0.01));
    expect(widthOf('a-video'), moreOrLessEquals(150 * 1.5, epsilon: 0.01));
  });
}
