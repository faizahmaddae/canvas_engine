import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/document_controller.dart';
import '../../application/selection_controller.dart';
import '../../canvas/application/canvas_commands.dart';
import '../../engine/commands/editor_command.dart';
import '../../engine/commands/image_commands.dart';
import '../../engine/commands/transform_commands.dart';
import '../../engine/core/editor_document.dart';
import '../../engine/modules/image/image_layer.dart';

/// Centralised crop session — single source of truth for the
/// editor's Crop Mode regardless of where it was launched from
/// (main toolbar, image-tool toolbar, etc.).
///
/// State is **draft-first**: gestures and aspect chips mutate
/// [draftCrop] only. The [SetImageCropCommand] is dispatched once
/// on [commit] so the document's undo stack gets one entry per
/// crop session, and the user can [cancel] at any point with no
/// document change.
@immutable
class CropSession {
  const CropSession({
    this.active = false,
    this.layerId,
    this.draftCrop = ImageLayer.fullCrop,
    this.aspectRatio,
    this.originalAspect,
    this.priorSelectionId,
  });

  /// Whether crop mode is currently shown.
  final bool active;

  /// Target [ImageLayer.id]. `null` whenever [active] is false.
  final String? layerId;

  /// Live crop rect (0..1, layer-local). Updated on every drag.
  final Rect draftCrop;

  /// Target aspect ratio (width / height). `null` = free.
  final double? aspectRatio;

  /// Layer-local aspect (width / height) at the moment crop opened.
  ///
  /// This is the aspect of the **current layer box** — i.e. the
  /// pixel area the user actually sees right now. After a previous
  /// crop commit it equals the cropped pixel aspect, not the source
  /// image's original natural aspect. The "Original" preset uses
  /// this so it always means "as the image is right now" — which
  /// matches Instagram / Canva behaviour and avoids surprising the
  /// user with re-introduced pixels they thought they discarded.
  final double? originalAspect;

  /// Selection that was active **before** Crop opened, captured so
  /// the editor can restore it on commit/cancel.
  ///
  /// This is what makes Crop feel like a discrete modal operation:
  /// a user who opens Crop from the **main toolbar** (no selection,
  /// or some unrelated layer selected) returns to that exact same
  /// state — the image-mode sub-toolbar does NOT appear just
  /// because we had to auto-select an image to know what to crop.
  /// Conversely, a user who deliberately tapped on the image first
  /// keeps it selected after Done.
  final String? priorSelectionId;

  bool get isFullCrop => _isFull(draftCrop);

  CropSession copyWith({
    bool? active,
    Object? layerId = _sentinel,
    Rect? draftCrop,
    Object? aspectRatio = _sentinel,
    Object? originalAspect = _sentinel,
    Object? priorSelectionId = _sentinel,
  }) {
    return CropSession(
      active: active ?? this.active,
      layerId: identical(layerId, _sentinel) ? this.layerId : layerId as String?,
      draftCrop: draftCrop ?? this.draftCrop,
      aspectRatio: identical(aspectRatio, _sentinel)
          ? this.aspectRatio
          : aspectRatio as double?,
      originalAspect: identical(originalAspect, _sentinel)
          ? this.originalAspect
          : originalAspect as double?,
      priorSelectionId: identical(priorSelectionId, _sentinel)
          ? this.priorSelectionId
          : priorSelectionId as String?,
    );
  }
}

const Object _sentinel = Object();

bool _isFull(Rect r) =>
    (r.left).abs() < 1e-6 &&
    (r.top).abs() < 1e-6 &&
    (1 - r.right).abs() < 1e-6 &&
    (1 - r.bottom).abs() < 1e-6;

/// Centralised crop controller. Mutates [CropSession] only; never
/// touches the document until [commit] is called.
class CropController extends Notifier<CropSession> {
  /// Smallest allowed crop side, in normalised units. Matches the
  /// previous overlay's minimum so downstream sanitisation in
  /// [SetImageCropCommand] never has to clamp further.
  static const double minNorm = 0.05;

