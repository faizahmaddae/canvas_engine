import 'dart:convert';

import 'package:canvas_engine/features/editor/engine/modules/text/text_style_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TextStyleSpec', () {
    test('default italic=false, underline=false and lineHeight=1.2', () {
      const s = TextStyleSpec();
      expect(s.italic, isFalse);
      expect(s.underline, isFalse);
      expect(s.lineHeight, 1.2);
    });

    test('isBold reflects fontWeight w600+', () {
      // The default constructor uses w600, which is already bold.
      expect(const TextStyleSpec().isBold, isTrue);
      expect(const TextStyleSpec(fontWeight: FontWeight.w400).isBold, isFalse);
      expect(const TextStyleSpec(fontWeight: FontWeight.w500).isBold, isFalse);
      expect(const TextStyleSpec(fontWeight: FontWeight.w600).isBold, isTrue);
      expect(const TextStyleSpec(fontWeight: FontWeight.w700).isBold, isTrue);
    });

    test('copyWith preserves italic + lineHeight', () {
      const original = TextStyleSpec(
        italic: true,
        underline: true,
        lineHeight: 1.8,
      );
      final copy = original.copyWith();
      expect(copy.italic, isTrue);
      expect(copy.underline, isTrue);
      expect(copy.lineHeight, 1.8);
    });

    test('toJson/fromJson round-trips italic + lineHeight', () {
      const original = TextStyleSpec(
        fontFamily: 'Inter',
        fontSize: 32,
        color: Color(0xFFFF0000),
        fontWeight: FontWeight.w700,
        italic: true,
        underline: true,
        letterSpacing: 1.5,
        lineHeight: 1.6,
        alignment: TextAlign.center,
      );
      final json = jsonEncode(original.toJson());
      final restored = TextStyleSpec.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
      expect(restored, original);
    });

    test(
      'fromJson defaults italic=false, underline=false, lineHeight=1.2 when missing',
      () {
        // Legacy JSON written before italic + underline + lineHeight existed.
        final restored = TextStyleSpec.fromJson(<String, dynamic>{
          'fontSize': 24.0,
        });
        expect(restored.italic, isFalse);
        expect(restored.underline, isFalse);
        expect(restored.lineHeight, 1.2);
        expect(restored.fontSize, 24.0);
      },
    );

    test('toJson omits italic when false (compact serialization)', () {
      const s = TextStyleSpec(italic: false);
      final json = s.toJson();
      expect(json.containsKey('italic'), isFalse);
    });

    test('toPaintingStyle applies italic + lineHeight to TextStyle', () {
      const s = TextStyleSpec(italic: true, lineHeight: 2.0);
      final painting = s.toPaintingStyle();
      expect(painting.fontStyle, FontStyle.italic);
      expect(painting.height, 2.0);
    });
  });

  test('toJson omits every shadow key while shadowColor is null', () {
    // Additive-serialization gate for the shadow effect: documents
    // without a shadow must encode WITHOUT shadow keys, so pre-shadow
    // fixtures stay byte-identical forever.
    final json = const TextStyleSpec(fontSize: 24).toJson();
    expect(json.containsKey('shadowColor'), isFalse);
    expect(json.containsKey('shadowBlur'), isFalse);
    expect(json.containsKey('shadowDx'), isFalse);
    expect(json.containsKey('shadowDy'), isFalse);
  });

  test('full shadow (colour + blur + offset) round-trips exactly', () {
    const original = TextStyleSpec(
      shadowColor: Color(0x8C1F1B16),
      shadowBlur: 18,
      shadowOffset: Offset(-6, 9),
    );
    final restored = TextStyleSpec.fromJson(original.toJson());
    expect(restored, original);
    expect(restored.toJson(), original.toJson());
  });
}
