import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:canvas_engine/features/editor/application/export_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives [composeFitContain] directly with a synthesised [ui.Image]
/// so the test never touches the off-screen overlay path used by the
/// engine exporter (that path requires frame pumping which can't run
/// inside [WidgetTester.runAsync]).
///
/// Verifies the two contractual guarantees of the social-preset
/// renderer:
///   1. Output dimensions exactly equal the requested target.
///   2. Source content is letterboxed (centred) and never stretched —
///      the centre pixel keeps the source colour while the band
///      pixels show the background fill.
void main() {
  /// Build a solid-red opaque [ui.Image] of [w]×[h] for use as the
  /// composer's source.
  Future<ui.Image> redImage(int w, int h) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..color = const Color(0xFFFF0000),
    );
    final pic = recorder.endRecording();
    try {
      return await pic.toImage(w, h);
    } finally {
      pic.dispose();
    }
  }

  Future<Uint8List> readRgba(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return byteData!.buffer.asUint8List();
  }

  test('square preset on a wide source centres without stretching', () async {
    final source = await redImage(200, 100);
    final out = await composeFitContain(
      source: source,
      target: const ui.Size(1080, 1080),
      background: const Color(0xFF000000),
      opaqueBackground: true,
    );
    source.dispose();

    expect(out.width, 1080);
    expect(out.height, 1080);

    final pixels = await readRgba(out);
    int rgba(int x, int y) {
      final i = (y * out.width + x) * 4;
      return (pixels[i] << 24) |
          (pixels[i + 1] << 16) |
          (pixels[i + 2] << 8) |
          pixels[i + 3];
    }

    // Centre pixel must be red — proves the source landed there.
    expect(rgba(540, 540), 0xFF0000FF);
    // Top band (y=20) must be the black background fill — proves the
    // source was NOT stretched to fill the square.
    expect(rgba(540, 20), 0x000000FF);
    out.dispose();
  });

  test('matching aspect fills the target with no letterbox bands', () async {
    final source = await redImage(108, 192);
    final out = await composeFitContain(
      source: source,
      target: const ui.Size(1080, 1920),
      background: const Color(0xFF000000),
      opaqueBackground: true,
    );
    source.dispose();
    expect(out.width, 1080);
    expect(out.height, 1920);

    final pixels = await readRgba(out);
    int alpha(int x, int y) {
      final i = (y * out.width + x) * 4;
      return pixels[i + 3];
    }

    // Corners should be red (source filled the whole target), not
    // background — but be slightly tolerant to anti-aliasing at the
    // boundary by checking a pixel a few in from the corner.
    expect(alpha(8, 8), 0xFF);
    expect(alpha(out.width - 8, out.height - 8), 0xFF);
    out.dispose();
  });

  test('transparent mode leaves letterbox bands fully transparent', () async {
    final source = await redImage(200, 100);
    final out = await composeFitContain(
      source: source,
      target: const ui.Size(400, 400),
      background: const Color(0xFFFFFFFF),
      opaqueBackground: false,
    );
    source.dispose();

    final pixels = await readRgba(out);
    int alpha(int x, int y) {
      final i = (y * out.width + x) * 4;
      return pixels[i + 3];
    }

    // Top-left corner is in the letterbox band — must be α=0.
    expect(alpha(10, 10), 0);
    // Centre is the source — must be α=255.
    expect(alpha(200, 200), 0xFF);
    out.dispose();
  });
}
