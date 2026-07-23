# Project Review & Roadmap — 2026-07-03

Full-project review (engine, UI/UX, tests, docs/rules) with a prioritized,
phased roadmap. Every finding below was grounded in code read during this
review and the load-bearing claims were independently re-verified against the
source; file:line references are as of commit `408b108`.

**Baseline at review time:** `flutter analyze` clean · `flutter test`
1,415/1,415 pass · schema v3 · 382 Dart files, ~104k lines (lib + test).

This review builds on — and does not replace — the prior audits:
`docs/product-audit-2026-05.md` (tiered product audit + session log),
`docs/editor-engine-core-audit.md` (UX/engine audit, Batches 4–7 done),
`docs/effects.md` (effect-system design), the template plans/audits, and
`docs/effects-a3-scoped-plan-2026-07.md` (in-flight stackMask work).

---

## 1. State of the project

### 1.1 Work in progress (the roadmap folds these in, not drops them)

* **Effects A3 — stackMask** (active sprint). Step 0 spike complete on branch
  `spike/a3-stackmask` (`dd1187c`, ShaderMask + `dstIn` chosen, 4/4 spike
  tests green). Model + serialization landed on main (`da5c35d`), command
  rebuilds preserve the mask structurally (`408b108`). **Not yet done:** the
  §7.3 `buildContent` render integration, the mask-raster cache it needs,
  `SetStackMaskCommand` (its absence is noted in
  `test/engine/effect_stack_stack_mask_test.dart:166`), and any UI. The full
  A3 plan §§1–6 is not committed — `docs/effects-a3-scoped-plan-2026-07.md`
  is an untracked placeholder holding only §7.
* **Per-effect masks**: model, serialization, and sampling are complete, but
  both render paths deliberately skip any effect with a non-null mask
  (`editor_effect.dart:357`, deferred in-code to "Step 6+"). Zero product
  reachability today.
* **`backgroundColor` deprecation** mid-flight: `BackgroundFill` fully landed,
  deprecated params/getters still live on `EditorDocument`, `DocumentView`,
  and `DocumentThumbnail.backgroundFor`.
* **Crash-recovery journal** half-landed: `EditJournal` writes atomically every
  750 ms, but `recover()` has **zero callers** — the launch-time resume prompt
  promised in its doc comment does not exist.
* **TemplateCatalog deletion** parked at Phase 5 of
  `docs/template-catalog-cleanup-plan.md` (runtime is asset-only; the 3,317-line
  legacy Dart catalog remains as a migration-test baseline).
* Housekeeping in flight: untracked `.github.zip` at repo root, eight ignored
  `lib*.zip` backups, empty `lib/features/shell/presentation/` directory.

### 1.2 Engine — genuinely strong core, with specific verified holes

**Strengths (this is a professional-grade foundation):**

* Command purity and the invert contract are enforced *structurally*:
  `HistoryStack.execute` computes the inverse from the pre-apply document
  (`history_stack.dart:56`), and all sampled commands read prior state only
  from the `before` doc, with `_NoopCommand` sentinels for stale ids.
* The `copyAll` single-source-of-truth pattern holds across all four layer
  types — every `with*`/`copyWith` delegates to one field-complete `copyAll`
  with Object sentinels for nullable fields. A field-by-field diff found no
  dropped field. Layer `==`/`hashCode` include full payloads.
* Coordinate-space hygiene (AGENTS rule 8) is genuinely followed —
  `LayerTransform`, `InteractionEngine.updateResize`, `ViewportState`, and
  `LayerMask` all document their spaces explicitly.
* Interaction engines (`InteractionEngine`, `SnapEngine`, `GroupEngine`,
  `AlignmentEngine`, `MotionSmoother`) are pure data-in/data-out.
* Export has real memory engineering: single choke-point pixel clamp,
  device-aware cap (8× screen px, floor 4 MP, ceiling 24 MP), JPEG encode on
  an isolate, disposal in `finally`. `DocumentView` is a clean single source
  of document pixels with a written sRGB contract shared by canvas, exporter,
  and thumbnail.
