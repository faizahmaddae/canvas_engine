// A3 Step 0 SPIKE — throwaway branch only, never merged.
//
// Prototypes the effects.md §5 stackMask compositing line:
//
//     I_prev := composite(I_prev over I0 through stack.stackMask)
//
// on a stand-in for one ImageLayer's pixel subtree, with one feathered
// RectMask. Two candidate Flutter mechanisms:
//
//   A. ShaderMask(blendMode: dstIn, shader: ImageShader(maskImage))
//      wrapping the effected subtree, stacked over the un-effected
//      base subtree. ShaderMask is a compositing layer, so it applies
//      to the child's *composited output* — safe even when the child
//      pushes its own layers (ColorFiltered does).
//
//   B. canvas.saveLayer + paint child + drawImageRect(mask, dstIn) +
//      restore, via a RenderProxyBox. Canvas-level trick: predicted to
//      BREAK when the child pushes a compositing layer (ColorFiltered
//      → ColorFilterLayer splits the recording, so the dstIn mask no
//      longer sees the child's pixels).
//
// Mask alpha source for both: RectMask.sampleAlpha rasterized into an
// RGBA image — the engine's own alpha definition (linear feather ramp,
// invert flag) is the ground truth, not a Gaussian approximation.
//
// Verified here:
//   (a) masked region effected / rest original / feather ramp smooth
//       and monotonic / inverted mask flips regions;
//   (b) the stackMask == null path returns the child subtree
//       IDENTICAL (same widget instance, same render tree) to today.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_engine/features/editor/engine/core/layer_mask.dart';

// ---------------------------------------------------------------------------
// Shared fixtures
// ---------------------------------------------------------------------------

const int kLayerW = 200;
const int kLayerH = 200;

/// BT.601 greyscale matrix — visually unmistakable on a pure-red base:
/// effected pixels read (76, 76, 76), un-effected read (255, 0, 0).
const List<double> kGreyscaleMatrix = <double>[
  0.299, 0.587, 0.114, 0, 0, //
  0.299, 0.587, 0.114, 0, 0, //
  0.299, 0.587, 0.114, 0, 0, //
  0, 0, 0, 1, 0, //
];

const Color kBaseRed = Color(0xFFFF0000);
const int kGrey = 76; // 0.299 * 255, rounded

/// Upper half of the layer, feathered 24px outward from the boundary
/// (RectMask semantics: alpha 1 inside, linear ramp 1→0 over feather
/// px outside).
const RectMask kMask = RectMask(
  rect: Rect.fromLTWH(0, 0, 200, 100),
  feather: 24,
);

const RectMask kMaskInverted = RectMask(
  rect: Rect.fromLTWH(0, 0, 200, 100),
  feather: 24,
  inverted: true,
);

