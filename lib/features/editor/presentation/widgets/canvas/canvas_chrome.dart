import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_tokens.dart';
import '../../../../../l10n/l10n.dart';
import '../../../application/canvas_chrome_visibility.dart';
import '../../../application/editing_controller.dart';
import '../../../application/editor_mode_controller.dart';
import '../../../application/interaction_controller.dart';
import '../../../application/mask_edit_controller.dart';
import '../../../application/selection_controller.dart';
import '../../../crop/application/crop_controller.dart';
import '../../../engine/core/editor_document.dart';
import '../../../engine/core/editor_layer.dart';
import '../../../engine/core/selection_state.dart';
import '../../../engine/core/viewport_state.dart';
import '../../../engine/interaction/group_engine.dart';
import '../../../image/presentation/photo_slot_badge.dart';
import '../editor_breakpoints.dart';
import '../mask_edit_overlay.dart';
import '../quick_capsule.dart';
import '../selection_overlay.dart';
import '../transform_hud.dart';
import 'canvas_gesture_router.dart';
import '../../../../../app/theme/app_icons.dart';

/// Builds the **screen-space chrome** slice of the editor canvas' outer
/// Stack: the select-and-move claim surface, the single/group selection
/// overlays, the transform HUD, the protected-base badge, photo-slot
/// badges, the quick capsule, the mask-edit overlay and the
/// multi-select mode chip.
///
/// Returned as a flat list so the caller can spread it into the Stack
/// unchanged — the relative order of these siblings encodes which
/// surface outranks which in the gesture arena and must not be nested.
List<Widget> buildCanvasChrome({
  required CanvasGestureRouter router,
  required EditorDocument doc,
  required SelectionState selection,
  required ViewportState viewport,
  required bool addTextComposerOpen,
  required bool maskEditActive,
}) {
  return [
    // Screen-space chrome — sits OUTSIDE the viewport
    // transform so handles never scale with zoom or doc
    // size. Receives the current viewport so it can map
    // canvas-space corners to screen coordinates.
    //
    // Routing:
    //   * count == 1 → per-layer selection chrome that
    //     hugs the rotated layer rect.
    //   * count >  1 → group selection chrome on the
    //     shared axis-aligned bounds. The per-layer
    //     overlay is suppressed; subtle outlines are
    //     painted *inside* the viewport (above) instead.
    //
    // Protected base photo (photo project + locked) is
    // the canvas itself, not a movable object. UX:
    //   * Selection FRAME is shown (outline only, no
    //     handles, no body drag) so the user can see
    //     what is selected when they pick the row in
    //     the Layers panel and the bottom Image tools
    //     appear. Without this the toolbar change is
    //     unexplained.
    //   * Transform HUD, floating duplicate/delete bar
    //     and inline contextual toolbars stay
    //     suppressed -- those imply move/scale/delete,
    //     none of which apply to the base photo.
    //   * A small "Base photo" badge is rendered near
    //     the photo's top-left corner so the selection
    //     state has a clear label. See
    //     [buildProtectedBaseBadge].
    // Handles + body drag suppression for protected
    // base photo is handled inside
    // [buildSelectionOverlay] (it passes
    // `showHandles: !locked` and `onBody: null` for
    // locked layers).
    // Select-and-move + drag-anywhere claim surface
    // (contract §5 rows 5 and 7) — BELOW the
    // selection overlays so the selected layer's
    // chrome quad, handles and group quad always
    // outrank it, and mounted unconditionally so
    // the mid-gesture selection switch never
    // disposes its recogniser. Mode gating lives
    // in its claim predicate.
    router.buildSelectAndMoveSurface(doc.layers),
    if (selection.count == 1 && !addTextComposerOpen && !maskEditActive)
      buildSelectionOverlay(
        router: router,
        layers: doc.layers,
        selection: selection,
        viewport: viewport,
      ),
    if (selection.count == 1 &&
        isProtectedSelection(doc, selection) &&
        !maskEditActive)
      buildProtectedBaseBadge(
        layers: doc.layers,
        selection: selection,
        viewport: viewport,
      ),
    if (selection.count > 1 && !addTextComposerOpen && !maskEditActive)
      buildGroupSelectionOverlay(
        router: router,
        layers: doc.layers,
        selection: selection,
        viewport: viewport,
      ),
    if (selection.hasSelection &&
        !isProtectedSelection(doc, selection) &&
        !addTextComposerOpen &&
        !maskEditActive)
      buildHud(layers: doc.layers, selection: selection, viewport: viewport),
    // Template photo slots (roadmap 4.11): a pill
    // over every image layer still showing bundled
    // placeholder pixels. Selection-independent, and
    // ABOVE the selection overlay on purpose — the
    // overlay's body-drag surface claims the arena
    // on pointer-down, so a badge underneath it
    // would never receive its own tap. Being a small
    // Positioned child, it only outranks the overlay
    // inside the pill.
    if (!addTextComposerOpen && !maskEditActive)
      PhotoSlotBadges(layers: doc.layers, viewport: viewport),
    // Floating text quick-capsule (re-added,
    // redesigned): a lean edit/font/size/color/more
    // pill over the selection. THE one floating
    // quick-capsule (tb2 9/16): registry-derived
    // per-type accelerators routing to the SAME
    // surfaces the bottom bar opens — quick
    // in-place access, not a second full bar. The
    // protected base photo keeps its badge and
    // gets NO capsule.
    if (selection.count == 1 &&
        !isProtectedSelection(doc, selection) &&
        !addTextComposerOpen &&
        !maskEditActive)
      buildQuickCapsule(
        layers: doc.layers,
        selection: selection,
        viewport: viewport,
      ),
    // Note: the legacy in-canvas image crop overlay
    // was removed. Cropping now happens in the
    // full-screen [CropModeOverlay] mounted by the
    // [EditorScreen] above this canvas.
    // Minimal multi-select mode indicator. Renders only
    // when the user has explicitly entered the mode via
    // long-press. A tiny chip in the top-left corner
    // tells the user "you are in multi-select" + the
    // current count, so toggling-on-tap behaviour is
    // never invisible.
    // Mask-edit chrome: region scrim/outline, drag
    // handles, and the bottom strip. Mounted above
    // every other chrome piece it replaces.
    if (maskEditActive) MaskEditOverlay(viewport: viewport),
    const _MultiSelectModeChip(),
  ];
}