* Serialization discipline is real: defaults omitted, the writer stamps the
  *minimum* schema version the document needs (`document_codec.dart:110`),
  unknown effects round-trip verbatim via `UnknownEffect`, byte-identity
  fixtures gate v2/v3.

**Verified defects and ceilings:**

* **[DONE] Undo-of-delete restores at the wrong z-index.** Fixed:
  `RemoveLayerCommand.invert` now returns
  `AddLayerCommand(prev, index: before.indexOf(layerId))`
  (`transform_commands.dart:63`), so undo re-inserts at the original depth.
  `test/engine/layer_management_test.dart` (group "RemoveLayerCommand undo
  restores z-order") covers middle-layer restore, bottom-layer restore +
  redo through `HistoryStack`, and multi-delete `CompositeCommand` ordering.
  *Original defect (record): invert returned `AddLayerCommand(prev)` and
  `addLayer` appended to the top, so undoing a middle-layer delete brought it
  back on top and multi-delete flipped restored order.*
* **[HIGH, confirmed] stackMask is invisible to `_writerVersion`.** A
  stackMask-only layer is stamped schema v1 while writing a v3-only
  `stackMask` key (probe verified: `version=1 hasStackMask=true`). An older
  reader would open it and silently drop the mask on resave. Latent only
  because no command can set a stackMask yet — it becomes a live corruption
  path the moment `SetStackMaskCommand` lands. **Must be fixed before A3
  continues.** (`document_codec.dart:114` promotes only on
  `effects.isNotEmpty`.)
* **[MEDIUM, confirmed] Adjust-slider drags destroy disabled effects.**
  `SetImageAdjustmentsCommand.apply` strips *all* derived-type effects
  including disabled ones, while `fromEffectStack` ignores disabled effects
  when reading current values (`image_commands.dart:381`). Toggle brightness
  off in the Effects panel, drag contrast → the disabled brightness effect
  and its amount are silently deleted. Also silently discards user reordering
  among derived effects.
* **[MEDIUM, confirmed] Reordering a vignette is a render no-op.** The
  renderer applies the one composed color matrix first and paints custom-paint
  effects on top unconditionally (`image_layer.dart:251–294`), so
  `[vignette, brightness]` renders identically to `[brightness, vignette]` —
  yet the Effects panel offers the drag and `ReorderEffectCommand`'s doc
  claims a real semantic change.
* **[MEDIUM, confirmed] Effects are modeled on every layer type but rendered
  only by `ImageLayer`**; every effect command guards `layer is! ImageLayer`.
  A document with effects on a shape decodes fine and silently renders
  nothing. `docs/effects.md` states "stack effects on any visual layer."
* **[MEDIUM, confirmed] Live-merge has no stream termination.** Sliders wire
  only `onChanged` (no drag-end settle), and a same-value settle would be
  swallowed by the history no-op guard — so two separate brightness drags
  minutes apart collapse into one undo entry. `UpdateTextCommand` and
  `UpdatePaintStyleCommand` merge with no live gate at all, so two discrete
  palette taps collapse too.
* **[MEDIUM, confirmed] Widget-tree rasterization is a structural export
  ceiling**: export needs a live `BuildContext`/Overlay and a pumped frame
  (no headless export), one `RepaintBoundary.toImage` for the whole document
  (hence the 24 MP cap), and the 2048 px decode-edge cap means a base photo
  wider than ~1024 canvas px exports soft at pixelRatio 2 (2× upscale from
  the decode). GPU-shader effects are limited to what
  `ColorFiltered`/`CustomPaint` can express. This is the known "Phase 2
  renderer" ceiling; the effect cache from `effects.md` §10 exists only as
  constants (no consumers).
* Smaller (verified or spot-checked): `GroupEngine`'s scale envelope
  (0.05..64) conflicts with `EngineConstants.minGestureScale/max` (0.2..8) —
  a group pinch can scale far past a single-layer pinch; `EditorDocument.layers`
  is an `UnmodifiableListView` *view* (caller-retained lists can desync
  `_layerIndex`) while its comment claims `List.unmodifiable`; a cosmetic
  dead-`dy` in `SnapEngine.snapPosition` guide extents; `_NoopCommand`
  duplicated in ~6 command files; seven engine files exceed the ~600-line
  rule (`shape_layer` 930, `image_commands` 840, `text_layer` 819,
  `image_layer` 764, `snap_engine` 750, `layer_mask` 658, `paint_layer` 653).

### 1.3 UI / UX — capable product, structurally expensive to improve

Honest level: feature-rich and far beyond a toy (six editor modes, unified
sheet chrome, real undo/redo, Persian-first l10n at 508/508 key parity), but
the *construction* is what limits polish speed and consistency.

**Strengths:**

* Localization is exemplary: proper gen-l10n pipeline, exact en/fa parity,
  zero literal user-facing strings in feature UI.
* Panel/sheet chrome is unified (`SubToolSheet`/`EditorToolPanelShell`), layer
  structural operations are centralized in one `LayerActions` facade, color
  editing genuinely reused (`InlineColorBody` across 10 consumers), RTL
  actively practiced (58 directional-widget usages).
* A minimal real design foundation exists: one M3 seed theme with locale-aware
  Persian/Latin font chains, `AppSpacing`/`AppRadii` tokens.

**Structural causes of weakness (verified):**

1. **The design system stops at chrome; atomic controls are per-feature
   private copies.** ~10 distinct "label + Slider + value" implementations,
   two byte-identical (`shape_shadow_body.dart:490` vs
   `image_shadow_body.dart:492`); the "Adjust precisely" disclosure is
   re-implemented ≥6×; `_TierGap`/`_PaintTierGap` are character-identical.
   Drift has already happened (label width 56 vs 80, `min` supported in some
   copies only). Every visual tweak to the slider grammar is an 8–10 file
   change.
2. **God files.** `text_mode_toolbar.dart` is 4,402 lines / 54 classes — an
   entire sub-application, all file-private, so none of it is reusable by
   shape/image/paint modes. `editor_screen.dart` (2,010) mixes mode routing,
   creation flows, and raw file IO in a presentation widget
   (`_persistPickedImage` at :824 does `getApplicationDocumentsDirectory` +
   `File.copy`, duplicated verbatim in `image_replace_flow.dart`).
   `editor_canvas.dart` 1,796; `paint_mode_toolbar.dart` 1,517.
   `shape_shadow_body`/`image_shadow_body` are ~550-line clones (80-line diff).
3. **Three parallel overflow-sheet implementations with inconsistent menus**
   across ~7 layer-action surfaces: `_TextMoreSheet`, `_LayerActionsSheet`
   (paint; doc comment stale), `_SelectedLayerActionsSheet` (shape/image/
   multi), plus `QuickActionsOverlay`, the layers drawer, floating toolbars,
   and context strips. Align/opacity links exist only in the text sheet;
   multi-select strips to almost nothing; each new layer type must pick among
   three patterns.

Also verified: Home and Onboarding each carry hardcoded *light-only* palettes
with duplicated color values while Settings offers dark mode — Home stays a
cream page in dark theme, and mixes two theming regimes internally. Semantics
coverage is thin outside shared chrome (31 hits across 11 of ~109
presentation files; none of the bespoke sliders name themselves to screen
readers — the primary Persian audience hits this hardest). Navigation is
ad-hoc `MaterialPageRoute` pushes (fine at 4–5 screens, no deep-link story).
Undo-history labels are hardcoded English in a Persian-first product.

### 1.4 Application layer & platform — good architecture, two data-safety holes

**Strengths:** live-overlay separation keeps 60 fps previews out of the
committed document; autosave is genuinely well-engineered (1.5 s debounce on
commit versions, skip-if-identical JSON, flushed at pop/dispose/lifecycle);
journal writes are torn-write safe (tmp + atomic rename); `MemoryGuard` caps
`ImageCache` (64 MB/50 entries) and reacts to `didHaveMemoryPressure`;
`InteractionController` encodes hard-won gesture invariants with a lifecycle
listener; 71 `.select()` call sites keep rebuilds disciplined.

**Verified weaknesses:**

* **[HIGH] Crash recovery is write-only.** `EditJournal.recover()` and
  `flushNow()` have no callers. The journal written every 750 ms is never
  read. Combined with the rule that autosave/journal require a `projectId`,
  a first-session user who never tapped Save has *zero* persistence net.
* **[HIGH] The entire project library lives in ONE SharedPreferences string**
  (`home.projects.v1`). Every autosave re-encodes every project; one corrupt
  byte → `_readAll` silently returns `[]` — total library loss, no backup, no
  quarantine, no user-visible error; `setString`'s bool result ignored
  (`project_store.dart:14–46`).
* **[MEDIUM] No telemetry or crash reporting at all**; the only logging is
  debug-gated, and failures are pervasively swallowed. Production corruption
  and OOM are invisible.
* `ProjectStore.upsert` lacks the store-loading guard autosave has — today it
  fails a manual save with a snackbar (`late` field throws) rather than losing
  data, but it is a latent footgun.
* Layering: `text_tool_controller.dart` and `paint_tool_controller.dart`
  import `presentation/widgets/recent_colors_controller.dart` — a pure
  Notifier misfiled under presentation; the import direction is inverted.
* Two god-controllers (`interaction_controller.dart` 1,861 — including a
  duplicated 1-D edge-snap implementation mirroring `SnapEngine`;
  `text_tool_controller.dart` 1,819 mixing UI state, style mutation, text
  measurement, and layer arrangement).
* Project delete leaks three artifacts (thumbnail PNG, viewport key, journal
  file); `ProjectViewportStore.clear()` documents its purpose but has no
  callers.

### 1.5 Tests — strong invariants where they exist, systematic gaps where it hurts

**What is well protected:** serialization (byte-identity corpus + a
schema-coverage gate framing reader/writer sides); per-layer `with*`/copy
suites; history merge + byte-budget; gesture tests with exact numeric
assertions (1e-6 tolerances, branch cuts, pointer-count oscillation); export
tests with real per-pixel assertions; stackMask model/serialization traps;
Persian export smoke with real Farsi fonts.

**Verified gaps:**

* The **stackMask writer-version hole shipped unguarded** — no writer-version
  test, no stackMask fixture (the probe that exposed it should become a test).
* **No systematic invert harness**: 37 command classes, direct `invert()`
  round-trips at only ~21 call sites; a wrong inverse in a new command relies
  on someone remembering. (The z-index bug above is exactly this class.)
* **Copy-contract tests are hand-enumerated**, not the codec-diff their own
  comments claim; a new field forgotten in both `copyAll` and the test's
  fixture is invisible. Only `ImageLayer` has even a partial encode-compare.
* **Effect rendering has almost no pixel coverage** (one mono-filter pixel
  check; zero goldens — a deliberate, documented deferral pending a baseline
  strategy). A renderer wiring bug (matrix applied twice or not at all) would
  pass the suite.
* Fixture corpus is thin: 6 fixtures, exactly one v3, none with masks,
  gradient+effects combos, or Persian text.
* Persian/RTL visual correctness is human-verified by design (the test says
  so); an RTL shaping regression passes CI — except **there is no CI** (below).
* Hygiene: two `test/engine/` files import `material.dart` (rule 6
  violation); no shared test-helper library (`makeContainer` re-declared in
  ~23 files); no performance tests.

### 1.6 Docs & rules — high-quality but stale at the exact point of risk

* **[HIGH, confirmed] AGENTS.md actively misleads about effects**: "the
  effect system is being introduced in the current sprint… do not invent your
  own effect API" — while `engine/effects/` shipped ~7 weeks ago in the same
  commit that last touched AGENTS.md. An obedient agent following "if
  anything here conflicts with code, the code is the bug" would flag shipped
  code as a bug.
* **[HIGH, confirmed] `docs/effects.md` says "Draft. Not yet implemented"**
  while much of it shipped — and the shipped parts diverge: code is a
  `sealed` class with `paint(Canvas, Rect)` + `EffectKind` dual dispatch, not
  the doc's `apply(Canvas, ui.Image, Rect)` rasterize-per-effect pipeline;
  §8's `CompositeCommand([AddEffect, SetEffectParam])` merge design was never
  built (idempotent replace-in-stack commands shipped instead); the
  implemented `EffectStack.isEmpty` semantics deliberately differ from §3.
* Both engine-subfolder tables (AGENTS.md, architecture.md) omit
  `engine/effects/`. `docs/product-audit-2026-05.md` Tier-1 statuses are
  stale: memory-pressure handling and the l10n framework are **done**, the
  crash journal is half-done, `PathMask.sampleAlpha` no longer throws, an
  effects panel exists; god-file line counts have drifted (some grew).
* **No CI whatsoever** — `.github/` holds only Copilot instruction files.
  Nothing enforces analyze/test/import-direction/round-trips on push. AGENTS
  says "CI does not enforce this yet — you do"; with agent-driven
  development, that is the single cheapest risk reduction available.
* README is Flutter boilerplate. No doc exists for the text system (the
  largest code area), l10n workflow, template authoring, or release process.
* The three `.github/instructions/*.md` files are a parallel rulebook that
  mostly agrees with AGENTS.md but is a second place for drift.

---

## 2. Prioritized roadmap

Ordering = impact × effort × dependency. Effort: **S** = days, **M** = 1–2 wk,
**L** = ~1 mo, **XL** = multi-month.

> **The keystone:** finishing the **mask/effect pipeline** — A3 stackMask
> render integration, then per-effect masks, then selective-adjustment UX.
> `docs/effects.md` §0 named the effect system "the load-bearing column that
> turns the foundation into a product," and that is still true: it is what
> separates a sticker editor from the Snapseed-class target. Everything in
> Phase 0 exists to make that work land safely; Phases 2 and 4 make the
> product trustworthy and the UI cheap to improve around it.

### Phase 0 — Rails and verified-bug fixes (S overall; do first, in order)

0.1 **[S] Fix `_writerVersion` stackMask promotion** + add a stackMask
    fixture and writer-version test (turn the probe into a regression gate).
    Blocks all further A3 work — without it, the first `SetStackMaskCommand`
    creates silently-corrupting documents.
0.2 **[S] CI**: GitHub Actions running `flutter analyze` + `flutter test` on
    push/PR. Add the import-direction check (even a grep-based one) and the
    fixture byte-identity suite explicitly. Repo hygiene in the same pass:
    delete `.github.zip` + `lib*.zip` backups, remove empty
    `lib/features/shell/presentation/`.
0.3 **[DONE] Fix undo-of-delete z-index** — `RemoveLayerCommand.invert` now
    captures `index: before.indexOf(layerId)` and restores at the original
    depth; middle-, bottom-, and multi-delete ordering are covered by
    `test/engine/layer_management_test.dart`.
0.4 **[S] Fix `SetImageAdjustmentsCommand` destroying disabled effects** and
    discarding derived-effect reorder.
0.5 **[S] Doc truth pass**: AGENTS.md effects section + subfolder table;
    architecture.md effects/ row; `docs/effects.md` header replaced with an
    "as-built" status block noting the EffectKind dual-path divergence;
    product-audit Tier-1 statuses corrected (memory ✓, l10n ✓, journal ~).
0.6 **[S] Small rule-violation cleanups**: move the two `test/engine/`
    material imports; relocate `recent_colors_controller.dart` to an
    application folder; align `GroupEngine` scale envelope with
    `EngineConstants` (or document the intentional difference).

### Phase 1 — Finish Effects A3 (in-flight work; M–L total)

1.1 **[S] Commit the full A3 plan** (§§1–6 merged into the placeholder doc).
1.2 **[M] stackMask render integration** per the spike: ShaderMask/`dstIn`
    over base-vs-painted subtrees in `ImageLayer.buildContent`, mask-raster
    cache keyed `(stackMask, w, h)` (first real consumer of the §10 cache
    constants), null-path render-tree identity gated by test.
1.3 **[S–M] `SetStackMaskCommand`** (mergeable family keyed
    `(layerId, "stackMask")` per effects.md §8) + minimal UI entry.
1.4 **[S] Pixel regression tests** for the composite (port the spike's
    masked/unmasked/feather-midpoint/inverted assertions into the main suite).

### Phase 2 — Data safety & trust (M–L total; nothing else earns user trust
until this is done)

