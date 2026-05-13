# Product Audit — 2026-05

Comprehensive audit of the Canvas Engine project. Findings ordered by
**severity × impact × dependencies**. Each item carries a triage tag
and an effort estimate (S = days, M = weeks, L = ~month, XL = multi-month).

Status legend (live progress): `[ ]` open · `[~]` in progress · `[x]` done
(this session) · `[-]` deferred (needs design / out of session scope).

> Source: brutal product audit, May 2026. See chat history for the full
> ~4,000-word write-up. This file is the actionable extract.

---

## Tier 0 — Quick wins this session

These are unambiguous, low-risk fixes with outsized perceived-quality impact.
They do **not** require design discussion and can be done by a single
contributor in one sitting without changing the engine contract.

- [x] **Dark mode is hardcoded.** `lib/app/app.dart:22` sets
  `themeMode: ThemeMode.dark`. A perfectly good light theme exists in
  `app_theme.dart` but is unreachable. Switch to `ThemeMode.system`.
  🔴 **High UX impact, S.**
- [x] **Stray `debugPrint` in production code.**
  `lib/features/editor/presentation/widgets/selection_overlay.dart:486`
  prints handle hitboxes on every layout pass. Wrap in `kDebugMode` or
  remove. 🟡 S.
- [x] **`PaintLayer` constructor does not enforce immutability of
  `normalizedPoints`.** `lib/features/editor/engine/modules/paint/paint_layer.dart:53`
  takes a `List<Offset>` without `List.unmodifiable`. `fromJson` wraps
  it; the constructor must too — otherwise a command building a
  `PaintLayer` directly with a growable list creates a quiet
  document-corruption vector. 🟡 S, engine.
- [x] **Engine tests import `application/`.** `test/engine/text_editing_test.dart:3`
  and `test/engine/viewport_test.dart:3` violate `tests.instructions.md`
  (engine tests must be pure). Move to `test/application/`. 🟡 S.
- [x] **Color-space contract is undocumented in the rendering code.**
  `docs/effects.md §6` declares "all effects in sRGB" but neither
  `engine/rendering/` nor `engine/export/` says so. Add a contract
  comment at the bake-point and at the exporter entry. 🟡 S.
- [x] **Raw exception strings exposed to users.** Sites:
  - `lib/features/editor/presentation/editor_screen.dart:672` →
    `Could not pick image: $e`
  - `lib/features/home/presentation/widgets/recent_projects_section.dart:69`
    → `Could not load projects: $e`
  - Other `ScaffoldMessenger` sites that interpolate `$e`.

  Replace with user-friendly copy; log the exception via `debugPrint`
  in dev. 🔴 S–M.