/// True when the current single-selection points at a layer that
/// the document marks as a protected base photo (photo project +
/// matching `basePhotoLayerId`). Used to suppress the chrome that
/// implies movability (transform HUD, floating duplicate/delete
/// bar, inline contextual toolbars). The selection FRAME itself
/// is shown -- see the build order above. Centralised here so the
/// rule lives in exactly one place.
bool isProtectedSelection(EditorDocument doc, SelectionState selection) {
  final id = selection.selectedId;
  if (id == null) return false;
  return doc.isProtectedBasePhoto(id);
}

/// Small screen-space "Base photo" pill anchored to the protected
/// photo's top-left corner. Provides the explicit label the bare
/// outline lacks, so the user understands why the bottom Image
/// tools just appeared. Pure indicator -- IgnorePointer so it can
/// never eat canvas gestures.
Widget buildProtectedBaseBadge({
  required List<EditorLayer> layers,
  required SelectionState selection,
  required ViewportState viewport,
}) {
  EditorLayer? layer;
  for (final l in layers) {
    if (l.id == selection.selectedId) {
      layer = l;
      break;
    }
  }
  if (layer == null) return const SizedBox.shrink();
  final t = layer.transform;
  final pos = t.position;
  final centerCanvas = t.center;
  final rot = t.rotation;
  final cos = math.cos(rot);
  final sin = math.sin(rot);
  final dx = pos.dx - centerCanvas.dx;
  final dy = pos.dy - centerCanvas.dy;
  final tlCanvas = Offset(
    centerCanvas.dx + dx * cos - dy * sin,
    centerCanvas.dy + dx * sin + dy * cos,
  );
  final tl = tlCanvas * viewport.scale + viewport.translation;
  // Above the photo when there is room, INSIDE its top edge when
  // there isn't. Unclamped, `tl.dy - 28` slid under the app bar the
  // moment a tall sub-tool panel pushed the canvas up: the pill kept
  // ~11 of its 27dp and what survived was the bottom half of the
  // Persian glyphs — the dots and ascenders that tell پ/ب/ی apart are
  // exactly what got cut. This is the ONLY on-canvas explanation for
  // why the Image tools appeared, so it must never be half-drawn.
  const badgeHeight = 28.0;
  final above = tl.dy - badgeHeight;
  return Positioned(
    left: math.max(0, tl.dx),
    top: above >= 0 ? above : math.max(0, tl.dy + 4),
    child: const IgnorePointer(child: _ProtectedBaseBadge()),
  );
}