2.1 **[M–L] Replace the single-key ProjectStore** with per-project files
    (atomic write + rename, corrupt-file quarantine instead of silent `[]`,
    one-time migration from `home.projects.v1`, write results checked).
2.2 **[M] Wire `EditJournal.recover()`**: cold-start detection + resume
    prompt; decide the never-saved-project story (draft project id at first
    edit is the simplest fix to the "first session, no Save" black hole).
2.3 **[S–M] Crash reporting + minimal telemetry** (service choice needed —
    Sentry or Crashlytics; then stop swallowing failures silently).
2.4 **[S] Project-delete cleanup** (thumbnail, viewport key, journal; wire
    the existing `ProjectViewportStore.clear()`).

### Phase 3 — Effect-system completion (L; the keystone continued)

3.1 **[M] Per-effect mask rendering** ("Step 6+"): render path honoring
    `EditorEffect.mask`, feather raster for PathMask, min(α) composition per
    effects.md §4.
3.2 **[M] Selective-adjustment UX**: mask editing UI (rect/ellipse first —
    Lightroom-style linear/radial gestures), on-canvas mask handles.
3.3 **[S–M] Effect-model coherence fixes**: make reorder honest (either the
    renderer honors matrix-vs-custom-paint order or the UI stops offering the
    meaningless drag); decide effects-on-non-image-layers (implement render +
    un-guard commands, or explicitly scope the model and document it);
    live-merge stream termination (drag-end settle) so undo granularity
    matches user gestures.
