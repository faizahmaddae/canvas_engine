import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/export/document_png_exporter.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/engine/rendering/document_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifies the PNG export pipeline:
///
///   * captures a [RepaintBoundary] containing only the document
///     (no chrome from the editor canvas);
///   * honours [pixelRatio] so the output is high-resolution and
///     not blurry;
///   * survives across visible / hidden layers and mixed types;
///   * surfaces a [DocumentExportException] (never a raw error or a
///     blank PNG) for misuse.
///
/// Tests intentionally avoid mounting the full [EditorCanvas] — the
/// exporter must work standalone, and that is exactly what the public
/// contract of [DocumentPngExporter] promises.
void main() {
  EditorDocument simpleDoc({double width = 200, double height = 100}) {
    return EditorDocument(
      width: width,
      height: height,
      layers: const [
        ShapeLayer(
          id: 'bg',
          transform: LayerTransform(
            position: Offset(0, 0),
            size: Size(200, 100),
          ),
          kind: ShapeKind.rectangle,
          fillColor: Color(0xFFFF0000),
        ),
      ],
    );
  }

  group('captureBoundary (low-level)', () {
    testWidgets('produces a non-empty PNG with the expected dimensions',
        (tester) async {
      final boundaryKey = GlobalKey();
      final doc = simpleDoc();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: DocumentView(document: doc),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // `RenderRepaintBoundary.toImage` schedules engine-side raster
      // work that the fake-async test scheduler does not advance —
      // hence `tester.runAsync` is mandatory here.
      final bytes = await tester.runAsync(() {
        return DocumentPngExporter.captureBoundary(
          boundaryKey: boundaryKey,
          pixelRatio: 2.0,
        );
      });

      expect(bytes, isA<Uint8List>());
      expect(bytes!, isNotEmpty);
      // PNG magic number: 89 50 4E 47 0D 0A 1A 0A.
      expect(
        bytes.sublist(0, 8),
        equals(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
      );

      // Decode the PNG and verify pixel dimensions match
      // doc * pixelRatio — proves [pixelRatio] is honoured and
      // output is not blurry.
      final image = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        return frame.image;
      });
      expect(image!.width, (doc.width * 2.0).round());
      expect(image.height, (doc.height * 2.0).round());
      image.dispose();
    });

    testWidgets('higher pixel ratio produces a larger image', (tester) async {
      final keyA = GlobalKey();
      final keyB = GlobalKey();
      final doc = simpleDoc();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              RepaintBoundary(
                key: keyA,
                child: DocumentView(document: doc),
              ),
              Positioned(
                left: 1000,
                child: RepaintBoundary(
                  key: keyB,
                  child: DocumentView(document: doc),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final low = await tester.runAsync(() => DocumentPngExporter.captureBoundary(
            boundaryKey: keyA,
            pixelRatio: 1.0,
          ));
      final high = await tester.runAsync(() => DocumentPngExporter.captureBoundary(
            boundaryKey: keyB,
            pixelRatio: 3.0,
          ));

      expect(high!.length, greaterThan(low!.length));
    });

    testWidgets('throws DocumentExportException when key is unattached',
        (tester) async {
      final orphan = GlobalKey();
      await tester.pumpWidget(const SizedBox());
      expect(
        () => DocumentPngExporter.captureBoundary(boundaryKey: orphan),
        throwsA(isA<DocumentExportException>()),
      );
    });

    testWidgets('mixed-type document with hidden layer renders', (tester) async {
      // Mixing a visible shape, a hidden shape, and a text layer
      // sanity-checks that the renderer follows visibility flags +
      // doesn't crash on text content.
      final boundaryKey = GlobalKey();
      final doc = EditorDocument(
        width: 300,
        height: 200,
        layers:  [
          ShapeLayer(
            id: 'bg',
            transform: LayerTransform(
              position: Offset(0, 0),
              size: Size(300, 200),
            ),
            kind: ShapeKind.rectangle,
            fillColor: Color(0xFF222222),
          ),
          ShapeLayer(
            id: 'hidden',
            transform: LayerTransform(
              position: Offset(50, 50),
              size: Size(100, 100),
            ),
            kind: ShapeKind.circle,
            fillColor: Color(0xFFFF00FF),
            visible: false,
          ),
          TextLayer(
            id: 't1',
            transform: LayerTransform(
              position: Offset(20, 20),
              size: Size(260, 60),
            ),
            content: 'Hello',
            style: TextStyleSpec(
              fontSize: 32,
              color: Color(0xFFFFFFFF),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        // ProviderScope is required because TextLayer.buildContent uses
        // a ConsumerWidget internally (for live edit-mode switching).
        // In production the editor canvas always lives under one.
        ProviderScope(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: boundaryKey,
              child: DocumentView(document: doc),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bytes = await tester.runAsync(() => DocumentPngExporter.captureBoundary(
            boundaryKey: boundaryKey,
          ));
      expect(bytes!, isNotEmpty);
    });
  });

  group('DocumentView (chrome-free contract)', () {
    testWidgets('does not paint any chrome widgets', (tester) async {
      final doc = simpleDoc();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: DocumentView(document: doc),
        ),
      );
      // The set of widgets that constitute editor chrome — none of
      // them should appear in a pure DocumentView render.
      expect(find.byType(GestureDetector), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('lays out at exactly document.width × document.height',
        (tester) async {
      final doc = simpleDoc(width: 640, height: 480);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: DocumentView(document: doc)),
        ),
      );
      // The outermost SizedBox in DocumentView should be 640×480.
      final sized = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .firstWhere((s) => s.width == 640 && s.height == 480);
      expect(sized, isNotNull);
    });
  });

  group('export (high-level)', () {
    testWidgets('throws DocumentExportException when no Overlay in context',
        (tester) async {
      // A bare Directionality has no Overlay ancestor. The exporter
      // must surface this with a clear error rather than silently
      // failing or hanging.
      late BuildContext capturedContext;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await expectLater(
        DocumentPngExporter.export(
          context: capturedContext,
          document: simpleDoc(),
        ),
        throwsA(isA<DocumentExportException>()),
      );
    });
  });
}
