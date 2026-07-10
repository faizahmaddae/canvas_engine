# Design System (Vibrant / Direction C) + Welcome Screen — July 2026

> First UI-quality deliverable (Workstream B). Establishes the app's design
> **language** — color/type/spacing tokens + core components, **light AND dark**
> — from the chosen Direction C, and rebuilds the welcome screen on top of it.
> This is the **seed**: every later screen extends it, and it replaces the
> per-screen palettes (`OnboardingPalette`) incrementally. Persian-first, RTL,
> dark-mode native from day one.
>
> Values below are concrete and opinionated — tweak the hex/sizes if you want a
> different feel, but keep the token/component structure.

---

## 1. Color tokens (light + dark)

Introduce these as a `ThemeExtension` (`AppTokens`) with a light and a dark
instance, wired into `app_theme`. **No screen hardcodes colors again — tokens
only.** Mental test for every value: still readable if the background were
near-black?

**Brand (violet):**
| token | light | dark |
|---|---|---|
| `brand` | `#7C5CFF` | `#7C5CFF` |
| `brandStrong` (large fills / hero) | `#6A4BF0` | `#6A4BF0` |
| `brandPressed` | `#5A3BD6` | `#5A3BD6` |
| `brandSoft` (tint) | `#F1ECFF` | `#241E3A` |
| `onBrand` (text/icon on brand) | `#FFFFFF` | `#FFFFFF` |

**Category accents** (template thumbs — these encode meaning, reuse app-wide):
`rose #D87995` · `saffron #E5A044` · `teal #22B8A0` · (`brand` violet). Each with
a dark on-text stop for labels (`#5A1E2E` / `#5A3B10` / `#0C3D34`).

**Neutrals / surfaces:**
| token | light | dark |
|---|---|---|
| `pageBg` | `#FBFAF7` | `#0E0E13` |
| `surface` (cards/sheets) | `#FFFFFF` | `#17161D` |
| `surfaceMuted` | `#F4F1EC` | `#1F1E27` |
| `textPrimary` | `#17151F` | `#F5F3F8` |
| `textSecondary` | `#6A6472` | `#B4AEC0` |
| `textMuted` | `#9A93A2` | `#7C7688` |
| `border` (hairline) | `#EAE5DF` | `#2A2833` |

---

## 2. Type scale (Persian-first)

Use the app's primary Persian UI sans (the current onboarding font). RTL is the
default; Persian needs generous line-height.

| role | size | weight | line-height |
|---|---|---|---|
| display (hero) | 44 | 900 | 1.05 |
| titleLg | 23 | 900 | 1.4 |
| title | 18 | 700 | 1.5 |
| body | 15 | 400/500 | 1.85 |
| caption | 13 | 500 | 1.6 |

---

## 3. Radius / spacing / elevation / motion

- **Radius:** pill/button `14`, card `16`, sheet-top `26`, thumb `12`. Reconcile
  with the existing `AppRadii` (extend, don't duplicate).
- **Spacing:** reuse the existing `AppSpacing` (sm/md/lg/xl); add steps only if
  a gap is missing.
- **Elevation:** mostly flat — colour blocks do the work. The content sheet gets
  ONE soft top shadow to lift it off the colour hero. No decorative shadows.
- **Motion:** reuse the existing entry fade + slide (≈400–600 ms `easeOutCubic`)
  the current welcome screen already uses.

---

## 4. Core components (the seed — build these, then reuse app-wide)

Each is token-driven and dark-mode-aware by construction. These replace the
one-off copies the review flagged.

- **`AppPrimaryButton`** — full-width, `brand` fill, `onBrand` text, radius 14,
  weight 700, pressed state. Replaces `OnboardingPrimaryButton`; becomes the
  app-wide primary CTA (kills duplicate button styles).
- **`AppContentSheet`** — a `surface` container, top corners radius 26, one soft
  top shadow, standard padding. The "rising sheet" used on welcome — reusable
  for every bottom-sheet/panel later (this is the seed that retires the 3
  parallel overflow-sheet implementations).
- **`TemplateThumb`** — rounded card (radius 12), category-colour fill, a mini
  preview/label. Reused on home + templates.
- **`BrandMark`** — the app identity mark (placeholder glyph for now).
- **`SkipTextButton`** — muted top skip (`textMuted`).
- **`SectionLabel`** (caption/eyebrow) — small labelled text.

---

## 5. Welcome screen build (Direction C)

Structure: a **colour hero** (top ~55%, `brandStrong` fill) with a **rising
`AppContentSheet`** below.

- **Hero:** `BrandMark` at top-start, `SkipTextButton` at top-end (RTL → skip
  sits on the left). Centre: a showcase of 3 `TemplateThumb`s from real
  templates, slight alternating rotation (≈ ±6°) for energy.
- **Sheet:** title (titleLg) + tagline (body / `textSecondary`) +
  `AppPrimaryButton`.
- **Dark mode:** hero → `brandStrong` (deeper violet), sheet → `surface`
  (`#17161D`), text flips to light. The violet hero reads well in both modes.
- **RTL** throughout; entry fade + slide (reuse existing); keep the current
  **compact-height** responsive handling (`constraints.maxHeight < 650`).
- **Copy:** reuse the existing l10n keys (`onboardingWelcomeTitle`,
  `onboardingWelcomeTagline`, `onboardingGetStarted`, `onboardingSkip`) — adjust
  the strings if you like, but keep the keys so fa/en parity stays intact.

---

## 6. Migration / scope

- Add `AppTokens` (light + dark `ThemeExtension`) alongside `app_theme`; wire the
  welcome screen to it.
- Route the welcome screen's colours through tokens and **remove its
  `OnboardingPalette` usage**. The other onboarding screens (Goal / Ready), home,
  and the editor migrate to tokens **as we rebuild each** — NOT in this step.
  (Leaving `OnboardingPalette` in place for Goal/Ready this commit is fine.)
- Keep the onboarding flow (Welcome → Goal → Ready → Home) fully working; the
  existing onboarding tests stay green.

---

## 7. Build sequence (commits)

1. **Tokens + type scale.** `AppTokens` ThemeExtension (light + dark), type
   roles, radius reconcile. Test: tokens resolve in both modes; theme builds.
2. **Core components** (§4) on tokens. A widget test per component, incl. a
   dark-mode render check.
3. **Rebuild `WelcomeScreen`** (Direction C) from the components; drop its
   `OnboardingPalette` usage. Widget test: renders, CTA + skip dispatch, RTL,
   dark mode. **Check in for review after this.**

---

## Discipline (UI edition)

- One concept per commit (tokens → components → screen).
- No byte-identity gate here, but: existing onboarding widget tests stay green;
  add a widget test for every new component and the screen.
- Dark mode verified for every new component (readable on near-black?).
- No hardcoded colours anywhere — tokens only. This rule is the whole point:
  it's what stops the next screen from drifting.