  @override
  CropSession build() => const CropSession();

  /// Open crop mode for [layerId]. Reads the current [ImageLayer]
  /// state for the initial draft so cancelling really is a no-op.
  ///
  /// [priorSelectionId] is the selection id that was active right
  /// before the editor decided to open crop (snapshotted by the
  /// caller **before** any auto-selection it had to perform to
  /// resolve a target). On Done/Cancel this is restored so the
  /// user lands back in the toolbar context they came from — the
  /// main toolbar in particular, instead of the image sub-tools.
  void openCrop(String layerId, {String? priorSelectionId}) {
    final doc = ref.read(documentControllerProvider);
    final layer = doc.layerById(layerId);
    if (layer is! ImageLayer) {
      state = const CropSession();
      return;
    }
    state = CropSession(
      active: true,
      layerId: layerId,
      draftCrop: layer.cropRect,
      aspectRatio: null,
      originalAspect: layer.transform.size.height <= 0
          ? null
          : layer.transform.size.width / layer.transform.size.height,
      priorSelectionId: priorSelectionId,
    );
  }

  /// Close crop mode without committing.
  void cancelCrop() {
    final prior = state.priorSelectionId;
    state = const CropSession();
    _restoreSelection(prior);
  }

  /// Restore the selection captured at [openCrop]. Null-prior
  /// means "no selection" (e.g. opened from the main toolbar with
  /// nothing selected) — clear instead of leaving the auto-selected
  /// image lit up, which would otherwise pop up the image sub-tools.
  void _restoreSelection(String? priorSelectionId) {
    final sel = ref.read(selectionControllerProvider.notifier);
    if (priorSelectionId == null) {
      sel.clear();
    } else {
      sel.select(priorSelectionId);
    }
  }

  /// Reset the draft to the full image. Does NOT commit; the user
  /// still has to tap Done (or hit Cancel to back out).
  void resetCrop() {
    if (!state.active) return;
    state = state.copyWith(
      draftCrop: ImageLayer.fullCrop,
      aspectRatio: null,
    );
  }

  /// Update the draft from a gesture. Rect is clamped to [0..1]
  /// with min side ≥ [minNorm].
  void updateDraft(Rect r) {
    if (!state.active) return;
    state = state.copyWith(draftCrop: sanitise(r));
  }

  /// Apply an aspect ratio preset.
  ///
  /// Presets are **deterministic and idempotent**: the rect is
  /// always computed against the **full image** ([ImageLayer.fullCrop])
  /// — never against the current draft — so:
  ///
  ///   * Tapping the same preset twice produces the exact same rect.
  ///   * Cycling between presets never accumulates shrink.
  ///   * Switching from a manual crop to a preset jumps to the
  ///     deterministic centred preset (matches Instagram / Canva).
  ///
  /// [aspectRatio] is interpreted in **image-pixel space** (w/h of
  /// the source image). The math converts it into normalised space
  /// using the layer's natural aspect so e.g. "1:1" really is a
  /// square in image pixels, not a square in the unit box.
  ///
  /// Pass [aspectRatio] `null` for **Free** — keeps the current
  /// [draftCrop] untouched and only clears the lock so the user can
  /// drag handles freely.
  void setAspectRatio(double? aspectRatio) {
    if (!state.active) return;
    if (aspectRatio == null) {
      state = state.copyWith(aspectRatio: null);
      return;
    }
    final layerAspect = state.originalAspect ?? 1.0;
    final next = _fitAspect(
      bounds: ImageLayer.fullCrop,
      aspect: aspectRatio,
      layerAspect: layerAspect,
    );
    state = state.copyWith(draftCrop: next, aspectRatio: aspectRatio);
  }

  /// Convenience: reset to full image AND lock to the source image's
  /// natural aspect (the "Original" preset). Equivalent to tapping
  /// the Original chip — included for callers that want a typed
  /// entry-point.
  void selectOriginal() {
    if (!state.active) return;
    final aspect = state.originalAspect;
    state = state.copyWith(
      draftCrop: ImageLayer.fullCrop,
      aspectRatio: aspect,
    );
  }

