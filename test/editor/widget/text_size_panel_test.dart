// Compact size panel contract (2026-07 polish): ONE control row —
// tappable value chip (exact-size keypad), slider, −/＋ nudge pair —
// plus the S/M/L/XL/XXL presets. Exactly one px readout on screen
// (the chip; the header chip and the «Adjust precisely» disclosure
// are gone), every old behaviour still reachable.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/presentation/panels/text/size_panel.dart';
import 'package:canvas_engine/features/editor/text/application/text_tool_controller.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pumpSizeSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(documentControllerProvider.notifier);
    ctrl.newDocument(width: 1080, height: 1080);
    ctrl.execute(
      AddLayerCommand(
        const TextLayer(
          id: 'text-1',
          // Box SMALLER than the natural metrics at 96px — keeps the
          // controller's visual-scale translation out of play so the
          // panel's writes land as raw px values.
          transform: LayerTransform(
            position: Offset(140, 220),
            size: Size(480, 100),
          ),
          content: 'Hello',
          style: TextStyleSpec(fontSize: 96),
        ),
      ),
    );
    container.read(selectionControllerProvider.notifier).select('text-1');
    container.read(textToolControllerProvider.notifier).openSheet('size');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const EditorScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  double fontSizeOf(ProviderContainer c) =>
      (c.read(documentControllerProvider).layerById('text-1')! as TextLayer)
          .style
          .fontSize;

  // Scoped to the Size sheet body: the Studio Bench's identity row
  // legitimately shows its own px pill above the dock now.
  final pxText = find.descendant(
    of: find.byType(SizeBody),
    matching: find.byWidgetPredicate(
      (w) => w is Text && RegExp(r'^\d+px$').hasMatch(w.data ?? ''),
    ),
  );
  final valueChip = find.descendant(
    of: find.byType(SizeBody),
    matching: find.text('96px'),
  );

  testWidgets('compact contract: one px readout, presets, no disclosure', (
    tester,
  ) async {
    await pumpSizeSheet(tester);
    // Exactly ONE px readout anywhere — the tappable value chip.
    // (The header chip and the disclosure's duplicate are gone.)
    expect(pxText, findsOneWidget);
    expect(valueChip, findsOneWidget);
    // Nudge pair + presets still present.
    expect(find.bySemanticsLabel('Decrease size'), findsOneWidget);
    expect(find.bySemanticsLabel('Increase size'), findsOneWidget);
    for (final label in ['S', 'M', 'L', 'XL', 'XXL']) {
      expect(find.text(label), findsOneWidget);
    }
    // The «Adjust precisely» disclosure row is gone.
    expect(find.text('Adjust precisely'), findsNothing);
  });

  testWidgets('value chip opens the exact-size keypad and commits', (
    tester,
  ) async {
    final c = await pumpSizeSheet(tester);
    await tester.tap(valueChip);
    await tester.pumpAndSettle();
    expect(find.text('Exact size'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '250');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(fontSizeOf(c), closeTo(250, 0.01));
  });

  testWidgets('keypad entry clamps to the absolute 4..2000 envelope', (
    tester,
  ) async {
    final c = await pumpSizeSheet(tester);
    await tester.tap(valueChip);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '999999');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(fontSizeOf(c), 2000);
  });

  testWidgets('nudge pair keeps the perceptual ±10% step', (tester) async {
    final c = await pumpSizeSheet(tester);
    await tester.tap(find.bySemanticsLabel('Increase size'));
    await tester.pumpAndSettle();
    expect(fontSizeOf(c), closeTo(106, 0.01)); // 96 + round(9.6)

    await tester.tap(find.bySemanticsLabel('Decrease size'));
    await tester.pumpAndSettle();
    expect(fontSizeOf(c), closeTo(95, 0.01)); // 106 - round(10.6)
  });

  testWidgets('preset chip pins its highlight through the session', (
    tester,
  ) async {
    final c = await pumpSizeSheet(tester);
    await tester.tap(find.text('L'));
    await tester.pumpAndSettle();
    final pin = c.read(textToolControllerProvider).selectedSizePreset;
    expect(pin?.label, 'L');
    expect(pin?.layerId, 'text-1');
  });
}
