import 'dart:async';
import 'dart:ui' as ui;

import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_mask.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:canvas_engine/features/editor/engine/export/document_png_exporter.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/rendering/document_view.dart';
import 'package:canvas_engine/features/editor/engine/rendering/stack_mask_composite.dart';
import 'package:canvas_engine/features/editor/engine/rendering/stack_mask_raster_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Step 6 — per-effect mask rendering gates
/// (docs/effects-step6-per-effect-masks-2026-07.md §6).

const int kDocSide = 200;
const Color kRed = Color(0xFFFF0000);

/// Upper half, hard edge (feather 0 keeps the pixel asserts crisp).
const RectMask kTopMask = RectMask(rect: Rect.fromLTWH(0, 0, 200, 100));

/// Left half — the stack-mask side of the min(α) intersection test.
const RectMask kLeftMask = RectMask(rect: Rect.fromLTWH(0, 0, 100, 200));

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

bool _nearPx(({int r, int g, int b}) px, ({int r, int g, int b}) e) =>
    _near(px.r, e.r) && _near(px.g, e.g) && _near(px.b, e.b);

Future<void> _prewarm(WidgetTester tester, LayerMask mask) async {
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
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  return key;
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

EffectStack _stack(List<EditorEffect> effects, {LayerMask? stackMask}) =>
    EffectStack(List<EditorEffect>.unmodifiable(effects),
        stackMask: stackMask);

List<double> _matrixOfStack(List<EditorEffect> unmasked) =>
    _stack(unmasked).composedColorMatrix!;

void main() {
  tearDown(StackMaskRasterCache.instance.clearForTest);

  group('structure gates', () {
    testWidgets('unmasked effect stacks never build the segmented path',
        (tester) async {
      await _mount(
        tester,
        _doc(_stack([const SaturationEffect(amount: 0.5)])),
      );
      expect(find.byType(StackMaskComposite), findsNothing,
          reason: 'fast path must stay widget-identical for every '
              'pre-Step-6 document');
      expect(find.byType(ShaderMask), findsNothing);
    });

    testWidgets('one masked matrix effect builds exactly one composite',
        (tester) async {
      await _prewarm(tester, kTopMask);
      await _mount(
        tester,
        _doc(_stack([BrightnessEffect(amount: 60, mask: kTopMask)])),
      );
      expect(find.byType(StackMaskComposite), findsOneWidget);
      expect(find.byType(ShaderMask), findsOneWidget);
    });
  });

  group('pixel gates', () {
    testWidgets(
        'masked effect confined to its region; effect below it applies '
        'everywhere', (tester) async {
      // effects[0] = saturation (unmasked, applies everywhere),
      // effects[1] = brightness masked to the top half.
      final effects = _stack([
        const SaturationEffect(amount: 0),
        BrightnessEffect(amount: 60, mask: kTopMask),
      ]);
      final bottomExpected = _applyMatrix(
        _matrixOfStack([const SaturationEffect(amount: 0)]),
        kRed,
      );
      final topExpected = _applyMatrix(
        _matrixOfStack([
          const SaturationEffect(amount: 0),
          BrightnessEffect(amount: 60),
        ]),
        kRed,
      );

      await _prewarm(tester, kTopMask);
      final key = await _mount(tester, _doc(effects));
      final shot = await _captureSettled(
        tester,
        key,
        (px) => _nearPx(px(100, 180), bottomExpected),
      );

      expect(_nearPx(shot.px(100, 30), topExpected), isTrue,
          reason: 'inside the mask both effects apply in stack order '
              '(${shot.px(100, 30)} vs $topExpected)');
      expect(_nearPx(shot.px(100, 180), bottomExpected), isTrue,
          reason: 'outside the mask only the unmasked effect applies '
              '(${shot.px(100, 180)} vs $bottomExpected)');
    });

    testWidgets('per-effect mask ∧ stack mask = min(α) intersection',
        (tester) async {
      // Brightness masked to the top half; the whole stack masked to
      // the left half → the effect may only survive top-left.
      final effects = _stack(
        [BrightnessEffect(amount: 60, mask: kTopMask)],
        stackMask: kLeftMask,
      );
      final effected = _applyMatrix(
        _matrixOfStack([BrightnessEffect(amount: 60)]),
        kRed,
      );
      const red = (r: 255, g: 0, b: 0);

      await _prewarm(tester, kTopMask);
      await _prewarm(tester, kLeftMask);
      final key = await _mount(tester, _doc(effects));
      final shot = await _captureSettled(
        tester,
        key,
        (px) => _nearPx(px(50, 30), effected),
      );

      expect(_nearPx(shot.px(50, 30), effected), isTrue,
          reason: 'top-left: both masks agree → effected');
      expect(_nearPx(shot.px(150, 30), red), isTrue,
          reason: 'top-right: stack mask vetoes (${shot.px(150, 30)})');
      expect(_nearPx(shot.px(50, 180), red), isTrue,
          reason: 'bottom-left: effect mask vetoes (${shot.px(50, 180)})');
      expect(_nearPx(shot.px(150, 180), red), isTrue,
          reason: 'bottom-right: both veto');
    });
  });
}
