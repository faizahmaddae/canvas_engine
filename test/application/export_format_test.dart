import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_engine/features/editor/application/export_format.dart';
import 'package:canvas_engine/features/editor/application/image_export_service.dart';

void main() {
  group('ExportFormat', () {
    test('extensions and mime types are correct', () {
      expect(ExportFormat.png.extension, 'png');
      expect(ExportFormat.jpg.extension, 'jpg');
      expect(ExportFormat.png.mimeType, 'image/png');
      expect(ExportFormat.jpg.mimeType, 'image/jpeg');
    });

    test('only JPG advertises a quality knob', () {
      expect(ExportFormat.png.supportsQuality, isFalse);
      expect(ExportFormat.jpg.supportsQuality, isTrue);
    });
  });

  group('ImageExportService.buildFilename with format', () {
    const svc = ImageExportService();

    test('PNG default produces .png extension', () {
      expect(
        svc.buildFilename(now: DateTime(2026, 4, 18, 12, 0, 0)),
        'design_20260418_120000.png',
      );
    });

    test('JPG format produces .jpg extension', () {
      expect(
        svc.buildFilename(
          now: DateTime(2026, 4, 18, 12, 0, 0),
          format: ExportFormat.jpg,
        ),
        'design_20260418_120000.jpg',
      );
    });
  });
}
