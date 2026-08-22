// Every numeric text field in a Persian-first app has two duties the
// app used to fail: seed itself with the digits the rest of the UI is
// using, and PARSE the digits a Persian keyboard produces. Seeding
// Latin was cosmetic; failing to parse ۸۰۰ was not — the field showed
// what the user typed and the dialog rejected it as empty.

import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/ui/size_picker_sheet.dart';
import 'package:canvas_engine/core/utils/editor_value_format.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('toAsciiDigits', () {
    test('folds the Persian block a Persian keyboard produces', () {
      expect(EditorValueFormat.toAsciiDigits('۸۰۰'), '800');
      expect(double.tryParse(EditorValueFormat.toAsciiDigits('۸۰۰')), 800);
    });

    test('folds the Arabic block too', () {
      expect(EditorValueFormat.toAsciiDigits('٨٠٠'), '800');
    });

    test('folds the Arabic decimal separator', () {
      expect(EditorValueFormat.toAsciiDigits('۲٫۵'), '2.5');
      expect(double.tryParse(EditorValueFormat.toAsciiDigits('۲٫۵')), 2.5);
    });

    test('leaves ASCII alone so an en user is unaffected', () {
      expect(EditorValueFormat.toAsciiDigits('1080'), '1080');
    });

    test('this is the exact input `double.tryParse` chokes on', () {
      // The regression in one line: without the fold, the parse that
      // gates the Create button returns null for what the user sees.
      expect(double.tryParse('۸۰۰'), isNull);
    });
  });

  group('SizePickerSheet custom fields', () {
    Future<void> openCustom(WidgetTester tester, Locale locale) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => SizePickerSheet.show(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('seed with Persian digits under fa', (tester) async {
      await openCustom(tester, const Locale('fa'));
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields, isNotEmpty);
      for (final f in fields) {
        expect(
          f.controller!.text,
          matches(RegExp(r'^[۰-۹]+$')),
          reason: 'the preset list above these boxes reads «۱۰۸۰ × ۱۳۵۰»',
        );
      }
    });

    testWidgets('seed with ASCII digits under en', (tester) async {
      await openCustom(tester, const Locale('en'));
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      for (final f in fields) {
        expect(f.controller!.text, matches(RegExp(r'^[0-9]+$')));
      }
    });

    testWidgets('accepts Persian numerals typed into the fields', (
      tester,
    ) async {
      await openCustom(tester, const Locale('fa'));
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '۸۰۰');
      await tester.enterText(fields.at(1), '۶۰۰');
      await tester.tap(find.byKey(const ValueKey('size-picker-create')));
      await tester.pumpAndSettle();

      // Accepted → the sheet closed. Before the fold it stayed open
      // with a validation error against input it had just rendered.
      expect(find.byType(SizePickerSheet), findsNothing);
    });
  });
}
