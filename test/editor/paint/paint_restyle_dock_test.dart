// tb4 3/14, reshaped by the 2026-08 bench redesign: selecting a
// committed stroke puts the paint bench in the ADJUST posture. The
// style row is keyed off the layer's kind (not off an armed tool),
// shows that layer's values, and the setters that used to be hidden
// behind a safety guard — blur, polygon, dash — edit the layer for
// real. The write rule is posture-scoped (docs/paint-redesign-2026-08
// §4): armed writes also re-ink the pen; adjust writes never do.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/editor_mode_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/canvas_sizing.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/paint/application/paint_tool_controller.dart';
import 'package:canvas_engine/features/editor/paint/domain/paint_tool_type.dart';
import 'package:canvas_engine/features/editor/paint/presentation/paint_bench.dart';
import 'package:canvas_engine/features/editor/paint/presentation/bodies/paint_fill_body.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  PaintLayer makeLayer(PaintKind kind) => PaintLayer(
    id: 'p1',
    transform: const LayerTransform(
      position: Offset(20, 20),
      size: Size(300, 200),
    ),
    kind: kind,
    normalizedPoints: const [Offset.zero, Offset(1, 1)],
    strokeColor: const Color(0xFF00AA55),
    strokeWidth: 18,
    sides: 5,
    blurSigma: 24,
  );

  ProviderContainer makeContainer(PaintKind kind) {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final ctrl = c.read(documentControllerProvider.notifier);
    ctrl.newDocument(width: 800, height: 800);
    ctrl.execute(AddLayerCommand(makeLayer(kind)));
    c.read(selectionControllerProvider.notifier).select('p1');
    return c;
  }

  PaintLayer committed(ProviderContainer c) =>
      c.read(documentControllerProvider).layerById('p1') as PaintLayer;

  Future<void> pumpBench(WidgetTester tester, ProviderContainer c) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SizedBox(width: 800, height: 140, child: PaintBench()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  test('a selected stroke owns the paint dock', () {
    final c = makeContainer(PaintKind.polygon);
    expect(c.read(editorToolModeProvider), EditorToolMode.paint);
    expect(
      c.read(paintToolControllerProvider).activeTool,
      isNull,
      reason: 'restyling must not arm the draw surface',
    );
  });

  group('the style view follows the selection', () {
    test('reads the layer, not the session defaults', () {
      final c = makeContainer(PaintKind.polygon);
      final view = c.read(paintStyleViewProvider);
      expect(view.strokeColor, const Color(0xFF00AA55));
      expect(view.strokeWidth, 18);
      expect(view.sides, 5);
      final doc = c.read(documentControllerProvider);
      expect(
        view.blurRadius,
        closeTo(24 / CanvasSizing.scaleFactor(doc), 0.0001),
      );
      expect(view.layerKind, PaintKind.polygon);
    });

    test('falls back to session defaults with nothing selected', () {
      final c = makeContainer(PaintKind.polygon);
      c.read(selectionControllerProvider.notifier).clear();
      final view = c.read(paintStyleViewProvider);
      final session = c.read(paintToolControllerProvider);
      expect(view.strokeWidth, session.strokeWidth);
      expect(view.layerKind, isNull);
    });

    test('armed: a style write reaches the stroke AND the pen', () {
      // §10.5 write rule as amended by the 2026-08 bench redesign
      // (docs/paint-redesign-2026-08.md §4): while a tool is armed,
      // the bound stroke gets the command and the author defaults
      // take the same value — "draw, restyle, draw again" must not
      // produce a stale second stroke.
      final c = makeContainer(PaintKind.rectangle);
      final ctrl = c.read(paintToolControllerProvider.notifier);
      ctrl.selectTool(PaintToolType.freestyle);
      c.read(selectionControllerProvider.notifier).select('p1');

      expect(c.read(paintStyleViewProvider).layerKind, PaintKind.rectangle);
      ctrl.setStrokeWidth(31);

      expect(committed(c).strokeWidth, 31);
      expect(
        c.read(paintToolControllerProvider).strokeWidth,
        31,
        reason: 'the pen keeps the ink while armed',
      );
      expect(
        c.read(paintToolControllerProvider).activeTool,
        PaintToolType.freestyle,
        reason: 'the tool stays armed through a restyle',
      );
    });

    test('adjust posture: a style write reaches the stroke only', () {
      // The unarmed half of the amended rule: editing an old
      // annotation does not re-ink the pen.
      final c = makeContainer(PaintKind.rectangle);
      final ctrl = c.read(paintToolControllerProvider.notifier);
      ctrl.enterAdjust();
      c.read(selectionControllerProvider.notifier).select('p1');
      final defaults = c.read(paintToolControllerProvider);

      ctrl.setStrokeWidth(31);

      expect(committed(c).strokeWidth, 31);
      expect(
        c.read(paintToolControllerProvider).strokeWidth,
        defaults.strokeWidth,
        reason: 'adjust-posture writes must not touch the pen defaults',
      );
      expect(c.read(paintToolControllerProvider).activeTool, isNull);
    });
  });

  group('the style row is the layer\'s, not a tool\'s', () {
    testWidgets('a selected polygon exposes its shape pill', (tester) async {
      final c = makeContainer(PaintKind.polygon);
      await pumpBench(tester, c);
      // Before tb4 3/14 a safety guard stripped these controls
      // whenever a paint layer was selected, because the setters
      // behind them only moved a session default. The fill pill
      // opens the shape sheet, which owns kind + sides + fill.
      expect(find.byKey(const ValueKey('paint-pill-fill')), findsOneWidget);
      expect(find.byKey(const ValueKey('paint-pill-size')), findsOneWidget);
    });

    testWidgets('a selected blur patch shows the radius pill only', (
      tester,
    ) async {
      final c = makeContainer(PaintKind.blur);
      await pumpBench(tester, c);
      expect(find.byKey(const ValueKey('paint-pill-blur')), findsOneWidget);
      expect(find.byKey(const ValueKey('paint-pill-size')), findsNothing);
      expect(find.byKey(const ValueKey('paint-ink-current')), findsNothing);
    });

    testWidgets('a selected line shows the line-style pill; a box does not', (
      tester,
    ) async {
      final line = makeContainer(PaintKind.line);
      await pumpBench(tester, line);
      expect(find.byKey(const ValueKey('paint-pill-line')), findsOneWidget);

      final box = makeContainer(PaintKind.rectangle);
      await pumpBench(tester, box);
      expect(find.byKey(const ValueKey('paint-pill-line')), findsNothing);
      expect(find.byKey(const ValueKey('paint-pill-fill')), findsOneWidget);
    });

    testWidgets('nothing auto-opens over a selection', (tester) async {
      final c = makeContainer(PaintKind.rectangle);
      await pumpBench(tester, c);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        c.read(paintToolControllerProvider).openSlot,
        isNull,
        reason: 'a self-opening sheet would answer the wrong question',
      );
    });

    testWidgets('the rack marks the adjust posture and arming a pen '
        'starts fresh', (tester) async {
      final c = makeContainer(PaintKind.rectangle);
      await pumpBench(tester, c);

      // Bound stroke, no armed tool: the adjust slot is the active one.
      expect(c.read(paintToolControllerProvider).activeTool, isNull);

      await tester.tap(find.byKey(const ValueKey('paint-rack-pen')));
      await tester.pump();
      expect(
        c.read(paintToolControllerProvider).activeTool,
        PaintToolType.freestyle,
      );
      expect(
        c.read(selectionControllerProvider).hasSelection,
        isFalse,
        reason: 'arming a rack tool starts a fresh stroke, not a restyle',
      );
    });
  });

  group('the previously-hidden setters now edit the layer', () {
    testWidgets('fill choices display and copy the selected stroke style', (
      tester,
    ) async {
      final c = makeContainer(PaintKind.rectangle);
      final defaults = c.read(paintToolControllerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: PaintFillBody(view: c.read(paintStyleViewProvider)),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Use stroke color'));
      await tester.pump();

      expect(committed(c).fillColor, const Color(0xFF00AA55));
      expect(c.read(paintToolControllerProvider).fillColor, defaults.fillColor);
    });

    test('sides', () {
      final c = makeContainer(PaintKind.polygon);
      c.read(paintToolControllerProvider.notifier).setPolygonSides(9);
      expect(committed(c).sides, 9);
      c.read(documentControllerProvider.notifier).undo();
      expect(committed(c).sides, 5);
    });

    test('blur sigma, but only on a blur patch', () {
      final blurDoc = makeContainer(PaintKind.blur);
      final doc = blurDoc.read(documentControllerProvider);
      blurDoc.read(paintToolControllerProvider.notifier).setBlurRadius(48);
      expect(
        committed(blurDoc).blurSigma,
        closeTo(CanvasSizing.scaleDimension(48, doc), 0.0001),
      );
      expect(
        blurDoc.read(paintStyleViewProvider).blurRadius,
        closeTo(48, 0.0001),
      );

      final rectDoc = makeContainer(PaintKind.rectangle);
      rectDoc.read(paintToolControllerProvider.notifier).setBlurRadius(48);
      expect(
        committed(rectDoc).blurSigma,
        24,
        reason: 'blur sigma is meaningless on a rectangle',
      );
    });

    test('line style restyles the selected line in place', () {
      final c = makeContainer(PaintKind.line);
      c
          .read(paintToolControllerProvider.notifier)
          .selectLineStyle(PaintToolType.dashLine);
      expect(committed(c).kind, PaintKind.dashLine);
      expect(
        c.read(selectionControllerProvider).selectedId,
        'p1',
        reason: 'restyling must not clear the selection the way arming does',
      );
      c.read(documentControllerProvider.notifier).undo();
      expect(committed(c).kind, PaintKind.line);
    });

    test('line style arms the tool when nothing is selected', () {
      final c = makeContainer(PaintKind.line);
      c.read(selectionControllerProvider.notifier).clear();
      c
          .read(paintToolControllerProvider.notifier)
          .selectLineStyle(PaintToolType.dashLine);
      expect(
        c.read(paintToolControllerProvider).activeTool,
        PaintToolType.dashLine,
      );
    });

    test('line style never crosses into a box kind', () {
      final c = makeContainer(PaintKind.rectangle);
      c
          .read(paintToolControllerProvider.notifier)
          .selectLineStyle(PaintToolType.dashLine);
      expect(committed(c).kind, PaintKind.rectangle);
      expect(
        c.read(paintToolControllerProvider).activeTool,
        PaintToolType.dashLine,
        reason: 'a non-peer pick falls back to arming the tool',
      );
    });

    test('restyling never changes the next-stroke defaults', () {
      final c = makeContainer(PaintKind.polygon);
      final ctrl = c.read(paintToolControllerProvider.notifier);
      final defaults = c.read(paintToolControllerProvider);

      ctrl.setStrokeColor(const Color(0xFF123456));
      ctrl.setStrokeWidth(32);
      ctrl.setFillColor(const Color(0xFF654321));
      ctrl.setPolygonSides(9);

      final after = c.read(paintToolControllerProvider);
      expect(after.strokeColor, defaults.strokeColor);
      expect(after.strokeWidth, defaults.strokeWidth);
      expect(after.fillColor, defaults.fillColor);
      expect(after.polygonSides, defaults.polygonSides);
    });

    test('preview restyles also leave next-stroke defaults alone', () {
      final c = makeContainer(PaintKind.rectangle);
      final ctrl = c.read(paintToolControllerProvider.notifier);
      final defaults = c.read(paintToolControllerProvider);

      ctrl.previewStrokeColor(const Color(0xFF123456));
      ctrl.commitStrokeColor();
      ctrl.previewStrokeWidth(32);
      ctrl.commitStrokeWidth(32);
      ctrl.previewFillColor(const Color(0xFF654321));
      ctrl.commitFillColor();

      final after = c.read(paintToolControllerProvider);
      expect(after.strokeColor, defaults.strokeColor);
      expect(after.strokeWidth, defaults.strokeWidth);
      expect(after.fillColor, defaults.fillColor);
    });
  });
}
