# The Text Studio — August 2026

> The Text tool stops being six property sheets behind six anonymous
> tiles and becomes one studio: a composer where writing and styling
> happen together, a bench that *is* the typographic state display,
> and a font room that finally shows the catalogue's Persian depth.
> Successor to `text-tool-redesign-2026-07.md` for the presentation
> layer; the application layer (write seam, sessions, metrics) is
> kept — it was already right.

## 1. Diagnosis (what the July system got wrong)

Verified on device 2026-08-20 (`build/redesign_shots/text_before/`):

1. **Writing and styling are divorced.** The composer offers Bold and
   Colour — two of the ~20 decisions a text layer carries. Everything
   else demands commit → find the right tile → sheet. The moment of
   highest design intent (while typing) is the moment with the least
   capability.
2. **No typographic state display.** Six generic icon tiles; the only
   live state is a font-name caption and a colour swatch. Nothing
   shows the specimen — what the text actually looks like.
3. **Duplicate surfaces.** The floating quick-capsule repeats size,
   colour and edit — the exact duplication the July "one text bar"
   doc existed to kill, regrown one surface over.
4. **The catalogue is invisible.** 61 faces — including a nastaliq
   section no competitor ships — presented as an 84dp strip and a
   name-only list.
5. **Structure is scattered.** Paragraph direction and resize
   behaviour live behind the full-scrim «بیشتر» list as
   pop-then-dialog rows (the P3-2 grammar again); alignment, spacing
   and multiline layout live in a sheet that is *named* alignment.

## 2. The model

Text has two postures and one room:

* **Writing posture** — the Studio Composer (draft session, §1-D).
  The keyboard is up, the canvas live-previews every keystroke, and
  the full style rail rides above the keyboard: fonts, inks, size,
  weight/italic/underline. Writing and dressing are one activity.
* **Dressed posture** — the Studio Bench (live panel, §1-L). Two
  rows: the **identity row** (specimen chip + font pill + size pill
  + ink dot — the "you are here" of typography, every element live)
  and the **aspect row** (سبک / چیدمان / بیشتر — three wide,
  state-carrying chips instead of six anonymous tiles).
* **The Font Room** — the all-fonts sheet becomes a two-column
  specimen gallery: the user's own words rendered large in every
  face, sectioned by category, live-previewed on the canvas behind a
  whisper barrier (highlight → preview, tap-again → pick; unchanged
  session semantics).

Every surface answers the contract questions structurally: the
identity row always shows the bound layer's actual font, size, ink
and treatment; the specimen chip is the permanent, obvious way back
to writing; the composer's ✕/تمام pair is the draft session's
cancel/commit; undo stays on the editor chrome.

## 3. The Studio Composer

`text_input_flow_sheet.dart`, rebuilt below the input:

* Header: title + ✕ (cancel) + commit pill (افزودن / تمام). The
  draft-session grammar is unchanged: cancel restores doc +
  selection, commit seals ONE history entry.
* Input: 1–3 line multiline hero field, autofocus, script-aware
  direction (all kept).
* **Style rail** (new, replaces the Bold+Colour bar):
  * **Font strip** — horizontal specimen chips of the recommended
    list for the content's script, each rendering the typed text
    (sample when empty) in its face; trailing «همهٔ فونت‌ها» chip
    opens the Font Room. Tap applies live through the session
    overlay — zero history until commit.
  * **Quick row** — current-ink dot (→ picker sheet) + six quick
    inks; size −/px/+ nudge; B/I/U toggles.
