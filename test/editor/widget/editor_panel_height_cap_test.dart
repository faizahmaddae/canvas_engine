// Locks the compact-panel contract (tightened in the 2026-07
// compactness pass): every text sheet — including the Styles panel
// with each effect section open, measured against a worst-case layer
// that has shadow + background + outline all enabled — is only as
// tall as its content, hard-capped at min(screen * 0.34, 380dp),
// renders WITHOUT internal vertical scrolling, and leaves the canvas
// clearly visible above the dock.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/controls/panel_chip.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/dock_sheet_chrome.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:canvas_engine/features/editor/text/application/text_tool_controller.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Worst-case style: every decoration enabled so each panel renders
/// its fullest state (colour rows, precision disclosures, pad).
const _effectsOn = TextStyleSpec(
  fontSize: 96,
  shadowColor: Color(0x66000000),
  shadowBlur: 8,
  shadowOffset: Offset(2, 2),
  backgroundColor: Color(0xD9000000),
  outlineColor: Color(0xFF000000),
  outlineWidth: 2,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pumpWithSheet(
    WidgetTester tester,
    String sheetId, {
    Size screenSize = const Size(440, 956),
    TextStyleSpec style = _effectsOn,
  }) async {
    tester.view.physicalSize = screenSize;
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
        TextLayer(
          id: 'text-1',
          transform: const LayerTransform(
            position: Offset(140, 220),
            size: Size(800, 240),
          ),
          content: 'سلام',
          style: style,
        ),
      ),
    );
    container.read(selectionControllerProvider.notifier).select('text-1');
    container.read(textToolControllerProvider.notifier).openSheet(sheetId);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('fa'),
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

  void expectCompact(WidgetTester tester, String name) {
    final chrome = find.byType(DockSheetChrome);
    expect(chrome, findsOneWidget);
    final panelHeight = tester.getSize(chrome).height;
    const cap = 956 * kEditorPanelMaxHeightFraction; // < 380dp here
    expect(
      panelHeight,
      lessThanOrEqualTo(cap + 1),
      reason:
          '"$name" panel is ${panelHeight}dp — must stay under '
          'min(34% of screen, ${kEditorPanelMaxHeightDp}dp)',
    );
    expect(panelHeight, lessThanOrEqualTo(kEditorPanelMaxHeightDp + 1));

    // Compact contract: the panel fits its content — no internal
    // vertical scrolling even at the worst-case style.
    double overflow = 0;
    for (final s in tester.stateList<ScrollableState>(
      find.descendant(of: chrome, matching: find.byType(Scrollable)),
    )) {
      if (s.position.axis == Axis.vertical) {
        overflow += s.position.maxScrollExtent;
      }
    }
    expect(
      overflow,
      0,
      reason:
          '"$name" content overflows its dock panel by ${overflow}dp — '
          'compact panels must fit without internal scroll',
    );

    // The canvas must remain visible above the dock: its viewport
    // keeps a meaningful share of the screen.
    final canvas = tester.getSize(find.byType(EditorCanvas));
    expect(
      canvas.height,
      greaterThan(956 * 0.35),
      reason: 'canvas squeezed to ${canvas.height}dp by "$name"',
    );
  }

  for (final sheetId in ['font', 'size', 'color', 'styles', 'layout']) {
    testWidgets('"$sheetId" panel stays compact at worst-case style', (
      tester,
    ) async {
      await pumpWithSheet(tester, sheetId);
      expectCompact(tester, sheetId);
    });
  }

  // Styles panel with each wired effect section open — these replaced
  // the standalone Background / Border / Shadow sheets in the bar
  // consolidation, so they carry those panels' compactness contract.
  for (final (chipLabel, name) in [
    ('سایه', 'styles + shadow section'),
    ('زمینه', 'styles + background section'),
    ('خط دور', 'styles + border section'),
  ]) {
    testWidgets('"$name" stays compact at worst-case style', (tester) async {
      await pumpWithSheet(tester, 'styles');
      final chip = find.descendant(
        of: find.byType(LayoutPresetChip),
        matching: find.text(chipLabel),
      );
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expectCompact(tester, name);
    });
  }
}
