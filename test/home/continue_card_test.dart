import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:canvas_engine/features/home/domain/project.dart';
import 'package:canvas_engine/features/home/presentation/widgets/continue_card.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The desk's hero slot, in both of its modes.
///
/// The draft mode inherits `ResumeDraftCard`'s contract wholesale and
/// these tests carry its pins forward: every control on screen at the
/// narrowest supported width in both directions, the destructive
/// action never reachable in the same tap-distance as the one that
/// opens the work, dismissing the menu deciding nothing.
///
/// New with the hero: a height ceiling (bigger than the old one-liner
/// on purpose, but still a ceiling the next addition has to argue
/// with), the honest-ratio preview pane, and the project mode — which
/// has no overflow at all, because managing saved projects belongs to
/// the Projects tab.
void main() {
  const kHeroHeightCeiling = 200.0;

  String docJson({double w = 1080, double h = 1080}) =>
      '{"version":1,"width":$w,"height":$h,"layers":[]}';

  Project project({double w = 1080, double h = 1080}) => Project(
    id: 'p1',
    name: 'پوستر نوروز',
    width: w,
    height: h,
    createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    lastModified: DateTime.now().subtract(const Duration(hours: 2)),
    documentJson: docJson(w: w, h: h),
  );

  Widget host(
    Widget child, {
    Brightness brightness = Brightness.light,
    Locale locale = const Locale('fa'),
    Size size = const Size(320, 640),
  }) {
    return ProviderScope(
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: MaterialApp(
          locale: locale,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(alignment: Alignment.topCenter, child: child),
          ),
        ),
      ),
    );
  }

  ContinueCard draft({
    VoidCallback? onResume,
    VoidCallback? onNotNow,
    VoidCallback? onDeleteDraft,
    String? draftName,
    String? json,
  }) => ContinueCard.draft(
    draftJson: json ?? docJson(),
    draftName: draftName,
    onResume: onResume ?? () {},
    onNotNow: onNotNow ?? () {},
    onDeleteDraft: onDeleteDraft ?? () {},
  );

  // ─────────────────────────── draft mode ───────────────────────────

  for (final locale in const [Locale('fa'), Locale('en')]) {
    for (final width in const [320.0, 360.0, 426.0]) {
      testWidgets('draft: controls stay on screen under the ceiling — '
          '${locale.languageCode} @ ${width.toInt()}dp', (tester) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          host(
            draft(draftName: 'یک نام پروژهٔ بلند برای آزمودن سرریز'),
            locale: locale,
            size: Size(width, 640),
          ),
        );
        expect(tester.takeException(), isNull);

        for (final key in const [
          ValueKey('resume-draft-resume'),
          ValueKey('resume-draft-overflow'),
        ]) {
          final rect = tester.getRect(find.byKey(key));
          expect(
            rect.left,
            greaterThanOrEqualTo(0),
            reason: '$key runs off the leading edge at ${width}dp',
          );
          expect(
            rect.right,
            lessThanOrEqualTo(width),
            reason: '$key runs off the trailing edge at ${width}dp',
          );
        }

        expect(
          tester.getSize(find.byType(ContinueCard)).height,
          lessThanOrEqualTo(kHeroHeightCeiling),
          reason: 'the hero is deliberately big, not unboundedly big',
        );
      });
    }
  }

  testWidgets('draft: both controls meet the 44dp touch floor', (tester) async {
    await tester.pumpWidget(host(draft()));
    for (final key in const [
      ValueKey('resume-draft-resume'),
      ValueKey('resume-draft-overflow'),
    ]) {
      expect(tester.getSize(find.byKey(key)).height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('draft: names the draft, and falls back when it has no name', (
    tester,
  ) async {
    await tester.pumpWidget(host(draft(draftName: 'پوستر نوروز')));
    expect(find.text('پوستر نوروز'), findsAtLeastNWidgets(1));

    await tester.pumpWidget(host(draft(), locale: const Locale('en')));
    expect(find.text('Recovered draft'), findsAtLeastNWidgets(1));
  });

  // Each brightness gets a FRESH tree. Re-pumping a new `themeMode`
  // into a live one lands mid-`AnimatedTheme` lerp, and the assertion
  // reads a colour that is neither token.
  for (final (brightness, expected) in [
    (Brightness.light, AppTokens.light.brand),
    (Brightness.dark, AppTokens.dark.brand),
  ]) {
    testWidgets('resume is a brand fill — ${brightness.name}', (tester) async {
      await tester.pumpWidget(host(draft(), brightness: brightness));
      final fill = tester.widget<Material>(
        find.descendant(
          of: find.byKey(const ValueKey('resume-draft-resume')),
          matching: find.byType(Material),
        ),
      );
      expect(fill.color, expected);
    });
  }

  testWidgets('draft: resume dispatches without opening anything', (
    tester,
  ) async {
    var resumed = 0;
    var notNow = 0;
    var deleted = 0;
    await tester.pumpWidget(
      host(
        draft(
          onResume: () => resumed++,
          onNotNow: () => notNow++,
          onDeleteDraft: () => deleted++,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('resume-draft-resume')));
    await tester.pumpAndSettle();
    expect([resumed, notNow, deleted], [1, 0, 0]);
  });

  testWidgets('draft: tapping the card body is also resume', (tester) async {
    var resumed = 0;
    await tester.pumpWidget(host(draft(onResume: () => resumed++)));
    await tester.tap(find.byKey(const ValueKey('continue-preview')));
    await tester.pumpAndSettle();
    expect(resumed, 1);
  });

  // The weight claim carried over from the old card: neither of the
  // two actions that are not Resume can be reached without
  // deliberately opening the menu.
  testWidgets('draft: neither menu action is reachable from the card', (
    tester,
  ) async {
    await tester.pumpWidget(host(draft(), locale: const Locale('en')));
    expect(find.byKey(const ValueKey('resume-draft-not-now')), findsNothing);
    expect(find.byKey(const ValueKey('resume-draft-delete')), findsNothing);
  });

  testWidgets('draft: the menu dispatches Not now', (tester) async {
    var notNow = 0;
    var deleted = 0;
    await tester.pumpWidget(
      host(draft(onNotNow: () => notNow++, onDeleteDraft: () => deleted++)),
    );
    await tester.tap(find.byKey(const ValueKey('resume-draft-overflow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('resume-draft-not-now')));
    await tester.pumpAndSettle();
    expect([notNow, deleted], [1, 0]);
  });

  testWidgets('draft: the menu dispatches Delete, painted in the error '
      'colour', (tester) async {
    var notNow = 0;
    var deleted = 0;
    await tester.pumpWidget(
      host(
        draft(onNotNow: () => notNow++, onDeleteDraft: () => deleted++),
        locale: const Locale('en'),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('resume-draft-overflow')));
    await tester.pumpAndSettle();

    final label = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('resume-draft-delete')),
        matching: find.text('Delete draft'),
      ),
    );
    expect(label.style?.color, AppTheme.light().colorScheme.error);

    await tester.tap(find.byKey(const ValueKey('resume-draft-delete')));
    await tester.pumpAndSettle();
    expect([notNow, deleted], [0, 1]);
  });

  // Dismissing the menu is not a decision. Neither callback may fire.
  testWidgets('draft: dismissing the menu leaves the offer untouched', (
    tester,
  ) async {
    var notNow = 0;
    var deleted = 0;
    await tester.pumpWidget(
      host(draft(onNotNow: () => notNow++, onDeleteDraft: () => deleted++)),
    );
    await tester.tap(find.byKey(const ValueKey('resume-draft-overflow')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(160, 40));
    await tester.pumpAndSettle();
    expect([notNow, deleted], [0, 0]);
  });

  // ────────────────────────── project mode ──────────────────────────

  testWidgets('project: shows name, relative time, and dispatches open '
      'from both the button and the card body', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      host(
        ContinueCard.project(project: project(), onOpen: () => opened++),
        locale: const Locale('en'),
      ),
    );

    expect(find.text('پوستر نوروز'), findsAtLeastNWidgets(1));
    expect(find.textContaining('ago'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-continue-open')));
    await tester.pumpAndSettle();
    expect(opened, 1);

    await tester.tap(find.byKey(const ValueKey('continue-preview')));
    await tester.pumpAndSettle();
    expect(opened, 2);
  });

  testWidgets('project: no overflow — saved-project management lives on '
      'the Projects tab', (tester) async {
    await tester.pumpWidget(
      host(ContinueCard.project(project: project(), onOpen: () {})),
    );
    expect(find.byKey(const ValueKey('resume-draft-overflow')), findsNothing);
    expect(
      tester.getSize(find.byType(ContinueCard)).height,
      lessThanOrEqualTo(kHeroHeightCeiling),
    );
  });

  // The honest-ratio pane: a square previews square, a story reads
  // tall, a widescreen thumbnail reads wide — and both extremes stop
  // at the clamp so the title column keeps its minimum width.
  for (final (name, w, h, expectedWidth) in [
    ('square', 1080.0, 1080.0, 132.0),
    ('story clamps at the narrow floor', 1080.0, 1920.0, 132 * 0.62),
    ('widescreen clamps at the wide ceiling', 1920.0, 1080.0, 132 * 1.5),
  ]) {
    testWidgets('preview ratio — $name', (tester) async {
      await tester.pumpWidget(
        host(
          ContinueCard.project(
            project: project(w: w, h: h),
            onOpen: () {},
          ),
          size: const Size(426, 640),
        ),
      );
      final size = tester.getSize(
        find.byKey(const ValueKey('continue-preview')),
      );
      expect(size.height, 132);
      expect(size.width, moreOrLessEquals(expectedWidth, epsilon: 0.01));
    });
  }

  testWidgets('draft ratio comes from the journal JSON itself', (tester) async {
    await tester.pumpWidget(
      host(
        draft(
          json:
              '{"version":1,"width":1080.0,"height":1920.0,'
              '"layers":[]}',
        ),
      ),
    );
    final size = tester.getSize(find.byKey(const ValueKey('continue-preview')));
    expect(size.width, moreOrLessEquals(132 * 0.62, epsilon: 0.01));
  });
}