3.4 **[M] Effect/mask picture cache** when profiling shows the recompute
    cost — the constants and eviction design already exist (§10).

### Phase 4 — UI foundation (L total; parallelizable with Phase 3)

4.1 **[M] Editor design-system primitives**: one `LabeledSliderRow` (label
    width, min/max, formatting), one precision-disclosure, one tier gap, one
    section label — placed in a shared editor-UI library; migrate the ~10
    copies; delete the byte-identical clones.
4.2 **[M] Unify the three overflow sheets** into one capability-driven layer
    sheet (LayerActions already centralizes the logic; this unifies the menu).
4.3 **[L] Split `text_mode_toolbar.dart`** along its natural seams (tool
    registry / panels / font picker / presets browser), which 4.1 makes
    mostly mechanical. Then `editor_screen.dart`: extract the image
    import/persist IO into an application-layer service (kills the
    `image_replace_flow` duplication), extract the shape picker.
4.4 **[M] Theming coherence**: one shared palette source for Home/Onboarding,
    dark-mode support on Home, migrate hardcoded spacing to tokens
    opportunistically.
4.5 **[M] Accessibility pass**: Semantics on every slider/toggle/pad via the
    new shared primitives (the reason to do 4.1 first); localized undo-history
    labels.

### Phase 5 — Test hardening (M; weave items alongside Phases 1–4)

