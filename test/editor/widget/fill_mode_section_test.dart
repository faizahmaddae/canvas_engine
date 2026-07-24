// tb4 2/14: the Solid | Gradient authoring control. The engine has
// always been able to CARRY a gradient (templates ship them, both
// fill commands invert one correctly since tb0); these pins cover the
// half that was missing — authoring one, and getting back out again
// without losing the colour you came in with.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/canvas/application/canvas_commands.dart';
import 'package:canvas_engine/features/editor/canvas/presentation/canvas_panel_body.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/background_fill.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/shape/presentation/shape_style_body.dart';
import 'package:canvas_engine/features/editor/ui/fill_mode_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const seed = Color(0xFF3366CC);

  ShapeLayer makeShape({BackgroundFill? fill}) => ShapeLayer(
    id: 'sh1',
    kind: ShapeKind.rectangle,
    transform: const LayerTransform(
      position: Offset(40, 40),
      size: Size(200, 200),
    ),
    fillColor: seed,
    fill: fill,
  );

  ProviderContainer makeContainer({ShapeLayer? layer}) {
    final c = ProviderContainer();
    c
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    if (layer != null) {
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(layer));
    }
    addTearDown(c.dispose);
    return c;
  }

  Future<void> pumpBody(
    WidgetTester tester,
    ProviderContainer container,
    Widget body,
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
          home: Scaffold(body: SingleChildScrollView(child: body)),
        ),
      ),
    );
  }

  ShapeLayer shapeOf(ProviderContainer c) =>
      c.read(documentControllerProvider).layerById('sh1') as ShapeLayer;

  Future<void> tapGradient(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('fill-mode-gradient')));
    await tester.pump();
  }

  group('shape fill', () {
    testWidgets('switching to Gradient seeds from the current colour', (
      tester,
    ) async {
      final c = makeContainer(layer: makeShape());
      await pumpBody(tester, c, ShapeStyleBody(layer: shapeOf(c)));

      expect(shapeOf(c).fill, isNull, reason: 'starts as a legacy solid');
      await tapGradient(tester);

      final fill = shapeOf(c).fill;
      expect(fill, isA<LinearGradientBackground>());
      final linear = fill as LinearGradientBackground;
      expect(
        linear.startColor,
        seed,
        reason: 'the gradient starts from the colour the user already had',
      );
      expect(linear.endColor, isNot(seed));
      expect(linear.angleDegrees, kDefaultGradientAngle);
    });

    testWidgets('one undo takes the gradient back off', (tester) async {
      final c = makeContainer(layer: makeShape());
      await pumpBody(tester, c, ShapeStyleBody(layer: shapeOf(c)));

      await tapGradient(tester);
      expect(shapeOf(c).fill, isA<LinearGradientBackground>());

      c.read(documentControllerProvider.notifier).undo();
      expect(shapeOf(c).fill, isNull);
      expect(shapeOf(c).fillColor, seed);
    });

    testWidgets('a preset tap installs that pair and keeps the angle', (
      tester,
    ) async {
      final c = makeContainer(
        layer: makeShape(
          fill: const LinearGradientBackground(
            startColor: Color(0xFF000000),
            endColor: Color(0xFFFFFFFF),
            angleDegrees: 40,
          ),
        ),
      );
      await pumpBody(tester, c, ShapeStyleBody(layer: shapeOf(c)));

      final preset = kGradientPresets.first;
      await tester.tap(find.byKey(const ValueKey('gradient-preset-0')));
      await tester.pump();

      final fill = shapeOf(c).fill;
      expect(fill, isA<LinearGradientBackground>());
      final linear = fill as LinearGradientBackground;
      expect((linear.startColor, linear.endColor), preset);
      expect(
        linear.angleDegrees,
        40,
        reason: 'picking colours must not reset the direction',
      );
    });

    testWidgets('switching back to Solid keeps the gradient start colour', (
      tester,
    ) async {
      const start = Color(0xFF11AA22);
      final c = makeContainer(
        layer: makeShape(
          fill: const LinearGradientBackground(
            startColor: start,
            endColor: Color(0xFF000000),
          ),
        ),
      );
      await pumpBody(tester, c, ShapeStyleBody(layer: shapeOf(c)));

      await tester.tap(find.byKey(const ValueKey('fill-mode-solid')));
      await tester.pump();

      expect(shapeOf(c).fill, isNull);
      expect(shapeOf(c).fillColor, start);
    });

    testWidgets('stroked kinds get no gradient switch', (tester) async {
      final c = makeContainer(
        layer: ShapeLayer(
          id: 'sh1',
          kind: ShapeKind.line,
          transform: const LayerTransform(
            position: Offset(40, 40),
            size: Size(200, 4),
          ),
          fillColor: seed,
        ),
      );
      await pumpBody(tester, c, ShapeStyleBody(layer: shapeOf(c)));

      expect(find.byType(FillModeSection), findsNothing);
    });
  });

  group('canvas background', () {
    testWidgets('authors a gradient and undo restores the solid', (
      tester,
    ) async {
      final c = makeContainer();
      await pumpBody(tester, c, const CanvasPanelBody());

      final before = c.read(documentControllerProvider).background;
      expect(before, isA<SolidBackground>());

      await tapGradient(tester);
      expect(
        c.read(documentControllerProvider).background,
        isA<LinearGradientBackground>(),
      );

      c.read(documentControllerProvider.notifier).undo();
      expect(c.read(documentControllerProvider).background, before);
    });

    testWidgets('a template gradient reads as Gradient on open', (
      tester,
    ) async {
      final c = makeContainer();
      c
          .read(documentControllerProvider.notifier)
          .execute(
            const SetCanvasBackgroundCommand(
              fill: LinearGradientBackground(
                startColor: Color(0xFFFF0000),
                endColor: Color(0xFF0000FF),
              ),
            ),
          );
      await pumpBody(tester, c, const CanvasPanelBody());

      // The gradient branch renders the angle slider; the solid
      // branch never does.
      expect(find.byType(Slider), findsOneWidget);
    });
  });
}
