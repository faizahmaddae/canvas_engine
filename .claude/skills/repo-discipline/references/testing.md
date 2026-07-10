# Writing tests in canvas_engine

The authoritative rulebook is `.github/instructions/tests.instructions.md`
(applies to `test/**/*.dart`). This file summarizes it and adds the traps the
rulebook doesn't spell out. When they disagree, the rulebook wins.

## Directory map

```
test/
├── engine/        pure Dart — the engine's math/model/commands/codec
│   └── fixtures/  serialization byte-identity corpus + generators (CI gate)
├── application/   Riverpod controllers
├── editor/        feature integration (own application/canvas/text/widget/… subdirs)
├── widget/        UI tests where Material is allowed
├── app/, core/, home/, onboarding/, settings/, templates/
└── support/       shared helpers (see below)
```

## Engine-test purity (convention-enforced — nothing will stop you but review)

Tests under `test/engine/` may import ONLY: `dart:math`, `dart:ui`,
`package:flutter/foundation.dart`, `package:flutter/painting.dart`,
`flutter_test`, and `package:canvas_engine/...`. Banned: `material.dart`,
`widgets.dart`, `flutter_riverpod`. If an engine test "needs" Material, it is
testing the wrong thing — move it to `test/widget/` or split the unit under
test. Note `tool/check_import_direction.sh` scans `lib/` only, so nothing
mechanical catches a violation in `test/` — discipline is on you.

## Conventions that reviews enforce

- Test names state the expected outcome ("translates by pointer delta", not
  "move test"). `group()` names the unit or behaviour cluster.
- Floats: never `expect(a.dx, b.dx)` — use `closeTo(expected, 1e-6)`. Tighter
  tolerances need a justifying comment.
- Compute expected values explicitly; never derive them from the code under
  test (accidental `expect(actual, actual)`).
- Build complex `EditorDocument` test data through the real
  `addLayer`/`replaceLayer` API, not by constructing internal state directly —
  synthetic state hides integration bugs.
- Coverage targets: `engine/core` = 100% of public methods (equality,
  `copyWith`, JSON round-trip); `engine/commands` = five patterns per command
  (forward, inverse, no-op, merge, history round-trip); `engine/interaction` =
  cardinal angles (0, π/2, π, 3π/2, plus one arbitrary); `engine/serialization`
  = every layer type round-trips + every malformed-input branch throws
  `DocumentDecodeException`.
- If an engine test you didn't write fails after your change: default
  assumption is your regression. Never change expectations to make it pass;
  stop and discuss.

## The fake-async zone (source of most mysterious test hangs)

`testWidgets` bodies run in a fake-async zone where **real `dart:io` /
image-codec futures never complete**. Rules:

- Real file IO, `toImage`, PNG encoding → wrap in `await tester.runAsync(...)`.
- The inverse trap: **futures created inside `runAsync` don't resume in the
  fake zone.** So: perform taps/pumps in the fake zone, enter `runAsync` only
  to let the real-IO future land, then return.
- `test/support/temp_projects_dir.dart` → `tempProjectsDir()`: deliberately
  synchronous (`createTempSync`) because an async variant deadlocks; registers
  its own `addTearDown`. Wire via
  `ProviderContainer(overrides: [projectsDirectoryProvider.overrideWith((ref) async => dir)])`.
  Hydrate the store inside `runAsync`:
  `await container.read(projectStoreProvider.future)` and any `upsert()` calls.
  Reuse one dir across containers to simulate app restarts; seed projects with
  distinct `lastModified` timestamps when order matters.
- `test/support/fake_path_provider.dart` → `installFakeDocumentsDir()`: fakes
  `getApplicationDocumentsDirectory` (EditJournal, thumbnails) without platform
  channels; auto-cleans in teardown.

## Pump discipline

- `pumpAndSettle` hangs forever on looping animations. Settle transitions with
  a bounded pump instead: `tester.pump(const Duration(milliseconds: 600))` for
  the onboarding `AnimatedSwitcher`, etc. Prefer plain `pump()` unless you
  genuinely need animation time — `pumpAndSettle` hides timing bugs.