  /// Commit the draft.
  ///
  /// **Aspect-preserving commit.** The naive approach -- writing
  /// only `cropRect` -- leaves the layer's bounding box at its
  /// pre-crop dimensions, so the renderer ends up scaling the
  /// cropped sub-rect anisotropically (`1/cw`, `1/ch`) to fill the
  /// box. That visibly stretches a 1:1 crop on a 3:4 layer by
  /// 33% vertically. To prevent any deformation we ALSO shrink the
  /// layer's bounding box to the cropped pixel rectangle and reset
  /// `cropRect` back to the full window. The result is identical
  /// pixels with a correctly-shaped frame.
  ///
  /// **Photo project commit.** When `projectKind == photo` the
  /// canvas IS the photo, so we additionally resize the canvas to
  /// match the new layer size (and reposition the layer to the
  /// origin). This is what stops the white-canvas band from
  /// appearing after a crop.
  ///
  /// All sub-commands are bundled into one [CompositeCommand] so
  /// the entire crop is a single undo step.
  void commitCrop() {
    final s = state;
    if (!s.active || s.layerId == null) return;
    final doc = ref.read(documentControllerProvider);
    final layer = doc.layerById(s.layerId!);
    if (layer is! ImageLayer) {
      final prior = s.priorSelectionId;
      state = const CropSession();
      _restoreSelection(prior);
      return;
    }
    final draft = sanitise(s.draftCrop);
    // No-op crop (Done with no change): close the session without
    // touching history. Two cases:
    //   * Fresh layer + fullCrop draft → nothing to do.
    //   * Re-opened crop on an already-cropped layer where the user
    //     pressed Done without dragging → draft equals fullCrop
    //     because openCrop() seeds it from layer.cropRect (which is
    //     reset to fullCrop after every commit). Same outcome:
    //     short-circuit so we don't push a redundant history entry.
    if (_isFull(draft) && layer.cropRect == ImageLayer.fullCrop) {
      final prior = s.priorSelectionId;
      state = const CropSession();
      _restoreSelection(prior);
      return;
    }

    final commands = <EditorCommand>[];

    // ----- Reshape the layer to the cropped pixel rectangle. -----
    // The layer currently displays its `cropRect` sub-region
    // stretched into `transform.size`. The new layer size = the
    // physical pixel rectangle of the crop; we then write back a
    // full crop rect so the renderer's scale becomes (1, 1).
    final oldSize = layer.transform.size;
    final oldPos = layer.transform.position;
    // The crop draft is normalised against the LAYER's local box
    // (which is what the user dragged the frame inside), so
    // multiplying by oldSize gives the new size in canvas pixels
    // directly -- no conversion through the source image's pixel
    // grid is needed here.
    final newSize = Size(
      math.max(1.0, oldSize.width * draft.width),
      math.max(1.0, oldSize.height * draft.height),
    );
    // Keep the cropped region anchored where it visually appeared
    // in design-mode commits. In photo-mode we instead snap the
    // layer to (0, 0) and resize the canvas around it -- see
    // below.
    final newPos = Offset(
      oldPos.dx + oldSize.width * draft.left,
      oldPos.dy + oldSize.height * draft.top,
    );

    if (doc.projectKind == ProjectKind.photo) {
      // Photo project: the photo IS the project. Snap the layer to
      // the canvas origin and reshape the canvas to match. No
      // white gaps possible.
      commands.add(SetLayerTransformCommand(
        layerId: layer.id,
        transform: layer.transform.copyWith(
          position: Offset.zero,
          size: newSize,
        ),
      ));
      commands.add(SetCanvasSizeCommand(
        width: newSize.width,
        height: newSize.height,
      ));
    } else {
      // Design project: leave the canvas alone, just shrink the
      // layer in place.
      commands.add(SetLayerTransformCommand(
        layerId: layer.id,
        transform: layer.transform.copyWith(
          position: newPos,
          size: newSize,
        ),
      ));
    }

    // Reset cropRect to full so the renderer no longer scales the
    // image anisotropically. Pixels are now physically the right
    // shape because the layer box itself is.
    commands.add(SetImageCropCommand(
      layerId: layer.id,
      cropRect: ImageLayer.fullCrop,
    ));

    ref.read(documentControllerProvider.notifier).execute(
          CompositeCommand(commands, labelOverride: 'Crop'),
        );
    final prior = s.priorSelectionId;
    state = const CropSession();
    _restoreSelection(prior);
  }

