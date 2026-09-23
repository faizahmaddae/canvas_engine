import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/features/home/application/project_store.dart';
import 'package:canvas_engine/features/home/domain/project.dart';
import 'package:canvas_engine/features/home/presentation/widgets/project_thumb.dart';
import 'package:canvas_engine/features/home/presentation/widgets/recent_projects_section.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/temp_projects_dir.dart';

/// The recent-work rail after the desk redesign: ProjectThumbs only —
/// the dashed «جدید» tile died with the continue hero's arrival, and
/// with [RecentProjectsSection.skipNewest] the rail starts from the
/// second-newest project so the hero's design never appears twice.
/// NOTHING renders when there is nothing left to show.
void main() {
  Project seed({
    required String id,
    required String name,
    Duration ago = const Duration(minutes: 5),
  }) {
    final t = DateTime.now().subtract(ago);
    return Project(
      id: id,
      name: name,
      width: 1080,
      height: 1080,
      createdAt: t,
      lastModified: t,
      documentJson: '{}',
    );
  }

  Future<void> pumpSection(
    WidgetTester tester, {
    required List<Project> projects,
    void Function(Project)? onOpen,
    bool skipNewest = false,
    Brightness brightness = Brightness.light,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final dir = tempProjectsDir();
    final container = ProviderContainer(
      overrides: [projectsDirectoryProvider.overrideWith((ref) async => dir)],
    );
    addTearDown(container.dispose);
    // Hydrate the store BEFORE first frame so the section renders the
    // rail on first pump. Real file IO — must run outside the
    // fake-async test zone (see temp_projects_dir.dart).
    await tester.runAsync(() async {
      await container.read(projectStoreProvider.future);
      for (final p in projects) {
        await container.read(projectStoreProvider.notifier).upsert(p);
      }
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentProjectsSection(
                onOpen: onOpen ?? (_) {},
                onSeeAll: () {},
                skipNewest: skipNewest,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('populated: renders thumbs, and no dashed tile anywhere', (
    tester,
  ) async {
    await pumpSection(
      tester,
      projects: [seed(id: 'p1', name: 'Birthday card')],
    );

    expect(find.text('Recent work'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-recent-p1')), findsOneWidget);
    expect(find.text('Birthday card'), findsAtLeastNWidgets(1));
    expect(find.byKey(const ValueKey('home-recent-new-tile')), findsNothing);
  });

  testWidgets('tapping a thumb opens it', (tester) async {
    Project? opened;
    await pumpSection(
      tester,
      projects: [seed(id: 'p1', name: 'Birthday card')],
      onOpen: (p) => opened = p,
    );

    await tester.tap(find.byKey(const ValueKey('home-recent-p1')));
    expect(opened?.id, 'p1');
  });

  testWidgets('empty: renders nothing at all — no rail, no header', (
    tester,
  ) async {
    await pumpSection(tester, projects: const []);

    expect(find.text('Recent work'), findsNothing);
    expect(find.byType(ProjectThumb), findsNothing);
  });

  testWidgets('skipNewest: the newest project belongs to the hero, the '
      'rail starts from the second', (tester) async {
    await pumpSection(
      tester,
      skipNewest: true,
      projects: [
        seed(
          id: 'newest',
          name: 'On the hero',
          ago: const Duration(minutes: 1),
        ),
        seed(id: 'older', name: 'On the rail', ago: const Duration(hours: 1)),
      ],
    );

    expect(find.byKey(const ValueKey('home-recent-newest')), findsNothing);
    expect(find.byKey(const ValueKey('home-recent-older')), findsOneWidget);
  });

  testWidgets('skipNewest with a single project: the hero holds it, the '
      'section renders nothing', (tester) async {
    await pumpSection(
      tester,
      skipNewest: true,
      projects: [seed(id: 'only', name: 'On the hero')],
    );

    expect(find.text('Recent work'), findsNothing);
    expect(find.byType(ProjectThumb), findsNothing);
  });

  testWidgets('see-all appears only past the preview limit', (tester) async {
    await pumpSection(
      tester,
      skipNewest: true,
      projects: [
        // Distinct timestamps so the newest-first cap is
        // deterministic: p0 newest (hero) … p9 oldest (the one cut).
        for (var i = 0; i < 10; i++)
          seed(
            id: 'p$i',
            name: 'P $i',
            ago: Duration(minutes: i + 1),
          ),
      ],
    );

    expect(find.byKey(const ValueKey('home-recent-see-all')), findsOneWidget);
    // p0 is the hero's; the rail holds the 8 next-newest (p1…p8) and
    // cuts p9. The rail is a lazy horizontal list, so drag to the end
    // before asserting on the tail.
    expect(find.byKey(const ValueKey('home-recent-p0')), findsNothing);
    expect(find.byKey(const ValueKey('home-recent-p1')), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(-900, 0));
    await tester.pump();
    expect(find.byKey(const ValueKey('home-recent-p8')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-recent-p9')), findsNothing);
  });

  testWidgets('dark mode renders without throwing', (tester) async {
    await pumpSection(
      tester,
      projects: [seed(id: 'p1', name: 'Birthday card')],
      brightness: Brightness.dark,
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('home-recent-p1')), findsOneWidget);
  });

  testWidgets('thumbs take the canvas\'s own shape — a square project is '
      'a square tile, not a portrait card with letterbox bands', (
    tester,
  ) async {
    final t = DateTime.now().subtract(const Duration(minutes: 5));
    await pumpSection(
      tester,
      projects: [
        // seed() makes 1080×1080; this one is a 9:16 story.
        seed(id: 'square', name: 'Square'),
        Project(
          id: 'story',
          name: 'Story',
          width: 1080,
          height: 1920,
          createdAt: t,
          lastModified: t,
          documentJson: '{}',
        ),
      ],
    );

    final squareW = tester
        .getSize(find.byKey(const ValueKey('home-recent-square')))
        .width;
    final storyW = tester
        .getSize(find.byKey(const ValueKey('home-recent-story')))
        .width;
    expect(squareW, moreOrLessEquals(140, epsilon: 0.01));
    expect(storyW, moreOrLessEquals(140 * 0.62, epsilon: 0.01));
  });
}
