import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';

void main() {
  group('ImageSource.file', () {
    test('serializes to {file: path}', () {
      const src = ImageSource.file('/tmp/picked/foo.jpg');
      expect(src.toJson(), {'file': '/tmp/picked/foo.jpg'});
    });

    test('round-trips through fromJson', () {
      const src = ImageSource.file('/path/to/img.png');
      final back = ImageSource.fromJson(src.toJson());
      expect(back.filePath, '/path/to/img.png');
      expect(back.assetName, isNull);
      expect(back.networkUrl, isNull);
      expect(back, src);
    });

    test('fromJson still accepts asset and url payloads', () {
      expect(
        ImageSource.fromJson({'asset': 'a.png'}).assetName,
        'a.png',
      );
      expect(
        ImageSource.fromJson({'url': 'https://x/y.png'}).networkUrl,
        'https://x/y.png',
      );
    });

    test('fromJson rejects empty payloads', () {
      expect(
        () => ImageSource.fromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });

    test('equality distinguishes between source kinds', () {
      const a = ImageSource.file('/a/b.png');
      const b = ImageSource.network('/a/b.png');
      expect(a == b, isFalse);
    });
  });
}
