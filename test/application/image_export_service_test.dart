import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_engine/features/editor/application/image_export_service.dart';

void main() {
  group('ImageExportService.buildFilename', () {
    const svc = ImageExportService();

    test('uses design_YYYYMMDD_HHmmss.png pattern with zero-padding', () {
      final name = svc.buildFilename(
        now: DateTime(2026, 1, 7, 9, 4, 8),
      );
      expect(name, 'design_20260107_090408.png');
    });

    test('two distinct timestamps produce distinct filenames', () {
      final a =
          svc.buildFilename(now: DateTime(2026, 4, 18, 12, 0, 0));
      final b =
          svc.buildFilename(now: DateTime(2026, 4, 18, 12, 0, 1));
      expect(a, isNot(equals(b)));
    });
  });
}
