# Paint/Draw Redesign — August 2026 («میز طراحی» / the drawing bench)

> Product + presentation redesign of the complete Paint/Draw
> experience, on `feat/command-scope-contract`. Successor to the
> August audit (`docs/paint-tool-audit-2026-08.md`), which fixed the
> P1 mechanics but deliberately left the *grammar* untouched. This
> document is the grammar change. The interaction contract
> (`docs/editor-interaction-contract-2026-07.md`) is amended in the
> same series; the amendments are listed in §7 and land in the
> contract file itself.
>
> Scope: paint presentation + application layers only. The engine
> (PaintLayer, PaintKind, paint commands, codec) is untouched.

## 1. Why the July/August work wasn't enough

The paint dock is the same property-tile strip every other mode
uses: nine `DockToolTile`s (icon + label + value word), each opening
a sheet. That grammar is right for *object property editing* (image
look, text style) and wrong for *drawing*:

- **Drawing is a live activity, not a form.** Color, size and tool
  are switched dozens of times per minute while sketching; a
  tile→sheet→adjust→close loop per change makes every switch a
  3-tap detour. The tools a drawing app keeps at zero taps (color,
  tool, size) were all one-or-more sheets deep.
- **The strip communicated properties, not state.** Nothing outside
  a sheet showed the current ink: the Color tile's swatch was one of
  nine equal tiles; the pen itself had no visual identity.
- **Tool choice was a questionnaire.** Entering paint (via any path
  but the main tile) opened a "choose a tool" sheet with three
  category chips and a grid — 11 abstract options before the first
  mark. Line/dash/dash-dot are one decision (a line's *style*), and
  rectangle/circle/hexagon/polygon are one decision (a shape's
  *kind*), yet all were peers of Pen in one flat catalogue.
- **The two scopes were invisible.** "Configuring the next stroke"
  vs "editing this stroke" differed only in a caption chip inside
  sheets and a relabelled Tool tile. The audit's P1s (auto-select on
  commit, tap-to-select) made restyle *reachable* but not *legible*.

## 2. The model: one bench, two postures

Paint mode is a **bench**: a persistent two-row surface in the dock
strip zone (reflow grammar preserved — the dock never overlays the
canvas). The bench always answers the two questions the old strip
couldn't: *what will my next touch do* (rack) and *with what ink*
(style row).

```
┌──────────────────────────────────────────────┐
│  style row   ● ● ● ● ● ●   [۱۲px ●] [◌ ٪۸۰]  │  ink: swatches + pills
│  tool rack   قلم  خط  پیکان  شکل  محو  ⌖  پاک‌کن │  verbs: 7 fixed slots
└──────────────────────────────────────────────┘
```

The bench has exactly two postures, and they are structurally
distinct on screen:

**Drawing posture** — a tool is armed. The canvas draws. The rack
highlights the armed tool; the style row shows the live ink. A
committed stroke auto-selects (contract §10 A) and style edits apply
to **both** the bound stroke and the pen (see §4). Selection chrome
(handles) stays down while armed — the binding is for restyle, not
transform.

**Adjust posture** — the ⌖ (انتخاب) slot; no tool armed. The paint
gesture surface unmounts, so the canvas gets the editor's ordinary
selection grammar back: tap a stroke to select it (handles, move,
transform), tap empty to deselect. The style row binds to the
selected stroke and edits **it only**. This is the affordance the
audit demanded for the orphaned `clearTool()` — "stop drawing, keep
the bench" — promoted to a first-class tool.

Scope disclosure is now *structural* (two visibly different
postures) instead of *captional* (a chip inside a sheet). The scope
chips die.

### The rack (7 slots, fixed order)

| Slot | Arms | Tap again |
|---|---|---|
| قلم Pen | freestyle | pen sheet (size + opacity) |
| خط Line | last line kind (solid ⁄ dashed ⁄ dash-dot; default solid) | line sheet (style + size + opacity) |
| پیکان Arrow | arrow | pen sheet |
| شکل Shape | last shape kind (rect ⁄ circle ⁄ hexagon ⁄ polygon; default rect) | shape sheet (kind + sides + fill) |
| محو Blur | blur | blur sheet (radius) |
| ⌖ انتخاب Adjust | nothing (adjust posture) | — |
| پاک‌کن Eraser | eraser | — |

- Line and shape *families* collapse to one slot each; the engine
  kinds are unchanged and the variants are chosen inside the slot's
  sheet (line kinds are already restyle-peers via
  `UpdatePaintStyleCommand.kind`).
- Rack tiles are drawn glyphs in the current ink color where the
  tool produces ink (pen/line/arrow/shape) — the rack *is* the state
  display. Blur/adjust/eraser use neutral glyphs.
- Entry: the main-strip Draw tile arms the pen directly. **No
  auto-opening tool picker** — the first frame of paint mode is
  drawable. The grouped picker sheet (`PaintToolBody`) dies.

### The style row (contextual, per posture/tool)

| Context | Row contents |
|---|---|
| pen / line / arrow armed | 6 ink swatches (once-curated + recents) + custom-color dot → color sheet; size pill (live px + dot preview) → pen sheet |
| shape armed | same + fill dot → shape sheet |
| blur armed | radius pill → blur sheet |
| eraser armed | hint text: sweep or tap strokes to erase |
| adjust + paint stroke selected | bound stroke's swatches/pills (kind-appropriate: dash pill for lines, sides pill for polygon, radius for blur) |
| adjust + nothing selected | hint text: tap a stroke to edit it |

Swatch tap = one-tap ink change (the single biggest tap-count win).
The custom dot opens the shared `ColorPickerBody` sheet (existing
preview/commit channel unchanged).

