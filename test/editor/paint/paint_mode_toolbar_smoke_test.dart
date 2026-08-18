// Widget smoke net for PaintModeToolbar (toolbar redesign roadmap
// tb1, Stage 1 item 1.1 — this surface had zero widget coverage).
// Pumps the REAL EditorScreen in paint mode and pins the CURRENT
// behaviour before the 1.3-1.5 paint split: the strip renders one
// DockToolTile per slot the per-tool capability matrix
// (`_allowedSlotsFor`) allows — freestyle = tool/color/size/opacity,
// blur = tool/eraser/blur, mirrored by the public
// `PaintModeToolbar.toolIdsFor` — and tapping a tile toggles its
// sheet body in the dock's expanded zone through
// `PaintSession.openSlot` (tap opens, re-tap closes). Later refactors
// that move the spec/bodies or swap the strip onto the registry must
// keep every assertion here green unchanged.

import 'package:canvas_engine/features/color_picker/presentation/color_picker_body.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/paint/application/paint_tool_controller.dart';
import 'package:canvas_engine/features/editor/paint/domain/paint_tool_type.dart';
import 'package:canvas_engine/features/editor/paint/presentation/paint_mode_toolbar.dart';
import 'package:canvas_engine/features/editor/paint/presentation/paint_size_body.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/dock_tool_strip.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/dock_tool_tile.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:canvas_engine/app/theme/app_icons.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Pumps EditorScreen with paint mode armed on [tool]. Arming
  /// BEFORE the first pump also pins that the toolbar's auto-open
  /// picker stays quiet when a tool is already active (openSlot
  /// must start null).
  Future<ProviderContainer> pumpPaintMode(
    WidgetTester tester, {
    PaintToolType tool = PaintToolType.freestyle,
  }) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 1080, height: 1080);
    container.read(paintToolControllerProvider.notifier).selectTool(tool);

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

  /// The strip's tiles in render order, identified by their spec
  /// icon (stable even for the Color tile, whose VISUAL swaps the
  /// icon for a swatch chip).
  List<IconData> stripTileIcons(WidgetTester tester) => tester
      .widgetList<DockToolTile>(
        find.descendant(
          of: find.byType(DockToolStrip),
          matching: find.byType(DockToolTile),
        ),
      )
      .map((t) => t.icon)
      .toList();

  Finder stripTile(IconData icon) =>
      find.byWidgetPredicate((w) => w is DockToolTile && w.icon == icon);

  testWidgets('freestyle strip renders tool/color/size/opacity tiles only', (
    tester,
  ) async {
    final container = await pumpPaintMode(tester);
    expect(find.byType(PaintModeToolbar), findsOneWidget);
    // Auto-open picker stayed quiet: a tool was already armed.
    expect(container.read(paintToolControllerProvider).openSlot, isNull);

    // Capability matrix for freestyle: {tool, eraser, color, size,
    // opacity}, in registry order. The tool tile shows the active DRAW
    // tool's icon (freestyle = gesture) and the eraser sits beside it
    // permanently — swapping between them is the mode's most frequent
    // action and used to cost a round trip through the picker.
    // fill/blur/polygon/dash stay hidden.
    expect(stripTileIcons(tester), [
      AppIcons.freehandTool,
      AppIcons.eraserTool,
      AppIcons.colorTool,
      AppIcons.strokeWeight,
      AppIcons.opacity,
    ]);

    // The sibling-swipe id list is filtered by the same matrix.
    expect(PaintModeToolbar.toolIdsFor(tool: PaintToolType.freestyle), [
      'tool',
      'color',
      'size',
      'opacity',
    ]);

    final armedTool = tester.widget<DockToolTile>(
      stripTile(AppIcons.freehandTool),
    );
    expect(
      armedTool.active,
      isTrue,
      reason: 'the armed drawing tool must remain visibly selected',
    );
  });

  testWidgets('color tile toggles the color body in the expanded zone', (
    tester,
  ) async {
    final container = await pumpPaintMode(tester);
    expect(container.read(paintToolControllerProvider).openSlot, isNull);
    expect(find.byType(ColorPickerBody), findsNothing);

    await tester.tap(stripTile(AppIcons.colorTool));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(paintToolControllerProvider).openSlot, 'color');
    expect(find.byType(ColorPickerBody), findsOneWidget);

    // Toggle idiom: re-tapping the active tile dismisses the sheet.
    await tester.tap(stripTile(AppIcons.colorTool));
    await tester.pump();
    expect(container.read(paintToolControllerProvider).openSlot, isNull);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ColorPickerBody), findsNothing);
  });

  testWidgets('size tile opens the size body in the expanded zone', (
    tester,
  ) async {
    final container = await pumpPaintMode(tester);

    await tester.tap(stripTile(AppIcons.strokeWeight));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(paintToolControllerProvider).openSlot, 'size');
    expect(find.byType(PaintSizeBody), findsOneWidget);
  });

  testWidgets('blur keeps the global eraser beside its blur control', (
    tester,
  ) async {
    final container = await pumpPaintMode(tester, tool: PaintToolType.blur);
    expect(
      container.read(paintToolControllerProvider).activeTool,
      PaintToolType.blur,
    );

    // Erase remains a global canvas action even while painting blur.
    // Both blur entries render the same glyph: the first is tool
    // identity, the last is blur strength.
    expect(stripTileIcons(tester), [
      AppIcons.blur,
      AppIcons.eraserTool,
      AppIcons.blur,
    ]);
    expect(PaintModeToolbar.toolIdsFor(tool: PaintToolType.blur), [
      'tool',
      'blur',
    ]);
  });
}
