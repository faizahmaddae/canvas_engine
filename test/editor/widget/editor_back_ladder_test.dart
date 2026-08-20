// UX audit P2-11: system Back popped the whole editor over an open
// dock panel or armed paint session. Contract §4 maps Back to the
// exit ladder instead: one press unwinds one level — E1 close the
// open sheet, E2 exit the armed mode — and only a chrome-free editor
// lets the route itself pop. Selection deliberately does not consume
// Back (E3 belongs to tap-empty).

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/editing_controller.dart';
import 'package:canvas_engine/features/editor/application/editor_lifecycle.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/image/application/image_tool_controller.dart';
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

  group('editorBackStepProvider ladder', () {
    ProviderContainer harness() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(documentControllerProvider.notifier)
          .newDocument(width: 800, height: 800);
      return c;
    }

    test('nothing open → none (the route may pop)', () {
      final c = harness();
      expect(c.read(editorBackStepProvider), EditorBackStep.none);
    });

    test('open sheet outranks armed mode: E1 first, then E2, then none', () {
      final c = harness();
      final paint = c.read(paintToolControllerProvider.notifier);
      paint.selectTool(PaintToolType.freestyle);
      paint.toggleSlot('color');

      expect(c.read(editorBackStepProvider), EditorBackStep.closePanels);
      paint.closeSlot();
      expect(c.read(editorBackStepProvider), EditorBackStep.exitMode);
      paint.closePanel();
      expect(c.read(editorBackStepProvider), EditorBackStep.none);
    });

    test('an object sub-panel is E1; selection alone never consumes Back', () {
      final c = harness();
      c
          .read(imageToolControllerProvider.notifier)
          .toggleSlot(ImageToolSlot.border);
      expect(c.read(editorBackStepProvider), EditorBackStep.closePanels);

      c.read(imageToolControllerProvider.notifier).closePanel();
      c.read(selectionControllerProvider.notifier).select('whatever');
      expect(
        c.read(editorBackStepProvider),
        EditorBackStep.none,
        reason: 'E3 belongs to tap-empty, not to Back',
      );
    });

    test('multi-select mode and inline editing are E2 sessions', () {
      final c = harness();
      c.read(selectionModeProvider.notifier).enterMulti();
      expect(c.read(editorBackStepProvider), EditorBackStep.exitMode);
      c.read(selectionModeProvider.notifier).exitMulti();

      c.read(editingControllerProvider.notifier).start('layer-1');
      expect(c.read(editorBackStepProvider), EditorBackStep.exitMode);
    });
  });

  testWidgets('three Backs: close the sheet, exit paint, then pop the '
      'editor', (tester) async {
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
        .newDocument(width: 800, height: 800);

    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('fa'),
          home: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );
    navKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const EditorScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final paint = container.read(paintToolControllerProvider.notifier);
    paint.selectTool(PaintToolType.freestyle);
    paint.toggleSlot('color');
    await tester.pump();

    // Back 1 — E1: the colour sheet closes, the session stays armed.
    await navKey.currentState!.maybePop();
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(paintToolControllerProvider).openSlot, isNull);
    expect(
      container.read(paintToolControllerProvider).activeTool,
      PaintToolType.freestyle,
    );
    expect(find.byType(EditorScreen), findsOneWidget);

    // Back 2 — E2: the paint session exits, the editor stays.
    await navKey.currentState!.maybePop();
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(paintToolControllerProvider).panelOpen, isFalse);
    expect(container.read(paintToolControllerProvider).activeTool, isNull);
    expect(find.byType(EditorScreen), findsOneWidget);

    // Back 3 — nothing owns it: the route pops.
    expect(container.read(editorBackStepProvider), EditorBackStep.none);
    final popped = await navKey.currentState!.maybePop();
    expect(popped, isTrue, reason: 'a chrome-free editor must let Back pop');
    // The reverse route transition needs several frames beyond its
    // duration before the subtree unmounts.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(EditorScreen), findsNothing);
  });
}
