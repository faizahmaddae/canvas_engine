import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/commands/image_commands.dart';
import '../engine/core/editor_document.dart';
import '../engine/core/layer_mask.dart';
import '../engine/modules/image/image_layer.dart';
import 'document_controller.dart';
import 'live_overlay_controller.dart';
import 'selection_controller.dart';

/// Handles the mask-edit overlay exposes. Body moves the region;
/// corners/edges resize it anchored on the opposite corner/edge.
enum MaskEditHandle {
  body,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  left,
  top,
  right,
  bottom,
}

/// Draft-first session for on-canvas stack-mask editing
/// (docs/mask-edit-mode-design-2026-07.md §2). Gestures mutate only
/// [draft]; the document is untouched until [MaskEditController.commit]
/// dispatches ONE non-live [SetStackMaskCommand]. Cancel restores the
/// entry state with zero commands — the crop-session contract.
@immutable
class MaskEditSession {
  const MaskEditSession({
    this.active = false,
    this.layerId = '',
    this.draft,
    this.entryMask,
    this.priorSelectionId,
  });

  final bool active;
  final String layerId;

  /// The in-flight mask, layer-local like the model. Null only when
  /// inactive.
  final LayerMask? draft;

  /// The layer's stack mask at open — Cancel's restore target and
  /// the no-op guard for Done.
  final LayerMask? entryMask;

  /// Selection to replay on exit (null clears), captured at open —
  /// same rationale as CropSession.priorSelectionId.
  final String? priorSelectionId;
}

class MaskEditController extends Notifier<MaskEditSession> {
  @override
  MaskEditSession build() {
    // Cancel when the target layer is deleted, stops being an image,
    // or its stack mask changes from outside the session (undo fired
    // from a surface this mode doesn't suppress, another controller,
    // …). Sound only because commit() clears session state BEFORE
    // executing — the listener fires synchronously on our own commit
    // and must observe an already-inactive session (the recursion
    // trap interaction_controller.dart documents).
    ref.listen<EditorDocument>(documentControllerProvider, (_, doc) {
      final s = state;
      if (!s.active) return;
      final layer = doc.layerById(s.layerId);
      if (layer is! ImageLayer || layer.effects.stackMask != s.entryMask) {
        cancel();
      }
    });
    return const MaskEditSession();
  }

  ImageLayer? get _layer {
    final s = state;
    final layer = ref.read(documentControllerProvider).layerById(s.layerId);
    return layer is ImageLayer ? layer : null;
  }

  /// Enter the mode for [layerId]. Seeds the draft from the layer's
  /// current stack mask, or [defaultDraft] when none is set (a new
  /// mask needs *something* to grab).
  void open(String layerId, {String? priorSelectionId}) {
    final layer = ref.read(documentControllerProvider).layerById(layerId);
    if (layer is! ImageLayer) return;
    final entry = layer.effects.stackMask;
    final draft = entry ?? defaultDraft(layer.transform.size);
    state = MaskEditSession(
      active: true,
      layerId: layerId,
      draft: draft,
      entryMask: entry,
      priorSelectionId: priorSelectionId,
    );
    // A fresh default mask isn't in the document yet — stage it so
    // the user immediately sees where the adjustment will land.
    if (entry == null) _stagePreview();
  }

  /// Update the draft during a drag. Chrome-only — the engine
  /// preview is deliberately NOT re-staged per tick (a full-res
  /// alpha raster per tick floods the cache and flashes the effect
  /// to base; design §4). Call [endGesture] on DragPhase.end.
  void updateDraft(LayerMask draft) {
    final s = state;
    if (!s.active) return;
    state = MaskEditSession(
      active: true,
      layerId: s.layerId,
      draft: draft,
      entryMask: s.entryMask,
      priorSelectionId: s.priorSelectionId,
    );
  }

  /// Gesture finished: land the draft and refresh the live preview
  /// (one raster per gesture).
  void endGesture(LayerMask draft) {
    updateDraft(draft);
    _stagePreview();
  }

  /// Discrete edits from the bottom strip — preview refreshes
  /// immediately.
  void setFeather(double feather) {
    final d = state.draft;
    if (d == null) return;
    final clamped = feather.clamp(0.0, LayerMask.maxFeatherPx);
    endGesture(switch (d) {
      RectMask() => d.copyWith(feather: clamped),
      EllipseMask() => d.copyWith(feather: clamped),
      PathMask() => d, // path editing is out of scope (design §8)
    });
  }

  void toggleInvert() {
    final d = state.draft;
    if (d == null) return;
    endGesture(switch (d) {
      RectMask() => d.copyWith(inverted: !d.inverted),
      EllipseMask() => d.copyWith(inverted: !d.inverted),
      PathMask() => d,
    });
  }

  /// Swap rect ↔ ellipse keeping bounds/feather/invert (design §7).
  void setShape({required bool ellipse}) {
    final d = state.draft;
    if (d == null) return;
    if (ellipse && d is RectMask) {
      endGesture(
        EllipseMask(bounds: d.rect, inverted: d.inverted, feather: d.feather),
      );
    } else if (!ellipse && d is EllipseMask) {
      endGesture(
        RectMask(rect: d.bounds, inverted: d.inverted, feather: d.feather),
      );
    }
  }

