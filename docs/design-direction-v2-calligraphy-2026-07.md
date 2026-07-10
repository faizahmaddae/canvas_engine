# Design Direction v2 — Persian Calligraphy-Forward — July 2026

> Supersedes the welcome-screen portion of `design-system-welcome-screen-
> 2026-07.md`. The token/component *system* from that doc stays; this changes
> the token *values* (palette) and redesigns the welcome screen around Persian
> calligraphy. The pivot is from a generic tech look (violet hero + template
> cards) to a rooted, editorial identity where beautiful Persian lettering is
> the hero.

---

## The idea

The product's real differentiator is Persian typography. So the identity leads
with it: **large nastaliq lettering as the centerpiece — the type is the art —**
on a warm paper/ink palette with a single saffron accent, paired with a clean
modern sans for UI. Ornate script + modern UI + rooted palette reads as
premium, cultural, and unmistakably Persian — not a Canva clone, and not
old-fashioned.

---

## What changes / what stays

- **Token *system* stays** (from the previous doc). Only the token **values**
  change (palette below) — because everything reads tokens, the recolour
  propagates app-wide for free. This is the payoff of the token work.
- **Components stay** (`AppPrimaryButton`, `AppContentSheet`, `TemplateThumb`,
  `BrandMark`, `SkipTextButton`, `SectionLabel`) — reused on home/templates.
- **WelcomeScreen is redesigned**: card-showcase → calligraphy hero.

---

## Revised color tokens (light + dark)

| token | light | dark |
|---|---|---|
| `pageBg` | `#F4EEE1` (warm paper) | `#14110D` (deep ink) |
| `surface` | `#FBF7EF` | `#1E1A14` |
| `surfaceMuted` | `#EDE5D4` | `#26211A` |
| `textPrimary` (ink/cream) | `#1F1B16` | `#F2EADB` |
| `textSecondary` | `#6B6155` | `#A9A090` |
| `textMuted` | `#9C8F7C` | `#7C7264` |
| `border` | `#E3D9C6` | `#2E2820` |
| `accent` (saffron) | `#C0872A` | `#D4A24A` |
| `accentDeep` | `#A5731E` | `#C0872A` |
| `primary` / CTA fill | `#1F1B16` (ink) | `#F2EADB` (cream) |
| `onPrimary` | `#F4EEE1` | `#1F1B16` |

Category accents (template thumbs) stay — `rose #D87995` · `saffron #E5A044` ·
`teal #22B8A0` — they harmonise with the warm system.

---

## Type: nastaliq hero + sans UI

- **Hero display:** the app's own **nastaliq** font (e.g. `IranNastaliq` from
  the existing catalog), large, `textPrimary` (ink on paper / cream on ink).
  Nastaliq needs generous line-height (≈ 1.8–2.0) and vertical room.
- **UI text** (subtitle, buttons, labels): the current clean Persian sans.
- The contrast between the two — ornate script hero, quiet modern sans — is the
  whole aesthetic. Keep the UI type restrained so the calligraphy carries the
  beauty.

---

## Welcome screen (v2) layout

- **Canvas:** `pageBg` (warm paper / deep ink), generous margins, editorial.
- **Top row:** a small saffron diamond mark (start) + `SkipTextButton` (end).
  Restrained.
- **Centre (the hero):** large nastaliq display — «طرحی نو» — centred; a thin
  saffron flourish line beneath (≈ 38×2); then a clean-sans subtitle in
  `textSecondary`, max ~2 lines, explaining the app.
- **Bottom:** a refined CTA (`AppPrimaryButton`) — ink-filled on light,
  cream-filled on dark. Comfortable bottom padding (safe-area + ~20); no void.
- **Motion:** reuse the existing entry fade + slide. Optionally, the hero word
  cross-fades through a few Persian words (طرحی نو · بنویس · بیافرین) on a slow
  loop — subtle, one word at a time.
- RTL throughout; dark-mode native; compact-height handling reused.
- **Copy:** keep existing l10n keys; add one key for the new subtitle.

---

## Build sequence (commits)

1. **Recolour tokens to the v2 palette** (light + dark). `primary`/CTA = ink,
   `accent` = saffron. Verify the app builds and every existing screen adopts
   the new palette automatically (that's the point). Screenshot a couple of
   screens in both modes to confirm nothing breaks contrast.
2. **Redesign `WelcomeScreen` v2** — the calligraphy hero per the layout above,
   using the app's nastaliq font. Widget test; existing onboarding tests green.
   **Check in with light + dark screenshots after this.**

---

## Discipline

Tokens only (no hardcoded colours); dark verified for every change; one concept
per commit; screenshot light + dark and iterate. The calligraphy is the star —
keep everything around it quiet.