/// Rasterize a [LayerMask] into a white RGBA image whose alpha channel
/// is `sampleAlpha` evaluated at each pixel center. This is the
/// ground-truth renderer contract candidate: the raster honours the
/// engine's linear feather ramp and invert flag exactly (unlike a
/// MaskFilter.blur approximation, whose Gaussian profile deviates from
/// sampleAlpha's linear ramp).
Future<ui.Image> rasterizeMaskAlpha(LayerMask mask, int w, int h) {
  final bytes = Uint8List(w * h * 4);
  var i = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final a = (mask.sampleAlpha(Offset(x + 0.5, y + 0.5)) * 255).round();
      bytes[i] = 255;
      bytes[i + 1] = 255;
      bytes[i + 2] = 255;
      bytes[i + 3] = a;
      i += 4;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bytes,
    w,
    h,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Stand-in for ImageLayer's pixel subtree. `effected` mirrors how
/// buildContent applies the composed colour matrix today: a
/// ColorFiltered wrapper (which pushes a ColorFilterLayer — the
/// compositing behaviour approach B must survive).
Widget layerPixels({required bool effected}) {
  final pixels = Container(color: kBaseRed);
  if (!effected) return pixels;
  return ColorFiltered(
    colorFilter: const ColorFilter.matrix(kGreyscaleMatrix),
    child: pixels,
  );
}

/// The §3.4 composite: effected `painted` over un-effected `base`
/// through the stack mask's alpha. `maskWidget` wraps ONLY the painted
/// subtree; base shows through wherever mask alpha < 1.
Widget composite({
  required Widget Function(Widget painted) maskWrap,
}) {
  return _harness(
    Stack(
      fit: StackFit.expand,
      children: <Widget>[
        layerPixels(effected: false), // base — I0
        maskWrap(layerPixels(effected: true)), // painted ∘ mask
      ],
    ),
  );
}

/// Directionality + fixed-size RepaintBoundary shell shared by every
/// pump, so pixel captures always come from a 200×200 surface.
Widget _harness(Widget child) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: RepaintBoundary(
        child: SizedBox(
          width: kLayerW.toDouble(),
          height: kLayerH.toDouble(),
          child: child,
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Approach A — ShaderMask + ImageShader
// ---------------------------------------------------------------------------

Widget approachA(ui.Image maskImage, Widget painted) {
  return ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (Rect bounds) => ui.ImageShader(
      maskImage,
      TileMode.clamp,
      TileMode.clamp,
      Matrix4.identity().storage,
    ),
    child: painted,
  );
}

// ---------------------------------------------------------------------------
// Approach B — canvas saveLayer + dstIn via RenderProxyBox
// ---------------------------------------------------------------------------

class SaveLayerMask extends SingleChildRenderObjectWidget {
  const SaveLayerMask({super.key, required this.maskImage, super.child});

  final ui.Image maskImage;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderSaveLayerMask(maskImage);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSaveLayerMask renderObject,
  ) {
    renderObject.maskImage = maskImage;
  }
}

class RenderSaveLayerMask extends RenderProxyBox {
  RenderSaveLayerMask(this._maskImage);

  /// Records the canvas-invalidation error the spike is designed to
  /// measure, so the test can assert on it instead of crashing the
  /// paint phase.
  static Object? lastPaintError;

  ui.Image _maskImage;
  set maskImage(ui.Image value) {
    if (identical(value, _maskImage)) return;
    _maskImage = value;
    markNeedsPaint();
  }

  ui.Image get maskImage => _maskImage;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final canvas = context.canvas;
    final bounds = offset & size;
    canvas.saveLayer(bounds, Paint());
    // If the child needs compositing (ColorFiltered does), paintChild
    // ends the current native recording and appends the child as its
    // own layer: the child ESCAPES this saveLayer, and the `canvas`
    // reference above is invalidated. The dstIn below then throws
    // ("native peer collected") — that failure mode is exactly what
    // this spike measures, so record it rather than crash.
    context.paintChild(child!, offset);
    try {
      canvas.drawImageRect(
        _maskImage,
        Rect.fromLTWH(
          0,
          0,
          _maskImage.width.toDouble(),
          _maskImage.height.toDouble(),
        ),
        bounds,
        Paint()..blendMode = BlendMode.dstIn,
      );
      canvas.restore();
    } catch (e) {
      lastPaintError = e;
    }
  }
}

// ---------------------------------------------------------------------------
// Pixel-capture helpers
// ---------------------------------------------------------------------------

Future<ByteData> capturePixels(WidgetTester tester) async {
  final boundary = tester
      .renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
  final data = await tester.runAsync(() async {
    final img = await boundary.toImage(); // pixelRatio 1.0 → 200×200
    final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    return bd!;
  });
  return data!;
}

({int r, int g, int b}) px(ByteData data, int x, int y) {
  final o = (y * kLayerW + x) * 4;
  return (
    r: data.getUint8(o),
    g: data.getUint8(o + 1),
    b: data.getUint8(o + 2),
  );
}

bool near(int actual, int expected, [int tol = 4]) =>
    (actual - expected).abs() <= tol;

