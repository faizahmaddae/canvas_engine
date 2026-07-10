---
name: repo-discipline
description: >-
  How to work in the canvas_engine repo: required reading order, per-surface
  doc routing, the verification gates that must pass before any commit, test
  recipes, commit-message style, and the repo's known traps. Use this for ANY
  task in this repository that reads or changes code, tests, templates, l10n,
  theme, or docs — even a one-line fix — BEFORE writing the first line. Also
  use when writing a commit message, adding a template/font/effect/layer type,
  producing screenshots, or deciding whether to ask before proceeding.
---

# Working in canvas_engine

Persian-first (RTL-default), bilingual fa/en Flutter design/photo-editor.
Two worlds share the repo: the **editor engine** (`lib/features/editor/engine/`,
strict `engine → application → presentation` layering, immutable document,
pure commands) and the **app shell** (nav/home/templates/onboarding, token-driven
design system). The engine's hard rules live in `AGENTS.md` at the repo root —
that file is law. This skill does not repeat it; it teaches the *process* around
it and the traps the law doesn't mention.

## Before you code: read in this order

1. **`AGENTS.md`** — hard rules (immutability, pure commands, `invert()`
   semantics, `withTransform` field preservation, serialization backward-compat,
   no magic numbers, explicit coordinate spaces). If your change touches
   `lib/features/editor/engine/`, these are non-negotiable and CI-adjacent
   tests enforce most of them.
2. **`CLAUDE.md`** — commands, app-shell architecture, design-system rules.
3. **The doc for your surface** (routing table below). This repo's docs are not
   decoration: tests cite doc sections as their executable spec. Before changing
   behaviour a doc specifies, run `grep -rn "docs/" test/ --include='*.dart'`
   filtered to that doc's filename — the hits are the contract tests you will
   break.
4. **Writing or touching tests?** `.github/instructions/tests.instructions.md`
   is the authoritative test-writing rulebook (import allowlist for engine
   tests, float tolerance, coverage targets, the never-edit-a-failing-test
   rule). Read it before your first test edit.

### Doc routing table

| Touching | Read first |
|---|---|
| Anything under `engine/` | `docs/architecture.md` + `AGENTS.md` |
| Effects (`engine/effects/`) | `docs/effects.md` (its status block lists where code deliberately diverges — **code wins**) + `docs/effects-a3-scoped-plan-2026-07.md` (placeholder holding only §7, the stackMask compositing decision) |
| Per-effect mask rendering | `docs/effects-step6-per-effect-masks-2026-07.md` |
| Mask edit mode | `docs/mask-edit-mode-design-2026-07.md` |
| Editor chrome / toolbars / panels | `docs/editor-redesign-2026-07.md`, `docs/editor-phase2-toolbar-system-2026-07.md` |
| Text tool | `docs/text-tool-redesign-2026-07.md` |
| Editor UI primitives (`lib/features/editor/ui/`) | `docs/phase4-ui-foundation-plan-2026-07.md` — its §1 non-goals are binding: chip-grammar unification and SlotStrip migration are PARKED; do not "clean them up" in passing |
| Tokens / theme / any app-shell visual | `docs/design-direction-v2-calligraphy-2026-07.md` (current identity; violet anywhere is a bug) |
| NavShell / tabs / Home | `docs/app-navigation-home-ia-2026-07.md` + `docs/home-screen-redesign-2026-07.md`. Core invariant: Home is a bounded launcher — its length never grows with content |
| Templates | `docs/template-product-quality-plan.md` (what to build) + `references/traps.md` §Templates in this skill (how to register) |

Stale-banner warning: several docs still say "awaiting sign-off (2026-07-03)"
(`effects-step6`, `mask-edit-mode-design`, `phase4-ui-foundation-plan`) but the
designs **shipped** — tests cite their sections. Trust code and tests over
banners. `docs/product-audit-2026-05.md` and `docs/editor-engine-core-audit.md`
are historical; `docs/template-catalog-cleanup-plan.md` has stale counts (the
generated `docs/template-system-audit.md` has the real numbers).

## The task loop

1. **Scope one concept.** This repo's history is one-concept-per-commit with
   large efforts split into independently-shippable numbered stacks
   (`(hardening 3/5)`, `(2A, commit 5/5)`). If your task needs more than ~12
   files, split it into a stack, and for cross-cutting refactors (>5 files)
   propose the plan in chat first (AGENTS.md rule).
2. **Read the surface before editing it.** Build understanding from the real
   files, not from doc summaries.
3. **Edit.** Match the surrounding code's comment density (comments explain
   *why*; see `InteractionEngine.updateGesture` for the bar). No hardcoded
   colours in presentation code — `AppTokens.of(context)` in the app shell;
   ColorScheme reads are tolerated inside the editor only. No magic numbers in
   math code — they go in `lib/core/constants/engine_constants.dart` with a
   justifying comment.
4. **New user-facing string?** Add the key to **both** `lib/l10n/app_en.arb`
   and `app_fa.arb` (flat lowerCamelCase; placeholder metadata as a compact
   one-liner: `"@minutesAgo": {"placeholders": {"count": {"type": "int"}}}`),
   run `flutter gen-l10n`, and **commit the regenerated**
   `lib/l10n/app_localizations*.dart` files — they are tracked. Then check
   `untranslated_messages.txt` still reads `{}`; anything else means you missed
   a locale. Access strings via the `context.l10n` extension
   (`lib/l10n/l10n.dart`), not `AppLocalizations.of(context)`. The one
   sanctioned hardcoded Persian string is the `طرحی نو` wordmark in
   `welcome_screen.dart`.
5. **Verify** (see gates below).
6. **UI change? Screenshot-gate it** (see below).
7. **Commit** (see style below).

## Verification gates — run what CI runs