  /// Commit the draft as ONE undo entry and leave the mode. No-op
  /// close (no history entry) when the draft equals the entry mask.
  void commit() {
    final s = state;
    if (!s.active) return;
    final draft = s.draft;
    // Clear state BEFORE execute — see the listener in [build].
    _reset(s, restoreSelection: true);
    if (draft != null && draft != s.entryMask) {
      ref
          .read(documentControllerProvider.notifier)
          .execute(SetStackMaskCommand(layerId: s.layerId, mask: draft));
    }
  }

  /// Leave the mode discarding the draft. Idempotent — safe to call
  /// from every dismiss seam.
  ///
  /// [restoreSelection] must be true ONLY for the mode's own exit
  /// affordances (Cancel button, back press): those return the user
  /// to the pre-mode toolbar context. Seam-driven cancels (empty-tap
  /// dismiss, selection change, project reset) MUST leave selection
  /// alone — the seam is already managing it, and re-selecting the
  /// prior layer here would fight the user's new selection or
  /// resurrect one the dismiss just cleared.
  void cancel({bool restoreSelection = false}) {
    final s = state;
    if (!s.active) return;
    _reset(s, restoreSelection: restoreSelection);
  }

  void _reset(MaskEditSession s, {required bool restoreSelection}) {
    state = const MaskEditSession();
    ref.read(liveOverlayProvider.notifier).clear();
    if (!restoreSelection) return;
    final prior = s.priorSelectionId;
    final selection = ref.read(selectionControllerProvider.notifier);
    if (prior != null) {
      selection.select(prior);
    } else {
      selection.clear();
    }
  }

  void _stagePreview() {
    final s = state;
    final draft = s.draft;
    final layer = _layer;
    if (!s.active || draft == null || layer == null) return;
    ref
        .read(liveOverlayProvider.notifier)
        .replaceLayer(
          layer.copyAll(effects: layer.effects.withStackMask(draft)),
        );
  }

  // ─── pure drag math (unit-tested without widgets) ────────────────

  /// Default draft for a layer with no mask yet: the centre preset
  /// (matches the Effects panel's Center chip so entering the mode
  /// from a fresh layer looks identical to tapping Center).
  static LayerMask defaultDraft(Size layerSize) {
    final feather = (layerSize.shortestSide * 0.15).clamp(
      0.0,
      LayerMask.maxFeatherPx,
    );
    return RectMask(
      rect: Rect.fromLTWH(
        layerSize.width * 0.15,
        layerSize.height * 0.15,
        layerSize.width * 0.7,
        layerSize.height * 0.7,
      ),
      feather: feather,
    );
  }

  /// Geometry bounds shared by rect and ellipse drafts.
  static Rect boundsOf(LayerMask mask) => switch (mask) {
    RectMask(:final rect) => rect,
    EllipseMask(:final bounds) => bounds,
    PathMask() => Rect.zero,
  };

  static LayerMask _withBounds(LayerMask mask, Rect bounds) => switch (mask) {
    RectMask() => mask.copyWith(rect: bounds),
    EllipseMask() => mask.copyWith(bounds: bounds),
    PathMask() => mask,
  };

  /// Smallest editable mask side, layer-local px. Below this the
  /// handles overlap and the region stops being grabbable.
  static const double minMaskSide = 16.0;

  /// Move the whole region by [delta] (layer-local), clamped so the
  /// region stays inside the layer.
  static LayerMask translate(LayerMask mask, Offset delta, Size layerSize) {
    final b = boundsOf(mask);
    final dx = delta.dx.clamp(
      -b.left,
      (layerSize.width - b.right).clamp(0.0, double.infinity),
    );
    final dy = delta.dy.clamp(
      -b.top,
      (layerSize.height - b.bottom).clamp(0.0, double.infinity),
    );
    return _withBounds(mask, b.shift(Offset(dx, dy)));
  }

  /// Resize by dragging [handle] by [delta] (layer-local), anchored
  /// on the opposite corner/edge, clamped to [minMaskSide] and the
  /// layer bounds.
  static LayerMask resize(
    LayerMask mask,
    MaskEditHandle handle,
    Offset delta,
    Size layerSize,
  ) {
    final b = boundsOf(mask);
    var left = b.left, top = b.top, right = b.right, bottom = b.bottom;
    final movesLeft =
        handle == MaskEditHandle.topLeft ||
        handle == MaskEditHandle.bottomLeft ||
        handle == MaskEditHandle.left;
    final movesRight =
        handle == MaskEditHandle.topRight ||
        handle == MaskEditHandle.bottomRight ||
        handle == MaskEditHandle.right;
    final movesTop =
        handle == MaskEditHandle.topLeft ||
        handle == MaskEditHandle.topRight ||
        handle == MaskEditHandle.top;
    final movesBottom =
        handle == MaskEditHandle.bottomLeft ||
        handle == MaskEditHandle.bottomRight ||
        handle == MaskEditHandle.bottom;
    if (movesLeft) {
      left = (left + delta.dx).clamp(0.0, right - minMaskSide);
    }
    if (movesRight) {
      right = (right + delta.dx).clamp(left + minMaskSide, layerSize.width);
    }
    if (movesTop) {
      top = (top + delta.dy).clamp(0.0, bottom - minMaskSide);
    }
    if (movesBottom) {
      bottom = (bottom + delta.dy).clamp(top + minMaskSide, layerSize.height);
    }
    return _withBounds(mask, Rect.fromLTRB(left, top, right, bottom));
  }
}

final maskEditControllerProvider =
    NotifierProvider<MaskEditController, MaskEditSession>(
      MaskEditController.new,
    );
