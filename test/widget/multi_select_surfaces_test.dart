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
import 'package:canvas_engine/features/editor/presentation/widgets/layer_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:canvas_engine/app/theme/app_icons.dart';

/// Multi-select surfaces (tb3 5/7): the interactive exit chip and the
/// membership-toggling layers drawer — plus the app-bar zoom-readout
/// fit tap (tb3 7/7), which shares this file's screen-level harness.
///
/// The mode's LIFETIME is pinned here across surfaces in one harness
/// (ux-audit P2-5): the canvas and the drawer had grown different
/// below-2 rules precisely because they were only ever tested apart.
/// The unified rule: armed at ANY member count until an explicit exit
/// (chip ✕, tap-on-empty, system Back), with the chip — gated on the
/// mode flag, labelled with the actionable count — visible the whole
/// time.

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

    testWidgets('chip renders at counts 0, 1 and 2 while armed, labelled '
        'with the actionable count (ux-audit P2-5)', (tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = _container(tester);
      _addRect(c, id: 'a', position: const Offset(100, 100));
      _addRect(c, id: 'b', position: const Offset(300, 300));
      // Armed from an empty long-press: no members yet. The chip is
      // the mode's presence signal, so it must already be up — this
      // is exactly the state that used to be armed and invisible.
      c.read(selectionModeProvider.notifier).enterMulti();

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
      expect(find.text('Multi-select • 0'), findsOneWidget);

      c.read(selectionControllerProvider.notifier).select('a');
      await tester.pump();
      expect(chip, findsOneWidget);
      expect(find.text('Multi-select • 1'), findsOneWidget);

      c.read(selectionControllerProvider.notifier).selectMany(['a', 'b']);
      await tester.pump();
      expect(chip, findsOneWidget);
      expect(find.text('Multi-select • 2'), findsOneWidget);

      // And the converse: single mode renders no chip at all.
      c.read(selectionModeProvider.notifier).exitMulti();
      await tester.pump();
      expect(chip, findsNothing);
    });

    testWidgets('chip exit works below 2 members: count 1 keeps the '
        'single selection, count 0 just ends the mode', (tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = _container(tester);
      _addRect(c, id: 'a', position: const Offset(100, 100));
      c.read(selectionModeProvider.notifier).enterMulti();
      c.read(selectionControllerProvider.notifier).select('a');

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
        ['a'],
        reason: 'exiting at count 1 keeps the lone member selected',
      );

      // Re-arm with nothing selected: the exit affordance must still
      // be one tap away.
      c.read(selectionControllerProvider.notifier).clear();
      c.read(selectionModeProvider.notifier).enterMulti();
      await tester.pump();
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pump();
      expect(c.read(selectionModeProvider), SelectionMode.single);
      expect(c.read(selectionControllerProvider).hasSelection, isFalse);
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
    // Tap the row's thumbnail rather than a magic pixel offset: the
    // offset used to sit just clear of the trailing icon buttons, so
    // widening those to the 48dp hit floor pushed them under it and
    // the "tap the row" gesture silently became "tap an icon".
    Future<void> tapRow(WidgetTester tester, String id) async {
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey(id)),
          matching: find.byType(LayerThumbnail),
        ),
      );
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
      expect(checkIconOf(tester, 'a'), AppIcons.selectedCheck);
      expect(checkIconOf(tester, 'b'), AppIcons.selectedCheck);
      expect(checkIconOf(tester, 'c'), AppIcons.selectionUnchecked);

      // Tap 'c' → ADDED to the group (audit: drawer-can't-extend-multi).
      await tapRow(tester, 'c');
      expect(
        c.read(selectionControllerProvider).selectedIds,
        unorderedEquals(['a', 'b', 'c']),
      );
      expect(checkIconOf(tester, 'c'), AppIcons.selectedCheck);
      expect(c.read(selectionModeProvider), SelectionMode.multi);

      // Tap 'c' again → removed.
      await tapRow(tester, 'c');
      expect(
        c.read(selectionControllerProvider).selectedIds,
        unorderedEquals(['a', 'b']),
      );
      expect(checkIconOf(tester, 'c'), AppIcons.selectionUnchecked);
    });

    testWidgets('dropping below 2 members keeps the mode armed — the '
        'drawer obeys the same lifetime rule as the canvas (ux-audit '
        'P2-5)', (tester) async {
      final c = _container(tester);
      _addRect(c, id: 'a', position: const Offset(100, 100));
      _addRect(c, id: 'b', position: const Offset(200, 200));
      c.read(selectionModeProvider.notifier).enterMulti();
      c.read(selectionControllerProvider.notifier).selectMany(['a', 'b']);
      await pumpPanel(tester, c);

      // Toggle down to 1, then 0: membership edits never end the
      // mode. The drawer used to exitMulti here while the canvas kept
      // the mode armed (invisibly) — the unified rule is explicit
      // exits only, with the chip visible throughout.
      await tapRow(tester, 'b');
      expect(c.read(selectionModeProvider), SelectionMode.multi);
      expect(c.read(selectionControllerProvider).selectedIds, ['a']);

      await tapRow(tester, 'a');
      expect(c.read(selectionModeProvider), SelectionMode.multi);
      expect(c.read(selectionControllerProvider).hasSelection, isFalse);

      // Still toggle grammar on the way back up: rows ADD to the
      // group instead of replacing, so building from zero works.
      await tapRow(tester, 'a');
      await tapRow(tester, 'b');
      expect(
        c.read(selectionControllerProvider).selectedIds,
        unorderedEquals(['a', 'b']),
        reason: 'armed at count 0, row taps toggle IN — not replace',
      );
      expect(c.read(selectionModeProvider), SelectionMode.multi);
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
      expect(checkIconOf(tester, 'lock'), AppIcons.selectionUnchecked);
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

  group('multi-select lifetime across surfaces (ux-audit P2-5)', () {
    // The audit's root cause: the drawer's below-2 rule and the
    // canvas's absence of one were each tested on their own harness,
    // which is exactly how they drifted. This test mounts BOTH
    // surfaces over one container and walks a single armed mode
    // through every count via alternating surfaces, pinning the one
    // lifetime rule: armed — with the chip visible — at any count,
    // until an explicit exit.
    testWidgets('canvas and drawer share one rule: armed and visible at '
        'every count until an explicit exit', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = _container(tester);
      _addRect(c, id: 'a', position: const Offset(100, 100));
      _addRect(c, id: 'b', position: const Offset(300, 300));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox(height: 500, child: EditorCanvas()),
                  Expanded(child: LayersPanel()),
                ],
              ),
            ),
          ),
        ),
      );
      // Two pumps: the second lets the post-frame viewport auto-fit
      // land before doc→screen mapping is computed.
      await tester.pump();
      await tester.pump();

      Offset toScreen(Offset docPoint) {
        final v = c.read(viewportControllerProvider);
        return docPoint * v.scale + v.translation;
      }

      // Canvas taps pump 500ms so the 400ms double-tap window can
      // never glue two deliberate toggles together.
      Future<void> canvasTap(Offset docPoint) async {
        await tester.tapAt(toScreen(docPoint));
        await tester.pump(const Duration(milliseconds: 500));
      }

      Future<void> drawerTap(String id) async {
        await tester.tap(
          find.descendant(
            of: find.byKey(ValueKey(id)),
            matching: find.byType(LayerThumbnail),
          ),
        );
        await tester.pump();
      }

      final chip = find.byKey(const ValueKey('multi-select-exit-chip'));
      SelectionMode mode() => c.read(selectionModeProvider);
      List<String> ids() =>
          c.read(selectionControllerProvider).selectedIds.toList();

      // Arm from empty canvas (long-press): count 0, chip already up.
      final gesture = await tester.startGesture(
        toScreen(const Offset(700, 700)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
      expect(mode(), SelectionMode.multi);
      expect(chip, findsOneWidget);

      // Build to 2 via CANVAS taps (layer centres).
      await canvasTap(const Offset(130, 130));
      await canvasTap(const Offset(330, 330));
      expect(ids(), unorderedEquals(['a', 'b']));
      expect(chip, findsOneWidget);

      // Drop to 1 via the DRAWER — the surface that used to exitMulti
      // here on its own.
      await drawerTap('b');
      expect(
        mode(),
        SelectionMode.multi,
        reason:
            'a drawer toggle below 2 must not end the mode the '
            'canvas would keep armed',
      );
      expect(ids(), ['a']);
      expect(chip, findsOneWidget);

      // Drop to 0 via a CANVAS toggle. At this zoom the corner-handle
      // halos blanket the small layer — the tap routes through the
      // handle's sub-slop forward (handle_drag_detector.onTap), which
      // is exactly the path this pins.
      await canvasTap(const Offset(130, 130));
      expect(c.read(selectionControllerProvider).hasSelection, isFalse);
      expect(mode(), SelectionMode.multi);
      expect(chip, findsOneWidget);

      // Armed still means toggle grammar — on BOTH surfaces.
      await drawerTap('a');
      expect(ids(), ['a']);
      await canvasTap(const Offset(330, 330));
      expect(ids(), unorderedEquals(['a', 'b']));
      expect(mode(), SelectionMode.multi);

      // Explicit exit (E3): tap empty canvas ends the mode, clears
      // the selection, and takes the chip with it.
      await canvasTap(const Offset(700, 700));
      expect(mode(), SelectionMode.single);
      expect(c.read(selectionControllerProvider).hasSelection, isFalse);
      expect(chip, findsNothing);
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