CI (`.github/workflows/ci.yml`, Flutter pinned 3.41.7 — bump deliberately and
locally first, never implicitly) runs, in order; each failing step fails the
build:

```bash
bash tool/check_import_direction.sh   # layering: engine imports nothing from
                                      # application/presentation/app; application
                                      # imports nothing from presentation
flutter analyze                       # must be clean; lints are stock flutter_lints
flutter test test/engine/fixtures     # serialization byte-identity gate (own step
                                      # so codec regressions fail legibly)
flutter test                          # full suite (~1700 tests, ~35s)
```

Also run `dart format lib/ test/` on touched files — the formatter is
authoritative.

**Fixture-step subtlety:** `flutter test test/engine/fixtures` also executes the
`_generate_*_fixtures_test.dart` generators, which **rewrite fixtures 01–04 on
disk**. After running it, check `git status` on `test/engine/fixtures/` — an
unexpected diff means your change altered the wire encoding: that is a
serialization regression, not a file to commit. (Exception: a deliberate,
version-bumped schema change, where the fixture diff is the reviewed artifact.)
`v2/05_image_with_crop_and_adjustments.json` is FROZEN — never regenerated; its
legacy shape can no longer be emitted and read-side compat is asserted by
`v2_legacy_lift_test.dart`.

**If an engine test you didn't write fails**, the default assumption is that
your change regressed. Never edit expectations to make it pass. If the new
behaviour is intentional, stop and write up the rationale in chat first.

Do not run `build_runner`. The repo has zero `*.g.dart`/`*.freezed.dart` files;
all `part` directives are hand-written library splits and serialization is the
hand-written `DocumentCodec`.

## Screenshot gate (any visual change)

There is no golden/emulator infra. Design review comes from RepaintBoundary
**capture tests** that write PNGs to `build/test_exports/` (gitignored):

| Surface | Test | Writes |
|---|---|---|
| Editor | `test/editor/widget/editor_screen_capture_test.dart` | `editor_{light,dark}.png` + selection/panel/filters/font-panel variants |
| Home / nav shell | `test/app/navigation/nav_shell_capture_test.dart` | `home_{light,dark}.png` |
| Size picker | `test/widget/size_picker_dialog_capture_test.dart` | `size_picker_dialog.png` |

Workflow: run the relevant test with plain `flutter test <path>`, then **open
and actually look at both light and dark PNGs**. Extend the existing capture
file with a new variant rather than inventing new infra. Mechanics if you must
add one: 440×956 viewport at DPR 1.0, `boundary.toImage(pixelRatio: 2.0)`
inside `tester.runAsync`, fonts loaded via `FontLoader` from `assets/fonts/`
plus MaterialIcons from
`$FLUTTER_ROOT/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf`
(without it, icons render as tofu). Editor captures run in the `fa` locale on
purpose — RTL is the product default.

## Commit style (mined from this repo's actual history)

- Format: `type(scope): summary` — types actually in use: `feat`, `refactor`,
  `fix`, `docs`, `test`, `polish` (visual-refinement-only), `chore`, `ci`.
  Scopes are lowercase feature areas (`editor`, `text`, `engine`, `home`,
  `theme`, …), occasionally nested (`editor/text`). Subject: English,
  lowercase after prefix, present tense, often "what changed - user-visible
  effect"; no strict length cap (median ~69 chars).
- Multi-commit workstreams carry a series tag in the subject:
  `(chrome 2/3)`, `(text redesign 3-A, part 2)` — tying back to the named plan
  in `docs/`.
- **Bodies are near-universal** and hand-wrapped ~72 cols. Fix bodies are
  root-cause narratives: failure mechanism → the fix → the regression test
  added (usually the closing sentence). Refactor bodies assert behaviour
  preservation ("token-stream identity, modulo declared renames") and state
  end-state metrics.
- **Call out deletions explicitly** — "orphan" is the repo idiom ("Deletes the
  three widgets this redesign fully orphans"). Delete orphaned files in the
  same commit that orphans them.
- **Say what you deliberately left undone or kept** ("the onboardingReady*
  keys stay for now (harmless; a copy pass can prune them)").
- UI commits record their visual proof: either the capture PNG pair added or
  "Verified on the simulator light + dark".
- Trailer: `Co-Authored-By: Claude <model> <noreply@anthropic.com>`. Nothing
  else — no issue refs, no Signed-off-by, no emojis.
- History is linear on `main` (zero merge commits); experiments live on
  `spike/<name>` branches.

## When to stop and ask (from AGENTS.md, enforced here)

- New engine concept (effect, mask, blend, group…) → ask for the design doc
  before coding.
- Cross-cutting refactor touching >5 files → propose plan, get approval,
  execute one file at a time.
- Anything changing the `EditorCommand` / `EditorLayer` / `EditorDocument`
  API → flag as breaking, explicitly.
- A rule in AGENTS.md contradicts deliberate-looking code → flag in chat; do
  not silently "fix" either side.

## Deep references (read on demand)

- **`references/testing.md`** — read before writing or modifying any test:
  directory map, engine-test import allowlist, `test/support/` helpers, the
  fake-async-zone rules (`tester.runAsync` traps), pump discipline (when
  `pumpAndSettle` hangs, the 400 ms double-tap window), ValueKey naming
  families, token-contract test pattern, fixture/byte-gate mechanics, coverage
  targets.
- **`references/traps.md`** — read before touching templates, text/fonts,
  RTL layout, theme/tokens, the colour picker, or editor panels: verified
  gotchas that have each already cost a debugging session (the `fillOpacity`
  alpha trap, Persian `letterSpacing`, glyph coverage, physical-geometry pads,
  the wheel-never-scrolls rule, template registration checklist and its two
  byte/content-gated docs, …).
