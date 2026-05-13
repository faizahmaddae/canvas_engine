# Canvas Engine — Effects (Design)

> Draft. Not yet implemented. Approved-outline cycle in progress;
> implementation does not begin until this document is signed off.

## 0. Why this exists

The Phase 1 self-audit was honest: today the project is a sticker editor
with text. The architectural foundation (immutable document, pure
commands, mergeable history, overlay-based previews) is solid, but a
photo editor with no curves, no brightness-on-anything, and no masks is
not a photo editor. **The effect system is the load-bearing column that
turns the foundation into a product.** Every decision below — attachment
shape, mask scope, ordering semantics, schema discipline — is anchored
to that one fact.

## 1. Goals and non-goals

**Goals.** A composable, immutable, GPU-portable, non-destructive
adjustment model. The user can stack effects on any visual layer,
re-order them, mask them, toggle them, and undo each parameter change
individually. Documents written today open identically tomorrow.

**Non-goals this phase.** GPU shaders. Wide-gamut or ICC-aware color.
Per-effect blend modes. Raster (painted) masks. LUTs. Convolution
effects (blur, sharpen). Each is its own future scope; bundling them
guarantees we ship none.

## 2. Vocabulary

* **`EditorEffect`** — one immutable adjustment. Has parameters, a
  render method, an optional mask, a stable type discriminator.
* **`EffectStack`** — an ordered list of effects belonging to one
  layer, plus an optional **stack mask** that clips the composed
  output. The unit of composition. Empty by default.
* **`LayerMask`** — shape primitives (rect / ellipse / path) plus an
  invert flag. Restricts where pixels are written. Used in two roles:
  per-effect (clips one effect's contribution) and per-stack (clips
  the whole composed stack). See §4.
* **Bake point** — the single moment in the render pipeline where the
  effect stack is collapsed onto the layer's pixels. Defined in §5.

## 3. Effect interfaces

```dart
@immutable
abstract class EditorEffect {
  String get type;                     // serialization discriminator
  bool get enabled;                    // user toggle, persisted
  LayerMask? get mask;                 // null = full-layer effect

  /// Pure paint. Reads `input`, writes to `canvas` clipped to `bounds`.
  /// MUST NOT touch the document, providers, or any global state.
  void apply(Canvas canvas, ui.Image input, Rect bounds);

  Map<String, dynamic> toJson();       // includes type + mask + enabled
  EditorEffect copyWith({...});        // typed in concrete subclasses

  // For Picture-cache keying. Effects with equal hashes produce
  // identical output; the renderer relies on this to skip work.
  @override int get hashCode;
  @override bool operator ==(Object other);
}

@immutable
class EffectStack {
  final List<EditorEffect> effects;    // ordered, default const []
  final LayerMask? stackMask;          // null = no clip on composed output

  bool get isEmpty;                    // effects.isEmpty && stackMask == null
  int  get hashCode;                   // cache-key contributor (§10)
}
```

There is no `invert()` on the effect itself. Undoability lives on the
**command** that mutates an effect's parameters (§8). Effects are pure
data; commands are how data changes.

## 4. Composition model

Effects attach as an **`EffectStack` field on `EditorLayer`** — not as
their own layer type, not as a separate sibling tree. One concrete
field, ordered list, default empty. This decision answers two questions
at once: *where does an effect live?* (on the layer it modifies) and
*what can it mask?* (its own contribution, nothing more).

**Why a field, not a layer:** an effect is a property of *something
visible*, not a thing in itself. Promoting effects to layers forces a
"target" pointer back at the actual layer, and that pointer becomes the
authority for selection, group operations, undo grouping, and export
ordering. The whole shape gets harder for no user-visible gain.

**Mask model.** `EffectStack` is a record
`{ effects: List<EditorEffect>, stackMask: LayerMask? }`. `LayerMask`
is referenced by `EditorEffect.mask` and `EffectStack.stackMask`. A
future layer-wide mask is out of scope this phase. Each effect carries
an optional per-effect mask; the stack carries an optional final-clip
mask. They compose via `min(α)` — a pixel is written only
where both masks agree. The stack mask answers "apply this whole
adjustment to just this region," the most common gesture in every
photo editor (Lightroom range mask, Photoshop group mask, Snapseed
selective); per-effect masks let advanced users say "darken just the
sky" underneath "warm the whole frame" — the worked example in §9.
Most users will only ever set the stack mask. (Rejected alternative:
a `groupMask` shared-id reference — introduces a parallel id space,
same complexity we rejected when picking `EffectStack`-as-field over
effect-as-layer.)

**Mask shape this phase:** `Rect`, `Ellipse`, `Path` (closed Bézier),
plus `inverted: bool` and `feather: double` (px in canvas space). All
serializable as data, no asset blob. Raster masks are a future phase
that needs brush-stroke serialization and per-mask asset storage —
deferred (§11).

## 5. Pipeline placement

For one layer the pipeline is:

