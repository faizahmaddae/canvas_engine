// The disclosure caret has to end up pointing DOWN when open, in both
// reading directions.
//
// It is the drill-in caret, which mirrors under RTL — so the closed
// state points right in English and LEFT in Persian. A fixed +0.25
// turn only reaches "down" from the right-pointing state; from the
// left-pointing one it lands on UP, and an expanded section sat there
// claiming to be collapsed. Caught by an icon audit, confirmed on
// device.

import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/features/editor/ui/precision_disclosure.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PrecisionDisclosure(
            titleClosed: 'more',
            children: const [SizedBox(height: 40, child: Text('body'))],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double turnsOf(WidgetTester tester) =>
      tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns;

  testWidgets('the open turn reverses with the reading direction', (
    tester,
  ) async {
    // Unit check on the shared helper — both call sites route through
    // it, so neither can drift from the other.
    for (final (direction, expected) in const [
      (TextDirection.ltr, 0.25),
      (TextDirection.rtl, -0.25),
    ]) {
      late double turns;
      await tester.pumpWidget(
        Directionality(
          textDirection: direction,
          child: Builder(
            builder: (context) {
              turns = disclosureOpenTurns(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(
        turns,
        expected,
        reason: 'a $direction caret must turn $expected to face down',
      );
    }
  });

  testWidgets('closed is unrotated in both directions', (tester) async {
    for (final locale in const [Locale('en'), Locale('fa')]) {
      await pump(tester, locale);
      expect(turnsOf(tester), 0);
    }
  });

  testWidgets('open turns clockwise under LTR', (tester) async {
    await pump(tester, const Locale('en'));
    await tester.tap(find.text('more'));
    await tester.pumpAndSettle();
    expect(turnsOf(tester), 0.25);
  });

  testWidgets('open turns ANTI-clockwise under RTL', (tester) async {
    await pump(tester, const Locale('fa'));
    await tester.tap(find.text('more'));
    await tester.pumpAndSettle();
    expect(
      turnsOf(tester),
      -0.25,
      reason: 'the mirrored caret points left, so +0.25 would face UP',
    );
  });
}
