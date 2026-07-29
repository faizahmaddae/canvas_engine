import 'package:canvas_engine/app/navigation/nav_shell.dart';
import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:canvas_engine/app/ui/bottom_tab_bar.dart';
import 'package:canvas_engine/features/home/application/project_store.dart';
import 'package:canvas_engine/features/home/presentation/home_screen.dart';
import 'package:canvas_engine/features/home/presentation/widgets/recent_projects_grid.dart';
import 'package:canvas_engine/features/templates/presentation/templates_browse_screen.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/temp_projects_dir.dart';
import 'package:canvas_engine/app/theme/app_icons.dart';

/// Navigation doc commit 1: the root NavShell hosts Home + the two
/// existing browser screens behind a v2 BottomTabBar.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
  }) async {
    final dir = tempProjectsDir();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [projectsDirectoryProvider.overrideWith((ref) async => dir)],
        child: MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const NavShell(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('starts on Home with three tabs', (tester) async {
    await pump(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(BottomTabBar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Templates'), findsAtLeastNWidgets(1));
    expect(find.text('Projects'), findsOneWidget);
  });

  testWidgets('tapping tabs switches the visible screen', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Projects'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // IndexedStack keeps Home mounted; assert on the visible layer.
    expect(find.byType(RecentProjectsGrid, skipOffstage: true), findsOneWidget);

    await tester.tap(find.text('Templates').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byType(TemplatesBrowseScreen, skipOffstage: true),
      findsOneWidget,
    );

    await tester.tap(find.text('Home'));
    await tester.pump();
    expect(find.byType(HomeScreen, skipOffstage: true), findsOneWidget);
  });

  testWidgets('active tab shows the saffron icon; inactive stays muted', (
    tester,
  ) async {
    await pump(tester);

    final activeIcon = tester.widget<Icon>(find.byIcon(AppIcons.homeTab));
    // accentText, not accent: the fill saffron measured 2.69:1 on the
    // tab bar and this glyph is the only cue for which tab is active.
    expect(activeIcon.color, AppTokens.light.accentText);

    final inactiveIcon = tester.widget<Icon>(find.byIcon(AppIcons.projectsTab));
    expect(inactiveIcon.color, AppTokens.light.textMuted);
  });

  testWidgets('dark mode: tab bar flips to ink with brighter saffron', (
    tester,
  ) async {
    await pump(tester, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);

    final bar = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(BottomTabBar),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final decoration = bar.decoration as BoxDecoration;
    expect(decoration.color, AppTokens.dark.pageBg);

    final activeIcon = tester.widget<Icon>(find.byIcon(AppIcons.homeTab));
    expect(activeIcon.color, AppTokens.dark.accent);
  });
}
