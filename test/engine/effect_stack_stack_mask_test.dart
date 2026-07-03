import 'dart:convert';
import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/commands/history_stack.dart';
import 'package:canvas_engine/features/editor/engine/commands/image_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_mask.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// A3 Step 1 — `EffectStack.stackMask` model + serialization.
///
/// The load-bearing invariant (plan §6, trap #1): the `effects` JSON
/// key is gated on the raw effects LIST, never on a composite
/// emptiness. A stackMask-only stack must write NO `effects` key —
/// writing `'effects': []` would change the bytes of every legacy
/// document on disk.
void main() {
  const mask = RectMask(
    rect: Rect.fromLTWH(0, 0, 800, 400),
    feather: 12,
    inverted: true,
  );

  ImageLayer makeImage({EffectStack effects = EffectStack.empty}) =>
      ImageLayer(
        id: 'img-1',
        transform: const LayerTransform(
          position: Offset(100, 100),
          size: Size(200, 200),
        ),
        source: const ImageSource.asset('stub.png'),
        effects: effects,
      );

  group('EffectStack.stackMask — value semantics', () {
    test('== and hashCode include stackMask', () {
      final effects = List<EditorEffect>.unmodifiable(
        <EditorEffect>[BrightnessEffect(amount: 20)],
      );
      final without = EffectStack(effects);
      final withMask = EffectStack(effects, stackMask: mask);
      final withEqualMask = EffectStack(
        effects,
        stackMask: const RectMask(
          rect: Rect.fromLTWH(0, 0, 800, 400),
          feather: 12,
          inverted: true,
        ),
      );

      expect(withMask, equals(withEqualMask));
      expect(withMask.hashCode, equals(withEqualMask.hashCode));
      expect(withMask, isNot(equals(without)));
      expect(withMask.hashCode, isNot(equals(without.hashCode)));
    });

    test('isEmpty reflects the effects list only, never the mask', () {
      const maskOnly = EffectStack(<EditorEffect>[], stackMask: mask);
      expect(maskOnly.isEmpty, isTrue,
          reason: 'isEmpty gates the effects JSON key; folding the '
              'mask in would emit "effects": [] and break legacy bytes');
      expect(maskOnly.isNotEmpty, isFalse);
      expect(maskOnly.stackMask, equals(mask));
    });
  });

  group('EffectStack.stackMask — layer serialization', () {
    test('effects + stackMask round-trip through layer JSON', () {
      final layer = makeImage(
        effects: EffectStack(
          List<EditorEffect>.unmodifiable(
            <EditorEffect>[BrightnessEffect(amount: 20)],
          ),
          stackMask: mask,
        ),
      );

      final json = layer.toJson();
      expect(json['effects'], isNotNull);
      expect(json['stackMask'], isNotNull);

      final decoded = ImageLayer.fromJson(json);
      expect(decoded.effects, equals(layer.effects));
      expect(decoded.effects.stackMask, equals(mask));

      // Re-encode stability: encode → decode → encode is identical.
      expect(jsonEncode(decoded.toJson()), equals(jsonEncode(json)));
    });

    test('stackMask-only stack writes NO effects key (trap #1)', () {
      final layer = makeImage(
        effects: const EffectStack(<EditorEffect>[], stackMask: mask),
      );

      final json = layer.toJson();
      expect(json.containsKey('effects'), isFalse,
          reason: 'a stackMask-only stack must omit the effects key '
              'entirely — "effects": [] changes every legacy doc\'s bytes');
      expect(json['stackMask'], isNotNull);

      final decoded = ImageLayer.fromJson(json);
      expect(decoded.effects.isEmpty, isTrue);
      expect(decoded.effects.stackMask, equals(mask));
      expect(jsonEncode(decoded.toJson()), equals(jsonEncode(json)));
    });

    test('no stackMask writes no stackMask key', () {
      final layer = makeImage(
        effects: EffectStack(
          List<EditorEffect>.unmodifiable(
            <EditorEffect>[BrightnessEffect(amount: 20)],
          ),
        ),
      );

      final json = layer.toJson();
      expect(json.containsKey('stackMask'), isFalse);

      final decoded = ImageLayer.fromJson(json);
      expect(decoded.effects.stackMask, isNull);
      expect(jsonEncode(decoded.toJson()), equals(jsonEncode(json)));
    });

    test('empty stack stays byte-identical to pre-stackMask encoding', () {
      final layer = makeImage();
      final json = layer.toJson();
      expect(json.containsKey('effects'), isFalse);
      expect(json.containsKey('stackMask'), isFalse);
    });

    test('legacy adjustments lift preserves a decoded stackMask', () {
      // Hybrid shape: v3 stackMask alongside a leftover v2
      // `adjustments` map. Never produced by our writers, but decode
      // must not silently drop the mask on the lift path.
      final layer = makeImage();
      final json = layer.toJson();
      json['adjustments'] = <String, dynamic>{'brightness': 20.0};
      json['stackMask'] = mask.toJson();

      final decoded = ImageLayer.fromJson(json);
      expect(decoded.effects.effects, hasLength(1));
      expect(decoded.effects.effects.single, isA<BrightnessEffect>());
      expect(decoded.effects.stackMask, equals(mask));
    });
  });

  group('EffectStack.copyWith', () {
    test('preserves stackMask; replaces effects list', () {
      final stack = EffectStack(
        List<EditorEffect>.unmodifiable(
          <EditorEffect>[BrightnessEffect(amount: 20)],
        ),
        stackMask: mask,
      );
      final next = stack.copyWith(effects: const <EditorEffect>[]);
      expect(next.effects, isEmpty);
      expect(next.stackMask, equals(mask));
      expect(stack.copyWith().stackMask, equals(mask));
    });
  });

  group('writer schema version — stackMask promotes to v3 (trap #2)', () {
    // A stackMask-only layer writes the v3-only `stackMask` key. If
    // the writer stamped it v1/v2, an older reader would open the doc
    // without complaint and silently drop the mask on resave — the
    // loud version-range rejection exists precisely to prevent that.
    test('stackMask-only document stamps v3', () {
      final doc = EditorDocument.empty.addLayer(makeImage(
        effects: const EffectStack(<EditorEffect>[], stackMask: mask),
      ));
      final json = DocumentCodec.toJson(doc);
      expect(json['version'], 3,
          reason: 'the stackMask key is v3-only; stamping lower lets '
              'old readers silently drop the mask on resave');
    });

    test('effects + stackMask document stamps v3', () {
      final doc = EditorDocument.empty.addLayer(makeImage(
        effects: EffectStack(
          List<EditorEffect>.unmodifiable(
            <EditorEffect>[BrightnessEffect(amount: 20)],
          ),
          stackMask: mask,
        ),
      ));
      expect(DocumentCodec.toJson(doc)['version'], 3);
    });

    test('empty stack, no mask still stamps v1 (byte-identity guard)', () {
      final doc = EditorDocument.empty.addLayer(makeImage());
      expect(DocumentCodec.toJson(doc)['version'], 1,
          reason: 'mask promotion must not disturb the minimum-version '
              'writer for legacy documents');
    });
  });

  group('SetStackMaskCommand', () {
    ImageLayer applied(EditorDocument doc) =>
        doc.layerById('img-1')! as ImageLayer;

    test('sets the mask without touching the effects list', () {
      final doc = EditorDocument.empty.addLayer(makeImage(
        effects: EffectStack(
          List<EditorEffect>.unmodifiable(
            <EditorEffect>[BrightnessEffect(amount: 20)],
          ),
        ),
      ));
      final next =
          const SetStackMaskCommand(layerId: 'img-1', mask: mask).apply(doc);
      final layer = applied(next);
      expect(layer.effects.stackMask, equals(mask));
      expect(layer.effects.effects.single, isA<BrightnessEffect>());
    });

    test('clearing the last state canonicalises to the empty singleton', () {
      final doc = EditorDocument.empty.addLayer(makeImage(
        effects: const EffectStack(<EditorEffect>[], stackMask: mask),
      ));
      final next =
          const SetStackMaskCommand(layerId: 'img-1', mask: null).apply(doc);
      expect(identical(applied(next).effects, EffectStack.empty), isTrue);
    });

    test('same mask is a no-op (identical document)', () {
      final doc = EditorDocument.empty.addLayer(makeImage(
        effects: const EffectStack(<EditorEffect>[], stackMask: mask),
      ));
      final next =
          const SetStackMaskCommand(layerId: 'img-1', mask: mask).apply(doc);
      expect(identical(next, doc), isTrue);
    });

    test('undo/redo restores prior mask in both directions', () {
      var doc = EditorDocument.empty.addLayer(makeImage());
      final history = HistoryStack();

      doc = history.execute(
        doc,
        const SetStackMaskCommand(layerId: 'img-1', mask: mask),
      );
      expect(applied(doc).effects.stackMask, equals(mask));

      doc = history.undo(doc);
      expect(applied(doc).effects.stackMask, isNull);
      expect(identical(applied(doc).effects, EffectStack.empty), isTrue);

      doc = history.redo(doc);
      expect(applied(doc).effects.stackMask, equals(mask));
    });

    test('live stream merges to one undo entry; settle stays discrete', () {
      var doc = EditorDocument.empty.addLayer(makeImage());
      final history = HistoryStack();
      const a = RectMask(rect: Rect.fromLTWH(0, 0, 100, 100));
      const b = RectMask(rect: Rect.fromLTWH(0, 0, 150, 100));

      doc = history.execute(
        doc,
        const SetStackMaskCommand(layerId: 'img-1', mask: a, live: true),
      );
      doc = history.execute(
        doc,
        const SetStackMaskCommand(layerId: 'img-1', mask: b, live: true),
      );
      expect(applied(doc).effects.stackMask, equals(b));

      // One undo rewinds the whole live stream.
      doc = history.undo(doc);
      expect(applied(doc).effects.stackMask, isNull);
      expect(history.canUndo, isFalse,
          reason: 'both live ticks must have merged into one entry');
    });

    test('missing / non-image layer is a safe no-op', () {
      final doc = EditorDocument.empty;
      const cmd = SetStackMaskCommand(layerId: 'ghost', mask: mask);
      expect(identical(cmd.apply(doc), doc), isTrue);
      final inverse = cmd.invert(doc);
      expect(identical(inverse.apply(doc), doc), isTrue);
    });
  });

  group('command rebuilds preserve stackMask', () {
    // Every command that rebuilds an existing layer's effects list
    // must keep a set stackMask while the effects change still lands.
    ImageLayer layerWith(List<EditorEffect> effects) => makeImage(
          effects: EffectStack(
            List<EditorEffect>.unmodifiable(effects),
            stackMask: mask,
          ),
        );

    ImageLayer applied(EditorDocument doc) =>
        doc.layerById('img-1')! as ImageLayer;

    test('SetImageAdjustmentsCommand (adjust)', () {
      var doc = EditorDocument.empty
          .addLayer(layerWith(<EditorEffect>[BrightnessEffect(amount: 20)]));
      doc = const SetImageAdjustmentsCommand(layerId: 'img-1', contrast: 1.5)
          .apply(doc);
      final layer = applied(doc);
      expect(layer.adjustments.contrast, 1.5, reason: 'edit must land');
      expect(layer.effects.stackMask, equals(mask));
    });

    test('SetImageVignetteCommand (vignette)', () {
      var doc = EditorDocument.empty.addLayer(layerWith(const <EditorEffect>[]));
      doc = const SetImageVignetteCommand(layerId: 'img-1', intensity: 0.6)
          .apply(doc);
      final layer = applied(doc);
      expect(layer.effects.effects.single, isA<VignetteEffect>());
      expect(layer.effects.stackMask, equals(mask));
    });

    test('ReorderEffectCommand (reorder)', () {
      var doc = EditorDocument.empty.addLayer(layerWith(<EditorEffect>[
        BrightnessEffect(amount: 20),
        ContrastEffect(amount: 1.5),
      ]));
      doc = const ReorderEffectCommand(
        layerId: 'img-1',
        oldIndex: 0,
        newIndex: 1,
      ).apply(doc);
      final layer = applied(doc);
      expect(layer.effects.effects.first, isA<ContrastEffect>());
      expect(layer.effects.stackMask, equals(mask));
    });

    test('ToggleEffectEnabledCommand (toggle)', () {
      var doc = EditorDocument.empty
          .addLayer(layerWith(<EditorEffect>[BrightnessEffect(amount: 20)]));
      doc = const ToggleEffectEnabledCommand(layerId: 'img-1', index: 0)
          .apply(doc);
      final layer = applied(doc);
      expect(layer.effects.effects.single.enabled, isFalse);
      expect(layer.effects.stackMask, equals(mask));
    });

    test('DeleteEffectCommand (delete) — mask outlives the last effect', () {
      var doc = EditorDocument.empty
          .addLayer(layerWith(<EditorEffect>[BrightnessEffect(amount: 20)]));
      doc = const DeleteEffectCommand(layerId: 'img-1', index: 0).apply(doc);
      final layer = applied(doc);
      expect(layer.effects.isEmpty, isTrue);
      expect(layer.effects.stackMask, equals(mask),
          reason: 'the mask is user state independent of list emptiness');
    });

    test('DeleteEffectCommand.invert (insert) restores with mask intact', () {
      final before = EditorDocument.empty
          .addLayer(layerWith(<EditorEffect>[BrightnessEffect(amount: 20)]));
      const delete = DeleteEffectCommand(layerId: 'img-1', index: 0);
      final after = delete.apply(before);
      final restored = delete.invert(before).apply(after);
      final layer = restored.layerById('img-1')! as ImageLayer;
      expect(layer.effects.effects.single, isA<BrightnessEffect>());
      expect(layer.effects.stackMask, equals(mask));
    });
  });
}
