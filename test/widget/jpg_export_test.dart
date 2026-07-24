import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:canvas_engine/features/editor/engine/export/document_jpg_exporter.dart';

/// Build a tiny solid-color [ui.Image] without a widget tree so the
/// JPEG encode path can be exercised in pure-Dart tests.
Future<ui.Image> _solidImage(int width, int height, Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  return picture.toImage(width, height);
}

void main() {
  group('DocumentJpgExporter.encodeImageAsJpg', () {
    test('produces valid JPEG bytes (SOI + EOI markers)', () async {
      final image = await _solidImage(8, 8, const Color(0xFFFF0000));
      final bytes = await DocumentJpgExporter.encodeImageAsJpg(image);
      image.dispose();
      expect(bytes, isNotEmpty);
      // JPEG magic: file starts 0xFFD8 (SOI) and ends 0xFFD9 (EOI).
      expect(bytes[0], 0xFF);
      expect(bytes[1], 0xD8);
      expect(bytes[bytes.length - 2], 0xFF);
      expect(bytes[bytes.length - 1], 0xD9);
    });

    test('higher quality produces larger output (compression knob '
        'actually wired)', () async {
      final image = await _solidImage(64, 64, const Color(0xFF80C0E0));
      // Add some variation so quality affects file size meaningfully.
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(image, Offset.zero, Paint());
      for (var i = 0; i < 32; i++) {
        canvas.drawRect(
          Rect.fromLTWH(i * 2.0, i * 2.0, 4, 4),
          Paint()..color = Color.fromARGB(255, i * 8, 200 - i * 4, i * 6),
        );
      }
      final pic = recorder.endRecording();
      final varied = await pic.toImage(64, 64);
      image.dispose();

      final low = await DocumentJpgExporter.encodeImageAsJpg(
        varied,
        quality: 70,
      );
      final high = await DocumentJpgExporter.encodeImageAsJpg(
        varied,
        quality: 100,
      );
      varied.dispose();
      expect(high.length, greaterThan(low.length));
    });

    test('quality is clamped to 1..100', () async {
      final image = await _solidImage(4, 4, const Color(0xFF00FF00));
      final tooLow = await DocumentJpgExporter.encodeImageAsJpg(
        image,
        quality: 0,
      );
      final tooHigh = await DocumentJpgExporter.encodeImageAsJpg(
        image,
        quality: 999,
      );
      image.dispose();
      expect(tooLow, isA<Uint8List>());
      expect(tooLow, isNotEmpty);
      expect(tooHigh, isA<Uint8List>());
      expect(tooHigh, isNotEmpty);
    });

    test(
      'round-trip: decoded RGB matches source within JPEG tolerance',
      () async {
        // The audit (May 2026) flagged JPEG round-trip pixel coverage
        // as a gap: SOI/EOI + size-vs-quality verifies the encoder is
        // wired, but only decoding-and-comparing-pixels catches a
        // channel-order regression (RGBA-vs-BGRA) or a colour-space
        // misinterpretation. Solid-fill source keeps the chroma
        // subsampling tolerance tight (~3/255 per channel at q=95).
        const w = 16;
        const h = 16;
        const src = Color(0xFF3060A0); // R=48, G=96, B=160
        final image = await _solidImage(w, h, src);
        final bytes = await DocumentJpgExporter.encodeImageAsJpg(
          image,
          quality: 95,
        );
        image.dispose();

        final decoded = img.decodeJpg(bytes);
        expect(decoded, isNotNull);
        expect(decoded!.width, w);
        expect(decoded.height, h);

        // Sample the centre pixel — JPEG block boundaries can perturb
        // edge pixels by a couple of LSBs even on a solid image.
        final px = decoded.getPixel(w ~/ 2, h ~/ 2);
        const tolerance = 3; // ~1.2% per channel; safe for q=95 solid.
        expect(
          (px.r - 0x30).abs(),
          lessThanOrEqualTo(tolerance),
          reason: 'red channel drifted: got ${px.r}',
        );
        expect(
          (px.g - 0x60).abs(),
          lessThanOrEqualTo(tolerance),
          reason: 'green channel drifted: got ${px.g}',
        );
        expect(
          (px.b - 0xA0).abs(),
          lessThanOrEqualTo(tolerance),
          reason: 'blue channel drifted: got ${px.b}',
        );
      },
    );
  });
}
