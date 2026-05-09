// Regression test for the ColorPickerSheet HEX/alpha contract.
//
// The hex display is `#RRGGBB` (6 chars). Editing it must NOT silently
// reset the user's chosen opacity — only an explicit 8-char hex is
// treated as an alpha edit. Driven through the public
// `showColorPickerSheet` entry so we exercise the same code path the
// editor uses.

import 'package:canvas_engine/features/color_picker/presentation/color_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _openSheet(
  WidgetTester tester, {
  required Color initial,
  ValueChanged<Color>? onLiveChange,
}) async {
  // Tall test surface so the full sheet (incl. the hex field, which
  // sits below the fold of the default 800x600 viewport) is on
  // screen without needing scroll plumbing.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showColorPickerSheet(
                ctx,
                initial: initial,
                onLiveChange: onLiveChange,
              ),
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

void main() {
  testWidgets(
      'editing the 6-char hex preserves the current alpha (no silent opacity reset)',
      (tester) async {
    Color? lastLive;
    await _openSheet(
      tester,
      // 50%-opaque red. Hex display will show `#FF0000` by design.
      initial: const Color(0x80FF0000),
      onLiveChange: (c) => lastLive = c,
    );

    final hex = find.byType(TextField);
    expect(hex, findsOneWidget);
    await tester.enterText(hex, '#00FF00');
    await tester.pump();

    expect(lastLive, isNotNull);
    expect(lastLive!.toARGB32() & 0x00FFFFFF, 0x00FF00,
        reason: 'RGB must reflect the typed value');
    expect(lastLive!.a, closeTo(0x80 / 255.0, 0.005),
        reason: 'alpha must survive a 6-char hex edit');
  });

  testWidgets(
      'editing an 8-char hex is treated as an explicit alpha edit',
      (tester) async {
    Color? lastLive;
    await _openSheet(
      tester,
      initial: const Color(0x80FF0000),
      onLiveChange: (c) => lastLive = c,
    );

    final hex = find.byType(TextField);
    // 8-char #AARRGGBB — user explicitly typed the alpha byte (0x33).
    await tester.enterText(hex, '#3300FF00');
    await tester.pump();

    expect(lastLive, isNotNull);
    expect(lastLive!.toARGB32() & 0x00FFFFFF, 0x00FF00);
    expect(lastLive!.a, closeTo(0x33 / 255.0, 0.005),
        reason: 'explicit 8-char alpha must be honoured');
  });
}
