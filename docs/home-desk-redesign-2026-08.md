# Home Desk Redesign («میز کار») — August 2026

> Supersedes the *layout* sections of `home-screen-redesign-2026-07.md`
> and amends one rule in `app-navigation-home-ia-2026-07.md` (the
> dashed «جدید» tile is retired). The launcher/browser IA split, the
> bounded-height invariant, and the calm-chrome token rules from those
> docs still stand unchanged. Shipped on `feat/home-desk-redesign`
> as four commits tagged `(home desk N/4)`.

---

## Why (the verdict)

The 07-2026 Home was structurally right and experientially flat — an
index, not a desk. Findings, in severity order:

1. **"Continue my work" — the #1 daily job — rendered weakest.** A
   110×140 thumb, second in the rail behind a dashed «جدید» tile that
   duplicated the create row 150dp above it.
2. **A static screen making a daily promise.** «امروز چه بسازیم؟» over
   the same ten templates in the same order forever; a subtitle that
   described the two buttons below it.
3. **Creation paid a dialog toll** — nine icon rows in five labelled
   groups, floated as framework Dialog chrome in an all-sheets app.
4. **Chrome:content inverted** — ~290dp of near-empty ink/paper on
   top; the user's work the smallest thing on screen.
5. **Rails lied about shape** — templates cover-cropped to one 0.73
   portrait; projects letterboxed inside the same frame.

## The desk

Home is the desk you left last night: the work sits on top, big
enough to recognise; making something new is one tap; the suggestion
shelf changes every day.

### 1 — Continue hero (`ContinueCard`, commit 1)

The top slot always holds the **most recent act**:

* **Draft mode** — the recovery journal's unsaved session. Successor
  to `ResumeDraftCard` with its action weights intact: Resume is the
  filled button (and the whole card); «نه حالا» behind «⋯»; delete one
  level deeper, confirmed by the caller. Keys carried verbatim
  (`home-resume-draft`, `resume-draft-*`) — the lifecycle tests are
  the contract.
* **Project mode** — the newest saved project, name + relative time,
  no overflow (saved-project management belongs to the Projects tab).
  Key `home-continue-project`, button `home-continue-open`.

The preview is a live document render at the canvas's true ratio
(shared band, see §4), width-capped at 42% of the card so narrow
screens never starve the title column. Draft previews go through
`DocumentJsonPreview` — extracted from `ProjectPreview` so journal
JSON and saved projects share one cascade.

The rail below takes `skipNewest` when the hero shows a project, so
one design never appears twice. The dashed «جدید» tile is dead: the
create row is 150dp above, and the rail's prime RTL-start slot
belongs to work.

### 2 — Format sheet (`SizePickerSheet`, commit 2)

`SizePickerDialog` is dead app-wide (Home create + canvas-panel
resize). The sheet is a three-across grid of **aspect-true ghost
tiles** — the ghost IS the taxonomy, so the five group labels died
with the row icons. Contract carried byte-for-byte: `CanvasSize` with
localized preset label, the ONE shared 16..8000 ceiling (P2-20),
locale digit seeding + Persian-numeral folding, «W × H» in an
explicit LTR subtree.

**Binding layout rule (tb5 9/9, relearned the hard way):** only the
format grid scrolls; the custom form and CTA are pinned below it,
always on screen. The first draft broke this and a missed test tap
hung the runner on an awaited never-popping sheet — the sheet tests
now assert the pop before awaiting the result.

### 3 — Living shelf + daypart greeting (commit 3)

* «پیشنهادی» → **«پیشنهادِ امروز»**, selected by `dailyTemplateShelf`:
  a date-seeded shuffle drawn ONLY from the top-20 slice of the
  curated order — stable within a day, different tomorrow, and the
  quality-batch tail never surfaces. The rail takes injectable
  `today`; determinism is pinned at the pure-function level.
* A saffron **daypart line** (صبح/ظهر/عصر/شب بخیر — hour bands
  [5,11) / [11,15) / [15,20) / else) above the headline; the static
  subtitle is deleted. `HomeHeader` takes injectable `now`.
* **Testing consequence:** cross-feature tests must NOT pin specific
  template ids on the shelf — pin wiring and filters (thumbs render;
  disabled categories never appear) instead.

### 4 — Honest rails (commit 4)

Tile width = canvas ratio × fixed rail height, through one shared
band — `lib/app/ui/thumb_ratio.dart` (`0.62..1.5`) — used by the hero
and both rails. Projects use stored width/height. `Template` carries
no dimensions **deliberately**; the template rail maps category →
canonical format ratio (stories 9:16, video 16:9, posters 4:5,
quote/poetry 1:1), exact for every bundled template.

**Deliberately not unified:** the rails' caption grammars. Template
labels stay inside the category-colour frame (that colour encodes
meaning on the welcome showcase and browse teasers sharing
`TemplateThumb`); project captions stay beneath the card. Ratio
honesty was the defect; the grammar split is identity.

---

## Visual proof

`nav_shell_capture_test.dart` writes `home_{light,dark}.png`,
`home_draft_{light,dark}.png`, and the desk variant
`home_desk_{light,dark}.png` (seeded projects, three ratios).
`size_picker_sheet_capture_test.dart` writes
`size_picker_sheet_{light,dark}.png`. The full stack was also
verified on the iOS Simulator (iPhone 17 Pro Max), light + dark,
including the live draft→promotion hero handoff and the one-tap
استوری create path.