### The size rail (canvas-side vertical slider)

While an inking tool is armed (pen/line/arrow/shape), a slim
vertical rail floats on the canvas edge (physical side follows the
`rightHandedToolbar` setting: rail on the non-drawing side). Drag =
live stroke-width preview via the existing §2 width channel; release
commits (bound stroke) or settles the pen default. A width bubble
follows the thumb. This is standard drawing-app furniture
(Procreate) and removes the last sheet-trip from the core loop.

The rail is floating canvas chrome: it hides with
`canvasChromeSuppressedProvider` — with one paint-local exception:
the *paint* dock sheets do not suppress it (they don't overlap it,
and live width feedback next to an open pen sheet is the point).
Pointer-wise it sits above the paint gesture surface and owns its
own pointers (same standing as the Done pill — §5 untouched).

## 3. Sheets (dock expanded zone, `DockSheetChrome` unchanged)

`PaintSession.openSlot` now ranges over `color · pen · line · shape
· blur`. All bodies are compositions of existing primitives
(`PresetSliderControl`, `EditorSegmentedControl`, `PresetChip`,
`ColorPickerBody`); the hand-rolled `_PaintSizeSlider` and the
bespoke `paint_size_body/paint_size_entry/paint_dash_body/
paint_polygon_body/paint_fill_body/paint_tool_body` widgets die.

- **color** — `ColorPickerBody` (unchanged channel).
- **pen** — Size (`PresetSliderControl`, presets 2⁄6⁄12⁄24, live dot
  preview) + Opacity (presets 25⁄60⁄100). Opened by size pill or
  tap-again on pen/arrow.
- **line** — style segmented (solid ⁄ dashed ⁄ dash-dot) above the
  same size+opacity stack.
- **shape** — kind row (4 preview tiles) + Sides slider (3–24,
  polygon only) + fill toggle & fill color + size+opacity.
- **blur** — radius `PresetSliderControl` (0⁄10⁄32 presets, 0–64).

Sibling swipe pages between the sheets reachable from the current
context (existing `SiblingSwipeStrategy`).

## 4. Write rule (one sentence per posture)

- **Drawing posture:** a style write targets the pen's defaults
  *and* the bound stroke when one is bound (the stroke just drawn,
  or one tap-selected while armed). One command for the layer
  (undoable); the default write is session state (no undo entry) —
  same gesture, both targets, so "draw → recolor → draw" behaves the
  way every drawing app trains users to expect: the stroke you're
  looking at changes *and* the pen keeps the ink.
- **Adjust posture:** a style write targets the selected stroke
  only. Editing an old annotation doesn't re-ink the pen.

This replaces the old either/or rule, under which recoloring the
just-drawn stroke silently left the pen on the previous color (the
next stroke came out "wrong"). Contract §10.5 is amended to match
(§7).

## 5. What dies (deleted in the same series)

- `paint_mode_toolbar.dart` (slot strip + auto-open picker) → new
  bench widget.
- `paint_tool_specs.dart` capability matrices + value-word helpers →
  per-slot logic in the bench/sheets.
- `bodies/paint_tool_body.dart` (grouped catalogue picker).
- `paint_size_body.dart`, `bodies/paint_size_entry.dart` (hand-rolled
  slider — audit P1).
- `bodies/paint_dash_body.dart`, `bodies/paint_polygon_body.dart`,
  `bodies/paint_fill_body.dart` (folded into line/shape sheets).
- `_PaintScopedSubTool` scope chips (structural disclosure now).
- The `nextStrokeScope`/`editingStrokeScope` l10n keys.

## 6. What deliberately stays

- Engine: `PaintLayer`, `PaintKind`, commands, codec — untouched.
- `PaintGestureSurface` pointer machine (buffer/draft/sweep/
  two-finger rescue) — behavior identical; adjust posture simply
  unmounts it, which is the pre-existing `activeTool == null` path.
- `PaintStrokeController` commit/select/erase semantics, including
  auto-select-on-commit (§10 A) and tap-select for two-point tools.
- Preview/commit channels (§2) and `paintStyleViewProvider` as the
  display source.
- Done pill (E2) + pasteboard-tap exit; dock reflow model (no
  overlay/scrim); `EditorToolDock` chrome.
- Eraser = whole-stroke removal, its own rack slot, sweep grammar.

## 7. Contract amendments (landed in the contract file, same series)

1. **§10.5 N write rule:** bound target wins for *reads* and for
   *unarmed* writes; while a tool is armed, a style write targets
   both the bound layer and the author defaults (both named in
   advance — still no searching, still no chooser).
2. **§10.5 disclosure:** satisfied structurally by the bench's two
   postures (rack highlight + row binding) instead of a scope chip.
3. **§4 table note:** the rack's adjust slot maps to *posture
   switch*, not an exit level; Done pill stays the only E2.

## 8. Test/capture plan

- Bench widget tests replace `paint_mode_toolbar_smoke_test` +
  restyle-dock coverage: rack arming, posture switch, contextual
  style row, swatch one-tap write rule (both-targets vs bound-only).
- Controller tests for the amended write rule.
- Capture variants: `editor_paint_entry`, `editor_paint_color`,
  `editor_paint_shape_sheet`, `editor_paint_adjust` light+dark
  (replacing `editor_paint_picker`); the size rail appears in entry
  captures.
- Device passes: iPhone 17 Pro Max sim (fa + en, light + dark),
  Pixel emulator (dark) — full workflow: enter → draw → swatch
  recolor → rail resize → shape + sides → blur → erase → adjust →
  restyle old stroke → undo chain → exit.
