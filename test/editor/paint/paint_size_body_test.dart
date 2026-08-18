// Pins the redesigned Paint Size body (tb8):
//
//   * the px readout lives INSIDE the preview card and is the only
//     place the width is spelled out;
//   * a width between presets is explained ("Custom") instead of
//     leaving every weight tile dark for no stated reason;
//   * the chosen weight carries a non-colour cue (the tick glyph);
//   * the weight grid reflows — no horizontal overflow at 320dp
//     with Persian copy at textScale 2.5, two label lines allowed;
//   * the live channel is untouched: slider ticks stream through
//     onChange, and release OR pointer-cancel commits exactly once.

import 'package:canvas_engine/app/theme/app_icons.dart';
import 'package:canvas_engine/features/editor/paint/presentation/paint_size_body.dart';
import 'package:canvas_engine/features/editor/toolbar/presentation/widgets/preset_chip.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpSize(
    WidgetTester tester, {
    required double value,
    ValueChanged<double>? onChange,
    VoidCallback? onChangeEnd,
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
                onChange: onChange ?? (_) {},
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a width between presets reads as Custom next to the px badge', (
    tester,
  ) async {
    await pumpSize(tester, value: 20);

    // ONE readout, and it sits inside the preview card.
    expect(find.text('20px'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(PaintSizeBody.readoutKey),
        matching: find.text('20px'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(PaintSizeBody.readoutKey),
        matching: find.text('· Custom'),
      ),
      findsOneWidget,
      reason: 'an unlit preset row must say WHY it is unlit',
    );
    expect(
      find.bySemanticsLabel('20px · Custom'),
      findsOneWidget,
      reason: 'the spoken readout carries the same status as the visible one',
    );

    // No weight is claimed, and no tick is painted.
    final chips = tester.widgetList<PresetChip>(find.byType(PresetChip));
    expect(chips.length, 4);
    expect(chips.every((c) => !c.selected), isTrue);
    expect(find.byIcon(AppIcons.confirm), findsNothing);
  });

  testWidgets('landing on a preset lights exactly that weight, tick and all', (
    tester,
  ) async {
    await pumpSize(tester, value: 8);

    expect(find.text('8px'), findsOneWidget);
    expect(find.text('· Custom'), findsNothing);
    expect(
      find.bySemanticsLabel('8px · Medium'),
      findsOneWidget,
      reason: 'the badge names the active weight to screen readers',
    );

    final selected = tester
        .widgetList<PresetChip>(find.byType(PresetChip))
        .where((c) => c.selected)
        .toList();
    expect(selected.length, 1);
    expect(selected.single.label, 'Medium');
    expect(
      find.byIcon(AppIcons.confirm),
      findsOneWidget,
      reason: 'selection needs a cue that survives without colour',
    );
  });

  testWidgets('a weight tap is one preview + one commit, and clears Custom', (
    tester,
  ) async {
    final previews = <double>[];
    var commits = 0;
    await pumpSize(
      tester,
      value: 20,
      onChange: previews.add,
      onChangeEnd: () => commits++,
    );

    await tester.tap(find.text('Thick'));
    await tester.pump();

    expect(previews, [18]);
    expect(commits, 1, reason: 'a tap is a single discrete commit (§3)');
  });

  testWidgets('320dp Persian at textScale 2.5: the weight grid reflows instead '
      'of overflowing, and labels keep two lines', (tester) async {
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

    // Every weight is on-screen — the old horizontal scroller pushed
    // «خیلی ضخیم» past the edge.
    for (final label in const ['نازک', 'متوسط', 'ضخیم', 'خیلی ضخیم']) {
      expect(find.text(label), findsOneWidget);
      final box = tester.getRect(find.text(label));
      expect(box.left, greaterThanOrEqualTo(-0.5));
      expect(box.right, lessThanOrEqualTo(320.5));
    }
    expect(
      tester.widget<Text>(find.text('خیلی ضخیم')).maxLines,
      2,
      reason: 'two-word Persian weights wrap rather than ellipsize',
    );

    // The tiles share ONE width (an equal-weight grid, not organically
    // sized pills) and clear the 44dp floor.
    final tiles = tester
        .widgetList<PresetChip>(find.byType(PresetChip))
        .map((c) => c.width)
        .toSet();
    expect(tiles.length, 1);
    for (var i = 0; i < 4; i++) {
      final size = tester.getSize(find.byType(PresetChip).at(i));
      expect(size.height, greaterThanOrEqualTo(44));
    }

    // The fine-tune drawer opens without overflowing either.
    await tester.tap(find.text('تنظیم دقیق'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the fine-tune slider still streams live and commits once — on '
      'release and on pointer-cancel', (tester) async {
    final previews = <double>[];
    var commits = 0;
    await pumpSize(
      tester,
      value: 20,
      onChange: previews.add,
      onChangeEnd: () => commits++,
    );

    await tester.tap(find.text('Adjust precisely'));
    await tester.pumpAndSettle();

    final slider = find.byType(Slider);
    expect(slider, findsOneWidget);
    expect(tester.widget<Slider>(slider).value, 20);
    expect(tester.widget<StrokeHero>(find.byType(StrokeHero)).width, 20);

    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(previews, isNotEmpty, reason: 'ticks stream while dragging (§2)');
    expect(commits, 0, reason: 'a drag is preview-only until it ends');
    await gesture.up();
    await tester.pump();
    expect(commits, 1);

    final cancelled = await tester.startGesture(tester.getCenter(slider));
    await cancelled.moveBy(const Offset(-30, 0));
    await tester.pump();
    await cancelled.cancel();
    await tester.pump();
    expect(
      commits,
      2,
      reason: 'pointer-cancel commits the last previewed value (§7)',
    );
  });

  testWidgets('the body no longer repeats the panel title', (tester) async {
    await pumpSize(tester, value: 20);
    expect(find.text('Stroke width'), findsNothing);
  });
}
