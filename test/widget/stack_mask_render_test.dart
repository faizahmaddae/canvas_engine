import 'dart:async';
import 'dart:ui' as ui;

import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_mask.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/rendering/document_view.dart';
import 'package:canvas_engine/features/editor/engine/rendering/stack_mask_composite.dart';
import 'package:canvas_engine/features/editor/engine/rendering/stack_mask_raster_cache.dart';
import 'package:canvas_engine/features/editor/engine/export/document_png_exporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A3 Step 1 — stackMask render integration, pixel + structure gates.
///
/// Ports the spike's verification (docs/effects-a3-scoped-plan §7.4)
/// onto the REAL ImageLayer.buildContent path through DocumentView:
/// masked region effected, unmasked region byte-original, feather
/// midpoint blends 50/50 on the linear ramp, ramp monotonic,
/// inverted mask swaps regions, and the null-mask path never
/// constructs the composite wrapper.

const int kDocSide = 200;
const Color kRed = Color(0xFFFF0000);

/// Upper half of the layer, feathered 24 px outward (RectMask
/// semantics: alpha 1 inside, linear 1→0 ramp over feather px).
const RectMask kMask = RectMask(
  rect: Rect.fromLTWH(0, 0, 200, 100),
  feather: 24,
);

EffectStack _stack({LayerMask? stackMask, bool contributing = true}) =>
    EffectStack(
      contributing
          ? List<EditorEffect>.unmodifiable(
              <EditorEffect>[const SaturationEffect(amount: 0)],
            )
          : const <EditorEffect>[],
      stackMask: stackMask,
    );

EditorDocument _doc(EffectStack effects) => EditorDocument(
  width: kDocSide.toDouble(),
  height: kDocSide.toDouble(),
  layers: [
    ImageLayer(
      id: 'img',
      transform: const LayerTransform(
        position: Offset.zero,
        size: Size(200, 200),
      ),
      source: const ImageSource.asset('red.png'),
      effects: effects,
    ),
  ],
  backgroundColor: const Color(0xFFFFFFFF),
);

/// Apply a 4×5 colour matrix (ColorFilter.matrix semantics: rows are
/// R,G,B,A; fifth column is an offset in 0..255) to an opaque colour.
({int r, int g, int b}) _applyMatrix(List<double> m, Color c) {
  final r = (c.r * 255).roundToDouble();
  final g = (c.g * 255).roundToDouble();
  final b = (c.b * 255).roundToDouble();
  const a = 255.0;
  double row(int i) =>
      m[i] * r + m[i + 1] * g + m[i + 2] * b + m[i + 3] * a + m[i + 4];
  int clamp8(double v) => v.clamp(0, 255).round();
  return (r: clamp8(row(0)), g: clamp8(row(5)), b: clamp8(row(10)));
}

bool _near(int actual, int expected, [int tol = 4]) =>
    (actual - expected).abs() <= tol;

Future<void> _prewarmRaster(WidgetTester tester, LayerMask mask) async {
  await tester.runAsync(() async {
    final done = Completer<void>();
    StackMaskRasterCache.instance
        .request(mask, kDocSide, kDocSide, done.complete);
    await done.future;
  });
}

