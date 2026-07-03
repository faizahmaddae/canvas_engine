import 'dart:ui' as ui;

import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_layer.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:canvas_engine/features/editor/engine/export/document_jpg_exporter.dart';
import 'package:canvas_engine/features/editor/engine/export/document_png_exporter.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/engine/rendering/document_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Future<GlobalKey> _mountDocument(
  WidgetTester tester,
  EditorDocument document, {
  AssetBundle? assetBundle,
}) async {
  final key = GlobalKey();
  tester.view.physicalSize = Size(document.width, document.height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  Widget tree = ProviderScope(
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: Material(
          type: MaterialType.transparency,
          child: RepaintBoundary(
            key: key,
            child: DocumentView(
              document: document,
              backgroundFill: document.background,
              honorTransparentMode: true,
            ),
          ),
        ),
      ),
    ),
  );
  if (assetBundle != null) {
    tree = DefaultAssetBundle(bundle: assetBundle, child: tree);
  }
  await tester.pumpWidget(tree);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  return key;
}

Future<Uint8List> _capturePng(GlobalKey key) {
  return DocumentPngExporter.captureBoundary(boundaryKey: key, pixelRatio: 1.0);
}

Future<({int width, int height, int Function(int x, int y) argb})> _decodePng(
  Uint8List bytes,
) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final data = raw!.buffer.asUint8List();
  final width = image.width;
  final height = image.height;
  image.dispose();

  int argb(int x, int y) {
    final i = (y * width + x) * 4;
    final r = data[i];
    final g = data[i + 1];
    final b = data[i + 2];
    final a = data[i + 3];
    return (a << 24) | (r << 16) | (g << 8) | b;
  }

  return (width: width, height: height, argb: argb);
}

