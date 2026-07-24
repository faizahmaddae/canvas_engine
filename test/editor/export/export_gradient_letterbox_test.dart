// Roadmap tb4 4.8 — gradient-aware letterbox / flatten.
//
// A fixed-size export (Square / Story / Custom) composites the canvas
// into the target rect with `BoxFit.contain` and fills the leftover
// bands with the canvas background. That fill used to be a single
// `Color` derived from the document — `EditorDocument.backgroundColor`,
// which for a gradient returns only the start/centre colour — so a
// gradient canvas exported with flat bands that did not match the
// canvas the user was looking at. The composer now takes the whole
// [BackgroundFill].
//
// The gradient is laid out over the *destination* rect (where the
// artwork lands) and painted across the whole output, so the bands
// continue the canvas past its own edge (Skia clamps the edge colours
// outward) rather than restarting a differently-scaled gradient with a
// seam at the artwork boundary.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:canvas_engine/features/editor/application/export_controller.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/export/document_jpg_exporter.dart';
import 'package:canvas_engine/features/editor/engine/rendering/document_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _red = Color(0xFFFF0000);
const _blue = Color(0xFF0000FF);

/// Opaque single-colour source image standing in for the rasterised
/// document — the composer only ever draws it, never inspects it.
Future<ui.Image> _solidImage(int w, int h, Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = color,
  );
  final pic = recorder.endRecording();
  try {
    return await pic.toImage(w, h);
  } finally {
    pic.dispose();
  }
}

Future<Uint8List> _rgba(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List();
}

void main() {
  int channel(Uint8List px, int width, int x, int y, int offset) =>
      px[(y * width + x) * 4 + offset];

  test('horizontal gradient continues across the letterbox bands', () async {
    // 200×100 source into a 400×400 target: scale 2 → dest 400×200
    // centred vertically, leaving full-width 100px bands top and
    // bottom.
    final source = await _solidImage(200, 100, const Color(0xFF00FF00));
    final out = await composeFitContain(
      source: source,
      target: const ui.Size(400, 400),
      // The legacy solid the old code would have used — the gradient's
      // start colour. If the fill were ignored, every band pixel would
      // be exactly this.
      background: _red,
      backgroundFill: const LinearGradientBackground(
        startColor: _red,
        endColor: _blue,
        angleDegrees: 90, // left → right
      ),
      opaqueBackground: true,
    );
    source.dispose();

    expect(out.width, 400);
    expect(out.height, 400);
    final px = await _rgba(out);

    // Top band (y = 20) sits outside the artwork. Left edge must be
    // red-dominant, right edge blue-dominant: a flat fill cannot
    // produce both.
    final leftR = channel(px, 400, 10, 20, 0);
    final leftB = channel(px, 400, 10, 20, 2);
    final rightR = channel(px, 400, 390, 20, 0);
    final rightB = channel(px, 400, 390, 20, 2);
    expect(leftR, greaterThan(leftB));
    expect(rightB, greaterThan(rightR));

    // Explicitly NOT the flat dominant-tone fill.
    expect(
      rightR,
      lessThan(0x80),
      reason: 'band must not be flat start colour',
    );

    // The bottom band is the same gradient at the same x — the fill is
    // laid out horizontally, so both bands agree.
    expect(
      channel(px, 400, 390, 380, 2),
      greaterThan(channel(px, 400, 390, 380, 0)),
    );
    out.dispose();
  });

  test('vertical gradient bands clamp to the artwork edge colours', () async {
    // A top→bottom gradient laid out over the destination rect: above
    // the artwork the shader clamps to startColor, below it to
    // endColor. That is what makes the seam invisible.
    final source = await _solidImage(200, 100, const Color(0xFF00FF00));
    final out = await composeFitContain(
      source: source,
      target: const ui.Size(400, 400),
      background: _red,
      backgroundFill: const LinearGradientBackground(
        startColor: _red,
        endColor: _blue,
        angleDegrees: 180, // top → bottom
      ),
      opaqueBackground: true,
    );
    source.dispose();
    final px = await _rgba(out);

    // Top band ≈ start colour, bottom band ≈ end colour.
    expect(channel(px, 400, 200, 10, 0), greaterThan(0xF0));
    expect(channel(px, 400, 200, 10, 2), lessThan(0x10));
    expect(channel(px, 400, 200, 390, 2), greaterThan(0xF0));
    expect(channel(px, 400, 200, 390, 0), lessThan(0x10));
    out.dispose();
  });

  test('a solid fill still paints exactly its colour', () async {
    // Regression guard for the fallback branch: no fill supplied →
    // the legacy solid `background` is used verbatim.
    final source = await _solidImage(200, 100, const Color(0xFF00FF00));
    final out = await composeFitContain(
      source: source,
      target: const ui.Size(400, 400),
      background: _red,
      opaqueBackground: true,
    );
    source.dispose();
    final px = await _rgba(out);
    expect(channel(px, 400, 10, 20, 0), 0xFF);
    expect(channel(px, 400, 10, 20, 1), 0x00);
    expect(channel(px, 400, 10, 20, 2), 0x00);
    out.dispose();
  });

  testWidgets('JPG flatten keeps the gradient (not a flat dominant tone)', (
    tester,
  ) async {
    // The no-target JPG path flattens through [DocumentView] rather
    // than the composer; JPEG has no alpha, so the backdrop is always
    // painted. Pin that the gradient — not `backgroundColor` — is what
    // lands in the encoded bytes.
    const gradient = LinearGradientBackground(
      startColor: _red,
      endColor: _blue,
      angleDegrees: 90,
    );
    final doc = EditorDocument(
      width: 60,
      height: 20,
      layers: const [],
      background: gradient,
    );
    final key = GlobalKey();
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
                    key: key,
                    child: DocumentView(
                      document: doc,
                      backgroundFill: doc.background,
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
    final decoded = img.decodeJpg(bytes!);
    expect(decoded, isNotNull);
    final left = decoded!.getPixel(2, 10);
    final right = decoded.getPixel(57, 10);
    expect(left.r, greaterThan(left.b));
    expect(right.b, greaterThan(right.r));
  });
}
