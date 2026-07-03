import 'dart:ui' as ui;

import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/export/document_jpg_exporter.dart';
import 'package:canvas_engine/features/editor/engine/export/document_png_exporter.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/engine/rendering/document_thumbnail.dart';
import 'package:canvas_engine/features/editor/engine/rendering/document_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Future<GlobalKey> _mount(
  WidgetTester tester, {
  required EditorDocument doc,
  required Widget child,
  AssetBundle? assetBundle,
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
        child: Center(
          child: SizedBox(
            width: doc.width,
            height: doc.height,
            child: RepaintBoundary(key: key, child: child),
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

Future<Uint8List> _capturePng(GlobalKey key) async {
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

void _expectJpgChannelClose(img.Pixel px, Color color) {
  const tolerance = 5;
  expect((px.r - (color.r * 255).round()).abs(), lessThanOrEqualTo(tolerance));
  expect((px.g - (color.g * 255).round()).abs(), lessThanOrEqualTo(tolerance));
  expect((px.b - (color.b * 255).round()).abs(), lessThanOrEqualTo(tolerance));
}

void main() {
  testWidgets('DocumentThumbnail and DocumentView share the same pixels', (
    tester,
  ) async {
    final doc = EditorDocument(
      width: 96,
      height: 64,
      backgroundColor: const Color(0xFF102030),
      layers: [
        ShapeLayer(
          id: 'shape-red',
          transform: const LayerTransform(
            position: Offset(0, 0),
            size: Size(48, 64),
          ),
          kind: ShapeKind.rectangle,
          fillColor: const Color(0xFFE53935),
        ),
        ShapeLayer(
          id: 'hidden-green',
          transform: const LayerTransform(
            position: Offset(0, 0),
            size: Size(96, 64),
          ),
          kind: ShapeKind.rectangle,
          fillColor: const Color(0xFF00FF00),
          visible: false,
        ),
        const TextLayer(
          id: 'label',
          transform: LayerTransform(
            position: Offset(56, 34),
            size: Size(32, 18),
          ),
          content: 'OK',
          style: TextStyleSpec(fontSize: 14, color: Color(0xFFFFFFFF)),
        ),
      ],
    );

    final viewKey = await _mount(
      tester,
      doc: doc,
      child: DocumentView(
        document: doc,
        backgroundFill: doc.background,
        honorTransparentMode: true,
      ),
    );
    final viewBytes = await tester.runAsync(() => _capturePng(viewKey));

    final thumbKey = await _mount(
      tester,
      doc: doc,
      child: DocumentThumbnail(document: doc),
    );
    final thumbBytes = await tester.runAsync(() => _capturePng(thumbKey));

    final view = await tester.runAsync(() => _decodePng(viewBytes!));
    final thumb = await tester.runAsync(() => _decodePng(thumbBytes!));
    expect(view!.width, doc.width.round());
    expect(view.height, doc.height.round());
    expect(thumb!.width, view.width);
    expect(thumb.height, view.height);
    expect(thumb.argb(12, 32), view.argb(12, 32));
    expect(view.argb(12, 32), const Color(0xFFE53935).toARGB32());
    expect(thumb.argb(80, 8), view.argb(80, 8));
    expect(view.argb(80, 8), const Color(0xFF102030).toARGB32());
  });

  testWidgets('transparent PNG keeps empty canvas pixels transparent', (
    tester,
  ) async {
    final doc = EditorDocument(
      width: 40,
      height: 40,
      layers: const [],
      backgroundMode: CanvasBackgroundMode.transparent,
    );
    final key = await _mount(
      tester,
      doc: doc,
      child: DocumentView(
        document: doc,
        backgroundFill: doc.background,
        honorTransparentMode: true,
      ),
    );

    final bytes = await tester.runAsync(() => _capturePng(key));
    final decoded = await tester.runAsync(() => _decodePng(bytes!));
    expect((decoded!.argb(20, 20) >> 24) & 0xFF, 0);
  });

  testWidgets('JPG flatten path paints transparent documents over background', (
    tester,
  ) async {
    const flatten = Color(0xFF20B2AA);
    final doc = EditorDocument(
      width: 32,
      height: 32,
      layers: const [],
      background: const SolidBackground(color: flatten),
      backgroundMode: CanvasBackgroundMode.transparent,
    );
    final key = await _mount(
      tester,
      doc: doc,
      child: DocumentView(document: doc, backgroundFill: doc.background),
    );

    final bytes = await tester.runAsync(() async {
      final ro =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await ro.toImage(pixelRatio: 1.0);
      try {
        return DocumentJpgExporter.encodeImageAsJpg(image, quality: 100);
      } finally {
        image.dispose();
      }
    });
    final decoded = img.decodeJpg(bytes!);
    expect(decoded, isNotNull);
    expect(decoded!.width, doc.width.round());
    expect(decoded.height, doc.height.round());
    _expectJpgChannelClose(decoded.getPixel(16, 16), flatten);
  });

  testWidgets('image layer exports with deterministic filter pixels', (
    tester,
  ) async {
    final bundle = _MemoryAssetBundle({
      'solid.png': _solidPngBytes(const Color(0xFFFF0000)),
    });
    final doc = EditorDocument(
      width: 48,
      height: 48,
      layers: [
        ImageLayer(
          id: 'image',
          transform: const LayerTransform(
            position: Offset(0, 0),
            size: Size(48, 48),
          ),
          source: const ImageSource.asset('solid.png'),
          fit: BoxFit.cover,
          filterPreset: ImageFilterPreset.mono,
        ),
      ],
      backgroundColor: const Color(0xFFFFFFFF),
    );
    final key = await _mount(
      tester,
      doc: doc,
      assetBundle: bundle,
      child: DocumentView(document: doc, backgroundFill: doc.background),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final bytes = await tester.runAsync(() => _capturePng(key));
    final decoded = await tester.runAsync(() => _decodePng(bytes!));
    final argb = decoded!.argb(24, 24);
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    expect((r - g).abs(), lessThanOrEqualTo(2));
    expect((g - b).abs(), lessThanOrEqualTo(2));
    expect(r, greaterThan(40));
  });
}
