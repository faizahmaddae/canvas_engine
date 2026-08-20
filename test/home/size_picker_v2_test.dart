import 'package:canvas_engine/core/constants/engine_constants.dart';
import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:canvas_engine/app/ui/app_primary_button.dart';
import 'package:canvas_engine/app/ui/size_picker_dialog.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:canvas_engine/app/theme/app_icons.dart';

/// v2 restyle of the canvas-size sheet: tokens only (no violet),
/// AppPrimaryButton CTA, hairline preset rows, RTL chevron, dark
/// aware. All preset + custom-size logic unchanged.
void main() {
  Future<CanvasSize?>? dialogResult;

  Future<void> pumpAndOpen(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    Locale? locale,
  }) async {
    dialogResult = null;
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
                onPressed: () => dialogResult = SizePickerDialog.show(context),
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

  testWidgets('renders on surface with hairline preset rows and no violet', (
    tester,
  ) async {
    await pumpAndOpen(tester);

    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    expect(dialog.backgroundColor, AppTokens.light.surface);

    // Preset rows: hairline border, no gradient icon well.
    final inks = tester.widgetList<Ink>(
      find.descendant(of: find.byType(Dialog), matching: find.byType(Ink)),
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
    // No gradient anywhere in the sheet (the old violet icon wells).
    for (final ink in inks) {
      final decoration = ink.decoration;
      if (decoration is BoxDecoration) {
        expect(decoration.gradient, isNull);
      }
    }

    expect(find.byType(AppPrimaryButton), findsOneWidget);
  });

  testWidgets('tapping a preset returns its CanvasSize', (tester) async {
    await pumpAndOpen(tester);

    await tester.tap(find.text('Instagram Post'));
    await tester.pumpAndSettle();
    final size = await dialogResult!;
    expect(size?.width, 1080);
    expect(size?.height, 1080);
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
    // Below the 16px floor → validation error, dialog stays open.
    expect(find.byType(Dialog), findsOneWidget);

    await tester.enterText(fields.at(0), '800');
    await tester.tap(find.byKey(const ValueKey('size-picker-create')));
    await tester.pumpAndSettle();
    final size = await dialogResult!;
    expect(size?.width, 800);
    expect(size?.height, 900);
  });

  testWidgets('custom size enforces the ONE document ceiling (8000) shared '
      'with layers and export', (tester) async {
    // ux-audit P2-20: this dialog used to accept 16384 while layers
    // capped at 8000 and the exporter at ~24 Mpx — the biggest
    // canvases it sold could never be filled or exported at size.
    await pumpAndOpen(tester);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '8001');
    await tester.enterText(fields.at(1), '1000');
    await tester.tap(find.byKey(const ValueKey('size-picker-create')));
    await tester.pump();
    expect(find.byType(Dialog), findsOneWidget, reason: '8001 is over cap');

    await tester.enterText(fields.at(0), '8000');
    await tester.tap(find.byKey(const ValueKey('size-picker-create')));
    await tester.pumpAndSettle();
    final size = await dialogResult!;
    expect(size?.width, EngineConstants.maxDocumentDimension.toDouble());
  });

  testWidgets('RTL: the preset chevron mirrors to point start-ward', (
    tester,
  ) async {
    await pumpAndOpen(tester, locale: const Locale('fa'));

    // The tile always names the FORWARD glyph. `chevron_right_rounded`
    // carries `matchTextDirection`, so Flutter flips it for RTL at
    // paint time; naming `chevron_left_rounded` under RTL instead
    // mirrored an already-mirroring glyph and the drill-in arrow came
    // out pointing at the screen edge. Assert the mechanism, not a
    // glyph identity — the identity is what let the bug through.
    // (The old `navPrevious` back-chevron assertion is gone with the
    // icon itself: the sibling-nav chip that owned it was deleted, so
    // asserting its absence no longer pins anything.)
    expect(find.byIcon(AppIcons.drillIn), findsWidgets);

    final icon = tester.widget<Icon>(find.byIcon(AppIcons.drillIn).first);
    expect(
      icon.icon!.matchTextDirection,
      isTrue,
      reason: 'the glyph has to be one Flutter will mirror for us',
    );
  });

  testWidgets('LTR: the preset chevron uses the same forward glyph', (
    tester,
  ) async {
    await pumpAndOpen(tester, locale: const Locale('en'));
    expect(find.byIcon(AppIcons.drillIn), findsWidgets);
  });

  testWidgets('dark mode: ink surface + cream CTA', (tester) async {
    await pumpAndOpen(tester, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);

    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    expect(dialog.backgroundColor, AppTokens.dark.surface);

    final cta = find.descendant(
      of: find.byType(AppPrimaryButton),
      matching: find.byType(Ink),
    );
    final decoration = tester.widget<Ink>(cta).decoration! as BoxDecoration;
    expect(decoration.color, AppTokens.dark.brand); // cream
  });
}
