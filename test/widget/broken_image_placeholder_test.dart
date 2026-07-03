import 'dart:io';
import 'dart:ui' as ui;

import 'package:canvas_engine/features/editor/engine/commands/image_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/export/document_png_exporter.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/rendering/document_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _placeholderText = 'Image unavailable';

EditorDocument _docWithImage(ImageSource source) => EditorDocument(
  width: 96,
  height: 64,
  layers: [
    ImageLayer(
      id: 'broken-image',
      transform: const LayerTransform(
        position: Offset(8, 8),
        size: Size(80, 48),
      ),
      source: source,
    ),
  ],
  backgroundColor: const Color(0xFFFFFFFF),
);

Future<GlobalKey> _pumpDocument(
  WidgetTester tester,
  EditorDocument doc, {
  AssetBundle? assetBundle,
  bool waitForPlaceholder = true,
}) async {
  final key = GlobalKey();
  tester.view.physicalSize = Size(doc.width, doc.height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  Widget tree = Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(),
      child: Material(
        type: MaterialType.transparency,
        child: RepaintBoundary(
          key: key,
          child: DocumentView(document: doc, backgroundFill: doc.background),
        ),
      ),
    ),
  );
  if (assetBundle != null) {
    tree = DefaultAssetBundle(bundle: assetBundle, child: tree);
  }
  await tester.pumpWidget(tree);
  if (waitForPlaceholder) {
    await _pumpUntilPlaceholder(tester);
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }
  return key;
}

Future<void> _pumpUntilPlaceholder(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text(_placeholderText).evaluate().isNotEmpty) return;
  }
}

Uint8List _solidPngBytes(Color color) {
  final image = img.Image(width: 24, height: 24);
  img.fill(
    image,
    color: img.ColorRgba8(
      (color.r * 255).round(),
      (color.g * 255).round(),
      (color.b * 255).round(),
      (color.a * 255).round(),
    ),
  );
  return Uint8List.fromList(img.encodePng(image));
}

class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(this.assets);

  final Map<String, Uint8List> assets;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      final manifest = <String, Object>{
        for (final assetKey in assets.keys)
          assetKey: [
            <String, Object>{'asset': assetKey},
          ],
      };
      return const StandardMessageCodec().encodeMessage(manifest)!;
    }
    final bytes = assets[key];
    if (bytes == null) throw StateError('Missing test asset $key');
    return ByteData.sublistView(bytes);
  }
}

Future<({int width, int height, int centerArgb})> _decodePngCenter(
  Uint8List bytes,
) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final data = raw!.buffer.asUint8List();
    final x = image.width ~/ 2;
    final y = image.height ~/ 2;
    final i = (y * image.width + x) * 4;
    final r = data[i];
    final g = data[i + 1];
    final b = data[i + 2];
    final a = data[i + 3];
    return (
      width: image.width,
      height: image.height,
      centerArgb: (a << 24) | (r << 16) | (g << 8) | b,
    );
  } finally {
    image.dispose();
  }
}

void main() {
  group('ImageLayer broken source placeholder', () {
    testWidgets('renders for a missing asset source', (tester) async {
      await _pumpDocument(
        tester,
        _docWithImage(const ImageSource.asset('assets/does_not_exist.png')),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(_placeholderText), findsOneWidget);
    });

    testWidgets('renders for an invalid file source', (tester) async {
      await _pumpDocument(
        tester,
        _docWithImage(
          ImageSource.file('${Directory.systemTemp.path}/nope.png'),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(_placeholderText), findsOneWidget);
    });

    testWidgets('renders for an invalid network source without live network', (
      tester,
    ) async {
      await _pumpDocument(
        tester,
        _docWithImage(
          const ImageSource.network('https://example.invalid/missing.png'),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(_placeholderText), findsOneWidget);
    });

    testWidgets('exports a broken image placeholder without crashing', (
      tester,
    ) async {
      final doc = _docWithImage(
        ImageSource.file('${Directory.systemTemp.path}/missing-export.png'),
      );
      final key = await _pumpDocument(tester, doc);

      final bytes = await tester.runAsync(
        () => DocumentPngExporter.captureBoundary(
          boundaryKey: key,
          pixelRatio: 1.0,
        ),
      );
      expect(bytes, isNotNull);
      expect(
        bytes!.sublist(0, 8),
        equals(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
      );

      final decoded = await tester.runAsync(() => _decodePngCenter(bytes));
      expect(decoded!.width, doc.width.round());
      expect(decoded.height, doc.height.round());
      expect((decoded.centerArgb >> 24) & 0xFF, 0xFF);
      expect(decoded.centerArgb & 0xFFFFFF, isNot(0xFFFFFF));
    });

    testWidgets('exports after broken image source is replaced', (
      tester,
    ) async {
      final broken = _docWithImage(
        ImageSource.file('${Directory.systemTemp.path}/missing-relink.png'),
      );
      final brokenKey = await _pumpDocument(tester, broken);
      final brokenBytes = await tester.runAsync(
        () => DocumentPngExporter.captureBoundary(
          boundaryKey: brokenKey,
          pixelRatio: 1.0,
        ),
      );
      expect(brokenBytes, isNotNull);

      final replaced = const ReplaceImageSourceCommand(
        layerId: 'broken-image',
        source: ImageSource.asset('solid.png'),
      ).apply(broken);
      final bundle = _MemoryAssetBundle({
        'solid.png': _solidPngBytes(const Color(0xFFFF0000)),
      });
      final replacedKey = await _pumpDocument(
        tester,
        replaced,
        assetBundle: bundle,
        waitForPlaceholder: false,
      );

      expect(tester.takeException(), isNull);
      expect(find.text(_placeholderText), findsNothing);
      final replacedBytes = await tester.runAsync(
        () => DocumentPngExporter.captureBoundary(
          boundaryKey: replacedKey,
          pixelRatio: 1.0,
        ),
      );
      expect(replacedBytes, isNotNull);
      final decoded = await tester.runAsync(
        () => _decodePngCenter(replacedBytes!),
      );
      expect(decoded!.width, replaced.width.round());
      expect(decoded.height, replaced.height.round());
      expect(decoded.centerArgb & 0x00FF0000, greaterThan(0x00800000));
    });
  });
}
