import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_mask.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:canvas_engine/features/editor/engine/export/document_png_exporter.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/rendering/stack_mask_raster_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Regression coverage for `DocumentPngExporter.prewarm` — the cold-cache
/// parity step that makes PNG / JPG / thumbnail export match the editor
/// render path even when the off-screen snapshot runs before the canvas
/// has ever painted the layer.
///
/// The full [DocumentPngExporter.export] overlay path can't be driven
/// end-to-end in a widget test: it waits on a post-frame callback that no
/// test pump fires, so it deadlocks under [WidgetTester.runAsync] (see the
/// note in export_background_test.dart). The prewarm is therefore exposed
/// as a public seam and its contract verified directly here: after it
/// resolves, both async render inputs the single-frame snapshot depends on
/// — the image decode and the stack-mask alpha raster — are ready.

const int kSide = 200;

/// Upper half of the layer, feathered like the stack-mask render tests.
const RectMask kMask = RectMask(
  rect: Rect.fromLTWH(0, 0, 200, 100),
  feather: 24,
);

Uint8List _solidPngBytes(Color color) {
  final image = img.Image(width: 16, height: 16);
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

/// Minimal in-memory bundle so `Image.asset` / precache resolve a real
/// PNG without touching disk. Mirrors the pattern in
/// export_render_parity_test.dart.
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

EditorDocument _imageDoc({EffectStack effects = EffectStack.empty}) =>
    EditorDocument(
      width: kSide.toDouble(),
      height: kSide.toDouble(),
      layers: [
        ImageLayer(
          id: 'img',
          transform: const LayerTransform(
            position: Offset.zero,
            size: Size(200, 200),
          ),
          source: const ImageSource.asset('solid.png'),
          effects: effects,
        ),
      ],
      backgroundColor: const Color(0xFFFFFFFF),
    );

/// Pumps a minimal mounted tree and returns a context under a
/// [DefaultAssetBundle] serving [bundle] — everything `precacheImage`
/// needs, nothing the prewarm doesn't read.
Future<BuildContext> _mountContext(
  WidgetTester tester,
  AssetBundle bundle,
) async {
  late BuildContext captured;
  await tester.pumpWidget(
    DefaultAssetBundle(
      bundle: bundle,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    ),
  );
  return captured;
}

void main() {
  tearDown(StackMaskRasterCache.instance.clearForTest);

  testWidgets(
    'prewarm makes a cold stack-mask raster ready before the snapshot',
    (tester) async {
      StackMaskRasterCache.instance.clearForTest();
      final bundle = _MemoryAssetBundle({
        'solid.png': _solidPngBytes(const Color(0xFFFF0000)),
      });
      final doc = _imageDoc(
        effects: EffectStack(const <EditorEffect>[
          SaturationEffect(amount: 0),
        ], stackMask: kMask),
      );

      // Cold: the composite would render the un-masked base here.
      expect(
        StackMaskRasterCache.instance.lookup(kMask, kSide, kSide),
        isNull,
        reason: 'raster must start cold so the fix is what fills it',
      );

      final context = await _mountContext(tester, bundle);
      await tester.runAsync(() => DocumentPngExporter.prewarm(doc, context));

      // Warm: a snapshot taken now composites the masked effect, not base.
      expect(
        StackMaskRasterCache.instance.lookup(kMask, kSide, kSide),
        isNotNull,
        reason:
            'prewarm must resolve the (mask, w, h) raster the exporter '
            'snapshot depends on',
      );
    },
  );

  testWidgets('prewarm decodes an uncached image layer into the image cache', (
    tester,
  ) async {
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.clear();
    imageCache.clearLiveImages();
    final bundle = _MemoryAssetBundle({
      'solid.png': _solidPngBytes(const Color(0xFF00A0FF)),
    });
    final doc = _imageDoc();

    expect(imageCache.currentSize, 0, reason: 'image cache must start cold');

    final context = await _mountContext(tester, bundle);
    await tester.runAsync(() => DocumentPngExporter.prewarm(doc, context));

    // The layer's bytes are now resident, so the off-screen Image
    // resolves synchronously in the export frame instead of blank.
    expect(
      imageCache.currentSize,
      greaterThan(0),
      reason: 'prewarm must precache the image layer provider',
    );
  });

  testWidgets('prewarm is a no-op for a document with no image layers', (
    tester,
  ) async {
    StackMaskRasterCache.instance.clearForTest();
    final doc = EditorDocument(width: 40, height: 40, layers: const []);
    final context = await _mountContext(tester, _MemoryAssetBundle(const {}));

    // Completes promptly without touching either cache.
    await tester.runAsync(() => DocumentPngExporter.prewarm(doc, context));
    expect(StackMaskRasterCache.instance.lookup(kMask, kSide, kSide), isNull);
  });

  test('exportImageProvider mirrors the source and is null when missing', () {
    final assetLayer = ImageLayer(
      id: 'a',
      transform: const LayerTransform(
        position: Offset.zero,
        size: Size(100, 100),
      ),
      source: const ImageSource.asset('x.png'),
    );
    expect(assetLayer.exportImageProvider(), isNotNull);

    // A non-existent file path resolves to no provider (the renderer
    // shows the missing-image placeholder), so prewarm skips it.
    final missingFile = ImageLayer(
      id: 'b',
      transform: const LayerTransform(
        position: Offset.zero,
        size: Size(100, 100),
      ),
      source: const ImageSource.file('/definitely/not/a/real/file.png'),
    );
    expect(missingFile.exportImageProvider(), isNull);
  });
}

// Kept intentionally simple: pixel-level parity of the composite is
// already covered by stack_mask_render_test / per_effect_mask_render_test
// (via captureBoundary + a manual settle). These tests lock the prewarm
// contract those render paths rely on for the one-shot export snapshot.
