// Widget net for the paint bench (docs/paint-redesign-2026-08.md).
// Pumps the REAL EditorScreen in paint mode and pins the bench's
// grammar: a fixed seven-slot rack (tap arms, tap-again opens the
// slot's sheet), a contextual style row (quick inks + value pills,
// hints where controls would be inert), and the five sheet ids in
// PaintSession.openSlot.

import 'package:canvas_engine/features/color_picker/presentation/color_picker_body.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/paint/application/paint_tool_controller.dart';
import 'package:canvas_engine/features/editor/paint/domain/paint_tool_type.dart';
import 'package:canvas_engine/features/editor/paint/presentation/bodies/paint_blur_body.dart';
import 'package:canvas_engine/features/editor/paint/presentation/bodies/paint_pen_body.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

  Finder rack(String slot) => find.byKey(ValueKey('paint-rack-$slot'));

  testWidgets('entry is drawable: pen armed, no sheet, full rack', (
    tester,
  ) async {
    final container = await pumpPaintMode(tester);
    expect(find.byKey(const ValueKey('paint-bench')), findsOneWidget);
    // Nothing auto-opens — the first frame of paint mode can draw.
    expect(container.read(paintToolControllerProvider).openSlot, isNull);
    expect(
      container.read(paintToolControllerProvider).activeTool,
      PaintToolType.freestyle,
    );

    // The rack is fixed: all seven verbs, always.
    for (final slot in [
      'pen',
      'line',
      'arrow',
      'shape',
      'blur',
      'adjust',
      'eraser',
    ]) {
      expect(rack(slot), findsOneWidget, reason: 'rack must show $slot');
    }

    // Ink row: current dot + six quick swatches + size pill.
    expect(find.byKey(const ValueKey('paint-ink-current')), findsOneWidget);
    expect(find.byKey(const ValueKey('paint-pill-size')), findsOneWidget);
  });

  testWidgets('a quick swatch re-inks the pen in one tap', (tester) async {
    final container = await pumpPaintMode(tester);
    final docBefore = container.read(documentControllerProvider);

    await tester.tap(find.byKey(const ValueKey('paint-ink-ff3b82f6')));
    await tester.pump();

    expect(
      container.read(paintToolControllerProvider).strokeColor,
      const Color(0xFF3B82F6),
    );
    expect(
      identical(container.read(documentControllerProvider), docBefore),
      isTrue,
      reason: 'an author-defaults write commits nothing',
    );
  });

  testWidgets('the current-ink dot toggles the colour sheet', (tester) async {
    final container = await pumpPaintMode(tester);
    expect(find.byType(ColorPickerBody), findsNothing);

    await tester.tap(find.byKey(const ValueKey('paint-ink-current')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(paintToolControllerProvider).openSlot, 'color');
    expect(find.byType(ColorPickerBody), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('paint-ink-current')));
    await tester.pump();
    expect(container.read(paintToolControllerProvider).openSlot, isNull);
  });

  testWidgets('the size pill opens the pen sheet (size + opacity)', (
    tester,
  ) async {
    final container = await pumpPaintMode(tester);

    await tester.tap(find.byKey(const ValueKey('paint-pill-size')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(paintToolControllerProvider).openSlot, 'pen');
    expect(find.byType(PaintPenBody), findsOneWidget);
  });

  testWidgets('tap-again on the active rack slot opens its sheet', (
    tester,
  ) async {
    final container = await pumpPaintMode(tester, tool: PaintToolType.blur);
    expect(container.read(paintToolControllerProvider).openSlot, isNull);

    await tester.tap(rack('blur'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(paintToolControllerProvider).openSlot, 'blur');
    expect(find.byType(PaintBlurBody), findsOneWidget);
  });

  testWidgets('blur context: radius pill instead of ink swatches', (
    tester,
  ) async {
    await pumpPaintMode(tester, tool: PaintToolType.blur);
    expect(find.byKey(const ValueKey('paint-pill-blur')), findsOneWidget);
    expect(find.byKey(const ValueKey('paint-ink-current')), findsNothing);
    expect(find.byKey(const ValueKey('paint-pill-size')), findsNothing);
  });

  testWidgets('eraser and unbound adjust show hints, not dead controls', (
    tester,
  ) async {
    final container = await pumpPaintMode(tester);

    await tester.tap(rack('eraser'));
    await tester.pump();
    expect(
      container.read(paintToolControllerProvider).activeTool,
      PaintToolType.eraser,
    );
    expect(find.byKey(const ValueKey('paint-style-hint')), findsOneWidget);
    expect(find.byKey(const ValueKey('paint-ink-current')), findsNothing);

    await tester.tap(rack('adjust'));
    await tester.pump();
    expect(container.read(paintToolControllerProvider).activeTool, isNull);
    expect(container.read(selectionControllerProvider).hasSelection, isFalse);
    expect(find.byKey(const ValueKey('paint-style-hint')), findsOneWidget);
  });

  testWidgets('rack line slot arms the remembered variant', (tester) async {
    final container = await pumpPaintMode(tester);
    final ctrl = container.read(paintToolControllerProvider.notifier);
    ctrl.selectTool(PaintToolType.dashLine);
    await tester.pump();

    await tester.tap(rack('pen'));
    await tester.pump();
    expect(
      container.read(paintToolControllerProvider).activeTool,
      PaintToolType.freestyle,
    );

    await tester.tap(rack('line'));
    await tester.pump();
    expect(
      container.read(paintToolControllerProvider).activeTool,
      PaintToolType.dashLine,
      reason: 'the Line slot re-arms the last line variant, not solid',
    );
  });
}
