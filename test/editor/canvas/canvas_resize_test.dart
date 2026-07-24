// tb4 4/14: canvas resize. SetCanvasSizeCommand shipped with the
// crop pipeline and never had a direct unit test — these pin its
// apply/invert contract, plus the anchor policy the new Size section
// layers on top of it (presets recentre, custom keeps top-left).

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/canvas/application/canvas_commands.dart';
import 'package:canvas_engine/features/editor/canvas/application/canvas_resize.dart';
import 'package:canvas_engine/features/editor/canvas/presentation/canvas_panel_body.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/toolbar/presentation/widgets/preset_chip.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ShapeLayer makeShape(String id, Offset position) => ShapeLayer(
    id: id,
    kind: ShapeKind.rectangle,
    transform: LayerTransform(position: position, size: const Size(100, 100)),
    fillColor: const Color(0xFF3366CC),
  );

  EditorDocument docWith(List<ShapeLayer> layers) =>
      EditorDocument(layers: layers, width: 800, height: 800);

  ProviderContainer makeContainer({List<ShapeLayer> layers = const []}) {
    final c = ProviderContainer();
    final notifier = c.read(documentControllerProvider.notifier);
    notifier.newDocument(width: 800, height: 800);
    for (final l in layers) {
      notifier.execute(AddLayerCommand(l));
    }
    addTearDown(c.dispose);
    return c;
  }

  Offset positionOf(ProviderContainer c, String id) =>
      c.read(documentControllerProvider).layerById(id)!.transform.position;

  group('SetCanvasSizeCommand', () {
    test('apply swaps width and height', () {
      final doc = docWith([]);
      final next = const SetCanvasSizeCommand(
        width: 1080,
        height: 1920,
      ).apply(doc);
      expect(next.width, 1080);
      expect(next.height, 1920);
    });

    test('apply returns the identical document when the size matches', () {
      final doc = docWith([]);
      final next = const SetCanvasSizeCommand(
        width: 800,
        height: 800,
      ).apply(doc);
      expect(identical(next, doc), isTrue);
    });

    test('apply leaves layer transforms untouched', () {
      final doc = docWith([makeShape('a', const Offset(40, 60))]);
      final next = const SetCanvasSizeCommand(
        width: 1080,
        height: 1920,
      ).apply(doc);
      expect(next.layerById('a')!.transform.position, const Offset(40, 60));
    });

    test('invert round-trips back to the pre-apply size', () {
      final doc = docWith([]);
      const cmd = SetCanvasSizeCommand(width: 1080, height: 1920);
      final after = cmd.apply(doc);
      final back = cmd.invert(doc).apply(after);
      expect(back.width, 800);
      expect(back.height, 800);
    });
  });

  group('buildCanvasResize', () {
    test('custom (no recentre) leaves every layer position untouched', () {
      final doc = docWith([
        makeShape('a', const Offset(40, 60)),
        makeShape('b', const Offset(300, 500)),
      ]);
      final cmd = buildCanvasResize(
        doc,
        width: 1080,
        height: 1920,
        recenterLayers: false,
      );
      expect(cmd, isA<SetCanvasSizeCommand>());
      final next = cmd.apply(doc);
      expect(next.width, 1080);
      expect(next.height, 1920);
      expect(next.layerById('a')!.transform.position, const Offset(40, 60));
      expect(next.layerById('b')!.transform.position, const Offset(300, 500));
    });

    test('recentre on an empty document is the bare size command', () {
      final doc = docWith([]);
      expect(
        buildCanvasResize(doc, width: 1080, height: 1080, recenterLayers: true),
        isA<SetCanvasSizeCommand>(),
      );
    });

    test('recentre with an unchanged size is the bare size command', () {
      final doc = docWith([makeShape('a', const Offset(40, 60))]);
      expect(
        buildCanvasResize(doc, width: 800, height: 800, recenterLayers: true),
        isA<SetCanvasSizeCommand>(),
      );
    });

    test('recentre shifts every layer by half the size delta', () {
      final doc = docWith([
        makeShape('a', const Offset(40, 60)),
        makeShape('b', const Offset(300, 500)),
      ]);
      final cmd = buildCanvasResize(
        doc,
        width: 1080,
        height: 1920,
        recenterLayers: true,
      );
      expect(cmd, isA<CompositeCommand>());
      expect(cmd.label, 'Resize canvas');

      final next = cmd.apply(doc);
      // (1080-800)/2 = 140, (1920-800)/2 = 560.
      expect(next.layerById('a')!.transform.position, const Offset(180, 620));
      expect(next.layerById('b')!.transform.position, const Offset(440, 1060));
      expect(next.width, 1080);
      expect(next.height, 1920);
    });

    test('one undo restores both the canvas size and every position', () {
      final c = makeContainer(
        layers: [
          makeShape('a', const Offset(40, 60)),
          makeShape('b', const Offset(300, 500)),
        ],
      );
      final notifier = c.read(documentControllerProvider.notifier);
      notifier.execute(
        buildCanvasResize(
          c.read(documentControllerProvider),
          width: 1080,
          height: 1920,
          recenterLayers: true,
        ),
      );
      expect(c.read(documentControllerProvider).width, 1080);
      expect(positionOf(c, 'a'), const Offset(180, 620));

      notifier.undo();
      final doc = c.read(documentControllerProvider);
      expect(doc.width, 800);
      expect(doc.height, 800);
      expect(positionOf(c, 'a'), const Offset(40, 60));
      expect(positionOf(c, 'b'), const Offset(300, 500));

      // The next undo pops the layer that was added before the
      // resize — proof the whole composite was exactly ONE entry, not
      // one per moved layer.
      notifier.undo();
      expect(c.read(documentControllerProvider).layerById('b'), isNull);
    });

    test('growing then undoing preserves the relative offset', () {
      final c = makeContainer(
        layers: [
          makeShape('a', const Offset(40, 60)),
          makeShape('b', const Offset(300, 500)),
        ],
      );
      final gap = positionOf(c, 'b') - positionOf(c, 'a');
      final notifier = c.read(documentControllerProvider.notifier);
      notifier.execute(
        buildCanvasResize(
          c.read(documentControllerProvider),
          width: 2000,
          height: 2000,
          recenterLayers: true,
        ),
      );
      expect(
        positionOf(c, 'b') - positionOf(c, 'a'),
        gap,
        reason: 'a uniform translation cannot change the layout',
      );

      notifier.undo();
      expect(positionOf(c, 'b') - positionOf(c, 'a'), gap);
      expect(positionOf(c, 'a'), const Offset(40, 60));
    });

    test('shrinking can strand a layer outside the canvas (documented)', () {
      final doc = docWith([makeShape('a', const Offset(600, 600))]);
      final next = buildCanvasResize(
        doc,
        width: 400,
        height: 400,
        recenterLayers: false,
      ).apply(doc);
      // The layer is not clamped or dropped — it stays authored where
      // it was, reachable by panning. See buildCanvasResize's doc.
      expect(next.layerById('a'), isNotNull);
      expect(next.layerById('a')!.transform.position, const Offset(600, 600));
    });
  });

  group('Canvas panel Size section', () {
    Future<void> pumpPanel(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: SingleChildScrollView(child: CanvasPanelBody()),
            ),
          ),
        ),
      );
    }

    testWidgets('a preset tap resizes and recentres; one undo restores', (
      tester,
    ) async {
      final c = makeContainer(layers: [makeShape('a', const Offset(40, 60))]);
      await pumpPanel(tester, c);

      await tester.tap(
        find.byKey(const ValueKey('canvas-size-preset-1080x1920')),
      );
      await tester.pump();

      final doc = c.read(documentControllerProvider);
      expect(doc.width, 1080);
      expect(doc.height, 1920);
      expect(positionOf(c, 'a'), const Offset(180, 620));

      c.read(documentControllerProvider.notifier).undo();
      await tester.pump();
      expect(c.read(documentControllerProvider).width, 800);
      expect(positionOf(c, 'a'), const Offset(40, 60));
    });

    testWidgets('the chip matching the document size renders selected', (
      tester,
    ) async {
      final c = makeContainer();
      c
          .read(documentControllerProvider.notifier)
          .execute(const SetCanvasSizeCommand(width: 1080, height: 1080));
      await pumpPanel(tester, c);

      PresetChip chipAt(String key) =>
          tester.widget<PresetChip>(find.byKey(ValueKey(key)));
      expect(chipAt('canvas-size-preset-1080x1080').selected, isTrue);
      expect(chipAt('canvas-size-preset-1080x1350').selected, isFalse);
      expect(chipAt('canvas-size-custom').selected, isFalse);
    });
  });
}