  // --------------------------------------------------------------
  // Pure helpers (also used by tests).
  // --------------------------------------------------------------

  /// Clamp [r] to [0..1] and enforce [minNorm] on each side.
  /// Public so [CropModeOverlay]'s pure resize helpers and unit
  /// tests can reuse the same clamp logic.
  static Rect sanitise(Rect r) {
    double l = r.left.clamp(0.0, 1.0);
    double t = r.top.clamp(0.0, 1.0);
    double rt = r.right.clamp(0.0, 1.0);
    double b = r.bottom.clamp(0.0, 1.0);
    if (rt - l < minNorm) rt = math.min(1.0, l + minNorm);
    if (b - t < minNorm) b = math.min(1.0, t + minNorm);
    if (rt - l < minNorm) l = math.max(0.0, rt - minNorm);
    if (b - t < minNorm) t = math.max(0.0, b - minNorm);
    return Rect.fromLTRB(l, t, rt, b);
  }

  /// Largest rect of [aspect] (= image-pixel w/h) that fits inside
  /// [bounds] (normalised 0..1), centred on [bounds.center].
  ///
  /// The aspect is converted from image-pixel space to normalised
  /// space using `aspectNorm = aspect / layerAspect`. This is what
  /// makes "1:1" a real square on a wide layer instead of a
  /// stretched rectangle.
  ///
  /// Public so the unit tests and the overlay's handle math can
  /// reuse the exact same computation.
  static Rect fitAspect({
    required Rect bounds,
    required double aspect,
    required double layerAspect,
  }) {
    if (bounds.width <= 0 ||
        bounds.height <= 0 ||
        aspect <= 0 ||
        layerAspect <= 0) {
      return bounds;
    }
    final aspectNorm = aspect / layerAspect;
    final boundsAspect = bounds.width / bounds.height;
    double w, h;
    if (aspectNorm >= boundsAspect) {
      w = bounds.width;
      h = w / aspectNorm;
    } else {
      h = bounds.height;
      w = h * aspectNorm;
    }
    return sanitise(
      Rect.fromCenter(center: bounds.center, width: w, height: h),
    );
  }

  // Internal alias kept for the controller's own call-sites.
  static Rect _fitAspect({
    required Rect bounds,
    required double aspect,
    required double layerAspect,
  }) =>
      fitAspect(bounds: bounds, aspect: aspect, layerAspect: layerAspect);

  /// Translate [r] by ([dx], [dy]) in normalised units, clamping the
  /// result so the rect stays fully inside `[0..1]`.
  ///
  /// Pure helper shared between the overlay's body-drag handler and
  /// unit tests so both branches use the identical clamp.
  static Rect translate(Rect r, double dx, double dy) {
    final w = r.width;
    final h = r.height;
    final l = (r.left + dx).clamp(0.0, 1.0 - w);
    final t = (r.top + dy).clamp(0.0, 1.0 - h);
    return Rect.fromLTWH(l, t, w, h);
  }

