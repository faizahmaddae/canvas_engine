// tb4 3/14: selecting a committed stroke opens the paint dock in
// RESTYLE mode. The strip is keyed off the layer's kind (not off an
// armed tool), every tile shows that layer's values, and the slots
// that used to be hidden behind a safety guard — blur, polygon,
// dash — now edit the layer for real.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/editor_mode_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/paint/application/paint_tool_controller.dart';
import 'package:canvas_engine/features/editor/paint/domain/paint_tool_type.dart';
import 'package:canvas_engine/features/editor/paint/presentation/paint_mode_toolbar.dart';
import 'package:canvas_engine/features/editor/paint/presentation/paint_tool_specs.dart';
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

  Future<void> pumpStrip(WidgetTester tester, ProviderContainer c) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SizedBox(width: 800, height: 140, child: PaintModeToolbar()),
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
      expect(view.blurRadius, 24);
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
  });

  group('the capability matrix is the layer\'s, not a tool\'s', () {
    test('a polygon exposes sides; a blur patch does not', () {
      expect(allowedPaintSlotsForKind(PaintKind.polygon), contains('polygon'));
      expect(
        allowedPaintSlotsForKind(PaintKind.blur),
        isNot(contains('polygon')),
      );
      expect(allowedPaintSlotsForKind(PaintKind.blur), contains('blur'));
      expect(allowedPaintSlotsForKind(PaintKind.line), contains('dash'));
      expect(
        allowedPaintSlotsForKind(PaintKind.rectangle),
        isNot(contains('dash')),
      );
    });

    testWidgets('the polygon tile renders for a selected polygon', (
      tester,
    ) async {
      final c = makeContainer(PaintKind.polygon);
      await pumpStrip(tester, c);
      // Before tb4 3/14 a safety guard stripped this tile whenever a
      // paint layer was selected, because the setter behind it only
      // moved a session default.
      expect(find.byIcon(Icons.pentagon_outlined), findsOneWidget);
    });

    testWidgets('no tool picker is auto-opened over a selection', (
      tester,
    ) async {
      final c = makeContainer(PaintKind.rectangle);
      await pumpStrip(tester, c);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        c.read(paintToolControllerProvider).openSlot,
        isNull,
        reason:
            'the picker would hide the capsule and answer the wrong '
            'question',
      );
    });
  });

  group('the previously-hidden setters now edit the layer', () {
    test('sides', () {
      final c = makeContainer(PaintKind.polygon);
      c.read(paintToolControllerProvider.notifier).setPolygonSides(9);
      expect(committed(c).sides, 9);
      c.read(documentControllerProvider.notifier).undo();
      expect(committed(c).sides, 5);
    });

    test('blur sigma, but only on a blur patch', () {
      final blurDoc = makeContainer(PaintKind.blur);
      blurDoc.read(paintToolControllerProvider.notifier).setBlurRadius(48);
      expect(committed(blurDoc).blurSigma, 48);

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
  });
}
