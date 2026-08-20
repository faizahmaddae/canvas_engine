import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/interaction_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/application/viewport_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tap latency + double-tap window + long-press-on-selected (tb3 3/7).
///
/// The canvas GestureDetector no longer registers a double-tap
/// recogniser, so plain taps resolve INSTANTLY instead of waiting out
/// the ~300ms double-tap timeout. The double-tap window is plain
/// bookkeeping inside `_handleTap` (400ms Timer + kDoubleTapSlop
/// radius + same-layer check) shared by BOTH tap entry paths — the
/// canvas detector and the selection overlay's re-injected onBodyTap.
/// The selected layer's chrome-quad claim defers its session start to
/// the slop crossing, which is what lets a stationary hold on the
/// SELECTED layer reach the long-press timer (multi-select entry).

ProviderContainer _setupCanvas(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

void _addRect(
  ProviderContainer container, {
  required String id,
  required Offset position,
  Size size = const Size(60, 60),
}) {
  container
      .read(documentControllerProvider.notifier)
      .execute(
        AddLayerCommand(
          ShapeLayer(
            id: id,
            transform: LayerTransform(position: position, size: size),
            kind: ShapeKind.rectangle,
          ),
        ),
      );
}

Future<void> _pumpCanvas(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: EditorCanvas())),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Offset _toScreen(ProviderContainer container, Offset canvas) {
  final vp = container.read(viewportControllerProvider);
  return canvas * vp.scale + vp.translation;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('first tap from empty selection selects INSTANTLY — no '
      'double-tap-timeout wait', (tester) async {
    final container = _setupCanvas(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(container, id: 'shape', position: const Offset(370, 370));
    await _pumpCanvas(tester, container);
    expect(container.read(selectionControllerProvider).hasSelection, isFalse);

    await tester.tapAt(_toScreen(container, const Offset(400, 400)));
    // 50ms is far inside the old ~300ms double-tap hold; the tap must
    // already have resolved.
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      container.read(selectionControllerProvider).selectedId,
      'shape',
      reason:
          'With no DoubleTapGestureRecognizer in the arena the tap '
          'must win immediately on lift.',
    );
    // Drain the double-tap window timer.
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('double-tap on a SELECTED text layer opens the editor '
      '(the chrome-quad tap path shares the window bookkeeping)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(documentControllerProvider.notifier);
    ctrl.newDocument(width: 400, height: 300);
    ctrl.execute(
      AddLayerCommand(
        const TextLayer(
          id: 'text-1',
          transform: LayerTransform(
            position: Offset(40, 40),
            size: Size(320, 120),
          ),
          content: 'Hello',
          style: TextStyleSpec(fontSize: 48),
        ),
      ),
    );
    // Pre-select the text layer: both taps of the double now route
    // through the selection overlay's body surface (eager arena
    // claim) and its re-injected onBodyTap — the audit's dead path.
    container.read(selectionControllerProvider.notifier).select('text-1');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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

    final target = tester.getCenter(find.text('Hello'));
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(container.read(selectionControllerProvider).selectedId, 'text-1');
    expect(
      find.byType(TextField),
      findsOneWidget,
      reason:
          'Double-tap on the selected text layer must open the '
          'keyboard editor.',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Hello',
    );
  });

  testWidgets('shapes never arm the double-tap window — a fast second tap '
      'cycles to the layer beneath immediately', (tester) async {
    // ux-audit P3-8: arming on every kind consumed one dead tap per
    // cycle step for layers with no double-tap action. The window is
    // now armed only where a double exists (editable text).
    final container = _setupCanvas(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(
      container,
      id: 'below',
      position: const Offset(350, 350),
      size: const Size(120, 120),
    );
    _addRect(
      container,
      id: 'top',
      position: const Offset(370, 370),
      size: const Size(60, 60),
    );
    await _pumpCanvas(tester, container);

    final spot = _toScreen(container, const Offset(400, 400));
    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 50));
    expect(container.read(selectionControllerProvider).selectedId, 'top');

    // Fast second tap: no window to consume it — cycles immediately.
    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      container.read(selectionControllerProvider).selectedId,
      'below',
      reason: 'no double-tap action → no dead tap between cycle steps',
    );
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('long-press ON the selected layer enters multi-select mode '
      'with the layer kept in the selection', (tester) async {
    final container = _setupCanvas(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(container, id: 'shape', position: const Offset(370, 370));
    container.read(selectionControllerProvider.notifier).select('shape');
    await _pumpCanvas(tester, container);
    expect(container.read(selectionModeProvider), SelectionMode.single);

    // Hold on the selected layer's body without moving. The overlay
    // claims the arena on down, but with defer-start-at-slop no
    // session begins — so the recogniser's long-press timer fires and
    // re-injects the intent (previously dead: the eager start
    // short-circuited the timer).
    final gesture = await tester.startGesture(
      _toScreen(container, const Offset(400, 400)),
    );
    await tester.pump();
    expect(
      container.read(interactionControllerProvider).session,
      isNull,
      reason: 'Claim ≠ start: a stationary hold must not open a session.',
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(
      container.read(selectionModeProvider),
      SelectionMode.multi,
      reason: 'Long-press on the SELECTED layer must enter multi mode.',
    );
    expect(
      container.read(selectionControllerProvider).selectedIds,
      contains('shape'),
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('on-quad drag still translates the selected layer and commits '
      'exactly ONE undo entry (start-at-slop changes feel by ≤ kTouchSlop '
      'only)', (tester) async {
    final container = _setupCanvas(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(container, id: 'shape', position: const Offset(370, 370));
    container.read(selectionControllerProvider.notifier).select('shape');
    await _pumpCanvas(tester, container);

    final gesture = await tester.startGesture(
      _toScreen(container, const Offset(400, 400)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();

    final session = container.read(interactionControllerProvider).session;
    expect(session, isNotNull);
    expect(session!.layerId, 'shape');

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final moved = container
        .read(documentControllerProvider)
        .layerById('shape')!;
    expect(moved.transform.position, isNot(const Offset(370, 370)));

    // ONE entry: first undo restores the position, second pops the
    // AddLayerCommand.
    final docCtl = container.read(documentControllerProvider.notifier);
    docCtl.undo();
    expect(
      container
          .read(documentControllerProvider)
          .layerById('shape')!
          .transform
          .position,
      const Offset(370, 370),
    );
    docCtl.undo();
    expect(
      container.read(documentControllerProvider).layerById('shape'),
      isNull,
    );
  });
}
