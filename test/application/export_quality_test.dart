import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_engine/features/editor/application/export_quality.dart';

void main() {
  group('ExportQuality', () {
    test('original maps to 1×, high to 2×, ultra to 3×', () {
      expect(ExportQuality.original.pixelRatio, 1.0);
      expect(ExportQuality.high.pixelRatio, 2.0);
      expect(ExportQuality.ultra.pixelRatio, 3.0);
    });

    test('multiplier formats as integer × suffix', () {
      expect(ExportQuality.original.multiplier, '1×');
      expect(ExportQuality.high.multiplier, '2×');
      expect(ExportQuality.ultra.multiplier, '3×');
    });

    test('output dimensions for 1080×1080 canvas match spec', () {
      const w = 1080;
      const h = 1080;
      expect((w * ExportQuality.original.pixelRatio).round(), 1080);
      expect((h * ExportQuality.original.pixelRatio).round(), 1080);
      expect((w * ExportQuality.high.pixelRatio).round(), 2160);
      expect((h * ExportQuality.high.pixelRatio).round(), 2160);
      expect((w * ExportQuality.ultra.pixelRatio).round(), 3240);
      expect((h * ExportQuality.ultra.pixelRatio).round(), 3240);
    });
  });
}
