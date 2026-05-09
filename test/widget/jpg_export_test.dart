import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_engine/features/editor/engine/export/document_jpg_exporter.dart';

/// Build a tiny solid-color [ui.Image] without a widget tree so the
/// JPEG encode path can be exercised in pure-Dart tests.
Future<ui.Image> _solidImage(
  int width,
  int height,
  Color color,
) async {
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
  });
}
