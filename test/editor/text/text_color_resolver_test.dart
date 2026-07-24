import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/text/application/text_color_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Centred 200x80 rect on a 1000x1000 canvas — used by every test
  // unless overridden so each test reads as "what does the resolver
  // do for text dropped at the canvas centre".
  const targetRect = Rect.fromLTWH(400, 460, 200, 80);

  EditorDocument docOf(List<dynamic> layers) => EditorDocument(
    layers: List.unmodifiable(layers),
    width: 1000,
    height: 1000,
  );

  group('TextColorResolver.resolve', () {
    test('keeps requested colour when it already contrasts the canvas', () {
      // Black text on the default white canvas: contrast is ~21:1,
      // so the user's choice should pass through untouched.
      final picked = TextColorResolver.resolve(
        requested: const Color(0xFF000000),
        doc: docOf(const []),
        targetRect: targetRect,
      );
      expect(picked, const Color(0xFF000000));
    });

    test('overrides white-on-white default to black for the canonical '
        '"white canvas" case', () {
      final picked = TextColorResolver.resolve(
        requested: const Color(0xFFFFFFFF),
        doc: docOf(const []),
        targetRect: targetRect,
      );
      expect(picked, TextColorResolver.kHighContrastDark);
    });

    test('overrides black-on-black to white when canvas is black', () {
      final picked = TextColorResolver.resolve(
        requested: const Color(0xFF000000),
        doc: docOf(const []),
        targetRect: targetRect,
        canvasFill: const Color(0xFF000000),
      );
      expect(picked, TextColorResolver.kHighContrastLight);
    });

    test('samples the topmost opaque shape under the text and switches '
        'to white when shape is dark', () {
      // A black rectangle covering the canvas centre. Default white
      // text reads fine over black, so it should pass through.
      final shape = ShapeLayer(
        id: 'bg',
        transform: const LayerTransform(
          position: Offset(0, 0),
          size: Size(1000, 1000),
        ),
        kind: ShapeKind.rectangle,
        fillColor: const Color(0xFF000000),
      );
      final picked = TextColorResolver.resolve(
        requested: const Color(0xFFFFFFFF),
        doc: docOf([shape]),
        targetRect: targetRect,
      );
      expect(picked, const Color(0xFFFFFFFF));
    });

    test('samples a white shape sitting on the (default white) canvas '
        'and overrides default white text to dark', () {
      final shape = ShapeLayer(
        id: 'bg',
        transform: const LayerTransform(
          position: Offset(0, 0),
          size: Size(1000, 1000),
        ),
        kind: ShapeKind.rectangle,
        fillColor: const Color(0xFFFFFFFF),
      );
      final picked = TextColorResolver.resolve(
        requested: const Color(0xFFFFFFFF),
        doc: docOf([shape]),
        targetRect: targetRect,
      );
      expect(picked, TextColorResolver.kHighContrastDark);
    });

    test('topmost layer wins (paint covers an underlying shape)', () {
      // White rectangle covers the canvas; on top, a black filled
      // paint rectangle covers the centre. Sampler must see black.
      final whiteShape = ShapeLayer(
        id: 'shape',
        transform: const LayerTransform(
          position: Offset(0, 0),
          size: Size(1000, 1000),
        ),
        kind: ShapeKind.rectangle,
        fillColor: const Color(0xFFFFFFFF),
      );
      final blackPaint = PaintLayer(
        id: 'paint',
        transform: const LayerTransform(
          position: Offset(200, 200),
          size: Size(600, 600),
        ),
        kind: PaintKind.rectangle,
        normalizedPoints: const [],
        fillColor: const Color(0xFF000000),
      );
      final picked = TextColorResolver.resolve(
        requested: const Color(0xFFFFFFFF),
        doc: docOf([whiteShape, blackPaint]),
        targetRect: targetRect,
      );
      expect(picked, const Color(0xFFFFFFFF));
    });

    test('layers whose bounds miss the text centre are ignored', () {
      // Black shape only covers the bottom-right corner; text centre
      // is (500, 500), which is on the bare white canvas.
      final cornerShape = ShapeLayer(
        id: 'corner',
        transform: const LayerTransform(
          position: Offset(700, 700),
          size: Size(300, 300),
        ),
        kind: ShapeKind.rectangle,
        fillColor: const Color(0xFF000000),
      );
      final picked = TextColorResolver.resolve(
        requested: const Color(0xFFFFFFFF),
        doc: docOf([cornerShape]),
        targetRect: targetRect,
      );
      expect(picked, TextColorResolver.kHighContrastDark);
    });

    test('translucent layers are treated as see-through to the canvas', () {
      // 30% black overlay isn't opaque enough to dominate the
      // background; the white canvas behind it still wins, so default
      // white text should override to dark.
      final overlay = ShapeLayer(
        id: 'overlay',
        transform: const LayerTransform(
          position: Offset(0, 0),
          size: Size(1000, 1000),
        ),
        kind: ShapeKind.rectangle,
        fillColor: const Color(0x4D000000),
      );
      final picked = TextColorResolver.resolve(
        requested: const Color(0xFFFFFFFF),
        doc: docOf([overlay]),
        targetRect: targetRect,
      );
      expect(picked, TextColorResolver.kHighContrastDark);
    });

    test('image layer under the text yields an unknown sample so the '
        'requested colour is preserved verbatim', () {
      // We can't summarise a photo as one colour, so the resolver
      // bails out and trusts the user's chosen colour rather than
      // forcing a black/white guess.
      final image = ImageLayer(
        id: 'photo',
        transform: const LayerTransform(
          position: Offset(0, 0),
          size: Size(1000, 1000),
        ),
        source: const ImageSource.asset('assets/x.png'),
      );
      final picked = TextColorResolver.resolve(
        requested: const Color(0xFFFFFFFF),
        doc: docOf([image]),
        targetRect: targetRect,
      );
      expect(picked, const Color(0xFFFFFFFF));
    });

    test('hidden layers do not affect the sample', () {
      // A black shape that would have flipped the result is hidden,
      // so the bare white canvas wins.
      final hiddenShape = ShapeLayer(
        id: 'hidden',
        transform: const LayerTransform(
          position: Offset(0, 0),
          size: Size(1000, 1000),
        ),
        kind: ShapeKind.rectangle,
        fillColor: const Color(0xFF000000),
        visible: false,
      );
      final picked = TextColorResolver.resolve(
        requested: const Color(0xFFFFFFFF),
        doc: docOf([hiddenShape]),
        targetRect: targetRect,
      );
      expect(picked, TextColorResolver.kHighContrastDark);
    });
  });

  // -------------------------------------------------------------------
  // Default-shadow helper: opposite-luminance, fixed subtle alpha.
  // -------------------------------------------------------------------
  group('TextColorResolver.defaultShadowFor', () {
    int alphaOf(Color c) => (c.a * 255.0).round();
    int redOf(Color c) => (c.r * 255.0).round();
    int greenOf(Color c) => (c.g * 255.0).round();
    int blueOf(Color c) => (c.b * 255.0).round();

    test('white text -> translucent black halo', () {
      final s = TextColorResolver.defaultShadowFor(const Color(0xFFFFFFFF));
      expect(redOf(s), 0);
      expect(greenOf(s), 0);
      expect(blueOf(s), 0);
      expect(alphaOf(s), TextColorResolver.kDefaultShadowAlpha);
    });

    test('black text -> translucent white halo', () {
      final s = TextColorResolver.defaultShadowFor(const Color(0xFF000000));
      expect(redOf(s), 255);
      expect(greenOf(s), 255);
      expect(blueOf(s), 255);
      expect(alphaOf(s), TextColorResolver.kDefaultShadowAlpha);
    });

    test('mid/dark colour text -> light halo (avoids colour bleed)', () {
      // Mid-grey luminance is well below 0.5 -> dark text -> white halo.
      final s = TextColorResolver.defaultShadowFor(const Color(0xFF555555));
      expect(redOf(s), 255);
      expect(greenOf(s), 255);
      expect(blueOf(s), 255);
    });

    test('light brand colour -> dark halo', () {
      // Bright yellow luminance > 0.5 -> dark halo.
      final s = TextColorResolver.defaultShadowFor(const Color(0xFFFFFF00));
      expect(redOf(s), 0);
      expect(greenOf(s), 0);
      expect(blueOf(s), 0);
    });

    test('alpha is always subtle (40%, never opaque)', () {
      for (final c in const [
        Color(0xFFFFFFFF),
        Color(0xFF000000),
        Color(0xFFFF0000),
        Color(0xFF0000FF),
        Color(0xFF888888),
      ]) {
        expect(
          alphaOf(TextColorResolver.defaultShadowFor(c)),
          TextColorResolver.kDefaultShadowAlpha,
          reason: 'shadow for $c must use the subtle default alpha',
        );
      }
    });
  });
}
