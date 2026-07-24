// Phase 3.2b — MaskEditController: draft-first session semantics
// (docs/mask-edit-mode-design-2026-07.md §2, §7).

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/live_overlay_controller.dart';
import 'package:canvas_engine/features/editor/application/mask_edit_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/image_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_mask.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _mask = RectMask(rect: Rect.fromLTWH(10, 10, 80, 60), feather: 8);

ImageLayer _image({LayerMask? stackMask}) => ImageLayer(
  id: 'img',
  transform: const LayerTransform(position: Offset.zero, size: Size(200, 100)),
  source: const ImageSource.asset('stub.png'),
  effects: EffectStack(
    List<EditorEffect>.unmodifiable(<EditorEffect>[
      BrightnessEffect(amount: 20),
    ]),
    stackMask: stackMask,
  ),
);

ProviderContainer _container({LayerMask? stackMask}) {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  c
      .read(documentControllerProvider.notifier)
      .newDocument(width: 400, height: 300);
  c
      .read(documentControllerProvider.notifier)
      .execute(AddLayerCommand(_image(stackMask: stackMask)));
  // Mount the controller so its document listener is registered.
  c.read(maskEditControllerProvider);
  return c;
}

LayerMask? _docMask(ProviderContainer c) =>
    (c.read(documentControllerProvider).layerById('img')! as ImageLayer)
        .effects
        .stackMask;

