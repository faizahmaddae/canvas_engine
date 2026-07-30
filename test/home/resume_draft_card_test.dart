import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:canvas_engine/features/home/presentation/widgets/resume_draft_card.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The draft-resume offer used to be a raw `MaterialBanner` whose
/// `OverflowBar` pushed the primary action off the left edge under
/// RTL — a Persian user saw a clipped «ادام» where «ادامه» belonged.
/// These tests pin the two properties that failure violated: both
/// actions stay fully on screen at the narrowest supported width in
/// both directions, and the card paints from tokens rather than
/// Material defaults.
void main() {
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
  }) => ResumeDraftCard(
    onResume: onResume ?? () {},
    onNotNow: onNotNow ?? () {},
    onDeleteDraft: onDeleteDraft ?? () {},
  );

  for (final locale in const [Locale('fa'), Locale('en')]) {
    for (final width in const [320.0, 360.0, 426.0]) {
      testWidgets(
        'both actions stay fully on screen — ${locale.languageCode} @ ${width.toInt()}dp',
        (tester) async {
          tester.view.physicalSize = Size(width, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            host(card(), locale: locale, size: Size(width, 640)),
          );
          expect(tester.takeException(), isNull);

          for (final key in const [
            ValueKey('resume-draft-delete'),
            ValueKey('resume-draft-not-now'),
            ValueKey('resume-draft-resume'),
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

          // Both fit on ONE line: a `Container` with an `alignment`
          // expands to fill, which silently pushed each action onto its
          // own run of the `Wrap` and doubled the card's height.
          expect(
            tester
                .getRect(find.byKey(const ValueKey('resume-draft-not-now')))
                .top,
            tester
                .getRect(find.byKey(const ValueKey('resume-draft-resume')))
                .top,
            reason: 'the safe pair should share a single run',
          );
        },
      );
    }
  }

  testWidgets('actions meet the 44dp touch floor', (tester) async {
    await tester.pumpWidget(host(card()));
    for (final key in const [
      ValueKey('resume-draft-delete'),
      ValueKey('resume-draft-not-now'),
      ValueKey('resume-draft-resume'),
    ]) {
      expect(tester.getSize(find.byKey(key)).height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('the primary action is a brand fill, the secondary is not', (
    tester,
  ) async {
    await tester.pumpWidget(host(card()));
    final resume = tester.widget<Material>(
      find.descendant(
        of: find.byKey(const ValueKey('resume-draft-resume')),
        matching: find.byType(Material),
      ),
    );
    expect(resume.color, AppTokens.light.brand);

    for (final key in const [
      ValueKey('resume-draft-not-now'),
      ValueKey('resume-draft-delete'),
    ]) {
      final secondary = tester.widget<Material>(
        find.descendant(of: find.byKey(key), matching: find.byType(Material)),
      );
      expect(secondary.color, Colors.transparent);
    }
  });

  testWidgets('brand fill flips with the theme', (tester) async {
    await tester.pumpWidget(host(card(), brightness: Brightness.dark));
    final resume = tester.widget<Material>(
      find.descendant(
        of: find.byKey(const ValueKey('resume-draft-resume')),
        matching: find.byType(Material),
      ),
    );
    expect(resume.color, AppTokens.dark.brand);
    expect(AppTokens.dark.brand, isNot(AppTokens.light.brand));
  });

  testWidgets('each action dispatches its own callback', (tester) async {
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
    await tester.pump();
    expect([resumed, notNow, deleted], [1, 0, 0]);

    await tester.tap(find.byKey(const ValueKey('resume-draft-not-now')));
    await tester.pump();
    expect([resumed, notNow, deleted], [1, 1, 0]);

    await tester.tap(find.byKey(const ValueKey('resume-draft-delete')));
    await tester.pump();
    expect([resumed, notNow, deleted], [1, 1, 1]);
  });

  // The point of the redesign: the one action that destroys work must
  // not read as a peer of the two that don't. It is held on the
  // opposite end of the row and painted in the error colour, so
  // reaching for Resume cannot land on it.
  testWidgets('the destructive action is separated and error-coloured', (
    tester,
  ) async {
    await tester.pumpWidget(host(card(), locale: const Locale('en')));
    final delete = tester.getRect(
      find.byKey(const ValueKey('resume-draft-delete')),
    );
    final resume = tester.getRect(
      find.byKey(const ValueKey('resume-draft-resume')),
    );
    expect(
      delete.top,
      greaterThanOrEqualTo(resume.bottom),
      reason: 'Delete draft must sit on its own row, below the safe pair',
    );

    final label = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('resume-draft-delete')),
        matching: find.byType(Text),
      ),
    );
    final scheme = AppTheme.light().colorScheme;
    expect(label.style?.color, scheme.error);
  });
}
