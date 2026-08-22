# The Shape Studio — catalogue growth + shape bench (2026-08)

Status: approved direction (user granted full latitude 2026-08-22);
this doc is the source of truth for the shape catalogue, the Add
Shape picker and the shape-mode dock. Supersedes the strip-era
`ShapeModeToolbar`. Panel behaviour contracts (fill preview channel,
border/shadow adapters, corner-radius presets) remain binding — this
redesign moves surfaces and grows the catalogue, never command paths.

## 1. Verdict on what exists

**The picker sheet is structurally right.** Sectioned grid, real
shape previews (not icon glyphs), shared by Add and Replace with the
current kind lit — that grammar survives. What's wrong is the
inventory: nineteen kinds is a starter pack. A design tool's shape
library is a growth surface the engine explicitly built for ("new
kinds can be added without any engine change"), and the catalogue
has not grown since Phase 2.

**The shape toolbar is the last strip.** Paint, text and image all
moved to the bench; shape mode still wears the generic `SlotStrip`:
six anonymous chips, none of which say anything about *this* shape —
what colour it is, whether a border or shadow is live, how opaque it
is, whether corner-drag will stretch or scale it.

## 2. Catalogue growth — 19 → 33 kinds

Fourteen new kinds, all filled silhouettes (no new stroked kinds, so
`ShapeDefaults` and the border panel's stroked-kind branch are
untouched):

| section | new kinds |
|---|---|
| **Basic** | pentagon, octagon, semicircle, rightTriangle, parallelogram, trapezoid, ring |
| **Bubbles** | thoughtBubble |
| **Symbols** | sparkle (4-point twinkle), seal (12-point badge burst), bolt, shield, crescent, cloud |

Aspect-locked (silhouette collapses when stretched): pentagon,
octagon, sparkle, seal, bolt, shield, crescent, ring. Free-resize
(container / free-form): semicircle, rightTriangle, parallelogram,
trapezoid, cloud, thoughtBubble.

Registration recipe per kind (all switches are exhaustive — the
analyzer walks you through): `ShapePaths` geometry → `ShapeKind`
enum (append at the end; enum order is serialization-friendly
display history, picker order lives in the catalogue sections) →
`isAspectLockedShapeKind` + the const-constructor capability inline →
`_ShapePainter._pathFor` → `shapeOutlinePath` → picker preview
painter → catalogue section entry → `_defaultShapeSize` →
`shapeKindLabel` l10n keys (en+fa). JSON is name-keyed with a
rectangle fallback, so files that mention a new kind degrade safely
on old builds and round-trip losslessly on this one.

The two pinned-order tests in `shape_kinds_test.dart` are the spec —
they get updated in the same commit, deliberately, as the reviewed
artifact of the growth.

## 3. Picker polish

The sheet keeps its structure and gains density: the grid moves from
three columns to four (33 tiles at 3-per-row is an eleven-row
scroll), with the preview scaled to fit the narrower tile. Sections,
gradient previews, selected-state ring and the Replace flow are
unchanged.

## 4. The shape bench

Shape mode joins the bench family (paint → text → image → shape):
two rows in the shared envelope (`dockHeight` 108/124).

### Identity row — *what this shape is*

* **Specimen chip** (expanded) — a live thumbnail of the layer's
  actual silhouette painted with its actual dress: fill (solid or
  gradient), corner radius, stroke. Label = the kind's localized
  name. Tapping opens the Replace picker — "tap the shape to change
  the shape", the same door grammar as the image bench's specimen.
* **Fact cluster** — the shared two-zone instrument:
  * **size zone** — `W × H` plus a lock/unlock glyph showing the
    layer's `effectiveResizeMode`. Tapping toggles free ↔ scale via
    `SetShapeResizeModeCommand` (one undo entry) — the toggle that
    decides what corner-drag does to the numbers shown, i.e. the
    tool that governs the number. Same affordance the floating
    toolbar already offers; the bench gives it a discoverable home.
  * **opacity zone** — «۸۰٪», toggles the shared opacity
    `ContextToolPanel`. The strip's dedicated opacity chip dies.

### Aspect row — *which aspect you are dressing*

One connected four-segment track (the shared `_AspectSegment`
grammar):

| segment | opens | badge |
|---|---|---|
| **رنگ** | Style panel (fill / fill-opacity / radius) | dot when the fill is a gradient |
| **کادر** | Border panel | stroke-colour dot when a border is live |
| **سایه** | Shadow panel | shadow-colour dot when a shadow is live |
| **بیشتر** | layer overflow sheet | — |

## 5. What dies

`ShapeModeToolbar` (SlotStrip) — deleted in the bench commit.
`ShapeToolSlot` shrinks to `{style, border, shadow}`;
replace/opacity/more become bench actions. `kShapeStripOrder` and
its `DockStripEntry` plumbing go with the strip; sibling-swipe walks
the three-panel order directly.

## 6. Contract compliance

Style/Border/Shadow stay B-panels on the dock with their §2 preview
channels and one-undo commits untouched. The resize-mode toggle is a
§3 discrete command (already existing). Opacity stays the shared
`ContextToolPanel`. No command path changes anywhere in this
redesign.

## 7. Keys

`shape-studio-bench`, `shape-specimen`, `shape-pill-size`,
`shape-pill-opacity`, `shape-aspect-style`, `shape-aspect-border`,
`shape-aspect-shadow`, `shape-aspect-more`. Panel-internal keys keep
their existing names.

## 8. Stages

1. this doc;
2. catalogue growth (+14 kinds, picker sections, l10n, default
   sizes, spec-test updates);
3. picker density polish (4-column grid);
4. the bench replaces the strip (identity row, aspect row, dock
   height wiring, controller shrink);
5. captures + device verification + doc pointer updates.