  /// Resize [r] by dragging [handle] by ([dx], [dy]) in normalised
  /// units. When [aspect] (normalised w/h) is provided the resulting
  /// rect is locked to that ratio anchored on the geometry opposite
  /// the dragged handle:
  ///
  ///   * Corners anchor on the opposite corner.
  ///   * Edges anchor on the **midpoint** of the opposite edge so
  ///     the perpendicular axis grows symmetrically about that
  ///     centre line (matches iOS Photos / Instagram).
  ///
  /// Output is always [sanitise]d \u2014 callers can feed it straight
  /// into [updateDraft].
  static Rect resize(
    Rect r, {
    required CropHandle handle,
    required double dx,
    required double dy,
    double? aspect,
  }) {
    double l = r.left, t = r.top, rt = r.right, b = r.bottom;
    switch (handle) {
      case CropHandle.tl:
        l += dx;
        t += dy;
        break;
      case CropHandle.tr:
        rt += dx;
        t += dy;
        break;
      case CropHandle.bl:
        l += dx;
        b += dy;
        break;
      case CropHandle.br:
        rt += dx;
        b += dy;
        break;
      case CropHandle.t:
        t += dy;
        break;
      case CropHandle.b:
        b += dy;
        break;
      case CropHandle.l:
        l += dx;
        break;
      case CropHandle.r:
        rt += dx;
        break;
    }
    Rect next = Rect.fromLTRB(l, t, rt, b);
    if (aspect != null && aspect > 0) {
      final anchor = switch (handle) {
        CropHandle.tl => r.bottomRight,
        CropHandle.tr => r.bottomLeft,
        CropHandle.bl => r.topRight,
        CropHandle.br => r.topLeft,
        CropHandle.t => Offset(r.center.dx, r.bottom),
        CropHandle.b => Offset(r.center.dx, r.top),
        CropHandle.l => Offset(r.right, r.center.dy),
        CropHandle.r => Offset(r.left, r.center.dy),
      };
      double w, h;
      switch (handle) {
        case CropHandle.t:
        case CropHandle.b:
          h = next.height.abs();
          w = h * aspect;
          break;
        case CropHandle.l:
        case CropHandle.r:
          w = next.width.abs();
          h = w / aspect;
          break;
        case CropHandle.tl:
        case CropHandle.tr:
        case CropHandle.bl:
        case CropHandle.br:
          final candW = next.width.abs();
          final candH = next.height.abs();
          if (candW / (candH == 0 ? 1e-6 : candH) > aspect) {
            h = candH;
            w = h * aspect;
          } else {
            w = candW;
            h = w / aspect;
          }
          break;
      }
      double nl, nt, nr, nb;
      switch (handle) {
        case CropHandle.tl:
          nr = anchor.dx;
          nb = anchor.dy;
          nl = nr - w;
          nt = nb - h;
          break;
        case CropHandle.tr:
          nl = anchor.dx;
          nb = anchor.dy;
          nr = nl + w;
          nt = nb - h;
          break;
        case CropHandle.bl:
          nr = anchor.dx;
          nt = anchor.dy;
          nl = nr - w;
          nb = nt + h;
          break;
        case CropHandle.br:
          nl = anchor.dx;
          nt = anchor.dy;
          nr = nl + w;
          nb = nt + h;
          break;
        case CropHandle.t:
          nb = anchor.dy;
          nt = nb - h;
          nl = anchor.dx - w / 2;
          nr = anchor.dx + w / 2;
          break;
        case CropHandle.b:
          nt = anchor.dy;
          nb = nt + h;
          nl = anchor.dx - w / 2;
          nr = anchor.dx + w / 2;
          break;
        case CropHandle.l:
          nr = anchor.dx;
          nl = nr - w;
          nt = anchor.dy - h / 2;
          nb = anchor.dy + h / 2;
          break;
        case CropHandle.r:
          nl = anchor.dx;
          nr = nl + w;
          nt = anchor.dy - h / 2;
          nb = anchor.dy + h / 2;
          break;
      }
      next = Rect.fromLTRB(nl, nt, nr, nb);
    }
    return sanitise(next);
  }
}

/// Public crop-frame handle identifier. Mirrors the eight resize
/// affordances pro photo editors expose (4 corners + 4 edges) so
/// the resize math can be reused by the overlay and by tests.
enum CropHandle { tl, tr, bl, br, t, r, b, l }

/// Single shared provider — every crop entry-point reads/writes the
/// same [CropSession].
final cropControllerProvider =
    NotifierProvider<CropController, CropSession>(CropController.new);
