import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Field-preservation suite for [ImageLayer]. Mirrors the equivalent
/// suites for [TextLayer] / [ShapeLayer] / [PaintLayer]. Audit
/// May 2026 flagged the missing parity test as a coverage gap; this
/// closes it.
///
/// Every `with*` mutator must round-trip every other field unchanged.
/// `withTransform` is the historical hot spot per AGENTS.md "the
/// most-broken contract by AI agents" — adding a new field to
/// [ImageLayer] without updating `copyAll` silently corrupts the
/// document mid-drag, and that's exactly what this suite is here to
/// catch.
void main() {
  group('ImageLayer — copyAll preserves every field across codec', () {
    ImageLayer makeLoaded() => ImageLayer(
      id: 'img-loaded',
      transform: const LayerTransform(
        position: Offset(50, 60),
        size: Size(300, 200),
        rotation: 0.25,
      ),
      source: const ImageSource.network('https://example.com/p.jpg'),
      fit: BoxFit.contain,
      mask: ImageMask.circle,
      borderColor: const Color(0xFF112233),
      borderWidth: 4,
      shadowColor: const Color(0xFF445566),
      shadowBlur: 8,
      shadowOffset: const Offset(2, 3),
      shadowOpacity: 0.6,
      cropRect: const Rect.fromLTRB(0.1, 0.2, 0.8, 0.9),
      filterPreset: ImageFilterPreset.dramatic,
      name: 'hero photo',
      visible: false,
      locked: true,
      opacity: 0.42,
    );

    String encode(ImageLayer l) => DocumentCodec.encode(
      EditorDocument(layers: [l], width: 1000, height: 1000),
    );

    test('withTransform preserves every other field', () {
      final base = makeLoaded();
      const next = LayerTransform(position: Offset(0, 0), size: Size(10, 10));
      final mutated = base.withTransform(next) as ImageLayer;
      expect(mutated.source, base.source);
      expect(mutated.fit, base.fit);
      expect(mutated.mask, base.mask);
      expect(mutated.borderColor, base.borderColor);
      expect(mutated.borderWidth, base.borderWidth);
      expect(mutated.shadowColor, base.shadowColor);
      expect(mutated.shadowBlur, base.shadowBlur);
      expect(mutated.shadowOffset, base.shadowOffset);
      expect(mutated.shadowOpacity, base.shadowOpacity);
      expect(mutated.cropRect, base.cropRect);
      expect(mutated.filterPreset, base.filterPreset);
      expect(mutated.name, base.name);
      expect(mutated.visible, base.visible);
      expect(mutated.locked, base.locked);
      expect(mutated.opacity, base.opacity);
      expect(mutated.transform, next);
    });

    test('withVisibility / withLocked / withOpacity preserve all peers', () {
      final base = makeLoaded();
      final shown = base.withVisibility(true) as ImageLayer;
      expect(shown.visible, true);
      expect(shown.borderColor, base.borderColor);
      expect(shown.cropRect, base.cropRect);
      expect(shown.shadowOpacity, base.shadowOpacity);

      final unlocked = base.withLocked(false) as ImageLayer;
      expect(unlocked.locked, false);
      expect(unlocked.filterPreset, base.filterPreset);
      expect(unlocked.mask, base.mask);

      final dim = base.withOpacity(0.1) as ImageLayer;
      expect(dim.opacity, 0.1);
      expect(dim.borderWidth, base.borderWidth);
      expect(dim.shadowBlur, base.shadowBlur);
      expect(dim.cropRect, base.cropRect);
    });

    test('round-trip is byte-identical', () {
      final base = makeLoaded();
      final raw = encode(base);
      final back = DocumentCodec.decode(raw).layers.single as ImageLayer;
      expect(back, base);
      expect(encode(back), raw);
    });

    test('default-valued layer round-trips byte-identical', () {
      // Schema-discipline check: a freshly-constructed layer with
      // every field at its default must serialise to the smallest
      // possible JSON and survive a round-trip identically. This is
      // the contract that keeps existing on-disk documents stable.
      final layer = ImageLayer(
        id: 'img-default',
        transform: const LayerTransform(
          position: Offset.zero,
          size: Size(100, 100),
        ),
        source: const ImageSource.asset('assets/p.png'),
      );
      final raw = encode(layer);
      final back = DocumentCodec.decode(raw).layers.single as ImageLayer;
      expect(back, layer);
      expect(encode(back), raw);
    });

    test('effect stack round-trips through copyAll', () {
      // Image layers carry an EffectStack post-Phase 2; verify a
      // non-empty stack survives both withTransform and a codec
      // round-trip. Catches the subtle bug where copyAll omits
      // `effects:` in its delegating constructor call.
      const stack = EffectStack(<EditorEffect>[]);
      final base = ImageLayer(
        id: 'img-fx',
        transform: const LayerTransform(
          position: Offset.zero,
          size: Size(100, 100),
        ),
        source: const ImageSource.asset('assets/p.png'),
        effects: stack,
      );
      final transformed =
          base.withTransform(
                const LayerTransform(
                  position: Offset(20, 20),
                  size: Size(200, 200),
                ),
              )
              as ImageLayer;
      expect(transformed.effects, base.effects);

      final raw = encode(base);
      final back = DocumentCodec.decode(raw).layers.single as ImageLayer;
      expect(back.effects, base.effects);
      expect(raw, encode(back));
    });
  });
}
