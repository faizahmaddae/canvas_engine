# Phase 3.2 — On-Canvas Mask Editing (Design)

> Status: **awaiting sign-off** (2026-07-03). Implementation begins on
> confirmation, per the design-first rule. Grounded in a code recon of
> the crop mode, canvas gesture arbitration, tool-slot plumbing, and
> lifecycle seams; file references are load-bearing.

## 1. Goal & UX walkthrough

Replace the placeholder Selective preset chips with real selective
adjustments: the user shapes **where** the effect stack applies by
dragging a region on the canvas — the Snapseed/Lightroom gesture.

Walkthrough:

1. Image layer selected → Effects panel → Selective section →
   **"Adjust region"** button (presets stay as quick starts; a mask
   that matches no preset shows a "Custom" chip state instead of all
   chips deselecting).
2. Editor enters **mask-edit mode**: panels close, floating toolbar
   and quick actions hide, the canvas stays live. Chrome drawn over
   the layer: the mask shape's outline + a dim scrim outside the
   region (both rotated with the layer), four corner + four edge
   handles, and a body-move surface inside the region.
3. A compact bottom strip offers: shape toggle (Rect / Ellipse),
   **Feather** slider, **Invert** toggle, and Cancel / Done.
4. Drags reshape a **draft** mask (no document commands). At each
   gesture end the live-overlay preview updates so the user sees the
   actual adjustment land in the region. Done commits ONE command;
   Cancel restores exactly the entry state.
5. Outside the region, one-finger drag pans and two-finger pinch
   zooms the viewport — free because the selection body surface
   yields while the mode is active (see §5).

## 2. Architecture — draft-first modal session (crop template)

`MaskEditController` (editor/application), copying the
`CropController` shape (crop_controller.dart:19-23, 125-162):

```dart
class MaskEditSession {
  final bool active;
  final String layerId;
  final LayerMask? draft;        // layer-local, like the model
  final LayerMask? entryMask;    // for Cancel + no-op detection
  final String? priorSelectionId;
}
```

* Gestures mutate **only** `draft` (plus a live-overlay staging at
  gesture end, §4). The document is untouched until Done.
* **Done** → if `draft != entryMask`, execute ONE non-live
  `SetStackMaskCommand(layerId, mask: draft)` → exactly one undo
  entry, immune to the merge-window edge cases, zero per-tick
  commit-version churn (the recon's documented reason
  `liveReplace` was deprecated). No-op guard skips history when
  unchanged, like `commitCrop` (crop_controller.dart:268-273).
* **Cancel** → clear overlay + state reset + selection restore. Zero
  commands.
* Selection restore: `priorSelectionId` captured at open, replayed on
  both exits (crop_controller.dart:59-68).

### Rejected: streaming `live: true` commands per tick