* Every control reads `stagedComposerStyle` and writes through
  `TextToolController` setters, which mid-session mirror onto the
  live overlay (the writer's existing rule). The composer can dress
  the text completely before it ever becomes a history entry.

## 4. The Studio Bench

`text_studio_bench.dart` (new), replacing `TextModeToolbar`'s
six-tile `SlotStrip`. Dock height 124 (108 compact) — the paint
bench's envelope, so mode switches reflow between two same-sized
benches.

**Identity row** — live state, each element a door:

| element | shows | tap |
|---|---|---|
| specimen chip | text excerpt rendered with the layer's full spec (face, ink, B/I/U, outline, shadow, plate) on an adaptive card + ✎ | Studio Composer (edit content) |
| font pill | family display name *in its own face* | Type sheet |
| size pill | visual px (the FittedBox-true readout) | Size sheet |
| ink dot | current colour with ring | Colour sheet |

**Aspect row** — three wide chips, each carrying its own state:

* **سبک** — active preset name (or «ساده») + tiny badges for live
  shadow/outline/plate. Opens the Look sheet (preset rail + B/I/U +
  effect sections — the existing `StylesBody`).
* **چیدمان** — current alignment glyph + direction badge when
  forced. Opens the Layout sheet: alignment, line height, letter
  spacing, **plus paragraph direction (auto/RTL/LTR segmented) and
  resize behaviour (scale/box toggle)** — moved home from «بیشتر»,
  where they were pop-then-dialog rows behind a full scrim.
* **بیشتر** — the layer overflow sheet, minus the two rows that
  moved (its text-specific rows die there).

Sheets keep the `SubToolSheet` chrome and sibling-swipe; sibling
order: type → size → color → look → layout.

**Quick capsule**: for text layers the capsule slims to ⋯ + ✎ — its
size and colour chips duplicated the identity row one gesture away.
Other layer kinds are untouched.

## 5. The Font Room

`font_picker/picker_sheet.dart` content rebuilt: the flat name list
becomes a **two-column specimen grid** — each card renders the
layer's excerpt (sample when empty) at display size in the candidate
face, caption underneath, category section headers between groups.
Script tabs, the whisper barrier, the highlight→preview debounce and
the tap-again-to-pick grammar are all kept verbatim — the session
semantics (§2: overlay preview, one command on pick, zero entries on
dismiss) were already correct.

## 6. What dies

* The six-tile registry + `SlotStrip` usage in
  `text_mode_toolbar.dart` (file replaced by the bench).
* `_AddTextQuickStyleBar` (composer rail replaces it).
* `text_resize_mode_picker.dart` and
  `text_direction_mode_picker.dart` dialogs — both controls become
  inline segmented rows in the Layout sheet. (Their icon/label
  helpers move with the callers that survive.)
* The «بیشتر» sheet's text-direction and resize-behaviour rows.
* The quick capsule's size + colour chips *for text layers only*.

## 7. What is deliberately kept

* The whole application layer: `TextStyleWriter` (sessions, the
  guarded execute gateway), `TextMetrics`, `TextColorResolver`,
  scope rules (§10 — a style write targets the bound layer;
  defaults only when nothing is bound).
* `InlineFontBody` (Type sheet), `SizeBody`, `ColorPickerBody`
  embed, `StylesBody` + effect sections, `LayoutPanel` (extended).
* Engine: `TextLayer` / `TextStyleSpec` / serialization —
  byte-identical fixtures are a gate, not a goal.
* Double-tap-to-edit on canvas, Done pill, E-level exits.

## 8. Test plan

* Bench: identity row shows font/size/ink truthfully (ValueKeys
  `text-specimen`, `text-pill-font`, `text-pill-size`,
  `text-ink-dot`, `text-aspect-look`, `text-aspect-layout`,
  `text-aspect-more`); pills toggle their sheets; specimen opens
  the composer.
* Composer rail: font chip tap stages overlay (zero history
  entries mid-session), commit seals one entry carrying the picked
  face; ink tap + B toggle same.
* Layout sheet: direction segmented writes
  `SetTextDirectionModeCommand` once; resize toggle writes
  `SetTextResizeModeCommand` once.
* Font room: grid renders per-script sections; highlight stages,
  pick commits one command, dismiss cancels (existing
  `text_input_flow_sheet_test` + new cases).
* Captures: `editor_text_bench_{light,dark}.png`,
  `editor_text_composer_light.png`, `editor_text_fontroom_light.png`
  variants in `editor_screen_capture_test.dart`.
