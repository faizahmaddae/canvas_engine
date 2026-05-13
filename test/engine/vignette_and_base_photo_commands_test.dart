import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/commands/image_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Targeted command tests for two paths the audit (May 2026) flagged
/// as undertested: vignette mutation on the effect stack, and the
/// base-photo marker on [EditorDocument]. Both are user-visible:
/// vignette is the photo editor's signature corner-darken effect,
/// and `basePhotoLayerId` is what makes Crop / Adjust target the
/// imported photo even after stickers and text land on top.
///
/// The contracts these tests are guarding:
/// 1. Commands are pure: same input doc -> same output doc, no
///    hidden state, no provider reads.
/// 2. `apply` is identity when the command would be a no-op
///    (returns the *same* instance, not a copy). This is what makes
///    the undo stack memory-efficient.
/// 3. `invert` always takes the document **before** apply and
///    restores it exactly.

void main() {
  group('SetBasePhotoCommand', () {
    EditorDocument blank() => EditorDocument(
          layers: const [],
          width: 1000,
          height: 1000,
        );

    test('apply sets the marker', () {
      final before = blank();
      expect(before.basePhotoLayerId, isNull);
      final after = const SetBasePhotoCommand('photo-1').apply(before);
      expect(after.basePhotoLayerId, 'photo-1');
    });

    test('apply is identity when target already matches', () {
      final doc = blank().copyWith(basePhotoLayerId: 'photo-1');
      final result = const SetBasePhotoCommand('photo-1').apply(doc);
      // Identity, not just equality — same instance means no rebuild
      // ripple, no spurious history entry, no needless GC.
      expect(identical(result, doc), isTrue);
    });

    test('invert restores prior marker (set -> clear)', () {
      final before = blank();
      const cmd = SetBasePhotoCommand('photo-1');
      final after = cmd.apply(before);
      final undo = cmd.invert(before).apply(after);
      expect(undo.basePhotoLayerId, isNull);
    });

    test('invert restores prior marker (replace one with another)', () {
      final before = blank().copyWith(basePhotoLayerId: 'photo-old');
      const cmd = SetBasePhotoCommand('photo-new');
      final after = cmd.apply(before);
      expect(after.basePhotoLayerId, 'photo-new');
      final undo = cmd.invert(before).apply(after);
      expect(undo.basePhotoLayerId, 'photo-old');
    });

    test('null clears the marker; invert restores it', () {
      final before = blank().copyWith(basePhotoLayerId: 'photo-1');
      const cmd = SetBasePhotoCommand(null);
      final after = cmd.apply(before);
      expect(after.basePhotoLayerId, isNull);
      final undo = cmd.invert(before).apply(after);
      expect(undo.basePhotoLayerId, 'photo-1');
    });
  });

  group('SetProjectKindCommand', () {
    EditorDocument blank({ProjectKind kind = ProjectKind.design}) =>
        EditorDocument(
          layers: const [],
          width: 1000,
          height: 1000,
          projectKind: kind,
        );

    test('apply switches design -> photo', () {
      final before = blank();
      expect(before.projectKind, ProjectKind.design);
      final after =
          const SetProjectKindCommand(ProjectKind.photo).apply(before);
      expect(after.projectKind, ProjectKind.photo);
    });

    test('apply is identity when kind already matches', () {
      // Identity (not just equality) is what the photo-import flow
      // relies on to avoid a no-op history entry when the user
      // re-imports into an already-photo project.
      final doc = blank(kind: ProjectKind.photo);
      final result =
          const SetProjectKindCommand(ProjectKind.photo).apply(doc);
      expect(identical(result, doc), isTrue);
    });

    test('invert restores prior kind', () {
      final before = blank();
      const cmd = SetProjectKindCommand(ProjectKind.photo);
      final after = cmd.apply(before);
      final undo = cmd.invert(before).apply(after);
      expect(undo.projectKind, ProjectKind.design);
    });

    test('label reflects target kind', () {
      // Surfaces in the undo menu — wrong copy here would mislead
      // the user about what undo is about to do.
      expect(
        const SetProjectKindCommand(ProjectKind.photo).label,
        'Photo project',
      );
      expect(
        const SetProjectKindCommand(ProjectKind.design).label,
        'Design project',
      );
    });
  });

  group('SetImageVignetteCommand', () {
    ImageLayer baseImage({EffectStack? effects}) => ImageLayer(
          id: 'img-1',
          transform: const LayerTransform(
            position: Offset.zero,
            size: Size(400, 400),
          ),
          source: const ImageSource.asset('p.png'),
          effects: effects ?? EffectStack.empty,
        );

    EditorDocument docWith(ImageLayer layer) => EditorDocument(
          layers: [layer],
          width: 1000,
          height: 1000,
        );

    test('non-image targets are ignored (apply is identity)', () {
      // A vignette command for a missing layer must be a pure no-op,
      // not a crash. The application layer can race here when a
      // delete completes mid-drag.
      final before = docWith(baseImage());
      final cmd = const SetImageVignetteCommand(
        layerId: 'no-such-layer',
        intensity: 0.5,
      );
      final result = cmd.apply(before);
      expect(identical(result, before), isTrue);
    });

    test('identity vignette (intensity 0) does not pollute the stack',
        () {
      // A drag-then-release at intensity 0 must round-trip the doc
      // unchanged. This is the contract the codec relies on to keep
      // existing files byte-identical after a no-op edit.
      final before = docWith(baseImage());
      const cmd = SetImageVignetteCommand(
        layerId: 'img-1',
        intensity: 0,
      );
      final result = cmd.apply(before);
      expect(identical(result, before), isTrue);
    });

    test('non-zero intensity adds a vignette effect to the stack', () {
      final before = docWith(baseImage());
      const cmd = SetImageVignetteCommand(
        layerId: 'img-1',
        intensity: 0.5,
        feather: 0.6,
      );
      final after = cmd.apply(before);
      final layer = after.layerById('img-1') as ImageLayer;
      expect(layer.effects.effects, hasLength(1));
      final v = layer.effects.effects.single as VignetteEffect;
      expect(v.intensity, 0.5);
      expect(v.feather, 0.6);
    });

    test('invert restores prior vignette state (add -> clear)', () {
      final before = docWith(baseImage());
      const cmd = SetImageVignetteCommand(
        layerId: 'img-1',
        intensity: 0.5,
      );
      final after = cmd.apply(before);
      final undo = cmd.invert(before).apply(after);
      // Undo of "add a vignette" must leave the stack empty, not
      // collapsed to an identity vignette entry.
      final layer = undo.layerById('img-1') as ImageLayer;
      expect(layer.effects.effects, isEmpty);
    });

    test('invert restores prior vignette knobs (modify existing)', () {
      final initial = baseImage(
        effects: EffectStack(const [
          VignetteEffect(intensity: 0.3, feather: 0.4),
        ]),
      );
      final before = docWith(initial);
      const cmd = SetImageVignetteCommand(
        layerId: 'img-1',
        intensity: 0.8,
      );
      final after = cmd.apply(before);
      final undo = cmd.invert(before).apply(after);
      final layer = undo.layerById('img-1') as ImageLayer;
      final v = layer.effects.effects.single as VignetteEffect;
      expect(v.intensity, 0.3);
      expect(v.feather, 0.4);
    });

    test('apply preserves non-vignette effects on the stack', () {
      // The command must address vignette positionally and never
      // touch peer effects. Otherwise undoing a vignette tweak would
      // also undo the user's brightness adjustment two minutes ago.
      const blur = VignetteEffect(intensity: 0.2, feather: 0.5);
      final initial = baseImage(
        effects: EffectStack(const [blur]),
      );
      final before = docWith(initial);
      const cmd = SetImageVignetteCommand(
        layerId: 'img-1',
        intensity: 0.7,
      );
      final after = cmd.apply(before);
      final layer = after.layerById('img-1') as ImageLayer;
      // Old vignette replaced (not duplicated); single effect on stack.
      expect(
        layer.effects.effects.whereType<VignetteEffect>().length,
        1,
      );
      expect(
        (layer.effects.effects.single as VignetteEffect).intensity,
        0.7,
      );
    });

    test('live drags merge into the previous live entry', () {
      // History merging is what keeps a slider drag from blowing up
      // the undo stack with one entry per pointer-move frame.
      const a = SetImageVignetteCommand(
        layerId: 'img-1',
        intensity: 0.3,
        live: true,
      );
      const b = SetImageVignetteCommand(
        layerId: 'img-1',
        intensity: 0.5,
        live: true,
      );
      expect(b.mergeWith(a), same(b));
    });

    test('non-live commands never merge', () {
      const a = SetImageVignetteCommand(
        layerId: 'img-1',
        intensity: 0.3,
      );
      const b = SetImageVignetteCommand(
        layerId: 'img-1',
        intensity: 0.5,
      );
      expect(b.mergeWith(a), isNull);
    });

    test('different layerIds do not merge', () {
      const a = SetImageVignetteCommand(
        layerId: 'img-A',
        intensity: 0.3,
        live: true,
      );
      const b = SetImageVignetteCommand(
        layerId: 'img-B',
        intensity: 0.5,
        live: true,
      );
      expect(b.mergeWith(a), isNull);
    });

    test('different field-sets do not merge', () {
      // Critical: a feather-only drag must not silently collapse an
      // in-flight intensity-only drag, otherwise undo loses one of
      // the two user-visible mutations.
      const intensityOnly = SetImageVignetteCommand(
        layerId: 'img-1',
        intensity: 0.3,
        live: true,
      );
      const featherOnly = SetImageVignetteCommand(
        layerId: 'img-1',
        feather: 0.7,
        live: true,
      );
      expect(featherOnly.mergeWith(intensityOnly), isNull);
    });
  });
}
