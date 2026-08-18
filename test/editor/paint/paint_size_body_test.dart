// Pins the Size body after its redesign onto the shared
// PresetSliderControl (the same control Blur/Opacity already use):
// a live readout lives in the control's own header, presets are
// chips, and the slider is always visible — no more floating
// readout badge, reflowing weight grid, or a disclosure hiding the
// fine-tune slider behind an extra tap.
//
// Generic preset/slider mechanics (drag streams onPreview, release
// or pointer-cancel commits exactly once) are pinned ONCE for every
// numeric tool by slider_preview_contract_test.dart's
// "PresetSliderControl commits once per drag..." — this file only
// pins how PaintSizeBody composes into that shared control.

import 'package:canvas_engine/features/editor/paint/presentation/paint_size_body.dart';
import 'package:canvas_engine/features/editor/toolbar/presentation/widgets/preset_chip.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpSize(
    WidgetTester tester, {
    required double value,
    ValueChanged<double>? onPreview,
    ValueChanged<double>? onCommit,
    Locale locale = const Locale('en'),
    Size size = const Size(400, 800),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: PaintSizeBody(
                value: value,
                color: const Color(0xFF112233),
                onPreview: onPreview ?? (_) {},
                onCommit: onCommit ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the hero previews the value and the slider needs no extra tap', (
    tester,
  ) async {
    await pumpSize(tester, value: 20);

    expect(
      tester.widget<StrokeHero>(find.byType(StrokeHero)).width,
      20,
      reason:
          'the stroke preview is unique to Size and stays above '
          'the control',
    );
    expect(
      find.byType(Slider),
      findsOneWidget,
      reason: 'no disclosure tap stands between the user and the slider',
    );
    expect(
      find.text('20px'),
      findsOneWidget,
      reason: 'the live readout now lives in the control\'s own header',
    );
  });

  testWidgets('a width between presets lights no chip', (tester) async {
    await pumpSize(tester, value: 20);
    final chips = tester.widgetList<PresetChip>(find.byType(PresetChip));
    expect(chips.length, 4);
    expect(chips.every((c) => !c.selected), isTrue);
  });

  testWidgets('landing on a preset lights exactly that weight', (tester) async {
    await pumpSize(tester, value: 8);
    expect(find.text('8px'), findsOneWidget);

    final selected = tester
        .widgetList<PresetChip>(find.byType(PresetChip))
        .where((c) => c.selected)
        .toList();
    expect(selected.length, 1);
    expect(selected.single.label, 'Medium');
  });

  testWidgets('a weight tap previews then commits the same value once', (
    tester,
  ) async {
    final previews = <double>[];
    final commits = <double>[];
    await pumpSize(
      tester,
      value: 20,
      onPreview: previews.add,
      onCommit: commits.add,
    );

    await tester.tap(find.text('Thick'));
    await tester.pump();

    expect(
      previews,
      isEmpty,
      reason: 'PresetSliderControl chips commit directly, no preview tick',
    );
    expect(commits, [18], reason: 'a tap is a single discrete commit (§3)');
  });

  testWidgets(
    '320dp Persian at textScale 2.5: no overflow, and every weight is '
    'reachable by scroll',
    (tester) async {
      await pumpSize(
        tester,
        value: 20,
        locale: const Locale('fa'),
        size: const Size(320, 700),
        textScale: 2.5,
      );

      expect(
        tester.takeException(),
        isNull,
        reason: 'no RenderFlex overflow at the narrowest supported dock',
      );

      // The chip row is a horizontal scroller (the same shape Blur and
      // Opacity already use), not the old reflowing grid — at this
      // extreme width+scale «خیلی ضخیم» (two Persian words, unlike
      // Blur/Opacity's single-word presets) genuinely doesn't fit
      // beside its siblings. The live readout in the control's own
      // header always names the exact value regardless, so nothing is
      // silently lost — but every weight must still be reachable.
      expect(find.text('نازک'), findsOneWidget);
      expect(find.text('متوسط'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(1000, 0));
      await tester.pumpAndSettle();

      expect(find.text('ضخیم'), findsOneWidget);
      expect(find.text('خیلی ضخیم'), findsOneWidget);
    },
  );

  testWidgets('a full drag previews live and commits once on release', (
    tester,
  ) async {
    final previews = <double>[];
    final commits = <double>[];
    await pumpSize(
      tester,
      value: 20,
      onPreview: previews.add,
      onCommit: commits.add,
    );

    final slider = find.byType(Slider);
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(previews, isNotEmpty, reason: 'ticks stream while dragging (§2)');
    expect(commits, isEmpty, reason: 'a drag is preview-only until it ends');

    await gesture.up();
    await tester.pump();
    expect(commits.length, 1);
  });

  testWidgets('the body no longer repeats the panel title', (tester) async {
    await pumpSize(tester, value: 20);
    expect(find.text('Stroke width'), findsNothing);
  });
}
