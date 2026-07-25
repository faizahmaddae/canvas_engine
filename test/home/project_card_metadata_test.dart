// The project card's metadata line — canvas size + relative time —
// carried a private copy of the `W × H` composer, so it reproduced
// the reversal commit 612dd38 fixed in the canonical formatter: a
// 1080 × 1350 portrait project announced itself as `1350 × 1080` on
// its own card. It also put both facts in one ellipsised `Text`, so
// on a narrow phone the time was the part that got cut.

import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/features/home/domain/project.dart';
import 'package:canvas_engine/features/home/presentation/widgets/recent_projects_grid.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/bidi_text.dart';

void main() {
  Project project({double width = 1080, double height = 1350}) {
    final now = DateTime(2026, 7, 25, 12);
    return Project(
      id: 'p1',
      name: 'طرح بی‌نام',
      width: width,
      height: height,
      createdAt: now,
      lastModified: now,
      documentJson: '{}',
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    required Project p,
    Locale locale = const Locale('fa'),
    double width = 426,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: locale,
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: ProjectCard(project: p, onOpen: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Every `Text` on the card, joined — the metadata is split across
  /// widgets now, so a single `find.text` would miss it.
  String allText(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .join('|');

  testWidgets('the dimension pair is isolated, so RTL cannot reverse it', (
    tester,
  ) async {
    await pump(tester, p: project());
    final text = allText(tester);

    expect(
      text.contains(kLri),
      isTrue,
      reason: 'the pair must be wrapped in LRI…PDI or bidi will swap it',
    );
    final stripped = stripBidi(text);
    expect(stripped, contains('۱۰۸۰ × ۱۳۵۰'));
    expect(
      stripped.indexOf('۱۰۸۰'),
      lessThan(stripped.indexOf('۱۳۵۰')),
      reason: 'width precedes height',
    );
  });

  testWidgets('digits follow the locale', (tester) async {
    await pump(tester, p: project(), locale: const Locale('en'));
    expect(stripBidi(allText(tester)), contains('1080 × 1350'));
  });

  testWidgets('a fractional size still drops its trailing .0', (tester) async {
    await pump(tester, p: project(width: 1080, height: 1350.5));
    final stripped = stripBidi(allText(tester));
    expect(stripped, contains('۱۰۸۰ × ۱۳۵۰٫۵'));
    expect(stripped, isNot(contains('۱۰۸۰٫۰')));
  });

  testWidgets('the size survives narrow widths — the TIME is dropped', (
    tester,
  ) async {
    // One ellipsised string cut whichever fact came last; making only
    // the time flexible silently clipped the HEIGHT off the pair, and
    // «۱۰۸۰ ×» reads as a different canvas. Whole-or-absent, never
    // half: the size always survives, the time is appended only when
    // there is room for all of it.
    await pump(tester, p: project(width: 1920, height: 1080), width: 200);
    expect(tester.takeException(), isNull);

    final stripped = stripBidi(allText(tester));
    expect(stripped, contains('۱۹۲۰ × ۱۰۸۰'));
    expect(
      stripped,
      isNot(contains('·')),
      reason: 'the separator only appears when the time came with it',
    );
  });

  testWidgets('a wide card keeps BOTH facts', (tester) async {
    await pump(tester, p: project(width: 1080, height: 1350), width: 560);
    final stripped = stripBidi(allText(tester));
    expect(stripped, contains('۱۰۸۰ × ۱۳۵۰'));
    expect(stripped, contains('·'));
  });

  testWidgets('the dimension pair is never truncated', (tester) async {
    // The specific regression: at a width where the full line does not
    // fit, the pair must be complete rather than cut after the «×».
    for (final width in const [140.0, 180.0, 240.0, 320.0]) {
      await pump(tester, p: project(width: 2480, height: 3508), width: width);
      final stripped = stripBidi(allText(tester));
      expect(
        stripped,
        contains('۲۴۸۰ × ۳۵۰۸'),
        reason: 'half a number pair at ${width}dp reads as a wrong canvas',
      );
    }
  });
}
