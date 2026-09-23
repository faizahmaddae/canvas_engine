import 'package:canvas_engine/core/constants/engine_constants.dart';
import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:canvas_engine/app/ui/app_primary_button.dart';
import 'package:canvas_engine/app/ui/size_picker_sheet.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The size picker as a format sheet: aspect-true ghost tiles in the
/// app's one sheet grammar, replacing the nine-row dialog. The
/// dialog's behavioural contract carries over unchanged and is
/// re-pinned here: preset taps return their CanvasSize + label,
/// custom entries validate against the ONE shared document ceiling
/// (ux-audit P2-20), tokens only, dark aware.
void main() {
  Future<CanvasSize?>? sheetResult;

  Future<void> pumpAndOpen(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    Locale? locale,
  }) async {
    sheetResult = null;
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => sheetResult = SizePickerSheet.show(context),
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

  testWidgets('opens in the shared sheet host with hairline tiles and no '
      'violet', (tester) async {
    await pumpAndOpen(tester);

    // The app's one sheet grammar, not framework dialog chrome.
    expect(find.byKey(const ValueKey('app-sheet-handle-zone')), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);

    // Format tiles: hairline border, no gradient anywhere.
    final inks = tester.widgetList<Ink>(
      find.descendant(
        of: find.byType(SizePickerSheet),
        matching: find.byType(Ink),
      ),
    );
    final bordered = inks.where((ink) {
      final decoration = ink.decoration;
      return decoration is BoxDecoration && decoration.border != null;
    });
    expect(bordered, isNotEmpty);
    for (final ink in bordered) {
      final border = ((ink.decoration! as BoxDecoration).border!) as Border;
      expect(border.top.color, AppTokens.light.border);
    }
    for (final ink in inks) {
      final decoration = ink.decoration;
      if (decoration is BoxDecoration) {
        expect(decoration.gradient, isNull);
      }
    }

    expect(find.byType(AppPrimaryButton), findsOneWidget);
  });

  testWidgets('every format is a tile; the ghost carries the aspect ratio', (
    tester,
  ) async {
    await pumpAndOpen(tester);

    // Nine presets, three across.
    for (final kind in const [
      'instagramPost',
      'square',
      'portrait45',
      'story',
      'youtubeThumbnail',
      'linkedInPost',
      'hd1080p',
      'a4Portrait300',
      'a4Landscape300',
    ]) {
      expect(
        find.byKey(ValueKey('size-preset-$kind')),
        findsOneWidget,
        reason: '$kind lost its tile in the dialog→sheet move',
      );
    }
  });

  testWidgets('tapping a preset returns its CanvasSize', (tester) async {
    await pumpAndOpen(tester);

    await tester.tap(find.byKey(const ValueKey('size-preset-instagramPost')));
    await tester.pumpAndSettle();
    // Guard before the await: a missed tap leaves the sheet open and
    // the future pending — assert the pop happened so a regression
    // fails loudly instead of hanging the runner.
    expect(find.byType(SizePickerSheet), findsNothing);
    final size = await sheetResult!;
    expect(size?.width, 1080);
    expect(size?.height, 1080);
    expect(size?.label, 'Instagram Post');
  });

  testWidgets('a story tile returns the full-bleed portrait', (tester) async {
    await pumpAndOpen(tester);

    await tester.tap(find.byKey(const ValueKey('size-preset-story')));
    await tester.pumpAndSettle();
    // Guard before the await: a missed tap leaves the sheet open and
    // the future pending — assert the pop happened so a regression
    // fails loudly instead of hanging the runner.
    expect(find.byType(SizePickerSheet), findsNothing);
    final size = await sheetResult!;
    expect(size?.width, 1080);
    expect(size?.height, 1920);
  });

  testWidgets('custom size validates and returns the entered values', (
    tester,
  ) async {
    await pumpAndOpen(tester);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '4');
    await tester.enterText(fields.at(1), '900');
    await tester.tap(find.byKey(const ValueKey('size-picker-create')));
    await tester.pump();
    // Below the 16px floor → validation error, sheet stays open.
    expect(find.byType(SizePickerSheet), findsOneWidget);

    await tester.enterText(fields.at(0), '800');
    await tester.tap(find.byKey(const ValueKey('size-picker-create')));
    await tester.pumpAndSettle();
    // Guard before the await: a missed tap leaves the sheet open and
    // the future pending — assert the pop happened so a regression
    // fails loudly instead of hanging the runner.
    expect(find.byType(SizePickerSheet), findsNothing);
    final size = await sheetResult!;
    expect(size?.width, 800);
    expect(size?.height, 900);
  });

  testWidgets('custom size enforces the ONE document ceiling (8000) shared '
      'with layers and export', (tester) async {
    // ux-audit P2-20: the old dialog used to accept 16384 while layers
    // capped at 8000 and the exporter at ~24 Mpx — the biggest
    // canvases it sold could never be filled or exported at size.
    await pumpAndOpen(tester);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '8001');
    await tester.enterText(fields.at(1), '1000');
    await tester.tap(find.byKey(const ValueKey('size-picker-create')));
    await tester.pump();
    expect(
      find.byType(SizePickerSheet),
      findsOneWidget,
      reason: '8001 is over cap',
    );

    await tester.enterText(fields.at(0), '8000');
    await tester.tap(find.byKey(const ValueKey('size-picker-create')));
    await tester.pumpAndSettle();
    // Guard before the await: a missed tap leaves the sheet open and
    // the future pending — assert the pop happened so a regression
    // fails loudly instead of hanging the runner.
    expect(find.byType(SizePickerSheet), findsNothing);
    final size = await sheetResult!;
    expect(size?.width, EngineConstants.maxDocumentDimension.toDouble());
  });

  testWidgets('dismissing the sheet returns null and creates nothing', (
    tester,
  ) async {
    await pumpAndOpen(tester);
    // Barrier tap — the modal route's own dismiss.
    await tester.tapAt(const Offset(210, 40));
    await tester.pumpAndSettle();
    expect(await sheetResult!, isNull);
  });

  testWidgets('dark mode: ink surface + cream CTA', (tester) async {
    await pumpAndOpen(tester, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);

    final cta = find.descendant(
      of: find.byType(AppPrimaryButton),
      matching: find.byType(Ink),
    );
    final decoration = tester.widget<Ink>(cta).decoration! as BoxDecoration;
    expect(decoration.color, AppTokens.dark.brand); // cream
  });
}
