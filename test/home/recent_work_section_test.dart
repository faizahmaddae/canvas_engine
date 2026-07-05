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

/// Home redesign commit 3 (docs/home-screen-redesign-2026-07.md §4):
/// the recent-work rail — ProjectThumbs ending in the dashed «جدید»
/// tile when projects exist, NOTHING at all when the store is empty.
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
    VoidCallback? onCreate,
    void Function(Project)? onOpen,
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
                onCreate: onCreate ?? () {},
                onOpen: onOpen ?? (_) {},
                onSeeAll: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('populated: renders thumbs + the dashed new tile', (
    tester,
  ) async {
    await pumpSection(
      tester,
      projects: [seed(id: 'p1', name: 'Birthday card')],
    );

    expect(find.text('Recent work'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-recent-p1')), findsOneWidget);
    expect(find.text('Birthday card'), findsAtLeastNWidgets(1));
    expect(find.byKey(const ValueKey('home-recent-new-tile')), findsOneWidget);
    expect(find.text('New'), findsOneWidget); // the dashed tile caption
  });

  testWidgets('tapping a thumb opens it; the new tile fires onCreate', (
    tester,
  ) async {
    Project? opened;
    var created = false;
    await pumpSection(
      tester,
      projects: [seed(id: 'p1', name: 'Birthday card')],
      onOpen: (p) => opened = p,
      onCreate: () => created = true,
    );

    await tester.tap(find.byKey(const ValueKey('home-recent-p1')));
    expect(opened?.id, 'p1');

    await tester.tap(find.byKey(const ValueKey('home-recent-new-tile')));
    expect(created, isTrue);
  });

  testWidgets('empty: renders nothing at all — no rail, no header', (
    tester,
  ) async {
    await pumpSection(tester, projects: const []);

    expect(find.text('Recent work'), findsNothing);
    expect(find.byType(ProjectThumb), findsNothing);
    expect(find.byKey(const ValueKey('home-recent-new-tile')), findsNothing);
  });

  testWidgets('see-all appears only past the preview limit', (tester) async {
    await pumpSection(
      tester,
      projects: [
        // Distinct timestamps so the newest-first cap is
        // deterministic: p0 newest … p8 oldest (the one cut).
        for (var i = 0; i < 9; i++)
          seed(
            id: 'p$i',
            name: 'P $i',
            ago: Duration(minutes: i + 1),
          ),
      ],
    );

    expect(find.byKey(const ValueKey('home-recent-see-all')), findsOneWidget);
    // «جدید» leads the rail (navigation doc), then the 8 newest;
    // the 9th project is cut. The rail is a lazy horizontal list,
    // so drag to the end before asserting on the tail.
    final tileX = tester
        .getTopLeft(find.byKey(const ValueKey('home-recent-new-tile')))
        .dx;
    final firstProjectX = tester
        .getTopLeft(find.byKey(const ValueKey('home-recent-p0')))
        .dx;
    expect(tileX, lessThan(firstProjectX), reason: 'tile leads in LTR');

    await tester.drag(find.byType(ListView), const Offset(-900, 0));
    await tester.pump();
    expect(find.byKey(const ValueKey('home-recent-p7')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-recent-p8')), findsNothing);
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
}
