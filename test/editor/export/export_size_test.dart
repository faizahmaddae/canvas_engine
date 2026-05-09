import 'dart:ui' show Size;

import 'package:canvas_engine/features/editor/application/export_size.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExportSize presets', () {
    test('original carries no fixed target', () {
      expect(ExportSize.original.target, isNull);
      expect(ExportSize.original.isCustom, isFalse);
    });

    test('social presets expose exact pixel rectangles', () {
      expect(ExportSize.square1080.target, const Size(1080, 1080));
      expect(ExportSize.story1080x1920.target, const Size(1080, 1920));
      expect(ExportSize.portrait1080x1350.target, const Size(1080, 1350));
    });

    test('custom flag distinguishes the escape-hatch entry', () {
      expect(ExportSize.custom.isCustom, isTrue);
      expect(ExportSize.square1080.isCustom, isFalse);
    });

    test('values list drives the picker order', () {
      expect(
        ExportSize.values.map((s) => s.id).toList(),
        const [
          'original',
          'square_1080',
          'story_1080x1920',
          'portrait_1080x1350',
          'custom',
        ],
      );
    });

    test('customSize() builds a typed preset that is custom', () {
      final c = ExportSize.customSize(1234, 567);
      expect(c.isCustom, isTrue);
      expect(c.target, const Size(1234, 567));
      expect(c.subtitle, '1234 × 567');
    });

    test('customSize() rejects non-positive dimensions', () {
      expect(() => ExportSize.customSize(0, 100), throwsAssertionError);
      expect(() => ExportSize.customSize(100, -1), throwsAssertionError);
    });
  });

  group('fitContain math', () {
    test('square source into wider target letterboxes left/right', () {
      final r = fitContain(
        source: const Size(100, 100),
        target: const Size(200, 100),
      );
      expect(r.width, 100);
      expect(r.height, 100);
      expect(r.left, 50);
      expect(r.top, 0);
    });

    test('wide source into square target letterboxes top/bottom', () {
      final r = fitContain(
        source: const Size(200, 100),
        target: const Size(100, 100),
      );
      expect(r.width, 100);
      expect(r.height, 50);
      expect(r.left, 0);
      expect(r.top, 25);
    });

    test('matching aspect fills target exactly with no bands', () {
      final r = fitContain(
        source: const Size(540, 960),
        target: const Size(1080, 1920),
      );
      expect(r.width, 1080);
      expect(r.height, 1920);
      expect(r.left, 0);
      expect(r.top, 0);
    });

    test('zero source returns empty rect (no NaNs)', () {
      final r = fitContain(
        source: const Size(0, 0),
        target: const Size(100, 100),
      );
      expect(r.width, 0);
      expect(r.height, 0);
    });
  });
}
