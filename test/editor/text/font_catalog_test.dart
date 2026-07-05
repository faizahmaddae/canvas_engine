import 'package:canvas_engine/features/editor/text/domain/font_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FontEntry.labelFor', () {
    test('fa locale shows the Persian name when one exists', () {
      final vazir = kFontCatalog.singleWhere(
        (e) => e.family == 'Vazir_Regular',
      );
      expect(vazir.labelFor('fa'), 'وزیر');
      expect(vazir.labelFor('en'), 'Vazir');
    });

    test('Latin faces keep their proper-noun label under fa', () {
      final roboto = kFontCatalog.singleWhere((e) => e.family == 'Roboto');
      expect(roboto.labelFor('fa'), 'Roboto');
      expect(roboto.labelFor('en'), 'Roboto');
    });

    test('every Farsi-script face ships a Persian display name', () {
      final missing = kFontCatalog
          .where((e) => e.script == FontScript.arabic && e.labelFa == null)
          .map((e) => e.family)
          .toList();
      expect(missing, isEmpty, reason: 'add labelFa for: $missing');
    });
  });
}
