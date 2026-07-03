# Phase 4 — UI Foundation (Plan)

> Status: **awaiting sign-off** (2026-07-03). No implementation until
> reviewed. Grounded in a three-reader code recon (slider/disclosure
> variant matrix, text_mode_toolbar reference graph, clone/palette/
> rotate anatomy); line references verified there.

## 1. Goals & non-goals

**Goals.** Make UI change cheap and consistent: one slider grammar
instead of ~10 private copies, one disclosure instead of 10, clone
files merged, the two worst god-files split along verified seams,
Home/Onboarding on one palette with real dark-mode behaviour, and
accessibility baked into the primitives instead of retrofitted 109
files at a time.

**Non-goals this phase.** No visual redesign (primitives reproduce
today's pixels unless a divergence is called out below as a deliberate
change); no chip-grammar unification (three chip styles exist —
PresetChip / _LayoutPresetChip / PanelOptionTile — merging them
changes selected-state visuals across every panel at once: parked);
no SlotStrip migration for text/paint toolbars (their strips are
positional with custom expansion hosts — own project, parked); no
navigation/router work.

## 2. Where the design system lives

`lib/features/editor/ui/` — a new sibling of `presentation/`,
editor-scoped (Home/Onboarding get the shared palette in `lib/app/
theme/`, not editor widgets). Rationale: every duplicated primitive is
editor-panel chrome; promoting to a top-level `lib/ui` would invite
non-editor consumers before the grammar is proven. The existing shared
widgets (`SlotStrip`, `PresetChip`, `PresetSliderControl`,
`SectionLabel`, `DockSheetChrome`, `FloatingActionBar`) stay where
they are; new primitives extend this set rather than wrapping it.

## 3. Primitives (specs from the variant matrix)

### 3.1 `EditorSliderRow` — replaces 8 private copies

