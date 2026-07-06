// Locks the compact-panel contract: an in-dock panel is only as tall
// as its content, hard-capped at min(screen * 0.34, 380dp), and long
// bodies (the inline font browser) scroll WITHIN the cap instead of
// growing — the canvas must stay clearly visible above every panel.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/dock_sheet_chrome.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:canvas_engine/features/editor/text/application/text_tool_controller.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pumpWithSheet(
    WidgetTester tester,
    String sheetId, {
    Size screenSize = const Size(440, 956),
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
          style: const TextStyleSpec(fontSize: 96),
        ),
      ),
    );
    container.read(selectionControllerProvider.notifier).select('text-1');
    container.read(textToolControllerProvider.notifier).openSheet(sheetId);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
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

  for (final sheetId in ['font', 'size', 'styles']) {
    testWidgets('"$sheetId" panel stays under the compact cap', (
      tester,
    ) async {
      await pumpWithSheet(tester, sheetId);

      final chrome = find.byType(DockSheetChrome);
      expect(chrome, findsOneWidget);
      final panelHeight = tester.getSize(chrome).height;
      const cap = 956 * kEditorPanelMaxHeightFraction; // < 380dp here
      expect(
        panelHeight,
        lessThanOrEqualTo(cap + 1),
        reason:
            '"$sheetId" panel is ${panelHeight}dp — must stay under '
            'min(34% of screen, ${kEditorPanelMaxHeightDp}dp)',
      );
      expect(panelHeight, lessThanOrEqualTo(kEditorPanelMaxHeightDp + 1));

      // The canvas must remain visible above the dock: its viewport
      // keeps a meaningful share of the screen.
      final canvas = tester.getSize(find.byType(EditorCanvas));
      expect(
        canvas.height,
        greaterThan(956 * 0.35),
        reason: 'canvas squeezed to ${canvas.height}dp by "$sheetId"',
      );
    });
  }
}