- **The double-tap window (300 ms; pump 400 ms past it):** the editor canvas
  root `GestureDetector` owns `onDoubleTapDown`, so every in-canvas single tap
  resolves only after Flutter's 300 ms double-tap window (`kDoubleTapTimeout`)
  lapses. After tapping floating-bar pills (text, paint, shape bars alike),
  `tester.pump(const Duration(milliseconds: 400))` — the margin over 300 ms is
  deliberate, and `pumpAndSettle` alone never lapses the window.
- `EditorCanvas` hides itself until its first auto-fit lands; capture/editor
  tests need a couple of extra `pump()`s (plus the 400 ms) before the canvas
  is visible.

## ValueKey naming (cross-feature tests depend on the exact strings)

Kebab-case `<feature>-<element>[-<id>]`. Families in use:
`home-template-<id>`, `home-recent-<id>`, `home-recent-new-tile`,
`home-{recent,templates}-see-all`, `home-create-new`, `home-edit-photo`,
`browse-category-<cat>`, `browse-language-<lang>`,
`browse-template-tile-<id>`, `onboarding-welcome-skip`,
`onboarding-get-started`, `onboarding-goal-<category>`,
`onboarding-goal-{continue,skip}`, `color-picker-*`, `add-text-{input,confirm}`,
`effect-row-<index>-<type>` (data index into the effect stack + effect type,
e.g. `effect-row-0-shadow`), `effect-{shadow,border,background}-color`,
`size-picker-create`, `canvas-bg-mode-{color,transparent}`,
`crop-aspect-strip`, `palette-{open,closed}`.

Find widgets exclusively via `find.byKey(const ValueKey('...'))`. When adding
UI a test needs to reach, add a key in the matching family — onboarding-flow →
Home-grid tests already cross feature boundaries on these strings.

## Token-contract tests (how dark-mode flips stay locked)

Find the widget by ValueKey, then compare its decoration/background directly
against `AppTokens.light` / `AppTokens.dark` constants (e.g. selected chip
color == `AppTokens.dark.brand`). See
`test/templates/templates_browse_v2_test.dart` for the pattern. Changing token
values means updating `test/app/theme/app_tokens_test.dart`, which pins the v2
contract to `docs/design-direction-v2-calligraphy-2026-07.md`.

## Serialization fixtures (the CI byte-gate)

- Byte-identity tests decode each committed fixture JSON, re-encode, and expect
  `'${DocumentCodec.encode(doc)}\n'` to equal the raw file exactly (trailing
  newline included).
- The `_generate_*_fixtures_test.dart` files are ordinary untagged tests, so
  `flutter test test/engine/fixtures` **rewrites fixtures 01–04 in place**.
  After running, `git status` the fixtures dir: an unexpected diff = your
  change altered the wire format. Only commit fixture diffs for a deliberate,
  version-bumped schema change.
- `v2/05_image_with_crop_and_adjustments.json` is FROZEN (legacy `adjustments`
  shape can no longer be emitted); excluded from the byte gate, covered by
  `v2_legacy_lift_test.dart`; the generator asserts it still exists.
- `schema_coverage_test.dart` asserts every supported schema version
  (`minSupportedSchemaVersion..schemaVersion`) has ≥1 fixture whose stamped
  `"version"` matches its bucket. The codec stamps the MINIMUM reader version a
  document requires — a legacy-shape doc writes v1 even on a v3-aware build;
  that is intended. Adding a schema version = add a bucket + fixture there.

## Capture tests

See SKILL.md §Screenshot gate for the inventory and mechanics. Capture tests
assert almost nothing — they exist for design review; `build/` is gitignored.
Fonts: `FontLoader` per family used from `assets/fonts/`, MaterialIcons from
`$FLUTTER_ROOT/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf`
(silently skipped if `FLUTTER_ROOT` unset → tofu icons, capture still writes).
