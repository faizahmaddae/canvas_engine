import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/application/viewport_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/paint/application/paint_tool_controller.dart';
import 'package:canvas_engine/features/editor/paint/domain/paint_tool_type.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:canvas_engine/features/editor/toolbar/presentation/mode_done_button.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Paint-mode pointer routing under the interaction contract, §5
/// rows 2/3 (tb3 4/7).
///
///   * 1 finger on the canvas → stroke (row 3); a sub-slop release is
///     a DOT for freestyle, a discrete erase for the eraser, a no-op
///     for two-point kinds — and NEVER a mode exit
///   * 2nd finger while drafting → draft DISCARDED, the pair drives
///     the viewport pinch (row 2 palm/zoom rescue); an in-flight
///     eraser sweep COMMITS instead (§7: overlay previews commit on
///     interruption)
///   * both fingers land before movement → pure viewport pinch, no
///     draft flash (the first point is buffered for
///     EngineConstants.paintDraftBufferLatency / until slop)
///   * mode exit is ONLY the Done pill + the pasteboard tap
///
/// Guards `PaintGestureSurface`'s `_PaintPointerRecognizer` state
/// machine (paint_gesture_surface.dart).

ProviderContainer _setup(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container
      .read(documentControllerProvider.notifier)
      .newDocument(width: 800, height: 800);
  return container;
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

int _paintLayerCount(ProviderContainer c) =>
    c.read(documentControllerProvider).layers.whereType<PaintLayer>().length;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('freestyle tap commits a DOT layer as one history entry', (
    tester,
  ) async {
    final container = _setup(tester);
    container
        .read(paintToolControllerProvider.notifier)
        .selectTool(PaintToolType.freestyle);
    await _pumpCanvas(tester, container);

    final versionBefore = container.read(documentCommitVersionProvider);
    await tester.tapAt(_toScreen(container, const Offset(400, 400)));
    await tester.pump();

    expect(_paintLayerCount(container), 1, reason: 'tap = dot');
    expect(
      container.read(documentCommitVersionProvider),
      versionBefore + 1,
      reason: 'the dot is exactly ONE AddLayer entry',
    );
    final dot = container
        .read(documentControllerProvider)
        .layers
        .whereType<PaintLayer>()
        .single;
    expect(dot.kind, PaintKind.freestyle);
    expect(
      container.read(paintToolControllerProvider).activeTool,
      PaintToolType.freestyle,
      reason: 'drawing a dot must not exit paint mode',
    );

    container.read(documentControllerProvider.notifier).undo();
    expect(_paintLayerCount(container), 0);
  });

  testWidgets('tap with a two-point tool (line) on empty canvas deselects, '
      'commits nothing and the mode stays', (tester) async {
    final container = _setup(tester);
    container
        .read(paintToolControllerProvider.notifier)
        .selectTool(PaintToolType.line);
    await _pumpCanvas(tester, container);

    final versionBefore = container.read(documentCommitVersionProvider);
    await tester.tapAt(_toScreen(container, const Offset(400, 400)));
    await tester.pump();

    expect(_paintLayerCount(container), 0);
    expect(container.read(documentCommitVersionProvider), versionBefore);
    expect(container.read(selectionControllerProvider).hasSelection, isFalse);
    expect(
      container.read(paintToolControllerProvider).activeTool,
      PaintToolType.line,
      reason: 'a stray tap must NOT exit paint mode any more',
    );
  });

  testWidgets('tap with a two-point tool on an existing stroke selects it '
      'for restyling without leaving the mode', (tester) async {
    final container = _setup(tester);
    final ctrl = container.read(paintToolControllerProvider.notifier);
    ctrl.selectTool(PaintToolType.freestyle);
    await _pumpCanvas(tester, container);

    // Draw a stroke, then switch to a two-point tool — selectTool
    // clears the commit-time selection, so the stroke is now an
    // ordinary older layer.
    final f = await tester.startGesture(
      _toScreen(container, const Offset(300, 400)),
      pointer: 81,
    );
    await tester.pump();
    await f.moveBy(const Offset(120, 0));
    await tester.pump();
    await f.up();
    await tester.pump();
    final stroke = container
        .read(documentControllerProvider)
        .layers
        .whereType<PaintLayer>()
        .single;
    ctrl.selectTool(PaintToolType.line);
    expect(container.read(selectionControllerProvider).hasSelection, isFalse);

    final versionBefore = container.read(documentCommitVersionProvider);
    await tester.tapAt(_toScreen(container, const Offset(360, 400)));
    await tester.pump();

    expect(
      container.read(selectionControllerProvider).selectedId,
      stroke.id,
      reason: 'a tap that cannot draw selects the stroke under it',
    );
    expect(container.read(documentCommitVersionProvider), versionBefore);
    expect(
      container.read(paintToolControllerProvider).activeTool,
      PaintToolType.line,
      reason: 'selecting for restyle keeps the tool armed',
    );
  });

  testWidgets('long-press on the pasteboard while a tool is armed does not '
      'hijack the session into multi-select', (tester) async {
    final container = _setup(tester);
    container
        .read(paintToolControllerProvider.notifier)
        .selectTool(PaintToolType.freestyle);
    await _pumpCanvas(tester, container);

    // (4,4) is the screen corner — pasteboard, outside the document
    // board the paint surface covers, so the press reaches the
    // background detector's long-press recogniser.
    final g = await tester.startGesture(const Offset(4, 4), pointer: 91);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await g.up();
    await tester.pump();

    expect(
      container.read(selectionModeProvider),
      SelectionMode.single,
      reason: 'an armed paint session owns its gesture space (§5)',
    );
    expect(
      container.read(paintToolControllerProvider).activeTool,
      PaintToolType.freestyle,
    );
  });

  testWidgets('eraser miss-tap is a silent no-op — no exit, no entry', (
    tester,
  ) async {
    final container = _setup(tester);
    container
        .read(paintToolControllerProvider.notifier)
        .selectTool(PaintToolType.eraser);
    await _pumpCanvas(tester, container);

    final versionBefore = container.read(documentCommitVersionProvider);
    await tester.tapAt(_toScreen(container, const Offset(400, 400)));
    await tester.pump();

    expect(container.read(documentCommitVersionProvider), versionBefore);
    expect(
      container.read(paintToolControllerProvider).activeTool,
      PaintToolType.eraser,
      reason: 'an eraser miss-tap used to exit the mode — it must not',
    );
  });

  testWidgets('second finger during a stroke DISCARDS the draft and drives '
      'the viewport pinch (row 2 rescue)', (tester) async {
    final container = _setup(tester);
    container
        .read(paintToolControllerProvider.notifier)
        .selectTool(PaintToolType.freestyle);
    await _pumpCanvas(tester, container);

    final viewportBefore = container.read(viewportControllerProvider);
    final versionBefore = container.read(documentCommitVersionProvider);

    final f1 = await tester.startGesture(
      _toScreen(container, const Offset(250, 400)),
      pointer: 71,
    );
    await tester.pump();
    // Draw past slop so a draft is in flight.
    await f1.moveBy(const Offset(60, 0));
    await tester.pump();
    await f1.moveBy(const Offset(40, 0));
    await tester.pump();

    // Palm/zoom rescue: second finger lands.
    final f2 = await tester.startGesture(
      _toScreen(container, const Offset(550, 400)),
      pointer: 72,
    );
    await tester.pump();
    await f1.moveBy(const Offset(-80, 0));
    await f2.moveBy(const Offset(80, 0));
    await tester.pump();

    final viewportDuring = container.read(viewportControllerProvider);
    expect(
      viewportDuring.scale,
      greaterThan(viewportBefore.scale),
      reason: 'the pair must zoom the viewport',
    );

    await f1.up();
    await f2.up();
    await tester.pump();

    expect(
      _paintLayerCount(container),
      0,
      reason: 'the in-flight draft must be discarded, not committed',
    );
    expect(container.read(documentCommitVersionProvider), versionBefore);
    expect(
      container.read(paintToolControllerProvider).activeTool,
      PaintToolType.freestyle,
      reason: 'the rescue must not exit paint mode',
    );
  });

  testWidgets('two fingers landing before movement pinch the viewport with '
      'no draft and no layer', (tester) async {
    final container = _setup(tester);
    container
        .read(paintToolControllerProvider.notifier)
        .selectTool(PaintToolType.freestyle);
    await _pumpCanvas(tester, container);

    final viewportBefore = container.read(viewportControllerProvider);

    // Both fingers land inside the buffer window, before any movement.
    final f1 = await tester.startGesture(
      _toScreen(container, const Offset(300, 400)),
      pointer: 73,
    );
    final f2 = await tester.startGesture(
      _toScreen(container, const Offset(500, 400)),
      pointer: 74,
    );
    await tester.pump();
    await f1.moveBy(const Offset(-70, 0));
    await f2.moveBy(const Offset(70, 0));
    await tester.pump();

    expect(
      container.read(viewportControllerProvider).scale,
      greaterThan(viewportBefore.scale),
    );

    await f1.up();
    await f2.up();
    await tester.pump();

    expect(_paintLayerCount(container), 0, reason: 'no draft flash, no dot');
    expect(
      container.read(paintToolControllerProvider).activeTool,
      PaintToolType.freestyle,
    );
  });

  testWidgets('solo stroke still commits exactly one layer, one entry', (
    tester,
  ) async {
    final container = _setup(tester);
    container
        .read(paintToolControllerProvider.notifier)
        .selectTool(PaintToolType.freestyle);
    await _pumpCanvas(tester, container);

    final versionBefore = container.read(documentCommitVersionProvider);
    final gesture = await tester.startGesture(
      _toScreen(container, const Offset(250, 400)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(80, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(80, -20));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(_paintLayerCount(container), 1);
    expect(container.read(documentCommitVersionProvider), versionBefore + 1);
  });

  testWidgets('second finger during an eraser SWEEP commits the sweep '
      '(§7: overlay previews commit on interruption) then navigates', (
    tester,
  ) async {
    final container = _setup(tester);
    final docCtl = container.read(documentControllerProvider.notifier);
    PaintLayer stroke(String id, double x) => PaintLayer(
      id: id,
      transform: LayerTransform(
        position: Offset(x, 350),
        size: const Size(100, 100),
      ),
      kind: PaintKind.line,
      normalizedPoints: const [Offset(0, 0.5), Offset(1, 0.5)],
    );
    docCtl.execute(AddLayerCommand(stroke('a', 200)));
    docCtl.execute(AddLayerCommand(stroke('b', 600)));
    container
        .read(paintToolControllerProvider.notifier)
        .selectTool(PaintToolType.eraser);
    await _pumpCanvas(tester, container);

    final viewportBefore = container.read(viewportControllerProvider);

    // Sweep across stroke 'a' (canvas x 200..300, y 350..450).
    final f1 = await tester.startGesture(
      _toScreen(container, const Offset(220, 400)),
      pointer: 75,
    );
    await tester.pump();
    await f1.moveBy(const Offset(40, 0));
    await tester.pump();

    // Second finger: the sweep must COMMIT (a stays gone) before the
    // pair navigates.
    final f2 = await tester.startGesture(
      _toScreen(container, const Offset(650, 200)),
      pointer: 76,
    );
    await tester.pump();
    expect(
      container.read(documentControllerProvider).layerById('a'),
      isNull,
      reason: 'the interrupted sweep must commit, not resurrect layers',
    );
    expect(
      container.read(documentControllerProvider).layerById('b'),
      isNotNull,
    );

    await f1.moveBy(const Offset(-60, 0));
    await f2.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(
      container.read(viewportControllerProvider).scale,
      greaterThan(viewportBefore.scale),
    );

    await f1.up();
    await f2.up();
    await tester.pump();
  });

  testWidgets('pasteboard tap still exits paint mode', (tester) async {
    final container = _setup(tester);
    container
        .read(paintToolControllerProvider.notifier)
        .selectTool(PaintToolType.freestyle);
    await _pumpCanvas(tester, container);

    // The fitted 800x800 doc leaves a pasteboard margin; a point at
    // half the translation offset is guaranteed to be outside the
    // document board.
    final vp = container.read(viewportControllerProvider);
    expect(vp.translation.dx, greaterThan(8));
    await tester.tapAt(Offset(vp.translation.dx / 2, vp.translation.dy + 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      container.read(paintToolControllerProvider).activeTool,
      isNull,
      reason: 'the pasteboard tap is a sanctioned exit and must stay',
    );
  });

  testWidgets('Done pill still exits paint mode', (tester) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 400, height: 300);
    container
        .read(paintToolControllerProvider.notifier)
        .selectTool(PaintToolType.freestyle);
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

    expect(find.byType(ModeDoneButton), findsWidgets);
    await tester.tap(find.byType(ModeDoneButton).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      container.read(paintToolControllerProvider).activeTool,
      isNull,
      reason: 'the Done pill is the other sanctioned exit',
    );
  });
}