Widget buildSelectionOverlay({
  required CanvasGestureRouter router,
  required List<EditorLayer> layers,
  required SelectionState selection,
  required ViewportState viewport,
}) {
  EditorLayer? layer;
  for (final l in layers) {
    if (l.id == selection.selectedId) {
      layer = l;
      break;
    }
  }
  if (layer == null) return const SizedBox.shrink();
  final selectedLayer = layer;
  return Consumer(
    builder: (context, ref, _) {
      final isEditing = ref.watch(
        editingControllerProvider.select((id) => id == selectedLayer.id),
      );
      if (isEditing) return const SizedBox.shrink();
      final live = ref.watch(
        interactionControllerProvider.select(
          (s) =>
              s.session?.layerId == selectedLayer.id ? s.liveTransform : null,
        ),
      );
      final activeHandle = ref.watch(
        interactionControllerProvider.select(
          (s) =>
              s.session?.layerId == selectedLayer.id ? s.session?.handle : null,
        ),
      );
      final isRotSnapped = ref.watch(
        interactionControllerProvider.select(
          (s) => s.session?.layerId == selectedLayer.id && s.isRotationSnapped,
        ),
      );
      final transform = live ?? selectedLayer.transform;
      return LayerSelectionOverlay(
        transform: transform,
        viewport: viewport,
        activeHandle: activeHandle,
        isSnapped: isRotSnapped,
        // Locked layers (notably the photo-mode base photo) get a
        // selection frame so users still see "this is what's
        // selected", but no transform handles -- handles imply
        // grab-and-resize, which would silently no-op against the
        // locked layer and feel broken.
        showHandles: !selectedLayer.locked,
        // Contract §5 rows 4/6/7 (chrome-quad claim model): the
        // body recogniser claims a FIRST finger only when it lands
        // on the selection's chrome quad — the rotated bbox plus
        // the drawn handle outset — or when a transform session is
        // already running. Everything else falls through to the
        // viewport, so:
        //
        //   * 1 finger ON the quad  → translates the selected layer
        //     (eager claim-and-start; off-canvas recovery depends
        //     on the layer responding from the very first frame)
        //   * 2 fingers, first ON the quad → pinch + rotate the
        //     layer (the second finger may land anywhere — pinching
        //     a small object never requires both fingers inside it)
        //   * 1 finger OFF the quad → falls through to the
        //     select-and-move surface below: another eligible
        //     layer's bbox select-and-moves that layer (row 5);
        //     empty canvas translates the current selection
        //     (row 7's drag-anywhere amendment); otherwise the
        //     viewport pans
        //   * 2 fingers, first OFF the quad → viewport pinch, even
        //     with a selection (row 6 — two-finger gestures ALWAYS
        //     navigate)
        //   * a true tap ON the quad is forwarded via [onBodyTap]
        //     → `handleTap` (overlapping-layer cycling); taps and
        //     long-presses OFF the quad reach the canvas-level
        //     recognisers natively now that nothing claims them.
        //
        // First-finger-wins backstop: if a viewport pan/pinch is
        // already in flight, refuse new pointers so a half-finished
        // viewport gesture can complete cleanly.
        shouldClaimBody: (globalPosition) {
          if (router.viewportGestureInFlight) return false;
          // Crop Mode owns the entire viewport via the
          // full-screen [CropModeOverlay]; the selection body
          // surface must yield so the canvas underneath stays
          // inert.
          final cropActive = ref.read(cropControllerProvider).active;
          if (cropActive) return false;
          // Mask-edit mode: the overlay owns the region + handles;
          // yielding lets outside-region pointers fall through to
          // viewport pan/zoom.
          if (ref.read(maskEditControllerProvider).active) return false;
          // Mid-session claim: a live transform keeps the surface
          // (off-canvas recovery — the finger may wander anywhere).
          // EXCEPT when the session belongs to the select-and-move
          // surface one Stack level below: new fingers must fall
          // through to the recogniser that owns the in-flight
          // pointers, or they would restart the session up here.
          if (ref.read(interactionControllerProvider).isActive) {
            return !router.selectAndMoveOwnsSession;
          }
          // Sequence continuation (row 6): another finger is
          // already down and was NOT claimed by this recogniser
          // (else isActive would be true / _pointers non-empty and
          // this first-pointer gate would not run). The sequence
          // belongs to the viewport — later fingers must join the
          // pinch even if they land on the quad.
          if (router.hasRawPointersDown) return false;
          return router.pointInChromeQuad(
            selectedLayer,
            router.toCanvas(globalPosition),
          );
        },
        // Defer-start gate: EVERY claimed pointer defers the
        // session start until movement past slop or a second
        // finger (tb3 3/7 — the eager on-bbox start is gone).
        // Claiming and starting are different promises:
        //
        //   * the arena CLAIM still happens on pointer-down, so
        //     off-canvas recovery keeps its guarantee (nothing can
        //     steal the pointer) and a second finger still joins
        //     the layer pinch (small-object pinch);
        //   * the session START waits for slop — at most
        //     kTouchSlop of dead travel, the same standard as
        //     every other drag in the editor.
        //
        // Deferring on the bbox itself is what revives the
        // stationary intents ON the selected layer:
        //
        //   * pure tap        → [onBodyTap] → cycling / double-tap
        //                       window (edit for text)
        //   * pure long-press → the recogniser's timer fires (no
        //                       session started) → [onBodyLongPress]
        //                       → enter multi-select with the
        //                       selected layer — previously dead
        //                       because the eager start
        //                       short-circuited the timer.
        shouldDeferStartBody: (_) => true,
        // Body surface eagerly claims the gesture arena on pointer-
        // down to guarantee drag priority over the viewport, which
        // also means it eats plain taps that the canvas-level tap
        // detector would otherwise route through `handleTap`. This
        // callback re-injects those taps so overlapping-layer
        // cycling continues to work when the topmost layer is the
        // currently selected one.
        onBodyTap: (globalPosition) => router.handleTap(globalPosition, layers),
        // Long-press intent re-injection. The body surface claims
        // every pointer-down whenever a layer is selected, so the
        // canvas-level `GestureDetector.onLongPressStart` is dead
        // while a selection exists. Without this hook, the
        // documented "long-press another layer to enter
        // multi-select with both layers" gesture would be silently
        // broken: the body surface would eat the held pointer and
        // long-press would never fire. Routing through
        // `handleLongPress` runs the exact same code path as a
        // long-press on empty canvas, so behaviour is uniform
        // regardless of selection state.
        onBodyLongPress: (globalPosition) =>
            router.handleLongPress(globalPosition, layers),
        onBody: selectedLayer.locked || !selectedLayer.capabilities.movable
            ? null
            : (update) {
                final controller = ref.read(
                  interactionControllerProvider.notifier,
                );
                final focalCanvas = router.toCanvas(update.focalGlobal);
                switch (update.phase) {
                  case DragPhase.start:
                    // Single-layer body drag. Multi-select group
                    // drags are routed through the group selection
                    // overlay, which calls `startGroupGesture` and
                    // friends directly — this per-layer overlay is
                    // only wired up when `selection.count == 1`.
                    controller.startGesture(
                      layer: selectedLayer,
                      focalPoint: focalCanvas,
                    );
                  case DragPhase.update:
                    controller.updateGesture(
                      focalPoint: focalCanvas,
                      scale: update.scale,
                      rotation: update.rotation,
                      pointerCount: update.pointerCount,
                    );
                  case DragPhase.end:
                    controller.end();
                }
              },
        onHandle: (handle, globalPointer, phase) {
          final controller = ref.read(interactionControllerProvider.notifier);
          switch (phase) {
            case DragPhase.start:
              // Handles claim on pointer-down, so a handle session
              // can supersede any prior owner; make sure the
              // select-and-move ownership flag never lingers.
              router.clearSelectAndMoveOwnership();
              final pointer = router.toCanvas(globalPointer);
              if (handle == InteractionHandle.rotate) {
                controller.startRotate(layer: selectedLayer, pointer: pointer);
              } else {
                controller.startResize(
                  layer: selectedLayer,
                  handle: handle,
                  pointer: pointer,
                );
              }
            case DragPhase.update:
              controller.update(router.toCanvas(globalPointer));
            case DragPhase.end:
              controller.end();
          }
        },
      );
    },
  );
}

