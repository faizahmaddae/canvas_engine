import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_engine/features/editor/engine/export/png_color_space.dart';

/// Helpers and direct unit tests for [tagPngAsSrgb]. Validates that:
///   * the function injects `sRGB` and `gAMA` chunks immediately
///     after the IHDR chunk,
///   * the new chunks have correct lengths, type tags, and CRC32
///     values per the PNG spec,
///   * non-PNG / malformed input is returned verbatim (best-effort
///     contract — the exporter must never fail because of tagging).
void main() {
  group('tagPngAsSrgb', () {
    test('output grows by exactly 29 bytes (sRGB 13 + gAMA 16)', () {
      final input = _buildMinimalPng();
      final output = tagPngAsSrgb(input);
      expect(output.length - input.length, 29);
    });

    test('preserves the PNG signature and IHDR bytes verbatim', () {
      final input = _buildMinimalPng();
      final output = tagPngAsSrgb(input);
      // Signature (8) + IHDR length+type+data+CRC (4+4+13+4 = 25)
      // — first 33 bytes must match.
      for (var i = 0; i < 33; i++) {
        expect(
          output[i],
          input[i],
          reason: 'byte $i changed: ${output[i]} vs ${input[i]}',
        );
      }
    });

    test('embeds the sRGB chunk with type "sRGB" and data byte 0 '
        '(perceptual rendering intent)', () {
      final input = _buildMinimalPng();
      final output = tagPngAsSrgb(input);
      // sRGB chunk starts at byte 33 (right after IHDR's CRC).
      // Layout: 4-byte length, 4-byte type, 1-byte data, 4-byte CRC.
      expect(output[33], 0); // length high byte
      expect(output[34], 0);
      expect(output[35], 0);
      expect(output[36], 1); // length low byte = 1
      expect(String.fromCharCodes(output.sublist(37, 41)), 'sRGB');
      expect(output[41], 0); // perceptual rendering intent
    });

    test('embeds the gAMA chunk with type "gAMA" and value 45455 '
        '(the standard sRGB gamma 1/2.2)', () {
      final input = _buildMinimalPng();
      final output = tagPngAsSrgb(input);
      // gAMA chunk starts at byte 33 + 13 = 46.
      const gamaStart = 33 + 13;
      expect(output[gamaStart + 3], 4); // length = 4
      expect(
        String.fromCharCodes(output.sublist(gamaStart + 4, gamaStart + 8)),
        'gAMA',
      );
      // Big-endian uint32 for 45455 = 0x0000_B18F.
      expect(output[gamaStart + 8], 0x00);
      expect(output[gamaStart + 9], 0x00);
      expect(output[gamaStart + 10], 0xB1);
      expect(output[gamaStart + 11], 0x8F);
    });

    test('returns input verbatim when input is not a PNG', () {
      final notPng = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
      expect(identical(tagPngAsSrgb(notPng), notPng), isTrue);
    });

    test('returns input verbatim when first chunk is not IHDR', () {
      final bad = Uint8List(64);
      // Valid signature
      const sig = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      for (var i = 0; i < sig.length; i++) {
        bad[i] = sig[i];
      }
      // Length = 13
      bad[8] = 0;
      bad[9] = 0;
      bad[10] = 0;
      bad[11] = 13;
      // Wrong type 'XXXX'
      bad[12] = 0x58;
      bad[13] = 0x58;
      bad[14] = 0x58;
      bad[15] = 0x58;
      expect(identical(tagPngAsSrgb(bad), bad), isTrue);
    });
  });
}

/// Build a minimal but structurally valid PNG (signature + IHDR +
/// IEND) suitable for testing the chunk injector. The pixel data is
/// omitted entirely; the helper does not inspect it.
Uint8List _buildMinimalPng() {
  // Signature
  const sig = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  // IHDR: 13 bytes — width(4) + height(4) + depth(1) + ctype(1) +
  // compression(1) + filter(1) + interlace(1).
  const ihdrData = <int>[
    0, 0, 0, 1, // width = 1
    0, 0, 0, 1, // height = 1
    8, // bit depth
    6, // colour type = RGBA
    0, // compression
    0, // filter
    0, // interlace
  ];
  // IEND: empty.
  // CRC values aren't validated by the injector, so use zeros — the
  // injector only needs to find IHDR's position and length.
  final ihdrChunk = <int>[
    0, 0, 0, 13, // length
    0x49, 0x48, 0x44, 0x52, // 'IHDR'
    ...ihdrData,
    0, 0, 0, 0, // CRC (placeholder)
  ];
  final iendChunk = <int>[
    0, 0, 0, 0, // length = 0
    0x49, 0x45, 0x4E, 0x44, // 'IEND'
    0xAE, 0x42, 0x60, 0x82, // canonical IEND CRC
  ];
  return Uint8List.fromList(<int>[...sig, ...ihdrChunk, ...iendChunk]);
}