Uint8List _solidPngBytes(Color color) {
  final image = img.Image(width: 32, height: 32);
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

_MemoryAssetBundle _bundle() => _MemoryAssetBundle({
  'red.png': _solidPngBytes(const Color(0xFFFF0000)),
  'blue.png': _solidPngBytes(const Color(0xFF004CFF)),
  'green.png': _solidPngBytes(const Color(0xFF00CC66)),
});

EffectStack _photoEffects() => EffectStack(<EditorEffect>[
  ...ImageAdjustments(
    brightness: 0.08,
    contrast: 1.12,
    saturation: 0.9,
    exposure: 6,
    warmth: 10,
  ).toEffectStack(),
  const VignetteEffect(intensity: 0.22, feather: 0.72),
]);

EditorDocument _heavyDocument() {
  final layers = <EditorLayer>[];
  for (var i = 0; i < 24; i++) {
    layers.add(
      ShapeLayer(
        id: 'shape-$i',
        transform: LayerTransform(
          position: Offset((i % 8) * 32.0, (i ~/ 8) * 36.0),
          size: const Size(34, 30),
          rotation: i.isEven ? 0 : 0.08,
        ),
        kind: i.isEven ? ShapeKind.rectangle : ShapeKind.circle,
        fillColor: Color(0xFF4455AA + i * 257),
        opacity: i % 5 == 0 ? 0.42 : 0.82,
        visible: i % 11 != 0,
      ),
    );
  }
  for (var i = 0; i < 18; i++) {
    layers.add(
      TextLayer(
        id: 'text-$i',
        transform: LayerTransform(
          position: Offset(8, 8 + i * 8.0),
          size: const Size(220, 18),
        ),
        content: 'Layer $i',
        style: TextStyleSpec(
          fontSize: 10 + (i % 3).toDouble(),
          color: const Color(0xFFFFFFFF),
        ),
        opacity: i % 4 == 0 ? 0.55 : 1,
      ),
    );
  }
  layers.add(
    ImageLayer(
      id: 'image-main',
      transform: const LayerTransform(
        position: Offset(132, 44),
        size: Size(92, 92),
        rotation: 0.12,
      ),
      source: const ImageSource.asset('red.png'),
      mask: ImageMask.squircle,
      filterPreset: ImageFilterPreset.dramatic,
      opacity: 0.88,
      effects: _photoEffects(),
    ),
  );
  return EditorDocument(
    width: 240,
    height: 160,
    layers: layers,
    background: const LinearGradientBackground(
      startColor: Color(0xFF18212F),
      endColor: Color(0xFF2E7D5B),
      angleDegrees: 35,
    ),
  );
}

EditorDocument _imageHeavyDocument() {
  final effects = _photoEffects();
  return EditorDocument(
    width: 220,
    height: 160,
    backgroundColor: const Color(0xFF101418),
    layers: [
      for (var i = 0; i < 7; i++)
        ImageLayer(
          id: 'image-$i',
          transform: LayerTransform(
            position: Offset(12 + (i % 4) * 48.0, 12 + (i ~/ 4) * 58.0),
            size: const Size(54, 54),
            rotation: i * 0.04,
          ),
          source: ImageSource.asset(i.isEven ? 'blue.png' : 'green.png'),
          mask: i % 3 == 0 ? ImageMask.circle : ImageMask.rounded,
          cropRect: i.isEven
              ? const Rect.fromLTRB(0.08, 0.08, 0.92, 0.92)
              : ImageLayer.fullCrop,
          filterPreset: i.isEven
              ? ImageFilterPreset.mono
              : ImageFilterPreset.warm,
          opacity: i == 6 ? 0.5 : 0.9,
          visible: i != 5,
          effects: effects,
        ),
    ],
  );
}

void _expectPng(Uint8List bytes) {
  expect(bytes, isNotEmpty);
  expect(
    bytes.sublist(0, 8),
    equals(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
  );
}

void main() {
  testWidgets('heavy mixed document builds and exports a valid PNG', (
    tester,
  ) async {
    final doc = _heavyDocument();
    final key = await _mountDocument(tester, doc, assetBundle: _bundle());
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final bytes = await tester.runAsync(() => _capturePng(key));
    _expectPng(bytes!);
    final decoded = await tester.runAsync(() => _decodePng(bytes));
    expect(decoded!.width, doc.width.round());
    expect(decoded.height, doc.height.round());
  });

  testWidgets('image and effects-heavy document exports a valid PNG', (
    tester,
  ) async {
    final doc = _imageHeavyDocument();
    final key = await _mountDocument(tester, doc, assetBundle: _bundle());
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final bytes = await tester.runAsync(() => _capturePng(key));
    _expectPng(bytes!);
    final decoded = await tester.runAsync(() => _decodePng(bytes));
    expect(decoded!.width, doc.width.round());
    expect(decoded.height, doc.height.round());
    expect(decoded.argb(24, 24) & 0xFF000000, 0xFF000000);
  });

  testWidgets('transparent PNG stress keeps uncovered pixels transparent', (
    tester,
  ) async {
    final doc = EditorDocument(
      width: 96,
      height: 96,
      backgroundMode: CanvasBackgroundMode.transparent,
      background: const LinearGradientBackground(
        startColor: Color(0xFFFF0000),
        endColor: Color(0xFF0000FF),
        angleDegrees: 0,
      ),
      layers: [
        ImageLayer(
          id: 'photo',
          transform: const LayerTransform(
            position: Offset(32, 32),
            size: Size(48, 48),
          ),
          source: const ImageSource.asset('red.png'),
          effects: _photoEffects(),
        ),
        const ShapeLayer(
          id: 'alpha-marker',
          transform: LayerTransform(
            position: Offset(44, 44),
            size: Size(12, 12),
          ),
          kind: ShapeKind.rectangle,
          fillColor: Color(0xFF00CC66),
        ),
      ],
    );
    final key = await _mountDocument(tester, doc, assetBundle: _bundle());
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final bytes = await tester.runAsync(() => _capturePng(key));
    _expectPng(bytes!);
    final decoded = await tester.runAsync(() => _decodePng(bytes));
    expect((decoded!.argb(4, 4) >> 24) & 0xFF, 0);
    expect((decoded.argb(48, 48) >> 24) & 0xFF, greaterThan(0));
  });

  testWidgets('large JPG export smoke encodes captured document pixels', (
    tester,
  ) async {
    final doc = _heavyDocument();
    final key = await _mountDocument(tester, doc, assetBundle: _bundle());
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final bytes = await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      try {
        return DocumentJpgExporter.encodeImageAsJpg(image, quality: 92);
      } finally {
        image.dispose();
      }
    });

    expect(bytes, isNotEmpty);
    expect(bytes![0], 0xFF);
    expect(bytes[1], 0xD8);
    final decoded = img.decodeJpg(bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, (doc.width * 2).round());
    expect(decoded.height, (doc.height * 2).round());
  });

  testWidgets('oversized image layer uses bounded decode cache hint', (
    tester,
  ) async {
    final layer = ImageLayer(
      id: 'huge-preview',
      transform: const LayerTransform(
        position: Offset.zero,
        size: Size(9000, 6000),
      ),
      source: const ImageSource.asset('red.png'),
    );

    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: _bundle(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 1,
            height: 1,
            child: OverflowBox(
              maxWidth: 10000,
              maxHeight: 10000,
              child: Builder(builder: layer.buildContent),
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image;
    expect(provider, isA<ResizeImage>());
    expect((provider as ResizeImage).width, 2048);
  });
}
