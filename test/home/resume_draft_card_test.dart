import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:canvas_engine/features/home/presentation/widgets/resume_draft_card.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The offer has failed twice in the same two ways, and these tests
/// pin both.
///
/// Layout: a `MaterialBanner`'s `OverflowBar` once pushed the primary
/// action off the leading edge under RTL, so a Persian user saw a
/// clipped «ادام». Every control still has to sit fully on screen at
/// the narrowest supported width, in both directions.
///
/// Height: the card that fixed the clipping spent three stacked rows
/// doing it — ~185dp on a launcher whose stated invariant is that its
/// height does not grow with content. The row form is pinned under a
/// ceiling here so the next well-meaning addition has to argue with a
/// failing test.
///
/// Weight: the action that destroys the only copy of unsaved work must
/// never be reachable in the same tap-distance as the one that opens
/// it. It is not on the card at all.
void main() {
  const kCardHeightCeiling = 84.0;

  Widget host(
    Widget child, {
    Brightness brightness = Brightness.light,
    Locale locale = const Locale('fa'),
    Size size = const Size(320, 640),
  }) {
    return MediaQuery(
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
    );
  }

  ResumeDraftCard card({
    VoidCallback? onResume,
    VoidCallback? onNotNow,
    VoidCallback? onDeleteDraft,
    String? draftName,
  }) => ResumeDraftCard(
    onResume: onResume ?? () {},
    onNotNow: onNotNow ?? () {},
    onDeleteDraft: onDeleteDraft ?? () {},
    draftName: draftName,
  );

  for (final locale in const [Locale('fa'), Locale('en')]) {
    for (final width in const [320.0, 360.0, 426.0]) {
      testWidgets('controls stay on screen and the row stays short — '
          '${locale.languageCode} @ ${width.toInt()}dp', (tester) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          host(
            card(draftName: 'یک نام پروژهٔ بلند برای آزمودن سرریز'),
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

        // One row, not three. A long name has to ellipsise rather
        // than wrap the card taller.
        expect(
          tester.getSize(find.byType(ResumeDraftCard)).height,
          lessThanOrEqualTo(kCardHeightCeiling),
          reason: 'the offer must not grow the launcher',
        );
      });
    }
  }

  testWidgets('both controls meet the 44dp touch floor', (tester) async {
    await tester.pumpWidget(host(card()));
    for (final key in const [
      ValueKey('resume-draft-resume'),
      ValueKey('resume-draft-overflow'),
    ]) {
      expect(tester.getSize(find.byKey(key)).height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('names the draft, and falls back when it has no name', (
    tester,
  ) async {
    await tester.pumpWidget(host(card(draftName: 'پوستر نوروز')));
    expect(find.text('پوستر نوروز'), findsOneWidget);

    await tester.pumpWidget(host(card(), locale: const Locale('en')));
    expect(find.text('Recovered draft'), findsOneWidget);
  });

  // Each brightness gets a FRESH tree. Re-pumping a new `themeMode`
  // into a live one lands mid-`AnimatedTheme` lerp, and the assertion
  // reads a colour that is neither token.
  for (final (brightness, expected) in [
    (Brightness.light, AppTokens.light.brand),
    (Brightness.dark, AppTokens.dark.brand),
  ]) {
    testWidgets('resume is a brand fill — ${brightness.name}', (tester) async {
      await tester.pumpWidget(host(card(), brightness: brightness));
      final fill = tester.widget<Material>(
        find.descendant(
          of: find.byKey(const ValueKey('resume-draft-resume')),
          matching: find.byType(Material),
        ),
      );
      expect(fill.color, expected);
    });
  }

  test('the brand token actually differs across modes', () {
    expect(AppTokens.dark.brand, isNot(AppTokens.light.brand));
  });

  testWidgets('resume dispatches without opening anything', (tester) async {
    var resumed = 0;
    var notNow = 0;
    var deleted = 0;
    await tester.pumpWidget(
      host(
        card(
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

  // The compression's whole claim: neither of the two actions that are
  // not Resume can be reached without deliberately opening the menu.
  testWidgets('neither menu action is reachable from the card itself', (
    tester,
  ) async {
    await tester.pumpWidget(host(card(), locale: const Locale('en')));
    expect(find.byKey(const ValueKey('resume-draft-not-now')), findsNothing);
    expect(find.byKey(const ValueKey('resume-draft-delete')), findsNothing);
  });

  testWidgets('the menu dispatches Not now', (tester) async {
    var notNow = 0;
    var deleted = 0;
    await tester.pumpWidget(
      host(card(onNotNow: () => notNow++, onDeleteDraft: () => deleted++)),
    );
    await tester.tap(find.byKey(const ValueKey('resume-draft-overflow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('resume-draft-not-now')));
    await tester.pumpAndSettle();
    expect([notNow, deleted], [1, 0]);
  });

  testWidgets('the menu dispatches Delete, painted in the error colour', (
    tester,
  ) async {
    var notNow = 0;
    var deleted = 0;
    await tester.pumpWidget(
      host(
        card(onNotNow: () => notNow++, onDeleteDraft: () => deleted++),
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
  testWidgets('dismissing the menu leaves the offer untouched', (tester) async {
    var notNow = 0;
    var deleted = 0;
    await tester.pumpWidget(
      host(card(onNotNow: () => notNow++, onDeleteDraft: () => deleted++)),
    );
    await tester.tap(find.byKey(const ValueKey('resume-draft-overflow')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(160, 40));
    await tester.pumpAndSettle();
    expect([notNow, deleted], [0, 0]);
  });
}