Future<GlobalKey> _mount(WidgetTester tester, EditorDocument doc) async {
  final key = GlobalKey();
  tester.view.physicalSize = const Size(200, 200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    DefaultAssetBundle(
      bundle: _MemoryAssetBundle({'red.png': _solidPngBytes(kRed)}),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: Center(
            child: SizedBox(
              width: doc.width,
              height: doc.height,
              child: RepaintBoundary(
                key: key,
                child: DocumentView(
                  document: doc,
                  backgroundFill: doc.background,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // Let the image decode + raster-ready rebuild land.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  return key;
}

/// Capture, waiting out the real-async image decode. Fake-async pumps
/// never complete `instantiateImageCodec`, so we alternate real-time
/// slices (runAsync) with pumps until [painted] reports the image
/// pixels have landed — bounded so a genuine failure still fails.
Future<({int width, int height, ({int r, int g, int b}) Function(int, int) px})>
    _captureSettled(
  WidgetTester tester,
  GlobalKey key,
  bool Function(({int r, int g, int b}) Function(int, int) px) painted,
) async {
  var shot = await _capture(tester, key);
  for (var i = 0; i < 40 && !painted(shot.px); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    shot = await _capture(tester, key);
  }
  return shot;
}

Future<({int width, int height, ({int r, int g, int b}) Function(int, int) px})>
    _capture(WidgetTester tester, GlobalKey key) async {
  final bytes = (await tester.runAsync(
    () => DocumentPngExporter.captureBoundary(boundaryKey: key, pixelRatio: 1.0),
  ))!;
  final decoded = (await tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final raw =
        await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final data = raw!.buffer.asUint8List();
    final width = frame.image.width;
    final height = frame.image.height;
    frame.image.dispose();
    return (width: width, height: height, data: data);
  }))!;
  ({int r, int g, int b}) px(int x, int y) {
    final i = (y * decoded.width + x) * 4;
    return (r: decoded.data[i], g: decoded.data[i + 1], b: decoded.data[i + 2]);
  }

  return (width: decoded.width, height: decoded.height, px: px);
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

void main() {
  tearDown(StackMaskRasterCache.instance.clearForTest);

  group('structure gates', () {
    testWidgets('null stackMask never constructs the composite wrapper',
        (tester) async {
      await _mount(tester, _doc(_stack(stackMask: null)));
      expect(find.byType(StackMaskComposite), findsNothing,
          reason: 'null mask must keep the render tree identical to a '
              'pre-stackMask document');
    });

    testWidgets('non-contributing stack skips the composite even with a mask',
        (tester) async {
      await _mount(
        tester,
        _doc(_stack(stackMask: kMask, contributing: false)),
      );
      expect(find.byType(StackMaskComposite), findsNothing,
          reason: 'base and painted are identical when the stack '
              'contributes nothing — the composite would be a no-op');
    });

    testWidgets('contributing stack + mask mounts exactly one composite',
        (tester) async {
      await _prewarmRaster(tester, kMask);
      await _mount(tester, _doc(_stack(stackMask: kMask)));
      expect(find.byType(StackMaskComposite), findsOneWidget);
      expect(find.byType(ShaderMask), findsOneWidget);
    });

    testWidgets('renders base only until the mask raster resolves',
        (tester) async {
      // No pre-warm: the first build must fall back to the base
      // subtree (no ShaderMask) rather than flash the unmasked effect.
      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: _MemoryAssetBundle({'red.png': _solidPngBytes(kRed)}),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: DocumentView(
              document: _doc(_stack(stackMask: kMask)),
              backgroundFill: const SolidBackground(color: Color(0xFFFFFFFF)),
            ),
          ),
        ),
      );
      expect(find.byType(StackMaskComposite), findsOneWidget);
      expect(find.byType(ShaderMask), findsNothing,
          reason: 'until the raster lands, only the un-effected base '
              'may render — a one-frame flash of the unmasked effect '
              'is the failure mode this guards');
    });
  });

  group('pixel gates (spike §7.4 ported to the real layer)', () {
    testWidgets('masked effected / unmasked original / linear feather',
        (tester) async {
      final stack = _stack(stackMask: kMask);
      final effected = _applyMatrix(stack.composedColorMatrix!, kRed);

      await _prewarmRaster(tester, kMask);
      final key = await _mount(tester, _doc(stack));
      // Painted once the unmasked region shows the source's red.
      final shot = await _captureSettled(
        tester,
        key,
        (px) => _near(px(100, 180).r, 255) && _near(px(100, 180).g, 0),
      );

      final inside = shot.px(100, 30); // α = 1 → effected
      final outside = shot.px(100, 180); // α = 0 → original
      final mid = shot.px(100, 112); // α = 0.5 on the 24px ramp
      final rampHi = shot.px(100, 104); // α = 5/6
      final rampLo = shot.px(100, 120); // α = 1/6

      expect(
        _near(inside.r, effected.r) &&
            _near(inside.g, effected.g) &&
            _near(inside.b, effected.b),
        isTrue,
        reason: 'masked region must show the stack-effected pixels '
            '($inside vs expected $effected)',
      );
      expect(
        _near(outside.r, 255) && _near(outside.g, 0) && _near(outside.b, 0),
        isTrue,
        reason: 'unmasked region must stay byte-original ($outside)',
      );
      final midR = ((effected.r + 255) / 2).round();
      final midG = ((effected.g + 0) / 2).round();
      expect(
        _near(mid.r, midR, 8) && _near(mid.g, midG, 8),
        isTrue,
        reason: 'feather midpoint must blend 50/50 ($mid, expected '
            'r≈$midR g≈$midG)',
      );
      expect(
        rampHi.r < mid.r && mid.r < rampLo.r,
        isTrue,
        reason: 'red must recover monotonically across the feather '
            'band (${rampHi.r} < ${mid.r} < ${rampLo.r})',
      );
    });

    testWidgets('inverted mask swaps the regions exactly', (tester) async {
      const inverted = RectMask(
        rect: Rect.fromLTWH(0, 0, 200, 100),
        feather: 24,
        inverted: true,
      );
      final stack = _stack(stackMask: inverted);
      final effected = _applyMatrix(stack.composedColorMatrix!, kRed);

      await _prewarmRaster(tester, inverted);
      final key = await _mount(tester, _doc(stack));
      // Painted once the (now unmasked) top region shows red.
      final shot = await _captureSettled(
        tester,
        key,
        (px) => _near(px(100, 30).r, 255) && _near(px(100, 30).g, 0),
      );

      final wasInside = shot.px(100, 30); // now α = 0 → original
      final wasOutside = shot.px(100, 180); // now α = 1 → effected
      expect(_near(wasInside.r, 255) && _near(wasInside.g, 0), isTrue,
          reason: 'inverted: inside old rect must be original ($wasInside)');
      expect(
        _near(wasOutside.r, effected.r) && _near(wasOutside.g, effected.g),
        isTrue,
        reason: 'inverted: outside old rect must be effected ($wasOutside)',
      );
    });
  });

  group('raster cache', () {
    testWidgets('evicts LRU past the byte budget, never the newest',
        (tester) async {
      final cache = StackMaskRasterCache.instance;
      // 10×10 rasters are 400 bytes each; budget for two.
      cache.byteBudget = 900;
      addTearDown(() => cache.byteBudget = 32 * 1024 * 1024);

      Future<void> warm(LayerMask m) => tester.runAsync(() async {
            final done = Completer<void>();
            cache.request(m, 10, 10, done.complete);
            await done.future;
          });

      const m1 = RectMask(rect: Rect.fromLTWH(0, 0, 1, 1));
      const m2 = RectMask(rect: Rect.fromLTWH(0, 0, 2, 2));
      const m3 = RectMask(rect: Rect.fromLTWH(0, 0, 3, 3));
      await warm(m1);
      await warm(m2);
      expect(cache.lookup(m1, 10, 10), isNotNull);
      expect(cache.lookup(m2, 10, 10), isNotNull);

      await warm(m3);
      expect(cache.lookup(m3, 10, 10), isNotNull,
          reason: 'newest entry must survive its own insert');
      expect(cache.lookup(m1, 10, 10), isNull,
          reason: 'oldest entry must be evicted past the budget');
    });

    testWidgets('lookup is keyed on mask value AND raster size',
        (tester) async {
      final cache = StackMaskRasterCache.instance;
      await tester.runAsync(() async {
        final done = Completer<void>();
        cache.request(kMask, 10, 10, done.complete);
        await done.future;
      });
      expect(cache.lookup(kMask, 10, 10), isNotNull);
      expect(cache.lookup(kMask, 20, 20), isNull,
          reason: 'a resized layer needs a fresh raster');
      const other = RectMask(rect: Rect.fromLTWH(0, 0, 200, 100), feather: 25);
      expect(cache.lookup(other, 10, 10), isNull,
          reason: 'any mask field change is a different key');
    });
  });
}