5.1 **[S–M] Command-invert catalog harness**: for every registered command, a
    generated `apply → invert(before).apply(after) == before` sweep over a
    loaded document (would have caught the z-index bug).
5.2 **[S–M] Copy-contract codec-diff harness**: encode-and-key-diff for all
    four layer types, replacing hand-enumerated lists.
5.3 **[S] Fixture corpus expansion**: stackMask fixture (Phase 0), LayerMask
    variants, gradient+effects combo, Persian text content.
5.4 **[M] Deterministic pixel smoke suite**: decide the golden strategy the
    tests explicitly defer (CI on one pinned platform makes goldens viable);
    start with the parity matrix the 2026-05 audit proposed (DocumentView vs
    export vs thumbnail for gradient/transparent/effects docs).
5.5 **[S] Shared test-helper library** (`test/support/`): document builders,
    pump hosts, font loading.

### Phase 6 — Pro-grade ceilings & store readiness (XL horizon; sequence after 1–3)

6.1 **[M] Store readiness**: branded icon/splash/app name, about/version/
    privacy screens, JPG-flattening copy (from 2026-05 audit Tier 2).
6.2 **[M] EXIF read/orientation/preserve-on-export.**
6.3 **[L] Export ceiling, stage 1**: fix the decode-cap softness for large
    exports (decode at export resolution, not screen bucket); headless/tiled
    export design.
