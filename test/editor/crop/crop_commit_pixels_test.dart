import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/crop/application/crop_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pixel-level regression test for the crop-commit fix: an
/// OFF-CENTRE crop must commit exactly the pixels the user framed.
///
/// The pre-fix commit reshaped the box and reset cropRect to full,
/// letting the renderer re-derive pixels through a cover fit at the
/// NEW box aspect — which shows the centre slice instead of the
/// chosen region. With a 2:1 source (left half red, right half blue)
/// in a square box, drafting the display's left half selects an
/// all-red region; the old commit rendered a red/blue mix. This test
/// renders the committed layer and asserts every sampled pixel is red.
void main() {
  testWidgets('off-centre crop commit renders exactly the drafted pixels', (
    tester,
  ) async {
    // ---- Build a 40x20 PNG: left half red, right half blue. ----
    late io.File imageFile;
    late io.Directory tempDir;
    await tester.runAsync(() async {
      tempDir = await io.Directory.systemTemp.createTemp('crop_pixels_test');
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, 20, 20),
        ui.Paint()..color = const ui.Color(0xFFFF0000),
      );
      canvas.drawRect(
        const ui.Rect.fromLTWH(20, 0, 20, 20),
        ui.Paint()..color = const ui.Color(0xFF0000FF),
      );
      final image = await recorder.endRecording().toImage(40, 20);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      imageFile = io.File('${tempDir.path}/src.png');
      await imageFile.writeAsBytes(bytes!.buffer.asUint8List());
    });
    addTearDown(() => tempDir.deleteSync(recursive: true));

    // ---- Document with the image cover-fitted into a square box. ----
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 1000, height: 1000);
    container
        .read(documentControllerProvider.notifier)
        .execute(
          AddLayerCommand(
            ImageLayer(
              id: 'img1',
              transform: LayerTransform(
                position: Offset.zero,
                size: const Size(200, 200),
              ),
              source: ImageSource.file(imageFile.path),
            ),
          ),
        );

    // ---- Crop: the display's left half (all-red source region). ----
    final crop = container.read(cropControllerProvider.notifier);
    crop.openCrop('img1');
    crop.setSourceAspect(2.0);
    crop.updateDraft(const Rect.fromLTRB(0, 0, 0.5, 1));
    crop.commitCrop();

    final layer =
        container.read(documentControllerProvider).layerById('img1')!
            as ImageLayer;
    expect(layer.fit, BoxFit.fill);
    expect(layer.transform.size, const Size(100, 200));

    // ---- Render the committed layer and sample pixels. ----
    // Decode the bitmap into the image cache FIRST so the layer's
    // Image.file resolves synchronously from cache when built —
    // widget tests never complete decodes outside runAsync.
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.expand(),
      ),
    );
    // Must match the widget's decode-hinted provider (ResizeImage
    // wraps FileImage with a cacheWidth key) — a plain FileImage
    // precache would populate a different cache entry.
    await tester.runAsync(
      () => precacheImage(
        layer.exportImageProvider()!,
        tester.element(find.byType(SizedBox)),
      ),
    );
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: SizedBox(
              width: 100,
              height: 200,
              child: Builder(builder: (c) => layer.buildContent(c)),
            ),
          ),
        ),
      ),
    );
    // Let the frame + any frameBuilder fade settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    late ByteData rgba;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
    });

    Color pixelAt(int x, int y) {
      final offset = (y * 100 + x) * 4;
      return Color.fromARGB(
        rgba.getUint8(offset + 3),
        rgba.getUint8(offset),
        rgba.getUint8(offset + 1),
        rgba.getUint8(offset + 2),
      );
    }

    // Pre-fix, the right column of the committed box rendered BLUE
    // (centre slice of the source at the new aspect). Every sample
    // must now be red.
    for (final (x, y) in [(10, 100), (50, 100), (90, 100), (90, 20)]) {
      final c = pixelAt(x, y);
      expect(
        c.r,
        greaterThan(0.9),
        reason: 'pixel ($x,$y) should be red, got $c',
      );
      expect(c.b, lessThan(0.1), reason: 'pixel ($x,$y) should be red, got $c');
    }
  });
}
