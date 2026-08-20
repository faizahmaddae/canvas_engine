# Canvas Tool Redesign — August 2026 («کارت سند» / the document card)

> Successor phase to the paint bench (`docs/paint-redesign-2026-08.md`,
> approved 2026-08-20). Scope: the Canvas control in the main bottom
> toolbar and the complete experience it opens — presentation +
> application only. Engine commands (`SetCanvasSizeCommand`,
> `SetCanvasBackgroundCommand`, `SetCanvasBackgroundModeCommand`,
> `buildCanvasResize` and its anchor policy) are untouched; the one
> new composition is an existing-`CompositeCommand` pairing so a
> single tap out of transparency is a single undo.

## 1. What was wrong

The panel was a settings *form*: a Size label with the current
dimensions riding it in 12sp, four abstract aspect outlines, then a
Background label with a 34×18 swatch, **two stacked segmented
controls** (Color|Transparent, then Solid|Gradient), and the full
colour picker embedded below the fold — the most common act (pick a
background colour) lived at the bottom of a scrolling panel, and the
current state of the document was the least visible thing on it.
Nothing communicated that this surface edits the *document* (contract
§10 W) rather than some selected object; orientation swap didn't
exist; a shrink could strand layers with no feedback.

## 2. The model: a document card over two one-tap rows

```
┌───────────────────────────────────────────┐
│ [bg mini-frame] نامِ سند                   │  the document card:
│    ۱۰۸۰×۱۳۵۰ · عمودی            [⇄ چرخش]  │  W-scope made structural
├───────────────────────────────────────────┤
│ اندازه   [مربع][عمودی][استوری][افقی][سفارشی…]   ← dims under each label
│ پس‌زمینه [شفاف][●●●●●●][طیف رنگ][سفارشی]        ← one row, one tap
│          (طیف expands: preset swatches + angle)
└───────────────────────────────────────────┘
```

- **The document card** is the state display and the scope statement
  in one: the actual background (checkerboard when transparent,
  `BackgroundFillBox` otherwise) drawn in a mini-frame at the
  document's own aspect ratio, beside the project name, exact
  dimensions and format word. The card answers "what is my canvas
  right now" before any control is read — the panel's target is
  visibly the document, not a layer.
- **Rotate canvas (⇄)** on the card swaps width/height through the
  same recentring composite the presets use (one undo). Hidden for a
  square document — a control that would no-op is not shown (§10.3).
- **Size row**: the four aspect presets + Custom…, unchanged in
  capability, but every chip now carries its target dimensions as a
  sublabel — the ratio is the picture, the numbers are the caption.
  Custom… keeps the shared `SizePickerDialog` (full preset catalogue
  + exact fields).
- **Background row replaces both segmented controls**: one row of
  direct choices in the paint-bench swatch grammar —
  a **checkerboard chip** for transparent (mode change; the last
  colour pick survives, as before), six **curated document grounds**
  (white · warm paper · grey · black · amber · blue), a **gradient
  chip** that expands the gradient presets + angle slider inline
  (`AnimatedSize` disclosure, selected whenever the fill IS a
  gradient), and a **custom dot** opening the shared colour picker as
  a modal sheet (barrier none — the canvas live-previews through the
  §2 overlay channel exactly as before). The below-the-fold embedded
  picker dies; the common path is one tap.
- **Tap-out-of-transparency is one undo**: picking any colour while
  transparent commits `CompositeCommand[mode→color, fill]`; the old
  UI required two separate acts and two undos.
- **Stranded-layer whisper**: after a resize that leaves at least one
  layer wholly outside the new canvas, a floating snackbar says so
  and that they can be dragged back — the audit-documented silent
  consequence, surfaced at the moment it happens (undo still one
  step).

## 3. What deliberately stays

- Anchor policy (`buildCanvasResize`): presets/rotate recentre,
  typed custom sizes keep the top-left anchor — including its
  rationale doc.
- Photo-project hint (background sits behind the photo), restyled
  into the background section.
- The Canvas entry (tier-3 tile + title-menu Resize), E3 semantics,
  `EditorToolPanelShell` chrome, dock reflow.
- `FillModeSection` itself — the shape Style panel still uses it;
  canvas simply stops being its second host.
- All engine/command behaviour, codec, history semantics.

## 4. Capability → surface map

| Capability | Before | After |
|---|---|---|
| See current size | 12sp digits on a label | Document card (dims + format word + ratio frame) |
| See current background | 34×18 swatch on a label | The card's frame IS the background |
| Solid colour | segmented×2 → embedded picker below fold | one-tap ground swatch, custom dot → modal picker |
| Transparent | segmented toggle | checkerboard chip in the same row |
| Gradient | segmented → presets+angle | gradient chip → inline disclosure |
| Resize | 4 aspect chips + Custom | same + dims sublabels |
| Orientation | — (missing) | ⇄ on the card |
| Consequence feedback | — (silent) | stranded-layer whisper |

## 5. Tests & captures

`canvas_panel_layout_test` is rewritten against the new structure
(card state, one-row background grammar, transparent chip, composite
undo, disclosure); command/engine suites untouched. Capture variants
`editor_canvas_panel_{light,dark}` re-shot; a gradient-open variant
added. Device passes per the phase contract: iPhone sim fa/en ×
light/dark, Pixel emulator.
