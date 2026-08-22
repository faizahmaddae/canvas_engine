# The Image Studio — photo bench redesign (2026-08)

Status: approved direction (user granted full latitude 2026-08-22);
this doc is the source of truth for the image-mode dock and its
sheets. Supersedes the strip-era layout of `ImageModeToolbar`
(tb4/tb6/tb12 decisions remain binding where they concern behaviour —
this redesign moves surfaces, never contracts).

## 1. Verdict on the strip

The image mode was the last major mode still wearing the generic
`SlotStrip`: ten anonymous icons, four of them past the scroll fold
on a phone. Nothing on the strip said anything about *this* photo —
which filter is on, what shape clips it, whether a shadow is live,
how opaque it is. Worse, the strip had a split brain: «فیلتر» (Look)
creates effects, «جلوه‌ها» (Effects) manages them, and the Effects
empty state literally redirects to Look — two tiles, one concept.
«انتخابی» was a tile that spends most of its life dimmed behind a
snackbar explaining why it does nothing. «شفافیت» spent a whole tile
on one slider.

## 2. The bench

Image mode joins the bench family (paint → text → image): a two-row
persistent dock in the shared envelope (`dockHeight` 108/124), always
answering the same two questions.

### Identity row — *what this photo is*

RTL order:

* **Specimen chip** (expanded) — a live thumbnail of the layer with
  its real treatment: filter matrix, silhouette mask, border. The
  picture IS the state display. A small replace glyph rides the
  corner; tapping opens the replace flow (گالری/دوربین) — "tap the
  picture to change the picture", the analog of the text bench's
  specimen→composer. Broken sources show the relink label the
  replace flow already computes.
* **Fact cluster** — one bordered two-zone cluster (text bench's
  type-cluster grammar): the **size zone** (the layer's canvas size,
  tabular digits, LTR-pinned) opens Crop — the tool that changes the
  number shown; the **opacity zone** («۸۰٪») toggles the existing
  opacity `ContextToolPanel`. No more full-tile شفافیت.

### Aspect row — *which aspect you are dressing*

One connected four-segment track (text bench `_AspectSegment`
grammar), each segment carrying its state as badges:

| segment | opens | state it carries |
|---|---|---|
| **برش** | `CropModeOverlay` (priorSelection = layer, unchanged) | — |
| **نما** | Look sheet | active filter name ≠ none as a dot; dot when adjustments/vignette live |
| **سبک** | Style sheet | dots for shape ≠ original, border on, shadow on |
| **بیشتر** | layer overflow sheet | — |

## 3. Sheet consolidation

### نما (Look) absorbs the stack

The Look sheet keeps its tb4 contract verbatim (filter row +
fine-tune disclosure + vignette disclosure; «بدون» resets the filter
only; fine-tuning never resets the preset; both compose). Below the
vignette it gains the two sections that lived in the deleted Effects
panel:

* **Applied effects** — the reorder/toggle/delete list, shown only
  when the stack is non-empty (the empty state dies with the panel:
  an empty list inside the surface that *creates* effects needs no
  redirect).
* **Selective mask** — presets + «ویرایش ناحیه», gated exactly as
  before (hidden over an empty stack unless a mask survives, P3-10);
  the mask-edit session opens with the panel left open so Done lands
  the user back here.

The strip's «انتخابی» tile and its snackbar recovery die: the mask
section now sits physically below the effects it masks, so the
precondition is visible instead of narrated.

### سبک merges the silhouette sheets

Shape, Border and Shadow were three sheets answering one question —
how the photo's silhouette is dressed. One Style sheet now holds:
the shape strip on top (most-visual choice first), then the border
and shadow bodies as titled sections. The shared
`LayerBorderBody`/`LayerShadowBody` are reused via their injectable
`shell` hooks (a section wrapper instead of a panel shell), so the
§2 preview channels and adapter divergences ship untouched.

## 4. What dies

`ImageModeToolbar` (SlotStrip), `image_effects_body.dart`,
`image_border_body.dart`, `image_shadow_body.dart`,
`image_shape_body.dart` — content migrates, files are deleted in the
commit that orphans them. `ImageToolSlot` shrinks to `{look, style}`
(panel-bearing slots only); crop/replace/opacity/more become bench
actions, selective moves inside Look. Sibling-swipe walks the
two-panel order.

## 5. Contract compliance

Surface classes unchanged: Look/Style are B-panels on the dock;
crop and mask-edit stay class-D sessions launched with
priorSelection; opacity stays the shared `ContextToolPanel`. Slider
preview channels (§2), discrete chip commands (§3) and the one-undo
rule ship as-is — this redesign relocates surfaces, it does not
touch a single command path.

## 6. Keys

`image-studio-bench`, `image-specimen`, `image-pill-size`,
`image-pill-opacity`, `image-aspect-crop`, `image-aspect-look`,
`image-aspect-style`, `image-aspect-more`. Sheet-internal keys keep
their existing names where the control survives.

## 7. Stages

1. this doc;
2. Look absorbs effects + selective (strip loses both tiles);
3. Style sheet merges shape/border/shadow (strip swaps three tiles
   for one);
4. the bench replaces the strip (identity row, aspect row, dock
   height wiring);
5. captures + device verification + doc pointer updates.