```
layer.buildPicture()        →  ui.Picture P0          (un-effected pixels)
rasterize(P0, bounds)       →  ui.Image  I0
foreach effect e in stack.effects:
    if !e.enabled: continue
    e.apply(canvas, I_prev, bounds)  drawing into  I_next
    if e.mask != null:
        composite I_next onto I_prev through e.mask  →  I_blended
        I_prev := I_blended
    else:
        I_prev := I_next
if stack.stackMask != null:
    I_prev := composite(I_prev over I0 through stack.stackMask)
publish I_prev as the layer's effective Picture for the composite stage
```

The **bake point is at the end of the per-layer effect stack**, *before*
inter-layer compositing. Composite (z-order, layer opacity, layer-level
blend if it ever exists) operates on already-effected layer pictures.
This keeps effect math local to the layer and lets the cross-layer
composite stay a thin walk.

**Limitation we're choosing.** A future per-layer blend mode applies
to the *post-effect* picture. To blend the source image and re-apply
effects above the blend (Photoshop's Smart Filter workflow), use an
adjustment layer in a future phase — not added here.

The renderer pipeline that lands in Step 2 of Phase 2 must honor this
bake point. The cache key for a layer's effective Picture is
`(layerHash, effectStackHash)`. Either changes → invalidate.

## 6. Color space contract

**All effects operate in sRGB.** Input is sRGB-encoded, output is
sRGB-encoded. We do **not** linearize before math this phase. Brightness
is a scalar nudge in sRGB, contrast is a midpoint pivot in sRGB,
saturation is HSL conversion in sRGB. The math is "good enough" for
proof-of-three and matches what the existing `ImageAdjustments` already
does — so the migration is behavior-preserving.

This is the wrong long-term answer. Linear-light math is required for
physically correct compositing, blur, and HDR. Documenting the choice
explicitly here means wide-gamut + linear pipeline becomes a known,
isolated future scope, not a surprise discovered when someone adds the
first kernel effect.

## 7. Serialization and schema versioning

`EditorLayer.toJson()` gains an optional `effects` array and an
optional `stackMask` object. Empty arrays and null masks are
**omitted** from JSON (Phase 1 schema discipline). Each entry:

```json
{ "type": "brightness", "enabled": true, "amount": 20,
  "mask": { "shape": "rect", "rect": [0,0,800,400], "feather": 12 } }
```

**Codec invariants (hard rules, not aspirations).**

* `effects: []` MUST serialize as omitted field.
* `stackMask: null` MUST serialize as omitted field.
* Any effect at parameter defaults with no mask and `enabled: true`
  serializes only its `type` discriminator (other keys omitted).
* **No-op effects (all params at defaults) are preserved on round-trip.**
  Stripping them on read would mutate user-authored document shape and
  break the round-trip-equivalence contract. UI may surface them as
  "effect added but inactive"; the codec does not.
* **Round-trip test (mandatory before any effect ships):** load a v1
  document → save → byte-identical to original until a non-default
  field is set. Same discipline that kept Phase 1's
  `ImageAdjustments.identity` round-trip safe.

Document `schemaVersion` bumps from `2` → `3` on first write of a
document containing any non-empty `EffectStack` (see §8 for the
migration timing rule). `minSupportedSchemaVersion` stays `1`. Schema
version is **per-document**, not
per-layer — per-layer would force a v1/v2/v3 layer matrix in a single
document that no test could cover. A v2 file may contain layers with
empty effect stacks; those layers serialize identically to their v1
form (because empty arrays are omitted), so v2 documents without
effects round-trip byte-for-byte against an old reader once the reader
knows how to skip the version field.

## 8. Undo / redo semantics

Each effect parameter is mutated through one **mergeable command** —
same shape as Phase 1's `SetImageAdjustmentsCommand`. Sliding the
brightness slider produces one command per frame; the `HistoryStack`
merges consecutive commands targeting the same `(layerId, effectIndex,
parameter)` tuple, so a 60-frame drag collapses to one undo entry.

**Effect creation + first parameter change form one composite.**
Opening the effect panel stages no command. The first slider tick emits
a `CompositeCommand([AddEffect(default), SetEffectParam(layerId,
effectId, value)])`. Subsequent ticks merge into the composite's last
child via the existing merge contract, extended one level so a
`CompositeCommand` can accept a merge by delegating to its last child.
Closing the panel terminates the merge stream; the next parameter edit
starts a fresh entry. **One undo press fully reverts "add the effect
and drag the slider" — the user's mental unit of work.**

Non-mergeable, each their own undo step:

* Removing an effect.
* Re-ordering effects (one command per reorder, even via drag).
* Toggling `enabled`.
* Editing the per-effect mask shape (mask geometry edits are their own
  mergeable family, keyed on `(layerId, effectIndex, "mask")`).
* Editing the stack mask (mergeable family, keyed on
  `(layerId, "stackMask")`).

**Migration timing: migrate-on-write, not migrate-on-read.** When v2
code reads a v1 document, the *in-memory* representation is the v2
shape (legacy `imageAdjustments` translated into a three-effect stack).
The **file on disk stays v1** until the user makes a change worth
saving. Opening-and-not-editing must never trigger an irreversible
upgrade — a v1 file that round-trips through v2 reading without user
edits is byte-identical on disk. Only a write path bumps
`schemaVersion`. The legacy reader is permanent; we never delete it.

**Cost of ordered effects.** Ordered semantics double the test surface:
every pair of effects needs at least one A-then-B vs B-then-A test to
prove the order is honored. The proof-of-three barely shows it —
brightness/contrast/saturation are *almost* commutative in practice. The
real cost lands when curves and LUTs arrive, which is also the moment
ordering becomes user-visible and unavoidable. Paying the test cost now,
on three near-commutative effects, is far cheaper than retrofitting
order into a previously-commutative API. Every professional editor
treats effects as ordered; matching that mental model from day one
removes a future migration we'd otherwise owe ourselves.

## 9. The proof-of-three — worked example

**Scenario.** User opens a JPEG (one `ImageLayer`, 800×800). They:

1. Drag brightness +20 (one slider gesture).
2. Mask that brightness to the upper half via a rect.
3. Drag contrast +15 (one slider gesture, applied *after* brightness).

### Resulting layer JSON (v2, after step 3)

```json
{
  "type": "image",
  "id": "img-1",
  "transform": { "position": [0,0], "size": [800,800] },
  "src": "asset://photo.jpg",
  "effects": [
    { "type": "brightness", "amount": 20,
      "mask": { "shape": "rect", "rect": [0,0,800,400] } },
    { "type": "contrast", "amount": 15 }
  ]
}
```

### Render pipeline call sequence (one frame, post step 3)

```
P0  = ImageLayer.buildPicture()                         // raw photo
I0  = rasterize(P0, 800x800)
I1  = brightnessEffect.apply(canvas, I0, bounds)        // +20 everywhere
I1m = composite(I1 over I0 through mask=rect[0,0,800,400])
I2  = contrastEffect.apply(canvas, I1m, bounds)         // +15 everywhere
publish(I2) as img-1's effective Picture
composite stage draws I2 at z-order
```

### Mergeable command sequences (per slider gesture)

* **Step 1.** First slider frame emits `CompositeCommand([AddEffect(
  brightness, default), SetEffectParam(img-1, brightness#0,
  amount=…)])`. Subsequent frames merge into the composite's last
  child. Result: **one** undo entry whose inverse removes the
  brightness effect entirely (back to no-effect state).
* **Step 2.** One non-mergeable `SetEffectMaskCommand(layer=img-1,
  index=0, mask=rect[…])`. Inverse: `mask=null`.
* **Step 3.** First slider frame emits `CompositeCommand([AddEffect(
  contrast, default), SetEffectParam(img-1, contrast#1, amount=…)])`.
  Subsequent frames merge into its last child. Result: **one** undo
  entry whose inverse removes contrast entirely.

### Undo behavior

| Undo press | State restored |
|---|---|
| 1st | contrast effect removed (add + drag revert together) |
| 2nd | brightness mask removed (full-layer brightness +20 again) |
| 3rd | brightness effect removed (add + drag revert together) |
| 4th | image layer back to raw — identical to pre-edit state |

If this sequence holds end-to-end, the model survives. If any row above
is ambiguous, the abstraction is hiding a decision.

## 10. Performance budget and caching

Per-layer Picture cache key: `(layer.contentHash,
layer.effectStack.hash)`. Mutating one effect parameter invalidates
exactly one layer's cache; mutating layer transform alone does not
invalidate effects (effects render in layer-local bounds).

**Two-tier eviction**, mirroring Phase 1's `HistoryStack` discipline:

* **Per-layer LRU cap.** At most **3** cached effected pictures per
  layer: current params + last two for fast undo preview. Older
  evicted on insert.
* **Global byte budget.** `kEffectCacheByteBudget = 128 MB` (half the
  history budget; effects are larger than commands). Evict global LRU
  on overflow.

Both limits live in [`engine_constants.dart`](../lib/core/constants/engine_constants.dart)
with rationale comments. A single `_enforce()` method runs both passes
on insert — same shape as `HistoryStack._enforceByteBudget`.

Mid-drag (overlay preview) effect changes do **not** write to the
committed cache; the renderer queries a transient cache keyed on the
overlay's effect stack hash. The transient cache is bounded the same
way but with a smaller global budget (`kEffectOverlayCacheByteBudget =
32 MB`) since only one in-flight gesture can be active at a time. The
transient cache is fully cleared on `LiveOverlay.clear()` — no LRU
needed across gesture boundaries.

## 11. Out of scope (deferred)

* **GPU shaders.** Unblocked by the Step 2 renderer rewrite, then a
  GPU phase of its own.
* **Wide-gamut / linear-light pipeline.** Unblocked by GPU.
* **Per-effect blend modes.** Unblocked by linear-light.
* **Raster / painted masks.** Unblocked by brush-stroke serialization
  + per-mask asset storage.
* **LUTs.** Unblocked by GPU + asset storage.
* **Kernel effects (blur, sharpen, denoise).** Unblocked by GPU; CPU
  implementations are too slow at full image size.

Each item here is a future scope with a concrete unblocker. Anything
not on this list and not in §1–§10 is undecided, which means: ask
before implementing.