/// Build the group selection chrome (shared bounding box + handles)
/// for the current multi-selection. Routes pointer events to the
/// `startGroup{Move|Resize|Rotate|Gesture}` family on the
/// interaction controller, so a single composite command commits
/// the entire transform on release.
Widget buildGroupSelectionOverlay({
  required CanvasGestureRouter router,
  required List<EditorLayer> layers,
  required SelectionState selection,
  required ViewportState viewport,
}) {
  final selectedSet = selection.selectedIds.toSet();
  final selectedLayers = <EditorLayer>[
    for (final l in layers)
      if (selectedSet.contains(l.id)) l,
  ];
  if (selectedLayers.length < 2) return const SizedBox.shrink();

  return Consumer(
    builder: (context, ref, _) {
      // Live group bounds. When a session is active, read the
      // controller's `groupLive` map (each entry already reflects
      // the in-flight transform). Otherwise compute from the
      // current document transforms.
      final ui = ref.watch(interactionControllerProvider);
      final Rect bounds;
      if (ui.groupSession != null) {
        bounds = ui.groupLiveBounds ?? Rect.zero;
      } else {
        bounds = const GroupEngine().computeBounds(
          selectedLayers.map((l) => l.transform),
        );
      }
      final activeHandle = ui.groupSession?.handle;
      return GroupSelectionOverlay(
        bounds: bounds,
        frameQuad: ui.groupLiveQuad,
        viewport: viewport,
        activeHandle: activeHandle,
        onBodyTap: (globalPosition) => router.handleTap(globalPosition, layers),
        // Long-press intent re-injection (see single-layer overlay
        // for full rationale). While in multi-select with the
        // group active, long-pressing another layer must still
        // route to `handleLongPress` so its toggle/extend
        // semantics fire. The eager arena claim hides it from
        // the canvas-level long-press recogniser otherwise.
        onBodyLongPress: (globalPosition) =>
            router.handleLongPress(globalPosition, layers),
        // Chrome-quad claim model for multi-select (contract §5
        // rows 4/6/7 — see the single-layer overlay above for the
        // full rationale). The group's chrome quad is its
        // axis-aligned bounds inflated by the drawn handle outset:
        // a first pointer ON that quad drives the group's
        // rigid-body translate (a second finger anywhere then
        // drives pinch + rotate around the gesture focal); a first
        // pointer OFF it falls through to the viewport. A true tap
        // ON the quad is forwarded via [onBodyTap] for selection
        // routing (toggle-in / toggle-out / mode exit).
        shouldClaimBody: (globalPosition) {
          if (router.viewportGestureInFlight) return false;
          final cropActive = ref.read(cropControllerProvider).active;
          if (cropActive) return false;
          // Mask-edit mode: the overlay owns the region + handles;
          // yielding lets outside-region pointers fall through to
          // viewport pan/zoom.
          if (ref.read(maskEditControllerProvider).active) return false;
          // Mid-session claim (off-canvas recovery), then the
          // row-6 sequence-continuation refusal — same order and
          // rationale as the single-layer overlay (including the
          // select-and-move ownership carve-out).
          if (ref.read(interactionControllerProvider).isActive) {
            return !router.selectAndMoveOwnsSession;
          }
          if (router.hasRawPointersDown) return false;
          return bounds
              .inflate(router.chromeOutset())
              .contains(router.toCanvas(globalPosition));
        },
        // Defer-start gate: claimed pointers landing in the outset
        // ring (inside the chrome quad, outside the group's
        // axis-aligned bbox) defer the session start until movement
        // past slop or a second finger. Same rationale as the
        // single-layer overlay — preserves tap (toggle / mode exit)
        // and long-press (extend) intents on the frame edge.
        shouldDeferStartBody: (globalPosition) {
          final local = router.toCanvas(globalPosition);
          return !bounds.contains(local);
        },
        onBody: (update) {
          final controller = ref.read(interactionControllerProvider.notifier);
          final focalCanvas = router.toCanvas(update.focalGlobal);
          switch (update.phase) {
            case DragPhase.start:
              controller.startGroupGesture(
                layers: selectedLayers,
                focalPoint: focalCanvas,
              );
            case DragPhase.update:
              controller.updateGroupGesture(
                focalPoint: focalCanvas,
                scale: update.scale,
                rotation: update.rotation,
                pointerCount: update.pointerCount,
              );
            case DragPhase.end:
              controller.end();
          }
        },
        onHandle: (handle, globalPointer, phase) {
          final controller = ref.read(interactionControllerProvider.notifier);
          final pointer = router.toCanvas(globalPointer);
          switch (phase) {
            case DragPhase.start:
              // See the single-layer overlay's onHandle: handles
              // claim on down and supersede any prior session owner.
              router.clearSelectAndMoveOwnership();
              if (handle == InteractionHandle.rotate) {
                controller.startGroupRotate(
                  layers: selectedLayers,
                  pointer: pointer,
                );
              } else {
                controller.startGroupResize(
                  layers: selectedLayers,
                  handle: handle,
                  pointer: pointer,
                );
              }
            case DragPhase.update:
              controller.updateGroup(pointer);
            case DragPhase.end:
              controller.end();
          }
        },
      );
    },
  );
}