void main() {
  group('pure drag math', () {
    const size = Size(200, 100);

    test('translate clamps to the layer bounds', () {
      final moved = MaskEditController.translate(
        _mask,
        const Offset(500, -500),
        size,
      );
      final b = MaskEditController.boundsOf(moved);
      expect(b.right, size.width);
      expect(b.top, 0);
      expect(
        b.size,
        MaskEditController.boundsOf(_mask).size,
        reason: 'translate never resizes',
      );
    });

    test('resize anchors the opposite corner and honours the minimum', () {
      final shrunk = MaskEditController.resize(
        _mask,
        MaskEditHandle.bottomRight,
        const Offset(-500, -500),
        size,
      );
      final b = MaskEditController.boundsOf(shrunk);
      expect(
        b.topLeft,
        MaskEditController.boundsOf(_mask).topLeft,
        reason: 'opposite corner is the anchor',
      );
      expect(b.width, MaskEditController.minMaskSide);
      expect(b.height, MaskEditController.minMaskSide);
    });

    test('edge resize moves only its axis, clamped to the layer', () {
      final wider = MaskEditController.resize(
        _mask,
        MaskEditHandle.right,
        const Offset(500, 33),
        size,
      );
      final b = MaskEditController.boundsOf(wider);
      expect(b.right, size.width);
      expect(b.top, _mask.rect.top);
      expect(b.bottom, _mask.rect.bottom);
    });

    test('preserves feather/invert through geometry edits', () {
      const inverted = RectMask(
        rect: Rect.fromLTWH(10, 10, 80, 60),
        feather: 8,
        inverted: true,
      );
      final moved = MaskEditController.translate(
        inverted,
        const Offset(5, 5),
        size,
      );
      expect(moved.feather, 8);
      expect(moved.inverted, isTrue);
    });
  });

  group('session lifecycle', () {
    test('open seeds the draft from the existing mask, no staging', () {
      final c = _container(stackMask: _mask);
      c.read(maskEditControllerProvider.notifier).open('img');
      final s = c.read(maskEditControllerProvider);
      expect(s.active, isTrue);
      expect(s.draft, _mask);
      expect(s.entryMask, _mask);
      expect(
        c.read(liveOverlayProvider).replacements,
        isEmpty,
        reason: 'existing mask already renders from the document',
      );
    });

    test('open on a maskless layer seeds the centre default and stages '
        'a preview', () {
      final c = _container();
      c.read(maskEditControllerProvider.notifier).open('img');
      final s = c.read(maskEditControllerProvider);
      expect(s.draft, isA<RectMask>());
      expect(s.entryMask, isNull);
      expect(
        c.read(liveOverlayProvider).replacements,
        isNotEmpty,
        reason: 'a fresh default mask must be visible immediately',
      );
    });

    test('updateDraft is chrome-only; endGesture stages the preview', () {
      final c = _container(stackMask: _mask);
      final ctl = c.read(maskEditControllerProvider.notifier);
      ctl.open('img');
      final moved = _mask.copyWith(rect: const Rect.fromLTWH(20, 10, 80, 60));

      ctl.updateDraft(moved);
      expect(
        c.read(liveOverlayProvider).replacements,
        isEmpty,
        reason: 'per-tick staging would raster per tick (design §4)',
      );

      ctl.endGesture(moved);
      final staged =
          c.read(liveOverlayProvider).replacements['img'] as ImageLayer;
      expect(staged.effects.stackMask, moved);
      expect(_docMask(c), _mask, reason: 'document untouched until Done');
    });

    test('commit lands ONE undo entry; undo restores the entry mask', () {
      final c = _container(stackMask: _mask);
      final ctl = c.read(maskEditControllerProvider.notifier);
      ctl.open('img');
      final moved = _mask.copyWith(rect: const Rect.fromLTWH(40, 20, 80, 60));
      ctl.endGesture(moved);
      ctl.commit();

      expect(c.read(maskEditControllerProvider).active, isFalse);
      expect(c.read(liveOverlayProvider).replacements, isEmpty);
      expect(_docMask(c), moved);

      c.read(documentControllerProvider.notifier).undo();
      expect(_docMask(c), _mask, reason: 'the whole session is one undo entry');
    });

    test('no-change commit pushes no history entry', () {
      final c = _container(stackMask: _mask);
      final ctl = c.read(maskEditControllerProvider.notifier);
      ctl.open('img');
      ctl.commit();
      // Only the AddLayer entry exists: one undo removes the layer.
      c.read(documentControllerProvider.notifier).undo();
      expect(
        c.read(documentControllerProvider).layerById('img'),
        isNull,
        reason: 'a no-op Done must not add a history entry above AddLayer',
      );
    });

    test('cancel discards the draft with zero commands', () {
      final c = _container(stackMask: _mask);
      final ctl = c.read(maskEditControllerProvider.notifier);
      ctl.open('img');
      ctl.endGesture(_mask.copyWith(rect: const Rect.fromLTWH(40, 20, 80, 60)));
      ctl.cancel(restoreSelection: true);

      expect(c.read(maskEditControllerProvider).active, isFalse);
      expect(_docMask(c), _mask);
      expect(c.read(liveOverlayProvider).replacements, isEmpty);
    });

    test('external stack-mask change cancels the session', () {
      final c = _container(stackMask: _mask);
      final ctl = c.read(maskEditControllerProvider.notifier);
      ctl.open('img');
      // Someone else (undo from an unsuppressed surface, another
      // controller) rewrites the mask under the mode.
      c
          .read(documentControllerProvider.notifier)
          .execute(const SetStackMaskCommand(layerId: 'img', mask: null));
      expect(c.read(maskEditControllerProvider).active, isFalse);
    });

    test('layer deletion cancels the session', () {
      final c = _container(stackMask: _mask);
      c.read(maskEditControllerProvider.notifier).open('img');
      c
          .read(documentControllerProvider.notifier)
          .execute(const RemoveLayerCommand('img'));
      expect(c.read(maskEditControllerProvider).active, isFalse);
    });

    test('commit restores the prior selection; seam cancel leaves '
        'selection alone', () {
      final c = _container(stackMask: _mask);
      final ctl = c.read(maskEditControllerProvider.notifier);
      c.read(selectionControllerProvider.notifier).select('img');

      ctl.open('img', priorSelectionId: 'img');
      c.read(selectionControllerProvider.notifier).clear();
      ctl.commit();
      expect(
        c.read(selectionControllerProvider).selectedIds,
        {'img'},
        reason: 'Done returns the user to the pre-mode context',
      );

      // Seam-driven cancel must not fight the seam's selection state.
      ctl.open('img', priorSelectionId: 'img');
      c.read(selectionControllerProvider.notifier).select('other');
      ctl.cancel(); // default: no restore
      expect(c.read(selectionControllerProvider).selectedIds, {'other'});
    });
  });
}
