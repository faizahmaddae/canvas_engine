# Effects Step 6 — Per-Effect Mask Rendering (Design)

> Status: **awaiting sign-off** (2026-07-03). Implementation does not
> begin until this note is confirmed — same gate the A3 stackMask
> plan used. Companion to `docs/effects.md` §4–§5 and
> `docs/effects-a3-scoped-plan-2026-07.md` §7.

## 1. Problem

`EditorEffect.mask` is model-complete (shape, feather, invert,
serialization, `min(α)` composition helper) but both render paths
skip any effect with a non-null mask (`editor_effect.dart` §
`composedColorMatrix` / `customPaintEffects`), so a masked effect
silently vanishes. The renderer that shipped is widget-level — the
§5 rasterize-per-effect pipeline was never built — so this design
maps §5's *semantics* onto the as-built mechanism, exactly as A3 did
for the stack mask.

## 2. Semantics to honour (from effects.md §5)

```
foreach effect e in stack.effects:
    if !e.enabled: continue
    I_next = e.apply(I_prev)
    I_prev = e.mask == null ? I_next
           : composite(I_next over I_prev through e.mask)
if stack.stackMask != null:
    I_prev = composite(I_prev over I0 through stackMask)
```

Key property: a masked effect blends its own output over the
*running* state (everything below it applied), not over the raw
pixels. The stack mask then clips the whole result against I0. The
`min(α)` rule of §4 falls out structurally: a pixel keeps an
effect's contribution only where the per-effect composite wrote it
AND the stack-mask composite keeps it.

## 3. Mechanism — segmented fold (widget-level)

Replace the single `composedColorMatrix` application in
`ImageLayer.buildContent` with a fold over the enabled effects, only
when a masked effect is present:

* **Segment**: a maximal run of enabled, *unmasked* `colorMatrix`
  effects composes into ONE 4×5 matrix (today's
  `composeColorMatrices`), applied with one `ColorFiltered`. Matrix
  composition is associative, so merging within a segment is exact;
  merging *across* a masked boundary is not — hence segmentation.
* **Masked colorMatrix effect `e`**:
  `painted = ColorFiltered(matrix: e.matrix, child: current)` and
  `current = StackMaskComposite(mask: e.mask, base: current,
  painted: painted)` — the A3 widget and raster cache reused
  verbatim (same `sampleAlpha` ground truth, same base-until-raster
  rule, same `(mask, w, h)` cache keys).
* **Masked customPaint effect** (e.g. a future masked vignette): the
  overlay draws *on top*, so masking the overlay alone is
  sufficient — wrap the `CustomPaint` in
  `ShaderMask(dstIn, ImageShader(raster))`. No base subtree needed.
* **Stack mask**: unchanged — the existing A3 composite wraps the
  fold's final result against the un-effected base, which reproduces
  §5's last line.

### Fast-path preservation (byte-identity gate)

When **no enabled effect carries a mask** — every existing document —
the fold degenerates to a single segment and MUST emit exactly
today's widget tree: one `ColorFiltered` with the memoised
`composedColorMatrix`, no wrapper widgets. Structure-gated by test,
same as A3's null path.

### Placement of filterPreset and crop

Unchanged. `filterPreset` composes into the *first* segment's matrix
(it acts on raw pixels, below every stack effect); crop applies to
the pixel subtree before the fold, so every composite branch sees
identically-cropped pixels — the A3 §7.2 base rules generalize
per-segment.

## 4. Engine surface changes

* `EffectStack`: add `hasEnabledMaskedEffect` (cheap scan, memoised
  alongside `composedColorMatrix`). `composedColorMatrix` keeps its
  current skip-masked semantics for the fast path.
* New pure helper (engine/effects): `renderSegments(EffectStack) →
  List<Segment>` where `Segment` is either
  `MatrixSegment(List<double>)` or `MaskedEffect(EditorEffect)` —
  unit-testable without widgets, so the segmentation order logic is
  engine-tested (A-then-B vs B-then-A across a mask boundary).
* `ImageLayer.buildContent`: fold described above. No command or
  serialization changes — the data model already round-trips masks.
* `SetEffectMaskCommand` (mergeable family
  `(layerId, effectIndex, "mask")` per effects.md §8) lands with the
  first UI in Phase 3.2, not here; rendering is exercised by tests
  and fixtures until then. (Rationale: same staging as A3, where the
  render mechanism landed one step before its command.)

## 5. Cost & limits

Each masked effect adds one composite subtree and one cached alpha
raster (shared `StackMaskRasterCache`, same 32 MB budget). Typical
documents carry 0–2 masked effects; no hard cap initially. If
profiling shows raster churn on many-masked documents, a per-layer
cap is a follow-up, not part of this step.

## 6. Test plan (gates before merge)

1. Engine: segmentation unit tests — single segment == memoised
   matrix; masked boundary splits segments; disabled masked effect
   ignored; order A-masked-B ≠ merged(A,B) via matrix inequality.
2. Widget structure: no-masked-effect documents build a widget tree
   with zero `StackMaskComposite`/`ShaderMask` (fast-path identity);
   one masked matrix effect builds exactly one.
3. Pixels (extend `stack_mask_render_test.dart` patterns): masked
   brightness confined to its rect with linear feather; effect below
   the masked one applies everywhere; masked + stack mask compose
   (`min(α)` observable: effect visible only in the intersection).
4. Fixture: v3 corpus gains `03_image_with_per_effect_mask.json`
   (writer already stamps v3 via the non-empty effects list).

## 7. Out of scope

Mask-editing UI/gestures (Phase 3.2), reorder honesty for
custom-paint effects (Phase 3.3), effects on non-image layers
(Phase 3.3 decision), raster/brush masks (effects.md §11).