Widget buildHud({
  required List<EditorLayer> layers,
  required SelectionState selection,
  required ViewportState viewport,
}) {
  EditorLayer? layer;
  for (final l in layers) {
    if (l.id == selection.selectedId) {
      layer = l;
      break;
    }
  }
  if (layer == null) return const SizedBox.shrink();
  final selectedLayer = layer;
  return Consumer(
    builder: (context, ref, _) {
      final handle = ref.watch(
        interactionControllerProvider.select(
          (s) =>
              s.session?.layerId == selectedLayer.id ? s.session?.handle : null,
        ),
      );
      if (handle == null) return const SizedBox.shrink();
      final live = ref.watch(
        interactionControllerProvider.select(
          (s) =>
              s.session?.layerId == selectedLayer.id ? s.liveTransform : null,
        ),
      );
      return TransformHud(
        transform: live ?? selectedLayer.transform,
        viewport: viewport,
        activeHandle: handle,
      );
    },
  );
}

/// Floating text quick-capsule for the selected (non-sticker) text
/// layer. Hidden while a transform gesture is in flight, while the
/// inline editor is active, and while any text dock sheet or
/// context panel is open — it just opened that surface; stacking
/// on top of it would be noise. Emoji stickers are excluded (they
/// carry no text flow; the generic quick-actions pill serves them).
/// THE one floating quick-capsule builder (tb2 9/16) — the five
/// per-type builders collapsed to one. Per-type contents live in
/// [QuickCapsule]'s registry; this builder owns only the guards
/// every old builder shared:
///   * inline edit on the selected layer (text) hides it,
///   * an in-flight transform session hides it (never chase a
///     moving selection),
///   * the shared [canvasChromeSuppressedProvider] signal
///     (tb1 15/17) hides ALL floating chrome uniformly.
Widget buildQuickCapsule({
  required List<EditorLayer> layers,
  required SelectionState selection,
  required ViewportState viewport,
}) {
  EditorLayer? layer;
  for (final l in layers) {
    if (l.id == selection.selectedId) {
      layer = l;
      break;
    }
  }
  if (layer == null) return const SizedBox.shrink();
  final selectedLayer = layer;
  return Consumer(
    builder: (context, ref, _) {
      final isEditing = ref.watch(
        editingControllerProvider.select((id) => id == selectedLayer.id),
      );
      if (isEditing) return const SizedBox.shrink();
      final inSession = ref.watch(
        interactionControllerProvider.select(
          (s) => s.session?.layerId == selectedLayer.id,
        ),
      );
      if (inSession) return const SizedBox.shrink();
      if (ref.watch(canvasChromeSuppressedProvider)) {
        return const SizedBox.shrink();
      }
      return QuickCapsule(layer: selectedLayer, viewport: viewport);
    },
  );
}

