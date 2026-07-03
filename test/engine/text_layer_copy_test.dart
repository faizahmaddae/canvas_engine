import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors the [ImageLayer] copyAll preservation suite. Each `with*`
/// MUST produce a layer that, when round-tripped through the codec,
/// differs from the receiver only in the targeted JSON keys. Drops
/// of any other field are the "field-loss" failure mode AGENTS.md
/// flags as the #1 broken-by-AI contract.
void main() {
  group('TextLayer — copyAll preserves every field across codec', () {
    TextLayer makeLoaded() => const TextLayer(
      id: 'txt-loaded',
      transform: LayerTransform(
        position: Offset(50, 60),
        size: Size(300, 200),
        rotation: 0.25,
      ),
      content: 'Hello, world',
      style: TextStyleSpec(
        fontSize: 32,
        color: Color(0xFFAB12CD),
        italic: true,
        underline: true,
        letterSpacing: 1.5,
        lineHeight: 1.4,
      ),
      resizeMode: TextResizeMode.resizeBox,
      textDirectionMode: TextDirectionMode.rtl,
      kind: TextLayerKind.emojiSticker,
      name: 'hero-text',
      visible: false,
      locked: true,
      opacity: 0.42,
    );

    String encode(TextLayer l) => DocumentCodec.encode(
      EditorDocument(layers: [l], width: 1000, height: 1000),
    );

    test('withTransform preserves every other field', () {
      final base = makeLoaded();
      const next = LayerTransform(position: Offset(0, 0), size: Size(10, 10));
      final mutated = base.withTransform(next) as TextLayer;
      expect(mutated.content, base.content);
      expect(mutated.style, base.style);
      expect(mutated.resizeMode, base.resizeMode);
      expect(mutated.textDirectionMode, base.textDirectionMode);
      expect(mutated.kind, base.kind);
      expect(mutated.name, base.name);
      expect(mutated.visible, base.visible);
      expect(mutated.locked, base.locked);
      expect(mutated.opacity, base.opacity);
      expect(mutated.transform, next);
    });

    test('withVisibility / withLocked / withOpacity preserve all peers', () {
      final base = makeLoaded();
      final shown = base.withVisibility(true) as TextLayer;
      expect(shown.visible, true);
      expect(shown.content, base.content);
      expect(shown.style, base.style);
      expect(shown.kind, base.kind);
      expect(shown.textDirectionMode, base.textDirectionMode);
      expect(shown.opacity, base.opacity);

      final unlocked = base.withLocked(false) as TextLayer;
      expect(unlocked.locked, false);
      expect(unlocked.style, base.style);
      expect(unlocked.textDirectionMode, base.textDirectionMode);

      final dim = base.withOpacity(0.1) as TextLayer;
      expect(dim.opacity, 0.1);
      expect(dim.style, base.style);
      expect(dim.kind, base.kind);
      expect(dim.textDirectionMode, base.textDirectionMode);
    });

    test('withName and copyWith preserve direction unless changed', () {
      final base = makeLoaded();
      final renamed = base.withName('caption') as TextLayer;
      expect(renamed.name, 'caption');
      expect(renamed.textDirectionMode, base.textDirectionMode);

      final restyled = base.copyWith(content: 'سلام');
      expect(restyled.content, 'سلام');
      expect(restyled.textDirectionMode, base.textDirectionMode);

      final forced = base.copyWith(textDirectionMode: TextDirectionMode.ltr);
      expect(forced.textDirectionMode, TextDirectionMode.ltr);
    });

    test('round-trip is byte-identical', () {
      final base = makeLoaded();
      final raw = encode(base);
      final back = DocumentCodec.decode(raw).layers.single as TextLayer;
      expect(back, base);
      expect(encode(back), raw);
    });

    test('missing or unknown textDirectionMode decodes as auto', () {
      final base = makeLoaded();
      final json = base.toJson();
      json.remove('textDirectionMode');
      expect(
        TextLayer.fromJson(json).textDirectionMode,
        TextDirectionMode.auto,
      );

      final unknown = <String, dynamic>{
        ...base.toJson(),
        'textDirectionMode': 'vertical',
      };
      expect(
        TextLayer.fromJson(unknown).textDirectionMode,
        TextDirectionMode.auto,
      );
    });
  });
}
