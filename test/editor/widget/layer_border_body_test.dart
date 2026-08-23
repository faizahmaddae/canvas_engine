import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_layer.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/image/presentation/image_style_body.dart';
import 'package:canvas_engine/features/editor/shape/presentation/shape_border_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the Phase 4 §4.2 clone merge: `LayerBorderBody`
/// unifies `ShapeBorderBody`/`ImageBorderBody` behind an adapter, but the
/// two panels have real behavioural divergences that must survive the
/// merge exactly — this locks those in rather than relying on structural
/// resemblance alone.
void main() {
  ShapeLayer makeShapeLayer({
    ShapeKind kind = ShapeKind.rectangle,
    Color? strokeColor,
    double strokeWidth = 0,
  }) {
    return ShapeLayer(
      id: 'shape1',
      transform: const LayerTransform(
        position: Offset(40, 40),
        size: Size(200, 200),
      ),
      kind: kind,
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
    );
  }

  ImageLayer makeImageLayer() {
    return ImageLayer(
      id: 'img1',
      transform: const LayerTransform(
        position: Offset(40, 40),
        size: Size(200, 200),
      ),
      source: const ImageSource.asset('stub.png'),
    );
  }

  ProviderContainer makeContainer(EditorLayer layer) {
    final c = ProviderContainer();
    c
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    c.read(documentControllerProvider.notifier).execute(AddLayerCommand(layer));
    addTearDown(c.dispose);
    return c;
  }

  group('ShapeBorderBody — stroked-kind gate', () {
    testWidgets('non-stroked kind shows None chip, Thickness label, and '
        'the Colour section', (tester) async {
      final layer = makeShapeLayer();
      final container = makeContainer(layer);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: ShapeBorderBody(layer: layer)),
          ),
        ),
      );

      expect(find.text('Thickness'), findsOneWidget);
      expect(find.text('Stroke width'), findsNothing);
      expect(find.text('None'), findsOneWidget);
      expect(find.text('Color'), findsOneWidget);
    });

    testWidgets('stroked kind (line) hides None chip, the Colour section, '
        'and shows Stroke width instead of Thickness', (tester) async {
      final layer = makeShapeLayer(kind: ShapeKind.line, strokeWidth: 4);
      final container = makeContainer(layer);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: ShapeBorderBody(layer: layer)),
          ),
        ),
      );

      expect(find.text('Stroke width'), findsOneWidget);
      expect(find.text('Thickness'), findsNothing);
      expect(find.text('None'), findsNothing);
      expect(find.text('Color'), findsNothing);
    });
  });

  group('ShapeBorderBody — None-chip clears colour (clearColor semantic)', () {
    testWidgets('tapping None on a border-on shape clears strokeColor', (
      tester,
    ) async {
      final layer = makeShapeLayer(
        strokeColor: const Color(0xFFFF0000),
        strokeWidth: 6,
      );
      final container = makeContainer(layer);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: ShapeBorderBody(layer: layer)),
          ),
        ),
      );

      await tester.tap(find.text('None'));
      await tester.pump();

      final updated =
          container.read(documentControllerProvider).layerById('shape1')
              as ShapeLayer;
      expect(updated.strokeWidth, 0);
      expect(updated.strokeColor, isNull);
    });
  });

  group('ImageBorderSection — no stroked-kind gate, always full panel', () {
    testWidgets('shows None chip, Colour section, and the precision '
        'slider even with no border set', (tester) async {
      final layer = makeImageLayer();
      final container = makeContainer(layer);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: ImageBorderSection(layer: layer)),
          ),
        ),
      );

      expect(find.text('Thickness'), findsOneWidget);
      expect(find.text('None'), findsOneWidget);
      expect(find.text('Color'), findsOneWidget);
      expect(find.text('Adjust precisely'), findsOneWidget);
    });

    testWidgets('tapping None only zeroes width — colour is untouched', (
      tester,
    ) async {
      final layer = makeImageLayer();
      final container = makeContainer(layer);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: ImageBorderSection(layer: layer)),
          ),
        ),
      );

      await tester.tap(find.text('None'));
      await tester.pump();

      final updated =
          container.read(documentControllerProvider).layerById('img1')
              as ImageLayer;
      expect(updated.borderWidth, 0);
      expect(updated.borderColor, const Color(0xFF000000));
    });
  });
}
