// Pointer-level safety net for the dock-sheet gesture grammar
// (toolbar redesign roadmap tb1, Stage 1 item 1.1). Drives REAL drag /
// fling / tap gestures against a pumped EditorScreen and pins the
// CURRENT thresholds in DockSheetChrome: swipe-down dismiss fires at
// > 36dp of accumulated downward travel OR a > 380px/s fling on the
// drag-handle zone; tapping the handle dismisses; a horizontal drag
// whose travel exceeds 56dp (or a > 520px/s fling) anywhere on the
// sheet chrome navigates to the sibling sheet in text-strip order
// (physical drag LEFT → next, drag RIGHT → prev — deliberately pinned
// as physical, not RTL-logical); sub-threshold drags do nothing. The
// later toolbar refactors (1.3-1.17) must keep every one of these
// observable behaviours byte-identical.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/dock_sheet_chrome.dart';
import 'package:canvas_engine/features/editor/text/application/text_tool_controller.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Pumps EditorScreen with one selected text layer and the given
  /// sheet open — same harness as editor_panel_height_cap_test.
  Future<ProviderContainer> pumpWithSheet(
    WidgetTester tester,
    String sheetId,
  ) async {
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

  /// Centre of the 14dp-tall drag-handle zone at the top of the
  /// sheet chrome. All chrome-level gestures start here: the zone is
  /// deterministic (no body slider / scrollable can claim the drag).
  Offset handleCenter(WidgetTester tester) {
    final rect = tester.getRect(find.byType(DockSheetChrome));
    return Offset(rect.center.dx, rect.top + 7);
  }

  group('swipe-down dismiss on the drag-handle zone', () {
    testWidgets('slow downward drag past 36dp travel dismisses the sheet', (
      tester,
    ) async {
      final container = await pumpWithSheet(tester, 'size');
      expect(container.read(textToolControllerProvider).openSheet, 'size');

      // 100dp down over 1s: ~100px/s (below the 380px/s fling bar) so
      // ONLY the travel threshold can fire. Post-slop travel is
      // ~100 - 18 = 82dp > 36dp → dismiss.
      await tester.timedDragFrom(
        handleCenter(tester),
        const Offset(0, 100),
        const Duration(milliseconds: 1000),
      );
      await tester.pump();

      expect(container.read(textToolControllerProvider).openSheet, isNull);
    });

    testWidgets('fast fling below the travel threshold still dismisses', (
      tester,
    ) async {
      final container = await pumpWithSheet(tester, 'size');

      // 52dp of travel (post-slop ~34dp < 36dp) at 800px/s > 380px/s:
      // isolates the fling branch of the dismiss threshold. 52dp
      // (not less) so the velocity tracker's 20-sample window still
      // spans > kTouchSlop and the gesture classifies as a fling.
      await tester.flingFrom(handleCenter(tester), const Offset(0, 52), 800);
      await tester.pump();

      expect(container.read(textToolControllerProvider).openSheet, isNull);
    });

    testWidgets('slow sub-threshold drag does NOT dismiss', (tester) async {
      final container = await pumpWithSheet(tester, 'size');

      // 40dp over 600ms: post-slop travel ~22dp < 36dp AND ~67px/s
      // < 380px/s — neither branch may fire.
      await tester.timedDragFrom(
        handleCenter(tester),
        const Offset(0, 40),
        const Duration(milliseconds: 600),
      );
      await tester.pump();

      expect(container.read(textToolControllerProvider).openSheet, 'size');
    });
  });

  testWidgets('tapping the drag handle dismisses the sheet', (tester) async {
    final container = await pumpWithSheet(tester, 'size');
    expect(find.byType(DockSheetChrome), findsOneWidget);

    await tester.tapAt(handleCenter(tester));
    await tester.pump();

    expect(container.read(textToolControllerProvider).openSheet, isNull);

    // The chrome itself leaves the tree once the dock's collapse
    // animation (240ms) runs out.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(DockSheetChrome), findsNothing);
  });

  group('horizontal sibling swipe on the sheet chrome', () {
    // Text strip sibling order (ids with sheet bodies):
    // font → size → color → styles → layout, wrapping. From 'size'
    // the physical mapping is: drag LEFT → next ('color'), drag
    // RIGHT → prev ('font'). Pinned as PHYSICAL direction — the
    // mapping does not flip under the fa/RTL locale this harness
    // runs in.
    testWidgets('drag left beyond 56dp travel navigates to the next sheet', (
      tester,
    ) async {
      final container = await pumpWithSheet(tester, 'size');

      // 140dp left over 400ms: ~350px/s < 520px/s fling bar, so only
      // the travel branch (post-slop ~122dp > 56dp) can fire.
      await tester.timedDragFrom(
        handleCenter(tester),
        const Offset(-140, 0),
        const Duration(milliseconds: 400),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(textToolControllerProvider).openSheet, 'color');
    });

    testWidgets('drag right beyond 56dp travel navigates to the prev sheet', (
      tester,
    ) async {
      final container = await pumpWithSheet(tester, 'size');

      await tester.timedDragFrom(
        handleCenter(tester),
        const Offset(140, 0),
        const Duration(milliseconds: 400),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(textToolControllerProvider).openSheet, 'font');
    });

    testWidgets('drag below 56dp travel does NOT navigate', (tester) async {
      final container = await pumpWithSheet(tester, 'size');

      // 60dp over 600ms: post-slop travel ~42dp < 56dp AND ~100px/s
      // < 520px/s — the sheet must stay put.
      await tester.timedDragFrom(
        handleCenter(tester),
        const Offset(-60, 0),
        const Duration(milliseconds: 600),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(textToolControllerProvider).openSheet, 'size');
    });
  });
}
