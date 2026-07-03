# Effects A3 — Scoped Plan (2026-07)

> **Placeholder note.** §§1–6 of this plan were authored outside the
> repository and have not been committed here yet. This file was
> created to hold the §7 design note produced by the A3 Step 0 spike
> (2026-07-03). When the full plan lands, merge §7 below into it
> verbatim and delete this banner.

## 7. Step 0 design note — stackMask compositing mechanism

Spike artifacts: branch `spike/a3-stackmask`, commit `dd1187c`,
`test/spike/a3_stack_mask_spike_test.dart` (4/4 green). Prototyped the
`docs/effects.md` §5 line

```
I_prev := composite(I_prev over I0 through stack.stackMask)
```

on a stand-in for one `ImageLayer` pixel subtree with one feathered
`RectMask` (`rect (0,0,200,100)`, `feather 24`), including the
inverted variant.

### 7.1 The Flutter mechanism (decided)

**Winner: `ShaderMask(blendMode: BlendMode.dstIn, shader:
ImageShader(maskAlphaImage))` wrapping the *painted* (effected)
subtree, stacked over the *base* (un-effected) subtree:**

```dart
Stack(fit: StackFit.expand, children: [
  base,                                   // I0 — un-effected pixels
  ShaderMask(                             // painted ∘ stackMask
    blendMode: BlendMode.dstIn,
    shaderCallback: (bounds) => ImageShader(
      maskAlphaImage, TileMode.clamp, TileMode.clamp,
      Matrix4.identity().storage,
    ),
    child: painted,                       // I_prev — effected pixels
  ),
])
```

Verified pixel-exact in the spike: masked region fully effected
(grey 76/76/76 under a BT.601 greyscale matrix on pure red), unmasked
region byte-original (255/0/0), feather midpoint blends 50/50
(observed r≈166 = 0.5·76 + 0.5·255), ramp monotonic, `inverted: true`
swaps the two regions exactly.

**Why ShaderMask and not canvas-level `saveLayer` + `dstIn`.** The
rejected approach (a `RenderProxyBox` doing `canvas.saveLayer` →
`paintChild` → `drawImageRect(mask, dstIn)` → `restore`) is
structurally broken for any child that pushes a compositing layer —
and our painted subtree always does: `buildContent` applies the
composed colour matrix through `ColorFiltered`, which pushes a
`ColorFilterLayer`. `PaintingContext.paintChild` on a compositing
child **ends the current native recording** and appends the child as
its own layer, so (a) the child's pixels escape the `saveLayer`
entirely — the spike observed the effect applied *unmasked across the
whole layer* — and (b) the cached `Canvas` reference is invalidated
mid-paint (the deferred `dstIn` throws `StateError: native peer has
been collected`). `ShaderMask` is immune because it is itself a
compositing layer (`ShaderMaskLayer`): the shader + blend apply to the
child's *composited output*, whatever layers the child pushed.

**Mask alpha source: rasterize `LayerMask.sampleAlpha`, not
`MaskFilter.blur`.** The spike builds the mask image by evaluating
`sampleAlpha` at every pixel centre into an RGBA buffer (white,
alpha = sample). This makes the engine's own alpha definition — the
*linear* outward feather ramp and the `inverted` flag in
`layer_mask.dart` — the literal ground truth of what renders. A
`MaskFilter.blur` approximation was rejected: its Gaussian profile
deviates from `sampleAlpha`'s linear ramp, so hit-tests (which use
`sampleAlpha`) and rendered pixels would disagree inside the feather
band. CPU cost is one `w×h` pass per (mask, size) pair and is
cacheable; see §7.3.

### 7.2 The `base` semantic (decided)

`base` = the layer's pixel subtree **with every `EffectStack`
contribution removed, and nothing else removed**. Concretely for
`ImageLayer.buildContent`:

