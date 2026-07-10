# Home Screen Redesign (v2 aesthetic) — July 2026

> Brings Home onto the calligraphy/paper-ink identity (`design-direction-v2-
> calligraphy-2026-07.md`). Home is the hub — the most-used screen after
> onboarding — so it gets the most care. Also retires the last of `WarmPalette`
> and the violet look here.

---

## Principle

**Calm chrome, colourful content.** The UI (header, cards, chips, labels) stays
quiet — paper/ink/saffron, hairlines, generous whitespace. The COLOUR comes from
the content: the user's project thumbnails and the template previews. This is
how premium design tools look, and it makes the user's work pop.

---

## Layout (top → bottom, scrollable)

1. **Header** (paper): app wordmark «کانواس» + the saffron-diamond brand mark
   (start); a settings icon in a quiet paper circle (end).
2. **Greeting**: headline «امروز چه بسازیم؟» (sans, `textPrimary`, ~22/700) +
   subtitle (`textSecondary`): «از یک قالب شروع کن یا طرحی تازه بساز.»
3. **Create row** — two equal cards:
   - «طرحِ جدید» — `primary` (ink) fill, cream label + saffron «+» icon. The
     main action.
   - «ویرایش عکس» — `surface` card, hairline border, ink label + icon.
4. **Recent work** (when projects exist): section label «کارهای اخیر» + a
   horizontal scroll of the user's project thumbnails, ending in a dashed
   «جدید» tile. **Empty state** (fresh user): hide the section, or a single
   quiet line — don't show an empty rail.
5. **Templates**: a header row — «قالب‌ها» (ink/700) + a «مشاهده همه» link
   (`accent`); filter chips (همه / فارسی / انگلیسی / ترکیبی) where SELECTED =
   ink-filled (cream text) and unselected = paper + hairline; then a 2-col grid
   of colourful template thumbnails (existing `TemplateThumb` / real previews).
   The templates carry the colour.

---

## Tokens / type / components

- Tokens only — paper/ink/saffron, no `WarmPalette`, no violet. Selected chip +
  links + accents use ink/saffron.
- Sans UI type throughout; optionally a small nastaliq flourish on the wordmark
  or a section header — restrained.
- Reuse `AppPrimaryButton`, `TemplateThumb`, `SectionLabel`. Add: a
  `QuickActionCard` (the create cards), a `FilterChip` (selected/unselected),
  a `ProjectThumb` (recent work). All token-driven, dark-aware.

## Dark mode

Deep-ink bg, cream text, brighter saffron; template + project thumbnails
unchanged (colour pops on ink too). Verify chip/selected contrast in both modes.

---

## Build sequence (commits)

1. **Chrome + create** — header, greeting, the two create cards, on tokens.
   Kill `WarmPalette` from the Home scaffold + these widgets. Widget test.
2. **Templates section** — header row + filter chips (`FilterChip`) + the
   template grid (`TemplateThumb`), tokens only. Keep the existing category/
   language filter logic; restyle only. Widget test (chip select, grid renders).
3. **Recent work** — the project row + the empty state. Widget test (populated +
   empty).

Check in with light + dark screenshots after each commit.

---

## Discipline

Tokens only (no hardcoded colours), dark verified, one concept per commit,
screenshot-iterate. Keep the chrome calm; let the content bring the colour.
