// UX audit P3-6 (raised to P2 on device evidence): the quality cards
// printed `canvas × multiplier` while the exporter silently clamps to
// the device pixel cap — on a phone photo, two of the three cards
// stated sizes the app cannot produce (a measured 4.6× gap). The
// number on a card is a promise (§10.3): every advertised dimension
// must come from the same clamp the exporter applies.

import 'dart:async';

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/engine/export/document_png_exporter.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/export_action_sheet.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/bidi_text.dart';

Future<void> _openSheet(
  WidgetTester tester, {
  required int width,
  required int height,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container
      .read(documentControllerProvider.notifier)
      .newDocument(width: width.toDouble(), height: height.toDouble());

  late BuildContext ctx;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) {
            ctx = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    ),
  );
  await tester.pump();
  unawaited(Future.sync(() => ExportActionSheet.open(ctx)));
  // Bounded pumps — pumpAndSettle risks hanging on looping affordances.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('capped quality cards advertise the delivered size, not the '
      'multiplier arithmetic', (tester) async {
    // 6000×8000 = 48 Mpx at 1× — over every device cap this test can
    // run under, so all three cards clamp.
    await _openSheet(tester, width: 6000, height: 8000);

    final cap = DocumentPngExporter.devicePixelCap();
    final ratio = DocumentPngExporter.clampPixelRatio(
      width: 6000,
      height: 8000,
      requested: 1.0,
      maxPixels: cap,
    );
    final w = (6000 * ratio).round();
    final h = (8000 * ratio).round();

    expect(
      findBidiTextContaining('$w × $h px'),
      findsWidgets,
      reason: 'the card states the clamped output, matching the exporter',
    );
    // The header chip legitimately states the CANVAS size («Canvas
    // 6000 × 8000» — an input fact, not an output promise); only the
    // cards' output lines («… px») must never carry the unachievable
    // arithmetic.
    expect(
      findBidiTextContaining('6000 × 8000 px'),
      findsNothing,
      reason: 'no card may advertise a size the exporter will not produce',
    );
    expect(
      find.text("Capped at this device's export limit"),
      findsNWidgets(3),
      reason: 'every capped card explains why its number is lower',
    );
  });

  testWidgets('an uncapped canvas keeps the plain multiplier sizes and no '
      'cap note', (tester) async {
    await _openSheet(tester, width: 400, height: 400);

    expect(findBidiTextContaining('400 × 400 px'), findsOneWidget);
    expect(findBidiTextContaining('800 × 800 px'), findsOneWidget);
    expect(findBidiTextContaining('1200 × 1200 px'), findsOneWidget);
    expect(find.text("Capped at this device's export limit"), findsNothing);
  });
}