/// Removed: legacy `_buildImageCropOverlay`. Cropping is now
/// handled by the full-screen [CropModeOverlay] mounted at the
/// editor-screen level. Kept this comment as a breadcrumb so
/// `git log` is enough to find the previous implementation.

/// Multi-select mode chip: count readout + the mode's visible EXIT
/// (tb3 5/7 — the audit's "no visible way out"). Renders nothing at
/// all in single mode so the canvas chrome stays untouched. Sits
/// inside the screen-space chrome stack so it never scales with
/// viewport zoom; top-START (directional) so it mirrors under RTL.
///
/// The whole capsule is one tap target (44dp floor via a transparent
/// halo, ModeDoneButton's pattern) and the trailing ✕ is what makes
/// it read as dismissible. Exit keeps the PRIMARY selection and drops
/// to single mode — the same landing state the editor's own <2-member
/// prune rule produces. Long-press-to-enter and tap-on-empty-to-exit
/// keep working unchanged; this is the discoverable path.
class _MultiSelectModeChip extends ConsumerWidget {
  const _MultiSelectModeChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Gated on the DOCK's own derivation, and labelled with the same
    // count it uses. Watching `selectionMode` alone let the chip
    // outlive the state it describes: a selection can name layers that
    // no longer exist (an undo, a delete), and the chip announced
    // «چندانتخاب · ۱۰» over a six-layer document while the dock —
    // which has always filtered — correctly showed the single
    // surviving layer's own tools.
    if (ref.watch(editorToolModeProvider) != EditorToolMode.multi) {
      return const SizedBox.shrink();
    }
    final count = ref.watch(actionableSelectionCountProvider);
    final tokens = AppTokens.of(context);
    return PositionedDirectional(
      // The 44dp hit halo centres the painted ~26dp pill, so 4/8 here
      // lands the visible capsule near the old 12/12 spot.
      top: 4,
      start: 8,
      child: Semantics(
        button: true,
        label: context.l10n.multiSelectExit,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('multi-select-exit-chip'),
            borderRadius: BorderRadius.circular(999),
            onTap: () {
              HapticFeedback.selectionClick().catchError((_) {});
              // Keep the primary, drop the rest, leave the mode —
              // matching what the <2-member flows land on.
              final primary = ref.read(selectionControllerProvider).selectedId;
              ref.read(selectionModeProvider.notifier).exitMulti();
              if (primary != null) {
                ref.read(selectionControllerProvider.notifier).select(primary);
              }
            },
            child: Container(
              constraints: const BoxConstraints(
                minWidth: kMinHitTarget,
                minHeight: kMinHitTarget,
              ),
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: tokens.brand.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      AppIcons.multiSelectCount,
                      size: 14,
                      color: tokens.onBrand,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.l10n.multiSelectCount(count),
                      style: TextStyle(
                        color: tokens.onBrand,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(AppIcons.close, size: 14, color: tokens.onBrand),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact "Base photo" pill that labels the protected base-photo
/// selection. Positioning is the host's job (see
/// [buildProtectedBaseBadge]); this widget only renders the visual.
/// Stateless + theme-driven so it follows light/dark automatically.
class _ProtectedBaseBadge extends StatelessWidget {
  const _ProtectedBaseBadge();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.brand.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 6,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.layerLocked, size: 12, color: tokens.onBrand),
          const SizedBox(width: 4),
          Text(
            context.l10n.basePhotoLabel,
            style: TextStyle(
              color: tokens.onBrand,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
