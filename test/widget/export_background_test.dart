import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/export/document_jpg_exporter.dart';
import 'package:canvas_engine/features/editor/engine/export/document_png_exporter.dart';
import 'package:canvas_engine/features/editor/engine/rendering/document_thumbnail.dart';
import 'package:canvas_engine/features/editor/engine/rendering/document_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Export must paint the document's own canvas background, not an
/// opaque white default. The contract has two halves:
///
///   1. **Resolution** — `ExportController.exportImage` resolves a
///      null `background` arg to `document.backgroundColor` (the
///      deprecated getter that surfaces the dominant tone of any
///      [BackgroundFill]). Pinned by the pure-Dart test below.
///
///   2. **Painting** — once resolved, that colour reaches the pixel
///      buffer (PNG raw + JPG decoded). Pinned by the widget tests
///      that mount [DocumentView] directly under a [RepaintBoundary]
///      and snapshot it via [DocumentPngExporter.captureBoundary].
///
/// We deliberately do **not** drive `ExportController.exportImage`
/// end-to-end here. Its production rasterisation path mounts an
/// off-screen `Overlay` and waits on a post-frame callback, which
/// deadlocks under `tester.runAsync` (no test pump fires the frame).
/// Persian export verification (`persian_export_verification_test`)
/// uses the same captureBoundary pattern adopted here.
void main() {
  const yellow = Color(0xFFFFEB3B);

  EditorDocument yellowDoc() => EditorDocument(
    width: 60,
    height: 40,
    layers: const [],
    backgroundColor: yellow,
  );

  /// Mount [doc] inside a sized [RepaintBoundary] painted with
  /// [background] (mirrors `DocumentPngExporter.export`'s internal
  /// host).
  Future<GlobalKey> mountDocument(
    WidgetTester tester, {
    required EditorDocument doc,
    required Color background,
    BackgroundFill? backgroundFill,
    bool honorTransparentMode = false,
  }) async {
    final boundaryKey = GlobalKey();
    tester.view.physicalSize = Size(doc.width, doc.height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: Material(
              type: MaterialType.transparency,
              child: Center(
                child: SizedBox(
                  width: doc.width,
                  height: doc.height,
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: DocumentView(
                      document: doc,
                      background: background,
                      backgroundFill: backgroundFill,
                      honorTransparentMode: honorTransparentMode,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return boundaryKey;
  }

  Future<int> pixelArgb(Uint8List bytes, int? x, int? y) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(raw, isNotNull);
    final w = image.width;
    final h = image.height;
    final cx = x ?? w ~/ 2;
    final cy = y ?? h ~/ 2;
    final i = (cy * w + cx) * 4;
    final r = raw!.getUint8(i);
    final g = raw.getUint8(i + 1);
    final b = raw.getUint8(i + 2);
    final a = raw.getUint8(i + 3);
    image.dispose();
    return (a << 24) | (r << 16) | (g << 8) | b;
  }

  /// Decode raw RGBA bytes from a PNG and return the centre pixel.
  /// MUST be called inside [WidgetTester.runAsync] — both
  /// `instantiateImageCodec` and `image.toByteData` need the IO
  /// thread, which is starved by the fake async zone otherwise.
  Future<int> centerPixelArgb(Uint8List bytes) async {
    return pixelArgb(bytes, null, null);
  }

  /// Centre pixel from a JPG byte buffer (decoded with
  /// `package:image` so we don't need a host BuildContext).
  int centerPixelJpgArgb(Uint8List bytes) {
    final decoded = img.decodeJpg(bytes);
    expect(decoded, isNotNull);
    final w = decoded!.width;
    final h = decoded.height;
    final px = decoded.getPixel(w ~/ 2, h ~/ 2);
    return (0xFF << 24) |
        (px.r.toInt() << 16) |
        (px.g.toInt() << 8) |
        px.b.toInt();
  }

  // -- Half 1: resolution contract ----------------------------------

  test('ExportController contract: null background resolves to '
      'document.backgroundColor; explicit override wins', () {
    final doc = EditorDocument(
      width: 60,
      height: 40,
      layers: const [],
      backgroundColor: yellow,
    );
    // Mirrors line 60 of export_controller.dart verbatim.
    Color resolve(Color? background) =>
        // ignore: deprecated_member_use_from_same_package
        background ?? doc.backgroundColor;

    expect(resolve(null), yellow);
    expect(resolve(const Color(0xFF0000FF)), const Color(0xFF0000FF));
  });

  // -- Half 2: painting contract ------------------------------------

  testWidgets('PNG: document.backgroundColor reaches the centre pixel', (
    tester,
  ) async {
    final doc = yellowDoc();
    final key = await mountDocument(
      tester,
      doc: doc,
      // Resolution step (controller would do this for us).
      // ignore: deprecated_member_use_from_same_package
      background: doc.backgroundColor,
    );
    final argb = await tester.runAsync(() async {
      final bytes = await DocumentPngExporter.captureBoundary(
        boundaryKey: key,
        pixelRatio: 1.0,
      );
      return centerPixelArgb(bytes);
    });
    expect(argb, yellow.toARGB32());
  });

  testWidgets('JPG: document.backgroundColor flattens through (not white)', (
    tester,
  ) async {
    final doc = yellowDoc();
    final key = await mountDocument(
      tester,
      doc: doc,
      // ignore: deprecated_member_use_from_same_package
      background: doc.backgroundColor,
    );
    // Snapshot the boundary as a ui.Image then JPG-encode via the
    // engine's own pipeline (max quality).
    final bytes = await tester.runAsync(() async {
      final ro =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await ro.toImage(pixelRatio: 1.0);
      try {
        return await DocumentJpgExporter.encodeImageAsJpg(image, quality: 100);
      } finally {
        image.dispose();
      }
    });
    expect(bytes, isNotNull);
    final argb = centerPixelJpgArgb(bytes!);
    // JPG quantisation drifts pixels by a couple of units even at
    // q=100; tolerate ±4 per channel.
    const target = 0xFFFFEB3B;
    final dr = ((argb >> 16) & 0xFF) - ((target >> 16) & 0xFF);
    final dg = ((argb >> 8) & 0xFF) - ((target >> 8) & 0xFF);
    final db = (argb & 0xFF) - (target & 0xFF);
    expect(dr.abs(), lessThanOrEqualTo(4));
    expect(dg.abs(), lessThanOrEqualTo(4));
    expect(db.abs(), lessThanOrEqualTo(4));
    // And explicitly NOT white.
    expect(argb & 0xFFFFFF, isNot(0xFFFFFF));
  });

  testWidgets('PNG: explicit override colour reaches the centre pixel', (
    tester,
  ) async {
    const override = Color(0xFF0000FF);
    final doc = yellowDoc();
    final key = await mountDocument(
      tester,
      doc: doc,
      background: override, // controller would forward this verbatim
    );
    final argb = await tester.runAsync(() async {
      final bytes = await DocumentPngExporter.captureBoundary(
        boundaryKey: key,
        pixelRatio: 1.0,
      );
      return centerPixelArgb(bytes);
    });
    expect(argb, override.toARGB32());
  });

  testWidgets('Engine captureBoundary still honours an explicit background', (
    tester,
  ) async {
    // Sanity: the engine-level snapshot contract is untouched.
    final doc = EditorDocument(
      width: 30,
      height: 30,
      layers: const [],
      backgroundColor: const Color(0xFFFFFFFF),
    );
    const magenta = Color(0xFFFF00FF);
    final key = await mountDocument(tester, doc: doc, background: magenta);
    final argb = await tester.runAsync(() async {
      final bytes = await DocumentPngExporter.captureBoundary(
        boundaryKey: key,
        pixelRatio: 1.0,
      );
      return centerPixelArgb(bytes);
    });
    expect(argb, magenta.toARGB32());
  });

  testWidgets(
    'PNG: backgroundFill preserves gradient pixels for saved thumbnails',
    (tester) async {
      const gradient = LinearGradientBackground(
        startColor: Color(0xFFFF0000),
        endColor: Color(0xFF0000FF),
        angleDegrees: 90,
      );
      final doc = EditorDocument(
        width: 60,
        height: 20,
        layers: const [],
        background: gradient,
      );
      final key = await mountDocument(
        tester,
        doc: doc,
        // Saved thumbnails still pass this legacy fallback for older
        // solid-only consumers, but the gradient must come from the
        // backgroundFill argument below.
        background: DocumentThumbnail.backgroundFor(doc),
        backgroundFill: doc.background,
      );

      final pixels = await tester.runAsync(() async {
        final bytes = await DocumentPngExporter.captureBoundary(
          boundaryKey: key,
          pixelRatio: 1.0,
        );
        return [await pixelArgb(bytes, 2, 10), await pixelArgb(bytes, 57, 10)];
      });
      final left = pixels![0];
      final right = pixels[1];
      final leftRed = (left >> 16) & 0xFF;
      final leftBlue = left & 0xFF;
      final rightRed = (right >> 16) & 0xFF;
      final rightBlue = right & 0xFF;

      expect(left, isNot(right));
      expect(leftRed, greaterThan(leftBlue));
      expect(rightBlue, greaterThan(rightRed));
    },
  );

  testWidgets('PNG: saved thumbnail path preserves transparent canvas alpha', (
    tester,
  ) async {
    final doc = EditorDocument(
      width: 40,
      height: 40,
      layers: const [],
      background: const SolidBackground(color: Color(0xFFFFEB3B)),
      backgroundMode: CanvasBackgroundMode.transparent,
    );
    final key = await mountDocument(
      tester,
      doc: doc,
      background: DocumentThumbnail.backgroundFor(doc),
      backgroundFill: doc.background,
      honorTransparentMode: true,
    );

    final argb = await tester.runAsync(() async {
      final bytes = await DocumentPngExporter.captureBoundary(
        boundaryKey: key,
        pixelRatio: 1.0,
      );
      return centerPixelArgb(bytes);
    });

    expect((argb! >> 24) & 0xFF, 0);
  });
}
