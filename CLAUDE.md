# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Read AGENTS.md first

`AGENTS.md` at the repo root is the **single source of truth** for the
engine's hard rules (immutability, pure commands, `invert()` semantics,
`withTransform` field preservation, serialization backward-compat, no
Material imports in engine tests, no magic numbers, explicit coordinate
spaces). It also contains the canonical recipes for adding a layer type
or an effect. Do not duplicate or contradict it — this file only adds
what it doesn't cover: commands, and the app-shell/design-system layer
that postdates it.

## Commands

```bash
flutter test                              # full suite (~1600 tests, ~35s)
flutter test test/engine/                 # pure engine tests (no Material allowed)
flutter test test/onboarding/welcome_screen_test.dart          # one file
flutter test path/to/file.dart --name "part of a test name"    # one test
flutter analyze                           # must be clean before any commit
dart format lib/ test/                    # formatter is authoritative; run on touched files
flutter gen-l10n                          # regenerate after editing lib/l10n/app_{en,fa}.arb
bash tool/check_import_direction.sh       # engine→application→presentation layering gate
flutter run -d <device-id>                # iOS Simulator is the usual target
```

CI (`.github/workflows/ci.yml`) runs: import-direction check → analyze →
`flutter test test/engine/fixtures` (serialization byte-identity gates) →
full suite. All four must pass.

## Big picture

Persian-first (RTL-default), bilingual fa/en Flutter design/photo-editor
app. Two largely separate worlds share one codebase:

1. **The editor engine** — `lib/features/editor/engine/` with strict
   `engine → application → presentation` layering (see AGENTS.md and
   `docs/architecture.md`). Immutable `EditorDocument`, pure commands +
   undo history, per-layer-type modules, one serialization codec.

2. **The app shell** — everything the user sees before the editor:
   - `lib/app/navigation/nav_shell.dart` — root `NavShell` with a bottom
     tab bar (Home · Templates · Projects). Tabs build lazily on first
     visit and stay alive in an `IndexedStack`. The active-tab index is a
     provider (`navShellIndexProvider`) so Home's "see all" links jump to
     tabs instead of pushing routes.
   - Home (`lib/features/home/`) is a bounded **launcher**: create row +
     horizontal rails. All content growth lives in the Templates tab
     (`templates_browse_screen.dart`, the full search/filter browser) and
     the Projects tab (`recent_projects_grid.dart`). Never add unbounded
     vertical content to Home.
   - Onboarding (`lib/features/onboarding/`) is two screens:
     Welcome → Goal → Home.

## Design system (v2 "calligraphy" direction — paper/ink/saffron)

The visual identity is warm paper/ink neutrals + a saffron accent.
Violet is dead; if you see it, it's a bug.

- **`AppTokens`** (`lib/app/theme/app_tokens.dart`) — a `ThemeExtension`
  with light/dark instances; resolve via `AppTokens.of(context)`.
  Key invariant: `brand`/`onBrand` **swap** across modes (ink CTA on
  light, cream CTA on dark); the category accents (rose/saffron/teal)
  stay fixed across modes.
- **Rule: tokens only.** No hardcoded colours in presentation code. The
  Material `ColorScheme` in `AppTheme` is itself pinned to the tokens,
  so scheme-reading widgets are acceptable inside the editor, but new
  app-shell UI should read `AppTokens` directly.
- **Type**: `AppTypeScale` (`app_typography.dart`) roles deliberately
  omit `fontFamily`/`color` — family inherits from the theme (locale-
  aware: Vazir for fa, Hanken Grotesk for Latin, with Vazir leading the
  Latin fallback chain so Persian renders identically under every
  locale); colour comes from tokens at the call site.
- Shared components live in `lib/app/ui/` (`AppPrimaryButton`,
  `AppContentSheet`, `AppFilterChip`, `TemplateThumb`, `ProjectThumb` +
  `EmptyDesignPlaceholder`, `BottomTabBar`, `SaffronDiamond`, …).
  Editor-scoped primitives live in `lib/features/editor/ui/`
  (`EditorSliderRow`, `PrecisionDisclosure`, …) — the two sets are
  deliberately separate; don't merge them.
- Every new user-facing string is an l10n key in **both**
  `lib/l10n/app_en.arb` and `app_fa.arb` (fa/en parity), then
  `flutter gen-l10n`. Persian copy in design docs is intended copy, not
  a literal to hardcode. Exception: «طرحی نو» on the welcome screen is a
  deliberate non-localized brand wordmark.

## Working discipline (established in this repo's history)

- **One concept per commit.** Delete orphaned files in the same commit
  that orphans them, and say so in the message.
- UI work is **screenshot-gated**: verify light AND dark on the iOS
  Simulator before committing visual changes
  (`xcrun simctl ui <udid> appearance dark|light`). RTL is the default —
  use `EdgeInsetsDirectional`/`PositionedDirectional`/`AlignmentDirectional`,
  and remember chevrons don't auto-mirror.
- Widget tests pin token contracts (fills, borders, dark-mode flips) via
  `ValueKey`s — follow the existing key naming (`home-template-<id>`,
  `browse-template-tile-<id>`, `onboarding-goal-<category>`, …) since
  cross-feature tests (onboarding flow → Home grid) rely on them.
- Tests that need the project store use the
  `test/support/temp_projects_dir.dart` + `tester.runAsync` hydration
  pattern (real file IO can't run in the fake-async zone); seed projects
  with distinct `lastModified` timestamps when order matters.
- `pumpAndSettle` hangs on looping animations — use bounded pumps
  (`tester.pump(const Duration(...))`) like the existing tests do.

## Where design intent lives

`docs/` holds dated design docs that are the source of truth for *why*
surfaces look the way they do. Most relevant for current work:
`design-direction-v2-calligraphy-2026-07.md` (palette/type),
`app-navigation-home-ia-2026-07.md` (launcher/browser split),
`home-screen-redesign-2026-07.md`, `editor-redesign-2026-07.md`,
`effects.md` + `effects-a3-scoped-plan-2026-07.md` (effect system,
required reading before touching effects), and
`mask-edit-mode-design-2026-07.md`.