6.4 **[XL] GPU render path** (FragmentProgram): unblocks blur/sharpen/
    structure/denoise, then curves/levels/HSL from the Tier-3 list.
6.5 **[M] Template Batch 4** + TemplateCatalog Phase-5 deletion (both plans
    already written; slot when product needs shelf growth).

---

## 3. How we work (execution discipline — applies to every future session)

1. **Plan before code** on anything non-mechanical. A new engine concept
   (effect, mask, blend, cache, store format) gets a written design confirmed
   before implementation — the A3 spike → design note → staged landing is the
   house style; keep it.
2. **One concept per commit.** Splitting a file, renaming a symbol, and
   changing behaviour are three commits, not one.
3. **Behaviour-preserving refactors keep `flutter test` green.** If a
   previously-green test breaks: STOP; decide real-regression vs stale-test
   with the user. **Never edit a test just to make it pass.**
4. **Prove verbatim moves byte-identical** (diff removed vs relocated block).
   Prove serialization changes byte-identical against the fixture corpus; new
   wire shapes need a fixture + writer-version test *in the same change*.
5. **Respect the AGENTS.md invariants**: document immutability, pure
   commands, `invert(before)`, field-complete `copyAll`, explicit coordinate
   spaces, backward-compatible serialization, constants in
   `engine_constants.dart`.
6. **Check in at meaningful boundaries**: after each roadmap ITEM (not each
   commit) — short report: what changed, analyze/test results, anything
   flagged. Anything ambiguous or API-breaking → stop and ask first.
7. **Keep the docs true**: when a change makes AGENTS.md, architecture.md, or
   a design doc stale, updating the doc is part of the change, not a
   follow-up. (This review exists partly because that rule wasn't followed.)
8. **Verify before asserting done**: run `flutter analyze` + `flutter test`
   before reporting any item complete; quote failures verbatim.

---

## 4. Immediate next step

**Phase 0.1 — fix the stackMask writer-version hole.**

Concretely: `_writerVersion` in
`lib/features/editor/engine/serialization/document_codec.dart` must promote
to v3 when any layer's `effects.stackMask != null` (not only when
`effects.effects.isNotEmpty`); add
`test/engine/fixtures/v3/02_image_with_stack_mask.json` to the byte-identity
corpus; add a writer-version test asserting a stackMask-only document stamps
v3. Small (S), fully specified, verified-real, and it unblocks the in-flight
A3 render work — the single highest-leverage day available.

Then proceed through Phase 0 in order (CI second), then resume A3 (Phase 1).
