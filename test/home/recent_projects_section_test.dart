import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/temp_projects_dir.dart';

import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:canvas_engine/features/home/application/project_store.dart';
import 'package:canvas_engine/features/home/domain/project.dart';
import 'package:canvas_engine/features/home/presentation/widgets/project_thumb.dart';
import 'package:canvas_engine/features/home/presentation/widgets/recent_projects_grid.dart';

import '../support/bidi_text.dart';

Project _seed({
  required String id,
  required String name,
  double w = 1080,
  double h = 1080,
  Duration ago = const Duration(minutes: 5),
  String documentJson = '{}',
}) {
  final t = DateTime.now().subtract(ago);
  return Project(
    id: id,
    name: name,
    width: w,
    height: h,
    createdAt: t,
    lastModified: t,
    documentJson: documentJson,
  );
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required List<Project> projects,
  Brightness brightness = Brightness.light,
}) async {
  SharedPreferences.setMockInitialValues({});
  final dir = tempProjectsDir();
  final container = ProviderContainer(
    overrides: [projectsDirectoryProvider.overrideWith((ref) async => dir)],
  );
  addTearDown(container.dispose);
  // Hydrate the store BEFORE first frame so the section renders the
  // grid (not the skeleton) on first pump. Real file IO — must run
  // outside the fake-async test zone (see temp_projects_dir.dart).
  await tester.runAsync(() async {
    await container.read(projectStoreProvider.future);
    for (final p in projects) {
      await container.read(projectStoreProvider.notifier).upsert(p);
    }
  });

  // The metadata line is measured, not ellipsised (a clipped `W ×`
  // reads as a different canvas), so the card drops the relative time
  // when the pair plus the time will not fit. The test font is a
  // fixed-width stand-in that measures far wider than Vazir does on a
  // device, so at the default 800dp surface these cards would report
  // "no room" for something that fits comfortably in the product.
  // Give the grid the width it needs to exercise the both-facts case.
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecentProjectsGrid(onCreate: () {}, onOpen: (_) {}),
          ),
        ),
      ),
    ),
  );
  // One extra frame to settle the AnimatedScale on cards.
  await tester.pump();
}

void main() {
  testWidgets('card shows name, canvas size, and relative time', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      projects: [_seed(id: 'p1', name: 'Birthday card', w: 1080, h: 1080)],
    );

    expect(find.text('Birthday card'), findsOneWidget);
    // Size + relative time live on the same metadata line.
    expect(
      findBidiTextContaining('1080 \u00D7 1080'),
      findsOneWidget,
      reason: 'card should display canvas dimensions',
    );
    expect(
      find.textContaining('ago'),
      findsOneWidget,
      reason: 'card should display relative last-modified time',
    );
  });

  testWidgets('non-integer dimensions render with one decimal', (tester) async {
    await _pumpHome(
      tester,
      projects: [_seed(id: 'p1', name: 'Imported', w: 1234.5, h: 800)],
    );
    expect(findBidiTextContaining('1234.5 \u00D7 800'), findsOneWidget);
  });

  testWidgets('empty state shows the create CTA', (tester) async {
    var created = 0;
    SharedPreferences.setMockInitialValues({});
    final dir = tempProjectsDir();
    final container = ProviderContainer(
      overrides: [projectsDirectoryProvider.overrideWith((ref) async => dir)],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(projectStoreProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: RecentProjectsGrid(onCreate: () => created++, onOpen: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('No projects yet'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    expect(created, 1);
  });

  testWidgets('v2: card is a flat surface tile with a hairline border', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      projects: [_seed(id: 'p1', name: 'Birthday card')],
    );

    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(ProjectCard),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, AppTokens.light.surface);
    expect(material.elevation, 0);

    final ink = tester.widget<Ink>(
      find
          .descendant(of: find.byType(ProjectCard), matching: find.byType(Ink))
          .first,
    );
    final border = (ink.decoration! as BoxDecoration).border! as Border;
    expect(border.top.color, AppTokens.light.border);
  });

  testWidgets('empty design shows the diamond+name placeholder, never a '
      'blank thumbnail', (tester) async {
    await _pumpHome(
      tester,
      projects: [
        _seed(id: 'empty', name: 'Fresh start', documentJson: '{"layers":[]}'),
        _seed(id: 'plain', name: 'Untitled', ago: const Duration(minutes: 9)),
      ],
    );

    // The empty design renders the shared placeholder inside its
    // grid card; the non-empty one does not.
    final placeholders = find.byType(EmptyDesignPlaceholder);
    expect(placeholders, findsOneWidget);
    expect(
      find.descendant(of: placeholders, matching: find.text('Fresh start')),
      findsOneWidget,
    );
  });

  testWidgets('v2: dark mode renders ink tokens without throwing', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      projects: [_seed(id: 'p1', name: 'Birthday card')],
      brightness: Brightness.dark,
    );
    expect(tester.takeException(), isNull);

    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(ProjectCard),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, AppTokens.dark.surface);
  });
}
