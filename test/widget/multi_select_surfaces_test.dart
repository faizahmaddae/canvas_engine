import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/application/viewport_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/layers_panel.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Multi-select surfaces (tb3 5/7): the interactive exit chip and the
/// membership-toggling layers drawer — plus the app-bar zoom-readout
/// fit tap (tb3 7/7), which shares this file's screen-level harness.

void _addRect(
  ProviderContainer c, {
  required String id,
  required Offset position,
  bool locked = false,
}) {
  c
      .read(documentControllerProvider.notifier)
      .execute(
        AddLayerCommand(
          ShapeLayer(
            id: id,
            transform: LayerTransform(
              position: position,
              size: const Size(60, 60),
            ),
            kind: ShapeKind.rectangle,
            locked: locked,
          ),
        ),
      );
}

ProviderContainer _container(WidgetTester tester) {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  c
      .read(documentControllerProvider.notifier)
      .newDocument(width: 800, height: 800);
  return c;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('multi-select exit chip', () {
    testWidgets('tapping the chip exits multi mode keeping the primary', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = _container(tester);
      _addRect(c, id: 'a', position: const Offset(100, 100));
      _addRect(c, id: 'b', position: const Offset(300, 300));
      c.read(selectionModeProvider.notifier).enterMulti();
      c.read(selectionControllerProvider.notifier).selectMany(['a', 'b']);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: Scaffold(body: EditorCanvas())),
        ),
      );
      await tester.pump();
      await tester.pump();

      final chip = find.byKey(const ValueKey('multi-select-exit-chip'));
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pump();

      expect(c.read(selectionModeProvider), SelectionMode.single);
      expect(
        c.read(selectionControllerProvider).selectedIds,
        ['b'],
        reason: 'exit keeps the PRIMARY (most recently added) selection',
      );
    });
  });

  group('layers drawer in multi mode', () {
    Future<void> pumpPanel(WidgetTester tester, ProviderContainer c) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: Scaffold(body: LayersPanel())),
        ),
      );
      await tester.pump();
    }

    IconData checkIconOf(WidgetTester tester, String id) => tester
        .widget<Icon>(find.byKey(ValueKey('layers-multi-check-$id')))
        .icon!;

    // Tap the row's HEADER line (thumbnail/name row): the primary row
    // grows an opacity slider below it, so tapping the tile's centre
    // could land on the slider instead of the row InkWell.
    Future<void> tapRow(WidgetTester tester, String id) async {
      final rect = tester.getRect(find.byKey(ValueKey(id)));
      await tester.tapAt(rect.topLeft + const Offset(120, 24));
      await tester.pump();
    }

    testWidgets('row taps TOGGLE membership and render checked state', (
      tester,
    ) async {
      final c = _container(tester);
      _addRect(c, id: 'a', position: const Offset(100, 100));
      _addRect(c, id: 'b', position: const Offset(200, 200));
      _addRect(c, id: 'c', position: const Offset(300, 300));
      c.read(selectionModeProvider.notifier).enterMulti();
      c.read(selectionControllerProvider.notifier).selectMany(['a', 'b']);
      await pumpPanel(tester, c);

      // Checked state mirrors membership, not just the primary.
      expect(checkIconOf(tester, 'a'), Icons.check_circle_rounded);
      expect(checkIconOf(tester, 'b'), Icons.check_circle_rounded);
      expect(checkIconOf(tester, 'c'), Icons.radio_button_unchecked);

      // Tap 'c' → ADDED to the group (audit: drawer-can't-extend-multi).
      await tapRow(tester, 'c');
      expect(
        c.read(selectionControllerProvider).selectedIds,
        unorderedEquals(['a', 'b', 'c']),
      );
      expect(checkIconOf(tester, 'c'), Icons.check_circle_rounded);
      expect(c.read(selectionModeProvider), SelectionMode.multi);

      // Tap 'c' again → removed.
      await tapRow(tester, 'c');
      expect(
        c.read(selectionControllerProvider).selectedIds,
        unorderedEquals(['a', 'b']),
      );
      expect(checkIconOf(tester, 'c'), Icons.radio_button_unchecked);
    });

    testWidgets('dropping below 2 members exits multi mode', (tester) async {
      final c = _container(tester);
      _addRect(c, id: 'a', position: const Offset(100, 100));
      _addRect(c, id: 'b', position: const Offset(200, 200));
      c.read(selectionModeProvider.notifier).enterMulti();
      c.read(selectionControllerProvider.notifier).selectMany(['a', 'b']);
      await pumpPanel(tester, c);

      await tapRow(tester, 'b');

      expect(c.read(selectionModeProvider), SelectionMode.single);
      expect(c.read(selectionControllerProvider).selectedIds, ['a']);
    });

    testWidgets('locked layers cannot join the group from the drawer', (
      tester,
    ) async {
      final c = _container(tester);
      _addRect(c, id: 'a', position: const Offset(100, 100));
      _addRect(c, id: 'b', position: const Offset(200, 200));
      _addRect(c, id: 'lock', position: const Offset(300, 300), locked: true);
      c.read(selectionModeProvider.notifier).enterMulti();
      c.read(selectionControllerProvider.notifier).selectMany(['a', 'b']);
      await pumpPanel(tester, c);

      await tapRow(tester, 'lock');

      expect(
        c.read(selectionControllerProvider).selectedIds,
        unorderedEquals(['a', 'b']),
        reason: 'a locked layer must not join a group transform',
      );
      expect(checkIconOf(tester, 'lock'), Icons.radio_button_unchecked);
    });

    testWidgets('single-mode drawer behaviour is unchanged: row tap '
        'REPLACES the selection, no check indicators', (tester) async {
      final c = _container(tester);
      _addRect(c, id: 'a', position: const Offset(100, 100));
      _addRect(c, id: 'b', position: const Offset(200, 200));
      c.read(selectionControllerProvider.notifier).select('a');
      await pumpPanel(tester, c);

      expect(
        find.byKey(const ValueKey('layers-multi-check-a')),
        findsNothing,
        reason: 'the membership indicator is multi-mode chrome only',
      );

      await tapRow(tester, 'b');
      expect(c.read(selectionControllerProvider).selectedIds, ['b']);
    });
  });

  group('app-bar zoom readout', () {
    testWidgets('tapping the zoom readout fits the viewport', (tester) async {
      tester.view.physicalSize = const Size(480, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final c = _container(tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
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

      // Knock the viewport off its auto-fit.
      c.read(viewportControllerProvider.notifier).panBy(const Offset(60, 40));
      await tester.pump();
      expect(c.read(viewportControllerProvider).userAdjusted, isTrue);

      final target = find.byKey(const ValueKey('appbar-zoom-fit-target'));
      expect(target, findsOneWidget);
      await tester.tap(target);
      await tester.pump();

      expect(
        c.read(viewportControllerProvider).userAdjusted,
        isFalse,
        reason: 'the readout tap must replay the auto-fit',
      );
    });
  });
}