/// Correctness predicate shared by both approaches, straight from the
/// §3.4 semantics with this fixture's colours:
///   out = α·grey + (1−α)·red, α = mask.sampleAlpha.
({bool inside, bool outside, bool featherMid, bool monotonic}) judge(
  ByteData data,
) {
  final inside = px(data, 100, 30); // α = 1 → grey
  final outside = px(data, 100, 180); // α = 0 → red
  final mid = px(data, 100, 112); // α = 0.5 → blend
  final rampHi = px(data, 100, 104); // α = 5/6 → mostly grey
  final rampLo = px(data, 100, 120); // α = 1/6 → mostly red
  return (
    inside: near(inside.r, kGrey) &&
        near(inside.g, kGrey) &&
        near(inside.b, kGrey),
    outside:
        near(outside.r, 255) && near(outside.g, 0) && near(outside.b, 0),
    // out.r at α=0.5: 0.5·76 + 0.5·255 ≈ 166; g/b: 0.5·76 = 38.
    featherMid: near(mid.r, 166, 8) && near(mid.g, 38, 8) && near(mid.b, 38, 8),
    // α decreases with y across the band → red recovers monotonically.
    monotonic: rampHi.r < mid.r && mid.r < rampLo.r && rampHi.g > rampLo.g,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  testWidgets('A: ShaderMask+ImageShader — masked effected, rest original, '
      'smooth feather', (tester) async {
    final maskImg = (await tester.runAsync(
      () => rasterizeMaskAlpha(kMask, kLayerW, kLayerH),
    ))!;

    await tester.pumpWidget(
      composite(maskWrap: (p) => approachA(maskImg, p)),
    );
    final data = await capturePixels(tester);
    final v = judge(data);

    expect(v.inside, isTrue, reason: 'masked region must be effected (grey)');
    expect(v.outside, isTrue, reason: 'unmasked region must stay original');
    expect(v.featherMid, isTrue, reason: 'feather midpoint must blend 50/50');
    expect(v.monotonic, isTrue, reason: 'feather ramp must be monotonic');
  });

  testWidgets('A: inverted mask flips effected/original regions',
      (tester) async {
    final maskImg = (await tester.runAsync(
      () => rasterizeMaskAlpha(kMaskInverted, kLayerW, kLayerH),
    ))!;

    await tester.pumpWidget(
      composite(maskWrap: (p) => approachA(maskImg, p)),
    );
    final data = await capturePixels(tester);

    final wasMasked = px(data, 100, 30); // now α = 0 → original red
    final wasOutside = px(data, 100, 180); // now α = 1 → effected grey
    expect(near(wasMasked.r, 255) && near(wasMasked.g, 0), isTrue,
        reason: 'inverted: inside old rect must be original');
    expect(near(wasOutside.r, kGrey) && near(wasOutside.g, kGrey), isTrue,
        reason: 'inverted: outside old rect must be effected');
  });

  testWidgets(
      'B: saveLayer+dstIn — measure whether a compositing child '
      '(ColorFiltered) survives the canvas-level mask', (tester) async {
    final maskImg = (await tester.runAsync(
      () => rasterizeMaskAlpha(kMask, kLayerW, kLayerH),
    ))!;

    await tester.pumpWidget(
      composite(
        maskWrap: (p) => SaveLayerMask(maskImage: maskImg, child: p),
      ),
    );
    final data = await capturePixels(tester);
    final v = judge(data);

    // Record the observed truth; the design note cites this result.
    // ignore: avoid_print
    print('SPIKE B verdict: inside=${v.inside} outside=${v.outside} '
        'featherMid=${v.featherMid} monotonic=${v.monotonic} '
        'insidePx=${px(data, 100, 30)} outsidePx=${px(data, 100, 180)} '
        'midPx=${px(data, 100, 112)} '
        'paintError=${RenderSaveLayerMask.lastPaintError}');

    // Approach B is structurally broken for compositing children:
    // the child leaks out of the saveLayer unmasked (effect applied
    // everywhere), and the deferred dstIn throws on the invalidated
    // canvas. Both symptoms must hold for the design note's claim.
    expect(RenderSaveLayerMask.lastPaintError, isNotNull,
        reason: 'compositing child must invalidate the cached canvas');
    expect(v.inside, isTrue,
        reason: 'leaked child still paints the effect inside the rect');
    expect(v.outside, isFalse,
        reason: 'leak applies the effect OUTSIDE the mask too — broken');
  });

  testWidgets('null stackMask path is render-tree identical to today',
      (tester) async {
    // Integration contract: when stackMask == null, buildContent
    // returns EXACTLY the subtree it returns today — the composite
    // wrapper is simply never constructed.
    Widget withStackMask(Widget child, {ui.Image? maskImage}) {
      if (maskImage == null) return child;
      return composite(maskWrap: (p) => approachA(maskImage, p));
    }

    final child = layerPixels(effected: true);
    final wrapped = withStackMask(child);
    expect(identical(wrapped, child), isTrue,
        reason: 'null mask must not allocate any wrapper widget');

    await tester.pumpWidget(_harness(wrapped));
    final treeWithNullMask =
        tester.renderObject(find.byType(SizedBox)).toStringDeep();

    await tester.pumpWidget(_harness(layerPixels(effected: true)));
    final treeToday =
        tester.renderObject(find.byType(SizedBox)).toStringDeep();

    expect(treeWithNullMask, equals(treeToday),
        reason: 'null-mask render tree must be byte-identical to today');
  });
}
