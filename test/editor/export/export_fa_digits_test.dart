// Roadmap tb4 4.8 — Persian parity in the export surfaces.
//
// fa is the product default, and every other editor readout already
// goes through [EditorValueFormat]. The export flow was the last place
// still printing Latin digits inside Persian sentences: the ICU
// placeholders were typed `int`, so `1080` was interpolated verbatim
// into «بوم …». Digits now arrive pre-formatted (the arb strings keep
// the units — `٪`, `px` — so meaning is untouched, only the numerals
// change).

import 'dart:async';
import 'dart:typed_data';

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/export_format.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/export_action_sheet.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/export_preview_screen.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../support/bidi_text.dart';

// 1×1 transparent PNG so the preview's decoder has real bytes.
final Uint8List _tinyPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, // IDAT
  0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, // IEND
  0x42, 0x60, 0x82,
]);

Widget _app(Widget home, {String locale = 'fa'}) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: Locale(locale),
    home: home,
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('export preview — fa numerals', () {
    testWidgets('the size read-out uses Persian digits', (tester) async {
      await tester.pumpWidget(
        _app(
          ExportPreviewScreen(
            bytes: _tinyPng,
            format: ExportFormat.png,
            pixelWidth: 1080,
            pixelHeight: 720,
          ),
        ),
      );
      await tester.pump();
      expect(findBidiText('۱۰۸۰ × ۷۲۰'), findsOneWidget);
      expect(findBidiText('1080 × 720'), findsNothing);
    });

    testWidgets('the quality chip uses Persian digits and ٪', (tester) async {
      await tester.pumpWidget(
        _app(
          ExportPreviewScreen(
            bytes: _tinyPng,
            format: ExportFormat.jpg,
            pixelWidth: 1080,
            pixelHeight: 1080,
            jpgQuality: 0.85,
          ),
        ),
      );
      await tester.pump();
      // The arb string owns the `٪`; only the digits are formatted, so
      // the sign must appear exactly once.
      expect(find.text('کیفیت ۸۵٪'), findsOneWidget);
    });

    testWidgets('en is unchanged (ASCII digits, %)', (tester) async {
      await tester.pumpWidget(
        _app(
          ExportPreviewScreen(
            bytes: _tinyPng,
            format: ExportFormat.jpg,
            pixelWidth: 1080,
            pixelHeight: 720,
            jpgQuality: 0.85,
          ),
          locale: 'en',
        ),
      );
      await tester.pump();
      expect(findBidiText('1080 × 720'), findsOneWidget);
      expect(find.text('Quality 85%'), findsOneWidget);
    });
  });

  group('export sheet — fa numerals', () {
    testWidgets('canvas chip and quality cards use Persian digits', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(documentControllerProvider.notifier)
          .newDocument(width: 1080, height: 1080);

      late BuildContext ctx;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('fa'),
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
      // Bounded pumps — `pumpAndSettle` risks hanging on the sheet's
      // looping progress affordances.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Header chip: «بوم ۱۰۸۰ × ۱۰۸۰».
      expect(findBidiText('بوم ۱۰۸۰ × ۱۰۸۰'), findsOneWidget);
      // Quality cards: the 1×/2×/3× badges and their output sizes.
      expect(findBidiText('۱×'), findsOneWidget);
      expect(findBidiText('۱۰۸۰ × ۱۰۸۰ px'), findsOneWidget);
      expect(findBidiText('۲۱۶۰ × ۲۱۶۰ px'), findsOneWidget);
      // No Latin-digit leftovers anywhere in the sheet.
      expect(find.textContaining('1080'), findsNothing);
    });

    testWidgets('the custom-size dialog seeds and parses Persian digits', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(documentControllerProvider.notifier)
          .newDocument(width: 1080, height: 1080);

      late BuildContext ctx;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('fa'),
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('سفارشی'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Seeded with locale digits, not `1080`.
      expect(find.text('۱۰۸۰'), findsNWidgets(2));

      // Committing must parse those very digits back — a plain
      // `int.tryParse` would reject them and show the validation error.
      await tester.tap(find.text('استفاده از اندازه'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('عددهای صحیح و مثبت وارد کنید.'), findsNothing);
      expect(findBidiText('سفارشی · ۱۰۸۰ × ۱۰۸۰'), findsOneWidget);
    });
  });
}
