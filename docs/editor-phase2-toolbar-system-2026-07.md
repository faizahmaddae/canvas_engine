# Editor — Phase 2: Unify the Toolbar System + Break Up the God-File — July 2026

> Phase 2 of `editor-redesign-2026-07.md`. The structural UX work: collapse the
> duplicated two-toolbar-per-tool into ONE context-aware bottom bar, move deep
> controls into consistent `AppContentSheet` panels, and break up
> `text_mode_toolbar.dart` (4,402 lines) — the panels + shared controls trapped
> inside it become modular, reusable files.
>
> Two intertwined goals, sequenced so the risky part is behaviour-preserving:
> **2A** breaks up the god-file (no UX change), **2B** unifies the toolbars on
> the now-modular pieces.

---

## The problem (verified in code)

- **Duplicated toolbars.** Every tool has BOTH a `*_mode_toolbar` (bottom bar)
  AND a `*_floating_toolbar` (the pill over the selection): `text_mode_toolbar`
  (4,402) + `text_floating_toolbar` (551); paint (1,517 + 193); shape (125 +
  106). The floating pill duplicates the bottom bar (both carry color, size, …).
  A `context_toolbar_controller.dart` (27 lines) already exists — the seed of
  the unified system.
- **God-file.** `text_mode_toolbar.dart` holds the text bar AND ~12 distinct
  panels (layout, size, font-picker, inline-font browser, styles,
  background/border/shadow precision, resize) AND the shared control widgets
  (slider row, section label, divider, chip, toggle, stepper) that every tool's
  panels should reuse but can't, because they're private to this file.

---

## Target structure

```
editor/presentation/
  toolbar/
    editor_tool_bar.dart          // idle: add text/photo/shape/sticker/draw
    selection_tool_bar.dart       // selected: dispatches to the per-type bar
    text_selection_bar.dart       // text contextual actions (font/size/color/…)
    image_selection_bar.dart      // (from image_mode_toolbar)
    shape_selection_bar.dart      // (from shape_mode_toolbar)
    …                             // paint, sticker, multi-select
  panels/
    text/  layout_panel.dart · size_panel.dart · styles_panel.dart
           font_picker/ (picker_sheet, picker_list, inline_browser, cards, tabs)
           precision/ (background, border, shadow + direction pad, presets)
           resize_panel.dart
    panel_host.dart               // one AppContentSheet-based host for all panels
  widgets/controls/               // SHARED control kit (reused by ALL tools)
    slider_row.dart · section_label.dart · precision_divider.dart
    toggle_segment.dart · stepper_row.dart · panel_chip.dart · advanced_section.dart
```

The **shared control kit** is the biggest structural win: the slider row,
section label, divider, toggle, stepper, chip — currently trapped in the text
god-file — become shared so the image / shape / paint panels reuse them
(consistency + far less duplication).

---

## 2A — Break up the god-file (behaviour-preserving, do first)

A1-style discipline: one concept per commit, `flutter test` green throughout,
each move byte-identical (diff removed vs. relocated). **No UX change in 2A** —
purely moving code into modular files. Suggested commit order (low-risk →
higher):

1. **Shared control kit** → `widgets/controls/`: `_FlatSliderRow`,
   `_LayoutSliderCard`, `_PanelSectionLabel`, `_PrecisionDivider`,
   `_ToggleSegment`, `_SizeStepperRow`, `_AdvancedSection`, `_TierGap`,
   `_WordChipRow`. Promote to public (drop `_`) as they cross files. Rewire the
   god-file to import them.
2. **Font picker + inline browser** → `panels/text/font_picker/`:
   `_FontPickerSheet`, `_FontPickerList`, `_PickerItem*`, `_InlineFontBody`,
   `_ScriptTabSwitcher`, `_FontCategoryFilter`, `_FontCardStrip`, `_FontCard`,
   `_AllFontsCard` (~1,400 lines — the single biggest chunk).
3. **Styles panel** → `panels/text/styles_panel.dart`: `_StylesBody`,
   `_StylesRow`, `_StyleChip`, `_StylePreviewTile`, `_StyleTileRow`, `_StyleTile`.
4. **Precision panels** → `panels/text/precision/`:
   `_BackgroundPrecisionAdvanced`, `_BorderPrecisionAdvanced`,
   `_ShadowPrecisionAdvanced`, `_ShadowDirectionPad`, `_BgPreset`,
   `_ShadowPreset`.
5. **Size + layout + resize** → their panel files: `_SizeBody`/
   `_SizePrecisionAdvanced`; `_LayoutPanel`/`_AlignmentSegmentedControl`/
   `_LayoutPresetChip`; `_ResizeOptionTile`/`_RadioDot`.

After 2A, `text_mode_toolbar.dart` is just the text bar + panel dispatch (well
under the limit), and every panel/control is modular.

## 2B — Unify the toolbars (UX change)

On the now-modular pieces:

1. **Idle tool bar** (`editor_tool_bar.dart`): the add-tools row, driven by no
   selection.
2. **Selection bar** (`selection_tool_bar.dart` + per-type bars): when an object
   is selected, show ONE contextual bar for its type, via
   `context_toolbar_controller`. Consolidate each tool's `*_mode_toolbar` +
   `*_floating_toolbar` into this one bar. **Remove the floating pill** (keep at
   most a minimal on-canvas "edit" affordance if it clearly earns its place).
3. **One panel host** (`panel_host.dart`): every deep control opens as an
   `AppContentSheet` (drag handle, title, control), canvas dimmed. Replaces the
   one-off sheets.
4. The bottom area now swaps `editor_tool_bar` ↔ `selection_tool_bar` on
   selection — one system, one grammar.

---

## Discipline

- 2A: behaviour-preserving. Byte-identical moves; `flutter test` green each
  commit; a previously-green test going red = real regression (stop, fix code,
  never edit the test). Watch the private→public promotions (privacy leaks).
- 2B: this is real UX change — screenshot light + dark after each commit and
  review; keep the text/image editing flows working; migrate tests to the new
  bar/panel contracts deliberately.
- Tokens only, global Persian font, dark verified throughout.
- Text + image are the most-used tools — do those bars/panels first in 2B.
