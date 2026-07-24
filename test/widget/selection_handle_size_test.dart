import 'package:canvas_engine/core/constants/engine_constants.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// At any document size, the selection chrome must keep a constant
/// screen-space size: a 48-dp touch box per handle and a 14-dp corner
/// glyph. If the chrome is mistakenly drawn inside the viewport
/// transform it will scale with the document and these assertions will
/// fail.
void main() {
  Future<void> pumpEditorWithSelectedShape(
    WidgetTester tester, {
    required double docSize,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: docSize, height: docSize);
    container
        .read(documentControllerProvider.notifier)
        .execute(
          AddLayerCommand(
            ShapeLayer(
              id: 'shape',
              transform: LayerTransform(
                position: Offset(docSize / 4, docSize / 4),
                size: Size(docSize / 2, docSize / 2),
              ),
              kind: ShapeKind.rectangle,
            ),
          ),
        );
    container.read(selectionControllerProvider.notifier).select('shape');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: EditorCanvas())),
      ),
    );
    // Let auto-fit + selection overlay materialise.
    await tester.pump();
  }

  void expectConstantHandleSize(WidgetTester tester) {
    // Five 48-dp Positioned hit boxes — FOUR resize corners plus the
    // dedicated rotate knob above the top-centre (tb3 6/7, D-a).
    final touch = EngineConstants.handleTouchSize;
    final hits = find.byWidgetPredicate(
      (w) => w is Positioned && w.width == touch && w.height == touch,
    );
    expect(
      hits,
      findsNWidgets(5),
      reason:
          'Selection should expose 5 fixed-size handle hit boxes '
          '(4 resize corners + the rotate knob) regardless of '
          'document size.',
    );

    // Four corner glyphs are AnimatedContainers sized to
    // handleVisualSize; the stemmed knob renders a _RotateGlyph.
    final visual = EngineConstants.handleVisualSize;
    final glyphs = find.byWidgetPredicate(
      (w) => w is AnimatedContainer && w.constraints?.maxWidth == visual,
    );
    expect(
      glyphs,
      findsNWidgets(4),
      reason:
          'Four corner glyphs must keep their fixed visual size in dp '
          'at any document size; rotation lives on the stemmed knob.',
    );
  }

  testWidgets('handle size is constant on a 512x512 document', (tester) async {
    await pumpEditorWithSelectedShape(tester, docSize: 512);
    expectConstantHandleSize(tester);
  });

  testWidgets('handle size is constant on a 1080x1080 document', (
    tester,
  ) async {
    await pumpEditorWithSelectedShape(tester, docSize: 1080);
    expectConstantHandleSize(tester);
  });

  testWidgets('handle size is constant on a 2000x2000 document', (
    tester,
  ) async {
    await pumpEditorWithSelectedShape(tester, docSize: 2000);
    expectConstantHandleSize(tester);
  });
}
