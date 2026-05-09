import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/viewport_state.dart';
import 'package:canvas_engine/features/editor/engine/rendering/document_view.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/canvas_framing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Canvas framing is editor-only', () {
    testWidgets('DocumentView (export path) does not include CanvasFraming',
        (tester) async {
      // The exporter renders documents through DocumentView. If that
      // tree ever started painting CanvasFraming, the hairline border
      // and dim mask would leak into the exported bitmap. Lock the
      // contract here with a widget-tree assertion.
      final doc = EditorDocument(layers: const [], width: 200, height: 200);
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: DocumentView(document: doc)),
      ));
      expect(find.byType(CanvasFraming), findsNothing);
    });
  });

  group('CanvasFraming border emphasis', () {
    testWidgets('standard and subtle produce distinct painters',
        (tester) async {
      // The border alpha is encoded in the painter swapped onto the
      // CustomPaint. Use shouldRepaint to prove a standard->subtle
      // swap actually triggers a repaint -- if the field were ignored
      // the painter would consider them equal and skip the redraw,
      // visually leaving the wrong colour on screen.
      const docSize = Size(400, 300);
      const viewport = ViewportState.identity;

      Widget framing(CanvasBorderEmphasis e) => Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 800,
              height: 600,
              child: Stack(
                children: [
                  CanvasFraming(
                    docSize: docSize,
                    viewport: viewport,
                    layer: CanvasFramingLayer.dimAndBorderAbove,
                    borderEmphasis: e,
                  ),
                ],
              ),
            ),
          );

      await tester.pumpWidget(framing(CanvasBorderEmphasis.standard));
      final standardPainter =
          tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!;

      await tester.pumpWidget(framing(CanvasBorderEmphasis.subtle));
      final subtlePainter =
          tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!;

      // The painter is private but exposes a CustomPainter contract:
      // shouldRepaint between the two emphases must be true, proving
      // the field actually changes paint output.
      expect(subtlePainter.shouldRepaint(standardPainter), isTrue);
      // And same emphasis -> no repaint, proving equality is sound.
      await tester.pumpWidget(framing(CanvasBorderEmphasis.subtle));
      final subtlePainter2 =
          tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!;
      expect(subtlePainter2.shouldRepaint(subtlePainter), isFalse);
    });

    test('default emphasis is standard', () {
      // Lock the default so blank/design projects keep the loud
      // border without a callsite needing to opt-in.
      const widget = CanvasFraming(
        docSize: Size(100, 100),
        viewport: ViewportState(scale: 1, translation: Offset.zero),
        layer: CanvasFramingLayer.dimAndBorderAbove,
      );
      expect(widget.borderEmphasis, CanvasBorderEmphasis.standard);
    });
  });
}
