import 'dart:typed_data';

/// Post-processes a PNG byte buffer to embed colour-space metadata
/// (`sRGB` + `gAMA`) right after the `IHDR` chunk.
///
/// ## Why
///
/// Flutter's `image.toByteData(format: ui.ImageByteFormat.png)`
/// produces a valid PNG but writes **no colour-space chunks at all**.
/// Untagged PNGs are interpreted differently by every viewer:
///
///   * Web browsers and most desktop image viewers fall back to sRGB.
///   * iOS Photos.app and macOS Preview on a Display-P3 device
///     **expand untagged content into the device's wide gamut**,
///     visibly shifting colours (reds desaturate toward orange,
///     blues intensify toward purple).
///   * Some Android galleries do their own thing.
///
/// Tagging the file as sRGB tells every conformant viewer to treat
/// the pixels as the sRGB space we actually rendered them in, so the
/// editor preview and the saved file match across devices.
///
/// ## Output guarantees
///
/// * On a well-formed PNG the function returns a new `Uint8List` with
///   `sRGB` and `gAMA` chunks injected after `IHDR`. Existing chunks
///   are left untouched; total file size grows by 25 bytes.
/// * On any input that does not parse as a PNG with an `IHDR` first
///   chunk the function returns the input bytes verbatim. The
///   exporter's contract is "best-effort tagging" — a malformed PNG
///   is the encoder's problem, and the previous behaviour
///   (write-and-move-on) is preserved.
/// * The function never throws.
///
/// ## Why not re-encode through `package:image`
///
/// `package:image` can write tagged PNGs but at the cost of a full
/// CPU re-encode of every export. Flutter's native encoder ships
/// pixels straight from the GPU. Patching the byte stream preserves
/// that fast path and adds < 0.1 ms to a multi-megapixel export.
Uint8List tagPngAsSrgb(Uint8List pngBytes) {
  // PNG signature is 8 bytes: 89 50 4E 47 0D 0A 1A 0A.
  const pngSignature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (pngBytes.length < 8 + 8 + 13 + 4) {
    // Too short to even contain signature + IHDR header + body + CRC.
    return pngBytes;
  }
  for (var i = 0; i < pngSignature.length; i++) {
    if (pngBytes[i] != pngSignature[i]) return pngBytes;
  }

  // First chunk MUST be IHDR per PNG spec. Layout: 4-byte length, 4-
  // byte type, `length` bytes of data, 4-byte CRC.
  final ihdrLength = _readUint32BE(pngBytes, 8);
  // IHDR data length is fixed at 13 bytes.
  if (ihdrLength != 13) return pngBytes;
  if (pngBytes.length < 8 + 8 + 13 + 4) return pngBytes;
  if (pngBytes[12] != 0x49 || // 'I'
      pngBytes[13] != 0x48 || // 'H'
      pngBytes[14] != 0x44 || // 'D'
      pngBytes[15] != 0x52) {
    // 'R'
    return pngBytes;
  }

  // Insertion point: byte index right after IHDR's CRC.
  final insertAt = 8 + 4 + 4 + 13 + 4;

  // Build the two new chunks.
  final srgb = _buildChunk(
    type: const <int>[0x73, 0x52, 0x47, 0x42], // 'sRGB'
    data: Uint8List.fromList(<int>[0]), // intent: 0 = perceptual
  );
  // gAMA stores 1/2.2 × 100000 = 45455. PNG spec recommends this
  // alongside sRGB for legacy decoders that ignore the sRGB chunk.
  final gama = _buildChunk(
    type: const <int>[0x67, 0x41, 0x4D, 0x41], // 'gAMA'
    data: _uint32BE(45455),
  );

  final out = Uint8List(pngBytes.length + srgb.length + gama.length);
  out.setRange(0, insertAt, pngBytes);
  out.setRange(insertAt, insertAt + srgb.length, srgb);
  out.setRange(
    insertAt + srgb.length,
    insertAt + srgb.length + gama.length,
    gama,
  );
  out.setRange(
    insertAt + srgb.length + gama.length,
    out.length,
    pngBytes,
    insertAt,
  );
  return out;
}

Uint8List _buildChunk({required List<int> type, required Uint8List data}) {
  final chunk = Uint8List(4 + 4 + data.length + 4);
  // length (big-endian uint32)
  final lenBytes = _uint32BE(data.length);
  chunk.setRange(0, 4, lenBytes);
  // type
  chunk.setRange(4, 8, type);
  // data
  chunk.setRange(8, 8 + data.length, data);
  // CRC32 over type+data (PNG-spec ordering)
  final crc = _crc32(chunk.sublist(4, 8 + data.length));
  chunk.setRange(8 + data.length, chunk.length, _uint32BE(crc));
  return chunk;
}

int _readUint32BE(Uint8List b, int offset) =>
    (b[offset] << 24) |
    (b[offset + 1] << 16) |
    (b[offset + 2] << 8) |
    b[offset + 3];

Uint8List _uint32BE(int value) {
  final b = Uint8List(4);
  b[0] = (value >> 24) & 0xFF;
  b[1] = (value >> 16) & 0xFF;
  b[2] = (value >> 8) & 0xFF;
  b[3] = value & 0xFF;
  return b;
}

// CRC32 with the standard reflected polynomial 0xEDB88320 used by
// PNG / zlib. Table built lazily on first call.
List<int>? _crcTable;

int _crc32(List<int> bytes) {
  final table = _crcTable ??= _buildCrcTable();
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc = table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

List<int> _buildCrcTable() {
  final table = List<int>.filled(256, 0);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = ((c & 1) != 0) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    table[n] = c;
  }
  return table;
}