Would bump `documentCommitVersionProvider` at drag rate (undo-rail /
layers-panel / autosave listener churn), rasterize a full-resolution
alpha mask per tick with no in-flight cancellation
(stack_mask_raster_cache.dart), inherit both merge-window edge cases,
and flash the effect to base during the whole drag
(StackMaskComposite's base-until-raster rule). The overlay + single
commit pattern is immune to all four.

## 3. Engine additions (small, contract-preserving)

* `EffectStack.withStackMask(LayerMask? mask)` — the mask-write
  helper. Today `EffectStack.copyWith` reserves mask writes for
  `SetStackMaskCommand` via doc comment; the live-overlay staging
  needs the same write, so the sanctioned-writer note moves onto
  `withStackMask` and both the command and the overlay staging call
  it. Canonicalises empty+null to `EffectStack.empty` exactly like
  the command does today.
* `RectMask.copyWith` / `EllipseMask.copyWith` — currently absent;
  drag math reconstructs masks every tick and the feather/invert
  strip edits one field at a time.
* `LayerMask.estimatedByteSize` — history entries hold the command +
  inverse; masks must report sane sizes for the byte budget
  (flagged in recon; PathMask counts its contour points).

No serialization changes — geometry already round-trips, and the
writer already stamps v3 for mask-bearing documents.

## 4. Preview & raster strategy

During a drag the engine preview is **frozen** and only the overlay
chrome (outline + scrim + handles) tracks the pointer. On
`DragPhase.end` (and on feather/invert/shape changes, which are
discrete) the controller stages the draft through
`liveOverlayController.replaceLayer(layer.copyAll(effects:
effects.withStackMask(draft)))` — one raster per gesture, not per
tick. The canvas already renders `renderedDocumentProvider`, so the
adjustment visibly lands in the region at gesture end.

Why not rasterize per tick: a 1080² alpha raster is a ~1.2 M-point
`sampleAlpha` CPU pass + async decode per distinct mask value, the
32 MB LRU floods, and the composite renders base-only until each
raster lands — the effect would flicker off for the entire drag.
Per-gesture staging gives correct feedback at a bounded cost; a
throttled mid-drag preview (~150 ms) is a later polish item, not v1.

Edge case: with an empty/non-contributing effect stack the engine
renders nothing for a mask (image_layer.dart guard). The mode still
works — chrome self-draws — and the bottom strip shows a hint line
("adjustments will apply here") so an empty-stack session isn't
mistaken for a broken one.

## 5. Gestures, coordinates, suppression

**Coordinates.** Masks are layer-local (layer_mask.dart:21-31); the
viewport is uniform scale + translation only; the layer may be
rotated about its centre. One pure helper (new
`mask_edit_geometry.dart`, unit-tested) owns the round-trip:

```
layerLocal → canvas:  c = center + R(rotation)·(l − size/2)
canvas → screen:      s = c·viewport.scale + viewport.translation
```

plus the inverses for pointers. (The repo already has three private
`_rotate` copies — flagged; consolidation belongs to the Phase 4
design-system pass, this helper just must not become a fourth
un-tested one.)

**Handles.** Reuse `HandleDragDetector` + the 48 dp
`_PositionedHandle` pattern (claim-on-pointer-down, DragPhase
callbacks, defensive end on cancel — selection_overlay.dart:412-442,
handle_drag_detector.dart). Handles positioned at the draft's rotated
screen corners/edge midpoints; drag math anchors on the opposite
corner/edge in **layer-local** space via pure static helpers
(`MaskEditController.translate/resize`, crop-style, unit-tested).
The 6 dp selection outset is visual-only and is not fed back into
geometry (recon warning).

**Suppression matrix** (each is manual per-mode wiring; recon
confirmed there is no shared mode abstraction):

| Gate | Where | Action |
|---|---|---|
| Selection body surface | `shouldClaimBody` (editor_canvas.dart:954-963, 1116-1121) | `return false` while active → outside-region pointers fall through to viewport pan/zoom |
| Multi-finger undo/redo | tap-window abort list (editor_canvas.dart:265-278) | abort while active — otherwise a 2-finger tap undoes mid-draft |
| Floating toolbar / quick actions / HUD | builder guards (editor_canvas.dart:1246-1266) | hide while active (`forceHidden` positioner path) |
| Tap re-injection | `onBodyTap`/`onBodyLongPress` | body surface yielded → canvas `_handleTap` would re-select; gate selection changes while active (mode cancels via seam below instead) |
| Back button | `PopScope` (editor_screen.dart:124-131) | route to `cancel()` while active, crop-style |
| AppBar / dock / rails | `select((s) => s.active)` gates | keep AppBar hidden + dock replaced by the mode's bottom strip (crop precedent) |

**Lifecycle seams** (editor_lifecycle.dart contract at :71-73):
idempotent `cancel()` wired into `dismissActiveEditing`,
`closeObjectSubPanels` (selection change), and
`resetEditorEphemeralState` (global non-autoDispose controller —
crop precedent at :42-47). Plus a `documentControllerProvider`
listener cancelling when the target layer is deleted/hidden/locked or
its `effects.stackMask`/`transform` changes externally, with the
clear-state-before-execute ordering that prevents self-cancel
recursion (interaction_controller.dart:222-227). App-lifecycle
non-resumed → cancel.

## 6. Entry point & panel changes

`ImageToolSlot.maskEdit(isPanel: false)` — the crop pattern for
non-panel slots (image_tool_controller.dart:16-31); no
`kImagePanelSlotOrder` change needed for non-panel slots (the drift
test only walks panel slots — verified before landing). The Effects
panel Selective section keeps the presets, adds "Adjust region", and
gains the Custom-state chip semantics. New l10n keys en+fa.

## 7. Tests (gates before merge)

1. Engine: `withStackMask` canonicalisation + sanctioned-writer parity
   with the command; mask `copyWith`; `estimatedByteSize` sanity.
2. Controller (pure): translate/resize anchoring, min-size clamp,
   rect↔ellipse conversion keeps bounds, feather/invert edits,
   Done-commits-one-command (HistoryStack depth 1), Cancel-commits
   -nothing, no-op Done pushes no entry, external layer deletion
   cancels the session.
3. Geometry helper: layer-local↔canvas↔screen round-trips under
   rotation + zoom (1e-9).
4. Widget: mode entry hides toolbar/quick-actions; handle drag
   reshapes draft; Done → document mask updated + single undo entry
   restores entry mask; Cancel → document untouched; 2-finger tap
   while active does NOT undo.
5. Existing suites stay green (mask render pixel gates unaffected —
   the mode never touches the render path).

## 8. Out of scope

Per-effect mask editing UI (this mode edits the stack mask; the
per-effect renderer from Step 6 gets UI when the Effects panel grows
per-row mask affordances), PathMask editing, linear-gradient masks,
mid-drag raster throttling, viewport-rotation support, consolidation
of the three `_rotate` duplicates (Phase 4).