- [x] **Placeholder tab copy reads like real features.** `lib/features/shell/presentation/root_shell.dart`
  lists Projects/Templates/Profile with promises ("A dedicated home for
  everything you've made") — that destroys trust on day one. Either
  hide the tabs or mark them as "Coming soon" explicitly so the user
  knows they're stubs. 🔴 S.

---

## Tier 1 — Critical, in-session if scope allows

- [ ] **No crash recovery / autosave journal.** Autosave debounces 1.5 s
  and only writes for projects with a `projectId`. Mid-edit crash =
  silent data loss with zero trail. Needs: write-ahead journal of
  commands + recovery prompt on cold start. 🔴 M. Out of session scope
  (design needed).
- [ ] **Effect system half-shipped.** Schema bumped to v3, `EffectStack`
  + `LayerMask` data shipped, but `PathMask.sampleAlpha` throws
  `UnimplementedError("Phase 2 Step 5")` and there is no per-effect
  mask renderer or stack-panel UI. Until this lands, the engine
  cannot grow. 🔴 L–XL. Out of session scope (design + multi-week impl).
- [ ] **God-files have rotted.**
  - `text_mode_toolbar.dart` — 4,697 lines
  - `editor_screen.dart` — 1,925
  - `interaction_controller.dart` — 1,861
  - `editor_canvas.dart` — 1,723
  - `text_tool_controller.dart` — 1,701
  - `paint_mode_toolbar.dart` — 1,489
  - `image_layer.dart` — 1,244 (engine!)

  AGENTS.md soft-limit is ~600. Splitting is M each, behaviour-preserving
  but risky. Out of session scope (each split is its own PR).
- [ ] **No memory-pressure handling.** No `didChangeMemoryPressure` wiring;
  `ImageCache` is shared and untuned. 🔴 M.
- [ ] **No telemetry / crash reporting.** Cannot diagnose production
  issues. 🔴 S to wire, but requires service choice.
- [ ] **No localization framework.** Persian font fallback is wired;
  `intl` / `.arb` / code-gen are not. 🔴 M.

---

## Tier 2 — High impact, deeper investment

- [ ] **No GPU render path.** Blocks sharpening / blur / denoise / lens
  distortion. XL.
- [ ] **No image preview-proxy.** Full-res decode at edit time on
  large photos. M.
- [~] **Picture-cache budgets from `effects.md §10` not implemented.**
  `kEffectCacheByteBudget`, `kEffectOverlayCacheByteBudget` are
  documented but absent from `engine_constants.dart`. L.
  - `[x]` Constants declared in `engine_constants.dart` with rationale
    comments (Session 3). Plumbing into the actual cache (still L) is
    deferred — needs the cache implementation itself, which is part of
    the Phase 2 effect renderer rewrite.
- [ ] **Accessibility patchy.** Many layer-panel icons / settings rows
  lack `Semantics`. M.
- [ ] **Branded app icon, splash, name.** `android/app/src/main/res/mipmap/`
  is Flutter default. App name is "canvas_engine" in AndroidManifest. M.
- [ ] **No about / version / privacy / terms screens.** Required for
  store submission. M.
- [ ] **EXIF: no read, no orientation respect, no preserve on export.** S–M.
- [ ] **No before/after, history panel, presets browser.** S–M each.
- [ ] **`backgroundColor` deprecation chain (5 sites).** Every reader
  pays the tax. Schedule the schema bump that removes it. S.

---

## Tier 3 — Photo-editor table-stakes feature gaps

Implementation order assumes the effect system from Tier 1 has shipped.

- [ ] Curves (RGB + per-channel) — L
- [ ] Levels + histogram — L
- [ ] Exposure / Highlights / Shadows / Whites / Blacks — M
- [ ] White balance (kelvin + tint + eyedropper) — M
- [ ] HSL color mixer — M–L
- [ ] Sharpening — L (blocked on GPU)
- [ ] Noise reduction — XL (blocked on GPU)
- [ ] Healing / spot removal / clone — L (needs raster-paint layer)
- [ ] Perspective correction — M
- [ ] Lens distortion — L
- [ ] RAW ingest — XL
- [ ] ICC / color-managed export — M
- [ ] Presets / looks — M
- [ ] Copy/paste adjustments between photos — S

## Tier 4 — Snapseed-class parity

- [ ] Selective adjustments (radial / linear masks) — L
- [ ] Brush masks — M
- [ ] Healing brush — L
- [ ] Double-exposure / blend modes UI — M
- [ ] Frames catalog — S
- [ ] Structure / clarity — M
- [ ] Dodge & burn — M
- [ ] Grain — S
- [ ] Faces / portrait — L
- [ ] Batch processing — L

---

## Test coverage gaps

- [x] No isolated test for `SetBasePhotoCommand`, `SetProjectKindCommand`,
  `SetImageVignetteCommand`. S.
  - `[x]` `SetBasePhotoCommand` — `test/engine/vignette_and_base_photo_commands_test.dart`
  - `[x]` `SetImageVignetteCommand` — same file (incl. live-merge rules)
  - `[x]` `SetProjectKindCommand` — same file (4 cases)
- [x] No `image_layer_copy_test` (text/shape/paint each have one). S.
  Added `test/engine/image_layer_copy_test.dart` (5 cases incl. effect
  stack round-trip).
- [x] No JPEG round-trip pixel test. S. Added a 4th case in
  `test/widget/jpg_export_test.dart` that decodes the encoded JPEG
  and asserts per-channel drift ≤ 3/255 at q=95 — catches
  channel-order regressions (RGBA vs BGRA).
- [x] No fixture corpus of v1 / v2 / v3 documents. S. The on-disk
  corpus already exercised all three, but nothing gated it. Added
  `test/engine/fixtures/schema_coverage_test.dart` enumerating the
  buckets and asserting every supported schema version has at least
  one fixture and still decodes.

---

## Tech-debt cleanup

- [ ] `// ignore: deprecated_member_use_from_same_package` chain around
  `EditorDocument.backgroundColor` (4 sites). S, schedule with v4 bump.
- [x] `// ignore: unused_element_parameter` / `unused_element` in
  `text_mode_toolbar.dart` (3 sites). S. — Session 4.

---

## Session log

Each completed item gets a one-line note here referencing the commit
or the file change.

### Session 1 — Tier 0 sweep

- **Dark mode → system.** `lib/app/app.dart` — `themeMode: ThemeMode.system`,
  rationale comment expanded (override belongs in Settings).
- **Stray `debugPrint` guarded.** `selection_overlay.dart` —
  `if (!kDebugMode) return;` early-out at the top of the postFrameCallback.
- **`PaintLayer` immutability defense.** `paint_layer.dart` `copyAll`
  wraps the input list with `List.unmodifiable`; `paint_draft.toLayer`
  does the same on the construction site. Const constructor preserved
  (compile-time const lists are already safe).
- **Engine test misplacement fixed.** `text_editing_test.dart` and
  `viewport_test.dart` moved from `test/engine/` to `test/application/`.
- **Color-space contract documented.** Added paragraphs in
  `document_view.dart` and `document_png_exporter.dart` declaring
  sRGB premultiplied as the wire/render contract; cross-references
  `docs/effects.md §6`.
- **Raw exception leaks fixed.** New helper
  `lib/core/utils/user_error.dart` (`userMessageFor` + `debugLogError`).
  7 user-facing sites converted: home actions (open project, import
  photo), image-mode toolbar, new-document dialog, editor screen
  (pick / size / save), export action sheet, recent projects
  section + grid.
- **Placeholder tab honesty.** `placeholder_tab.dart` — added explicit
  "Coming soon" pill above the title so Projects/Templates/Profile
  no longer read like missing real features.
- **Image layer copy test added.** `test/engine/image_layer_copy_test.dart`
  (5 cases). Closes the parity gap with text/shape/paint copy suites.
- **Vignette + base-photo command tests added.**
  `test/engine/vignette_and_base_photo_commands_test.dart` (15 cases)
  covering: identity-no-op, invert correctness, peer-effect
  preservation, live-merge rules incl. field-set discrimination.
- **Verification.** `flutter analyze` clean (only pre-existing info
  lints). `flutter test` 1,146 → 1,166 pass after the new test files.

### Session 2 — Coverage trio + analyzer cleanup

- **`SetProjectKindCommand` tests added** — 4 cases (apply, identity
  no-op, invert, label copy). Closes the command-coverage trio with
  Tier 0 #6 / #9.
- **Vignette modernization.** `vignette_effect.dart` switched off
  deprecated `Color.alpha` / `withOpacity` / `value` to the
  precision-preserving `color.a` / `withValues` / `toARGB32()`
  forms. Behaviour-preserving (alpha math is bit-identical for
  in-range values).
- **`part of` directives modernized.** Two effect part-files now use
  `part of 'editor_effect.dart'` + `library;` instead of the legacy
  named-library form. Drops 3 `unnecessary_library_name` /
  `use_string_in_part_of_directives` / `dangling_library_doc_comments`
  lints.
- **Codec uses null-aware map elements.** `'background': ?backgroundJson`
  + `'basePhotoLayerId': ?doc.basePhotoLayerId` replace explicit
  `if (x != null)` entries. Round-trip byte-identical (verified by
  the v2 fixture suite).
- **Stale imports purged.** 5 redundant `background_fill` /
  `text_style_spec` / `dart:ui` imports removed across rendering,
  codec, and 4 test files.
- **Analyzer status:** 18 → 2 issues. Remaining 2 are intentional
  underscore-prefixed locals in a Persian-export verification test.
- `flutter test` 1,170/1,170 passing.

### Session 3 — Cache budgets + reader/encoder coverage

- **Effect cache budget constants declared.** `engine_constants.dart`
  now has `kEffectCachePerLayerLruCap = 3`,
  `kEffectCacheByteBudget = 128 MB`,
  `kEffectOverlayCacheByteBudget = 32 MB`, mirroring `effects.md §10`
  with rationale. Constants only — actual cache plumbing is still
  L work and lives with the Phase 2 renderer rewrite.
- **JPEG round-trip pixel test added.** `jpg_export_test.dart` gains
  a 4th case: decode the encoded JPEG and verify per-channel drift
  ≤ 3/255 at q=95. Catches channel-order regressions the prior
  SOI/EOI + size-vs-quality cases would silently let through.
- **Schema-coverage gate added.** New `schema_coverage_test.dart`
  buckets every fixture by declared `version`, asserts every
  supported schema version has at least one fixture, and asserts
  each fixture's `"version"` stamp matches its bucket and still
  decodes under the current build. Cross-cuts with the existing
  per-version byte-identity gates.
- `flutter test` 1,178/1,178 passing. `flutter analyze` 2 issues
  (both intentional `_-prefixed` locals in a Persian-export test).

### Session 4 — Dead-code excision in text_mode_toolbar

- **`_InlineSliderRow` + `_InlineSliderRowState` + `_InlinePresetChip`
  removed.** The inline-expand slider variant had no live call site;
  panels route through `_FlatSliderRow`. The 2 `unused_element_parameter`
  ignores on `presets` / `unit` were the only thing keeping the dead
  trio (~250 lines) compiling.
- **`_AdvancedGroupHeader` removed.** Sub-section header widget never
  used; the visually-equivalent `_PanelSectionLabel` already exists
  and is what the panels actually call. The 1 `unused_element` ignore
  is gone.
- **Analyzer status:** 5 → 2 issues. The remaining 2 are the same
  intentional `_-prefixed` locals in the Persian-export test.
- `flutter test` 1,178/1,178 passing.
