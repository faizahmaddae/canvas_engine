// The canvas-side width rail (docs/paint-redesign-2026-08.md §2):
// visible only for inking tools, drag-up = thicker through the §2
// width channel — session-only when nothing is bound, staged+one
// commit for a bound stroke.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/paint/application/paint_tool_controller.dart';
import 'package:canvas_engine/features/editor/paint/domain/paint_tool_type.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pumpEditor(
    WidgetTester tester, {
    PaintToolType? tool,
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
    if (tool != null) {
      container.read(paintToolControllerProvider.notifier).selectTool(tool);
    }
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

  final rail = find.byKey(const ValueKey('paint-size-rail'));

  testWidgets('exists for inking tools only', (tester) async {
    await pumpEditor(tester, tool: PaintToolType.freestyle);
    expect(rail, findsOneWidget);
  });

  testWidgets('absent outside paint mode, for blur and for the eraser', (
    tester,
  ) async {
    final c = await pumpEditor(tester);
    expect(rail, findsNothing);

    c.read(paintToolControllerProvider.notifier).selectTool(PaintToolType.blur);
    await tester.pump();
    expect(rail, findsNothing);

    c
        .read(paintToolControllerProvider.notifier)
        .selectTool(PaintToolType.eraser);
    await tester.pump();
    expect(rail, findsNothing);
  });

  testWidgets('drag up thickens the pen with zero document commands', (
    tester,
  ) async {
    final c = await pumpEditor(tester, tool: PaintToolType.freestyle);
    final before = c.read(documentCommitVersionProvider);
    final start = c.read(paintToolControllerProvider).strokeWidth;

    final gesture = await tester.startGesture(tester.getCenter(rail));
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(c.read(paintToolControllerProvider).strokeWidth, greaterThan(start));
    expect(
      c.read(documentCommitVersionProvider),
      before,
      reason: 'author-defaults width writes commit nothing',
    );
  });
}