* **In `base`:** source pixels, `fit`, the decode-size cap
  (`cacheWidth`), `filterPreset`, and the crop transform.
  `filterPreset` is a layer field, *not* an `EffectStack` entry — per
  `effects.md` §5, `I0` is the layer's un-effected picture and the
  stack composes on top of it, so the stack mask must not clip the
  preset. Crop selects which pixels exist at all; it applies to both
  subtrees identically.
* **Not in `base`:** the stack's composed colour matrix
  (`effects.composedColorMatrix`) and the custom-paint effect overlay
  (`_CustomPaintEffectsPainter`, e.g. vignette). Those two are exactly
  the stack's render contributions today; `painted` = `base` + both.
* **Unaffected by the composite entirely:** `ImageMask` silhouette
  clip, border, shadow. The composite happens at the *pixels* stage,
  before `_maskClip`; silhouette chrome wraps the already-composited
  result, exactly as it wraps the single subtree today.

Cost note: the source `Image` widget is built twice (base + painted),
but both use the same provider and `cacheWidth`, so Flutter's
`ImageCache` serves one decode — the overhead is one extra widget
subtree plus the GPU composite, not a second decode.

### 7.3 `buildContent` integration (precise)

Today's chain in `image_layer.dart`:

```
adjusted = _loadableImage(cacheWidth, colorMatrix: combined)
pixels   = isFullCrop ? adjusted : _applyCrop(adjusted)
painted  = hasContributingCustomPaint ? Stack([pixels, CustomPaint(...)]) : pixels
clipped  = _maskClip(mask, painted)
… border → shadow → SizedBox
```

Step 1 inserts, between `painted` and `clipped`:

```dart
final stackMask = effects.stackMask;
final composited = stackMask == null
    ? painted                                  // ← today's tree, untouched
    : Stack(fit: StackFit.expand, children: [
        // base: filter preset only — no stack matrix, no custom paint.
        _basePixels(cacheWidth: cacheWidth, colorMatrix: filterMatrix),
        ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (b) => ImageShader(maskImage, …identity…),
          child: painted,
        ),
      ]);
final clipped = _maskClip(mask, composited);
```

where `_basePixels` is `_loadableImage` (+ the same `_applyCrop`)
called with the filter-preset matrix only. The `combined` matrix
passed to `painted` stays exactly as today.

* **Null path is render-tree identical to today** — the wrapper is
  never constructed when `stackMask == null`. Spike test 4 asserts
  both `identical(widget)` and byte-equal `toStringDeep()` render
  dumps. This is what keeps the v2/v3 byte-identity and
  widget-structure gates green for every existing document.
* **Mask raster lifecycle.** `ImageShader` needs the `ui.Image`
  synchronously inside `shaderCallback`, so the raster must exist
  before paint. Plan: an engine-side cache keyed on
  `(stackMask, width, height)` (mask value-equality already exists),
  filled asynchronously on stack-mask change via
  `ui.decodeImageFromPixels` over the `sampleAlpha` buffer. Until the
  raster resolves (typically one frame), render **base only** — a
  one-frame delay of the adjustment is invisible; a one-frame flash
  of the *unmasked* effect is not. Raster size: layer-local logical
  px is sufficient (the feather is layer-local by contract);
  DPR-scaling the raster is a quality follow-up, not a correctness
  requirement.
* **Rect/ellipse fast path (optional, later).** For an unfeathered
  `RectMask`/`EllipseMask`, `ClipRect`/`ClipOval` on the painted
  subtree would avoid the raster entirely. Deferred — one mechanism
  first, fast paths after correctness is gated.

### 7.4 Spike verification summary

| Check | Result |
|---|---|
| Masked region effected | grey (76,76,76) exact |
| Unmasked region original | red (255,0,0) exact |
| Feather midpoint (α=0.5) | r=166±8, linear ramp honoured |
| Feather monotonicity | r strictly increasing across band |
| `inverted: true` | regions swap exactly |
| saveLayer+dstIn approach | broken: effect leaks unmasked + canvas invalidated (StateError) |
| `stackMask == null` | widget identical + render tree byte-identical to today |