Covers: shape/image `_LabeledSlider` (byte-identical pair + adjust
variant), `_OpacitySlider`, `_RadiusSlider`, `_PrecisionSlider`,
`_FlatSliderRow`, `_JpgQualitySlider`, the mask-edit feather row.
Excluded by design: `color_picker_sheet._LabeledSlider` (custom
gradient track, not a Slider) and `_LayoutSliderCard` /
`_SizePrecisionAdvanced` (card-shaped, header-embedded — they migrate
to the primitive's inner row but keep their card shells).

```dart
EditorSliderRow({
  String? label,                    // null = no label column
  double labelWidth = 56,           // adjust panel passes 80
  required double value,            // clamped into [min,max] defensively
  double min = 0,
  required double max,
  int? divisions,                   // JPG quality
  bool enabled = true,              // JPG quality
  required String Function(double) format,
  double readoutWidth = 44,
  required ValueChanged<double> onChanged,
  VoidCallback? onDragStart,        // text beginStyleDrag; haptic window
  VoidCallback? onDragEnd,
  EditorSliderHaptics haptics = EditorSliderHaptics.none,
  String? semanticLabel,            // defaults to label
})
```

Decisions encoded:
* **Commit semantics stay at the call site.** The four observed
  strategies (live command stream / beginStyleDrag window / local
  draft + commit-on-end / overlay preview + commit-on-end) all
  express through `onChanged` + `onDragStart`/`onDragEnd`. The
  primitive never dispatches commands.
* **Haptics profile is a parameter** (`none` / `startEnd` /
  `startTickEnd` with the text panels' span/20 tick), preserving each
  surface's current feel. Normalising feel is a later product call,
  not a refactor side effect.
* **Semantics by default**: `Semantics(label) +
  semanticFormatterCallback(format)` on every row — this closes the
  systemic gap (only 2 of ~20 controls attach semantics today) as a
  *deliberate behaviour change* of this phase.
* **Readout uses logical `TextAlign.end`** everywhere — fixes
  `_FlatSliderRow`'s physical `TextAlign.right` under RTL (visible
  change in fa text panels; correct one).
* Disclosure animation standardises on 180 ms/easeOutCubic (the
  shape/image timing); text panels change from 240 ms — visible but
  trivial.

### 3.2 `PrecisionDisclosure` — replaces 10 copies

One stateful widget owning the chevron-rotate + AnimatedSize +
header; parameters: `title`, `subtitle?`, `icon?`, `openLabel`/
`closeLabel` (l10n `adjustPrecisely`/`hidePreciseControls` defaults),
`children`. Absorbs the four header-only `_AdjustHeader`s, the five
self-stateful `_*PrecisionAdvanced` shells, and `_VignetteHeader`.
The text variants keep their inner content; only the disclosure
chrome unifies.

### 3.3 `PanelDirectionPad` — replaces 3 copies, fixes an RTL bug

Adopts the shape/image geometry (3×3 grid, rotated single arrow) with
the selection threshold parameterised. Two deliberate changes:
* **Directionality pinned to LTR inside the pad** — today's
  `GridView.count`/`Row` mirror visually under fa while emitting
  physical `Offset`s, so the visually-left cell moves the shadow
  right. Pinning fixes the Persian bug; it is a visible change in fa.
* Text's `_ShadowDirectionPad` migrates onto the same pad; its
  self-computed magnitude rule moves to its call site.

### 3.4 Small items

* `SectionLabel` gains `uppercase`/`letterSpacing` options so paint's
  `_Label`/`_SectionLabel` fold in without changing paint's visible
  casing; text's `_PanelSectionLabel` folds in as-is.
* Tier gaps: `_TierGap`/`_PaintTierGap` become one
  `EditorTierGap` (13 px gutter, 1×28 hairline). SlotStrip's
  `_TierDivider` stays (data-driven variant) — full strip migration
  is parked (§1).
* `_tileExtent` comment-synced constant (70 = 66+2·2) becomes a real
  exported constant next to `DockToolTile`.

## 4. Clone merges

### 4.1 Shadow bodies (byte-identical logic, ~550 lines × 2)

One `LayerShadowBody` parameterised by a tiny adapter — recon
verified both layer types expose identical fields/defaults and both
commands have identical signatures:

```dart
class ShadowPanelAdapter<L extends EditorLayer> {
  final EditorCommand Function({required String layerId, Color? color,
      double? blur, Offset? offset, double? opacity, bool live}) command;
  final ({Color color, double blur, Offset offset, double opacity})
      Function(L layer) read;
  final Widget Function({required Widget child}) shell; // Shape/ImagePanelShell
}
```

The shell must be part of the adapter (recon risk: the twin shells
bind different tool controllers for close/prev/next navigation).
Commands stay per-layer-type — unifying below the widget layer would
entangle live-merge keying across layer types for zero benefit.

### 4.2 Border bodies (5 behavioural divergences — adapter, not merge)

Same adapter pattern but with explicit hooks for the real
differences: shape's nullable `strokeColor` + `clearColor` None-chip
semantics vs image's non-null `borderColor`; shape's
stroked-shape gate. `hasBorder` and the None-chip commit are adapter
callbacks so shape's clear-colour behaviour survives verbatim.

### 4.3 Palette + dark mode (the one real product change)

`HomePalette` and `OnboardingPalette` are byte-identical 14-constant
sets consumed by 18 files, all hardcoding light-warm colours while
the app ships `ThemeMode.system` with a dark theme — Home renders
light-on-light in dark mode today.

Plan: one `WarmPalette` in `lib/app/theme/warm_palette.dart` exposing
the same 14 names **as `WarmPalette.of(context)` (theme-aware)** with
a dark variant tuned per-constant (ink↔paper flips, accent kept,
shadows raised). Migration is two steps so risk is separable:
1. Mechanical: both palettes become deprecated aliases of the light
   `WarmPalette` values; consumers re-pointed file-by-file (18 files
   incl. `templates_browse_screen`, the largest consumer — keep a
   shim until it migrates). Zero visual change.
2. Behavioural: switch `of(context)` on brightness → Home/Onboarding/
   Browse get real dark mode. Needs a designed dark constant set +
   simulator screenshots before/after; the two thumbnail widgets
   already branching on `isDark` are the template to follow.

### 4.4 Rotate helpers → `LayerSpaceMapper`

Two named `_rotate` copies (selection_overlay, positioner) + inline
inverse math (`editor_canvas._pointInLayerBbox`) + two `_toScreen`
duplicates. Consolidation per site: selection overlay holds
transform+viewport already (direct mapper); `_pointInLayerBbox` uses
`canvasToLayer` (add the regression test recon suggested: mapper ≡
rotate-about-center only while `center == position + size/2`);
`FloatingToolbarPositioner` keeps its decomposed public signature
(4 callers + a unit test) and builds a mapper internally.

## 5. God-file splits

### 5.1 `text_mode_toolbar.dart` (4,402 lines, 47 classes) — part files

Reference graph says **part-file split** (repo precedent: the
image_layer split): the public surface leaks `_ToolSpec` via
`specById`, the registry hard-links to `_TextBodies`, and
`_FontPickResult`'s private constructor is called cross-class.
Library root keeps Cluster A (toolbar + sheet host + registry);
part files: `text_bodies.dart` (B), `text_layout_panel.dart` (C),
`text_panel_primitives.dart` (D → shrinks as primitives migrate to
§3), `text_decoration_panels.dart` (E), `text_font_picker.dart`
(F+G, keeping `recommendedFontEntries`/`fontSampleText` re-exported
for font_panel_test), `text_size_panel.dart` (H — moves `_TextBodies`'
three size statics with it, their only callers), `text_resize_tiles
.dart` (I), `text_style_browser.dart` (J).

Pre-split cleanups (own commits, BEFORE moving anything):
* Delete dead `_AdvancedSection` (+ tombstone comments) so the split
  doesn't scatter noise.
* **Replace label-string logic sentinels**: `_bgMatches`/
  `_applyBgPreset` branch on `p.label == 'Pill'` and
  `_shadowPresetLabel` switches on English preset labels — renames
  silently break matching. Presets gain stable `id` fields first.
* Drop `_ToolSpec.label`/`dockLabel` hardcoded English (display
  already routes through `_localizedToolLabel`); keep `id`/`icon`/
  `bodyBuilder` + document the l10n switch as the single source.
  Guards: `persian_toolbar_labels_test` must stay green; tool id
  strings ('behavior', …) are persistence contracts — never renamed.

### 5.2 `editor_screen.dart` (2,038 lines) — extractions

Verified self-contained units, each its own commit:
1. **Image import IO → application layer** (`image_import_service
   .dart`): `_persistPickedImage` (byte-identical duplicate in
   image_replace_flow) + `_pickImageSource` + `_resolveImageSize`
   as shared primitives; the base-photo-claim policy STAYS at the
   editor_screen call site (replace-flow deliberately lacks it —
   recon risk). Kills the IO-in-presentation violation.
2. **Shape picker** → `shape_picker_sheet.dart` (methods + 4 tail
   classes incl. `_PreviewPainter`).
3. **Save/new-doc/overflow unit** and **sticker flow** — small,
   optional, only if the first two go smoothly.

Load-bearing constraint: the selection-change `ref.listen` →
`closeObjectSubPanels`, the commit-version watch, and the autosave
keep-alive stay on the top-level screen widget — moving them into an
extracted child that can unmount regresses the documented openSlot
re-mount bug.

### 5.3 Parked with reasons

`paint_mode_toolbar` (1,517): seams identified but crossed by a
private-symbol web (`_PaintSpec` leak mirrors text's) — do it after
the text split proves the pattern, if at all this phase.
`editor_canvas` (1,836): interaction-critical; only the rotate/
hit-test consolidation (§4.4) touches it this phase.

## 6. Device-pass polish log (from the 2026-07-03 simulator pass)

Folded into this phase's scope:
* Mask-region **outline stroke** thin/low-contrast on bright content
  → width 2 + subtle dark halo, with the primitive colours from the
  theme (S, rides with §3 work).
* **RTL undo/redo rail order** — deliberate review: keep mirrored
  (platform-consistent) or pin LTR (muscle-memory-consistent).
  Decision item, not assumed.
* **RTL slider direction** — flipped fill direction is
  RTL-conventional; keep, but ensure readouts/labels use logical
  alignment (§3.1 fixes the one violation found).
* **Base-photo discoverability** (Effects reachable only via Layers
  panel) — out of scope here; logged for the selected-layer-actions
  roadmap thread (2026-05 audit Phase 2 items).

## 7. Commit sequence (safety order, gates on every step)

Standing gates: `flutter analyze` clean + full suite green per
commit; verbatim moves diff-proven byte-identical; a broken
previously-green test = stop and discuss.

1. **Dead code deletes** (text `_AdvancedSection` + tombstones,
   `ToggleRow`, `text_value_sheet.dart` if confirmed dead) — shrinks
   the matrix the primitives must satisfy.
2. **Primitives land additively** (`EditorSliderRow`,
   `PrecisionDisclosure`, `PanelDirectionPad`, `EditorTierGap`,
   `SectionLabel` options) with their own widget tests incl.
   semantics assertions. No consumer changes yet.
3. **Leaf migrations, one file per commit**, easiest first: shadow
   bodies → adjust body → border bodies → export JPG slider →
   mask-edit strip → style body sliders → paint labels/tier gap →
   text panels last (they need the `beginStyleDrag` callback
   inversion). Each commit deletes the private copy it replaces.
4. **Clone merges**: `LayerShadowBody` + adapters (deletes ~550
   duplicated lines), then border adapter.
5. **Rotate consolidation** (§4.4) + the center-equivalence
   regression test.
6. **text_mode_toolbar pre-split cleanups** (sentinel ids, dead
   labels) → **part-file split**, one cluster per commit, each a
   byte-identical move.
7. **editor_screen extractions** (§5.2), import-IO first.
8. **Palette step 1** (mechanical unification), then **step 2**
   (dark mode) behind explicit before/after simulator screenshots.
9. **A11y sweep remainder**: controls not covered by migrated
   primitives (dock tiles, segmented toggles, preset chips) get
   Semantics; add the missing-labels widget test.

Rough effort: steps 1–5 ≈ one M; 6–7 ≈ one M; 8–9 ≈ S–M. Any step is
independently shippable; the sequence never leaves a file half-
migrated across commits.

## 8. Decisions for review (defaults chosen, flag to override)

| # | Decision | Default |
|---|---|---|
| D1 | Primitive home | `lib/features/editor/ui/` |
| D2 | Slider semantics-by-default (a11y tree change) | yes |
| D3 | Direction-pad LTR pinning (fa visual change) | yes — it fixes a real bug |
| D4 | Disclosure timing standardisation (text 240→180 ms) | yes |
| D5 | Dark-mode Home/Onboarding (product change) | yes, as separate step 8b with screenshots |
| D6 | RTL undo/redo rail order | keep mirrored (RTL convention) — review |
| D7 | paint_mode_toolbar split this phase | no (parked) |
