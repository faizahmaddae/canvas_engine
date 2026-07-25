# Toolbar & Tool-Interaction Redesign — Roadmap — July 2026

> Status: **APPROVED (Gate 0, 2026-07-23)** with recommended decisions:
> D-c unpark phase4 §1 items (this doc supersedes that section) · D-d RTL undo/redo
> rail stays mirrored · D-f wide/tablet breakpoint + iPad capture variant + Gate C
> iPad pass. D-a/D-b/D-e/D-g decided at their marked stages.
>
> Companion: `toolbar-redesign-audit-2026-07.md` (the evidence base).
> Direction was validated on an interactive prototype before this roadmap.
> Verified against the codebase by an adversarial multi-agent pass; corrections folded in.

~79 commits across 6 stages, each independently shippable. Series tags `(tb<stage> n/m)`.

## Standing rules (every commit)

- Gates: `tool/check_import_direction.sh` → `flutter analyze` → `flutter test test/engine/fixtures`
  (byte-gate) → full `flutter test` → `dart format` on touched files. Pinned SDK 3.41.7.
- UI commits: capture-test PNGs light+dark (fa) reviewed; interaction changes verified on simulator.
- **Test-migration carve-out** (verified necessity): a commit that deliberately deletes or reshapes a
  pinned API/behavior migrates or deletes the pinning tests IN THE SAME COMMIT and enumerates them in
  the commit body. The never-edit-a-failing-test rule applies to everything OUTSIDE the commit's
  declared blast radius. Every commit below lists its blast radius.
- Engine-command API changes flagged BREAKING-INTERNAL. Commands are NOT serialized (verified:
  DocumentCodec references zero commands; journal is a document-post-state WAL) — command flags/fields
  cannot break fixtures. Any new PERSISTED document/layer field = omit-default serialization + new
  fixture + schema-coverage + legacy-lift test in the same commit (triggers: 4.7, 4.10).
- New strings: both arb files + gen-l10n + committed generated files; `untranslated_messages.txt == {}`.
- Behaviour-preserving moves are diff-proven; deletions name their orphans.

## Prototype divergences — NOT copied (unchanged from draft; see prototype notes)

Command history not snapshots · reflowPreservingZoom not refit-on-open · fit-basis-aware crop fix ·
recognizer/arena gestures not pointer counting · ColorPickerBody live/settled contract · doc-resize
anchor policy explicit · Vazir stack · registry-derived capsule.

## Shipped divergences — accepted, recorded after the parity review (2026-07-24)

A post-Stage-5 review compared the shipped editor against the approved prototype's ten tour claims.
Eight held outright; the review found four gaps, three of which were fixed in `tb6` (multi-strip
batch actions, crop's strip position, sticker's missing More chip, plus the Done pill's duplicate
mode derivation). What remains below is **deliberate and permanent** — the prototype was a direction
validator, not a specification of the final tool inventory, and in each case the shipped behaviour is
the better answer. They are written down because a future reader comparing the two would otherwise
read them as defects.

- **"Two fingers = ALWAYS the viewport" is not literal.** When the first finger lands on the selected
  layer's chrome quad, two fingers pinch/rotate **the layer**, not the canvas (`selection_overlay.dart`
  `addAllowedPointer`). This is the Canva/CapCut rule: pinching a small object must not require both
  fingers inside its bounding box. Two fingers starting anywhere else navigate. Pinned by
  `viewport_gesture_routing_test.dart` and by contract §5 (row 4 vs row 6).
- **"Exit paint only via Done" is not literal.** A tap on the pasteboard also exits
  (`canvas_gesture_router.dart`). Without it a user who has panned the canvas away has no visible way
  out. Pinned by `paint_gesture_navigation_test.dart`.
- **Save indicator.** The prototype had a transient two-state dot (saving… / saved). Shipped renders a
  binary "unsaved" badge in the title subtitle that clears permanently on first save. The per-write
  pulse was noise on a 1.5 s debounce.
- **Strips are supersets, not copies.** The prototype carried a simplified subset. Shipped image =
  10 tiles (adds border, mask shape, effects, selective), paint = 8 (adds fill, opacity, blur, sides,
  dash), shape = 6, and shape's `fill`/`corner` are merged into one Style panel. Idle, text and
  sticker match the prototype. Removing real engine capabilities to match a mock would be a
  regression.
- **The capsule carries a trailing ⋯ More pill** the prototype lacked, so a three-accelerator type
  renders four buttons. More is the capability-driven overflow every mode shares; without it the
  capsule would be the one surface that dead-ends.
- **No `done` tile in the paint strip / no `exit` tile in the multi strip.** Both are floating
  affordances instead (`ModeDoneButton`, the multi-select exit chip) — always visible, never scrolled
  off a strip.
- **The prototype's state line under the canvas is not shipped.** It carried a `simtag:
  EditorModeController` badge: a teaching device for the prototype's reviewer, never product UI.
- **Crop is a full-screen mode with its own top bar**, not the prototype's single floating pill
  (`انصراف · ۱:۱ · آزاد · انجام شد`). Crop wants the maximum canvas area it can get, and the shipped
  mode carries aspect presets, rotate, flip and the grid toggle — a pill that hosted all four would be
  a panel wearing a pill's clothes. Device-approved at Gate C. **Decision closed 2026-07-25.**
- **The colour panel is the full `ColorPickerBody`** (two-level palette, recents from prefs, hex entry,
  canvas eyedropper), not the prototype's single row of eight swatches. The prototype's row was the
  cheapest thing that could show *where* colour lives; matching it would delete four working
  capabilities. **Decision closed 2026-07-25.**

## Stage 0 — Correctness triage (`tb0`, 11 commits) — no visual redesign
(0.4/0.4b are deliberate SEMANTICS changes, owned as such.)

- **0.1 fix(text): edit-session quick-style writes go through the overlay.** `_applyStyle` uses overlay
  whenever `_live != null`; style delta folds into the single commit. Tests: bold+color inside
  beginEditText → commit & cancel both correct, no assert; **style-only change with unchanged content
  still commits one entry** (edit branch early-returns on same content today — must not eat the style).
- **0.2 fix(crop): commit renders the chosen pixels.** ENGINE (fit-basis-aware `_applyCrop`/commit).
  Pixel-compare test: off-center crop + centered inset crop. Fixture gate green.
- **0.3 fix(editor): New document rebinds the session.** Order matters and is part of the spec:
  rebind fresh `EditorSession` → `resetEditorEphemeralState` → `newDocument`; dirty-confirm first.
  Test with autosave debounce elapsed: never upserts old projectId; old journal intact.
- **0.4 fix(editor): back never destroys work.** Reverses a documented product decision (autosave
  doc-comments updated in-commit). Keep AND FRESH-FLUSH the draft journal on `sessionEnding` when doc
  non-empty & never saved (current discard branch skips the flush — a kept-but-750ms-stale journal is
  not enough). Blast radius: `project_recovery_test.dart:240-276` (pins the old discard) — migrated
  deliberately.
- **0.4b fix(home): resume banner is a real net.** Today `_draftOfferShown` latches once per cold
  start and Home never remounts (IndexedStack) — re-offer when Home becomes visible after an editor
  pop; define draft-slot collision policy (single 'draft' slot: newest wins, prior kept draft is
  promoted to an unsaved project entry before overwrite).
- **0.5 fix(engine): `SetCanvasBackgroundCommand` invert/apply carry full `BackgroundFill`.**
  Test: gradient bg → solid pick → undo restores gradient. Blast radius: `canvas_background_test.dart`
  :75 no-op test (compares derived color) — extended, not weakened.
- **0.6 fix(engine): `SetShapeFillCommand` clears `fill` on solid pick; invert restores old fill.**
  Fixes silent no-op on 94 gradient template shapes + undo pollution.
- **0.7 fix(text): `endStyleDrag` tolerant of mid-drag undo** (commit-version captured at begin;
  changed → drop overlay, undo wins).
- **0.8 fix(editor): selection-integrity owner.** Commit-version listener prunes dead selection ids,
  exits multi <2. Hosted next to the EXISTING selection-change seam (editor_screen.dart:106-109);
  both idempotent, prune runs first. Panels keep reading the merged view (documented).
- **0.9 fix(export): failures keep the preview alive** — inline retry, open-Settings action on
  permissionDenied, disk-write failure distinct from permission failure (fake gateway covers both).
- **0.10 fix(editor): duplicate-of-locked is unlocked; drawer reorder-past-base gives feedback.**

## Stage 1 — One brain (`tb1`, 18 commits) — behaviour-preserving
Hard ordering: 1.1/1.2 nets → 1.3-1.5 paint split → 1.6 deletions → 1.7 mode controller →
1.8 screen consumption → 1.9 registry → 1.10-1.14 per-tool migration → 1.15-1.17.

- **1.1 test: pointer-level net** — sheet swipe-down dismiss, sibling swipe across panels, two-finger
  undo matrix + aborts, paint toolbar smoke suite.
- **1.2 test: RTL pins** (tile x-order, fade sides, swipe mapping, pill anchor) landed `skip:` with a
  link to **1.17** (which unskips them).
- **1.3 refactor(paint): extract shared spec** (`_PaintSpec`, label helpers → own file) — the one
  non-mechanical prerequisite, so that
- **1.4-1.5 refactor(paint): bodies + tool picker move to `paint/presentation/bodies/`** are genuinely
  mechanical diff-proven moves.
- **1.6a chore: pure dead-code deletions** — ToolbarController, ToolbarUiState, ModeId, EditorMode,
  QuickActionCapsule (306 ln), `DocumentController.liveReplace`, `setDashPattern`, dead
  `ToolbarSlot.valueBadge`. **Keep `SlotPresentation`** (1.9 reuses it). Zero-consumer status verified.
- **1.6b chore: retire `ToolbarItem` alias + dead text session API.** Alias has live consumers in
  editor_screen (:344, 9 literals) — renamed here. Text `TextToolCategory`/7 dead methods deleted;
  blast radius: `text_tool_controller_test.dart:57-96` deleted-with-API (named in body); the
  editor_canvas dockBusy guard reading text openSlot adjusted here.
- **1.7 feat(toolbar): `EditorModeController`** — mode = explicit session (paint/crop/mask/compose) ▸
  multi ▸ selected-layer type ▸ idle. Text `panelOpen` stops driving mode (verified safe: exactly one
  production writer, selection guaranteed at that point). Commit body lists the three intentional
  behavior kills for Gate A: stale-text-mode-after-reselect, drawer-selection-shows-wrong-toolbar,
  undo-strands-disabled-text-bar. Blast radius: dismiss_panels_test + editor_screen widget tests audited.
- **1.8 refactor(editor): editor_screen consumes it** — `_resolveDock` ladder ×3 + `_activeToolId` die.
- **1.9 feat(toolbar): unified slot registry.** ToolbarSlot gains swatch/fontFamily/value resolvers,
  capability predicate, bodyBuilder; one list per mode feeds strip + swipe + capsule;
  `SlotStrip.ensureVisible(activeId)`. **Per-mode tile extents preserved through Stage 1** (68/70/66
  today) — visual unification happens in Stage 2 where redesign is allowed; Gate A stays byte-honest.
- **1.10-1.12 refactor: image / shape+sticker / multi onto the registry**; three identical openSlot
  controllers merge into one `DockToolController`. Blast radius per commit: image/shape/sticker
  controller tests + image_target_resolver_test — migrated in the owning commit. Slot-order drift test
  extended to RENDERED-vs-swipe per mode AS each mode lands (not before).
- **1.13 refactor(text): strip onto SlotStrip+registry** (phase4 §1 parked item — unparked per D-c).
- **1.14 refactor(paint): strip onto SlotStrip+registry** (capability matrix → per-slot predicates).
- **1.15 feat(canvas): `canvasChromeSuppressed` + `selectedLayerProvider`** — replaces 5 divergent
  guards + the 7 per-chrome selectedId scans.
- **1.16 perf: rebuild isolation.** DEPENDS ON 1.7 (add-text staged layer lives only in the overlay;
  committed-doc selects would drop text mode mid-composer without the compose session). Six
  renderedDocumentProvider watches narrowed; snap-guide list identity (SnapResult.none + const
  empties); viewport watch narrowed. Panel bodies stay on the merged view. Before/after rebuild counts
  measured against a generated **200-layer fixture** (also exercises 0.8 prune + drawer scroll).
- **1.17 refactor: `EditorDockMetrics`/`EditorBreakpoints`** (compact rule ×6 → one; strip heights;
  `kMinHitTarget=44`; adds a **wide/tablet breakpoint** per D-f) **+ fix(rtl): strip layer** —
  physical handedness, fade sides, swipe mirroring, PositionedDirectional pill. Unskips 1.2.

**Gate A (you):** capture PNGs byte-comparable except: RTL fixes (1.17). Registry + mode-controller
walkthrough. No visible redesign.

## Stage 2 — One grammar (`tb2`, 16 commits)
Order is load-bearing: contract → overlay migrations → merge-gate flip LAST → chrome.

- **2.1 docs: the interaction contract** (committed to docs/, linked from AGENTS.md):
  three surface classes (live panel / draft session / modal picker); preview channels (transforms →
  InteractionController; layer property edits → LiveOverlay + one command on release; **canvas
  background exempt** — it is a document property the overlay cannot express; it keeps gesture-fenced
  live-merge, documented); undo grouping = gesture-fenced (stepper bursts defined here); exit-semantics
  table (close-panel / exit-mode / clear-selection × every affordance); **claim-decision table**
  (pointer origin × selection state × mode → gesture owner) that Stage 3 implements row by row;
  **app-pause policy**: overlay preview commits on pause (never discards) — pause-time flushNow then
  persists it; post-Stage-2 fate of live-merge flags (permitted: steppers, canvas bg; rest removed).
- **2.2-2.4 refactor: overlay migrations** (hosts wire onChanged → LiveOverlay preview AND
  onCommitted/dragEnd → ONE non-live execute): 2.2 image adjust/border/shadow/vignette (overlay-driven
  effect preview verified feasible — effect cache already budgets for it); 2.3 shape fill/stroke/radius
  + **paint stroke-color/opacity + paint size** (all three UI surfaces; PaintSizeBody API change +
  paint_size_sheet doc-watch rewiring named); 2.4 **text color** (routes through the styleDrag session
  like every text slider). Eraser sweep → one CompositeCommand (rides 2.3).
- **2.5 fix(color): ColorPickerBody hosts complete the live/settled contract** everywhere; hex commits
  on complete input; preset picks don't pollute recents; eyedropper cancel = zero history entries.
- **2.6 feat(engine): merge-gate flip** — `live` flag on UpdateTextCommand + UpdatePaintStyleCommand,
  discrete taps never merge. Lands AFTER 2.2-2.4 so nothing per-tick remains un-flagged. Paired
  merge-matrix tests (live merges / discrete don't / two separate drags = two entries) land first
  skipped, flip here. Blast radius: `text_commands_test.dart:18-64` migrated in-commit.
- **2.7 refactor: ONE overflow sheet.** Row-spec union (acceptance list): edit-text · align link ·
  opacity link · B/I/U inline row · rename · duplicate · reorder fwd/back · lock · resize-mode row
  (text/shape/paint) · text-direction row · layers link · delete (single confirm-before-pop sequence)
  · multi variant: count header + batch delete/duplicate/lock (CompositeCommand). Replaces all three
  sheets. Blast radius: selected_layer_actions_sheet_test (4), text_more_sheet_test (2).
- **2.8 feat: modal host `showEditorSheet`.** Full grep-verified inventory (~17 surfaces) with an
  explicit migrate/stay-dialog decision per surface (font picker, paint size, color picker, composer,
  export, shape picker, sticker picker, both image-source sheets (merged), canvas-image pick, size
  dialogs stay AlertDialog…). Barrier enum {none, whisper, full} keyed by live-preview; **export uses
  barrier=full AND registers as a session in 2.12** (undo-during-render exposure). Blast radius:
  modal_sheet_overflow_test rewritten once here.
- **2.9 refactor: floating chrome.** Paint/shape pills die; ONE registry-derived QuickCapsule for all
  types; **sticker capsule gets a More slot wired to 2.7's sheet in this commit** (stickers currently
  have NO overflow anywhere — no regression window); shape/paint resize-mode surfaces as capsule
  accelerator + 2.7 row; capsule width computed from content for FloatingToolbarPositioner. Blast
  radius: text_quick_capsule_test (:150 expects QuickActionsOverlay for stickers),
  protected_base_photo_chrome_test, quick_actions_overlay tests — all named.
- **2.10 fix: exit semantics per 2.1 table** — Done-pill scope, canvas-panel resurrect,
  Filters/Adjust restore prior selection like Crop.
- **2.11 l10n: `EditorValueFormat`** (locale digits, ٪/px placement, ~30 sites) + layers panel names
  localized (stable ordinal, not live index). Lands BEFORE 2.12 so px-readout tests migrate once.
  Blast radius: text_size_panel_test (regex `^\d+px$`, literal taps), text_panel_header_value_test.
- **2.12 feat(text): TextStyleWriter seam + font live preview.** One write API resolving
  overlay-vs-execute internally; all-fonts sheet applies-on-highlight with revert-on-dismiss
  (long-text latency policy from 2.1: preview debounced, content capped); size readout reports visual
  px (numeric expectations only — format already migrated in 2.11).
- **2.13 feat: session registry.** DISABLES affordances while a draft session is open: top-bar
  undo/redo AND the editor_canvas multi-tap shortcut (currently ungated). The doc-listener
  cancellation nets are correctness backstops and are explicitly RETAINED. Export registered here.
  Layers-drawer edge-swipe disabled during crop/mask.
- **2.14 a11y: ≥44dp hit areas** (visual sizes unchanged) via kMinHitTarget; Semantics on swatches,
  script tabs, segmented controls.
- **2.15 polish: chip-grammar unification** (three chip families → one; phase4 parked, unparked per D-c).
- **2.16 polish: tile-extent + strip visual unification** (the 68/70/66 cleanup deferred out of Stage 1).

## Stage 3 — Gestures & selection (`tb3`, 11 commits, simulator-verified each)
All claim/tap changes implement rows of the 2.1 claim-decision table; 3.1→3.3 are sequential.

- **3.1 Two-finger = viewport.** Claim-on-down only when first pointer on selected bbox
  (hit-testing the OUTSET chrome quad, not the raw bbox) or `interactionController.isActive`; two
  fingers starting off-layer → viewport. Named consequences in spec: off-canvas recovery survives
  (canvas-space bbox test extrapolates), small-object pinch survives (recognizer already accepts
  second fingers), body-tap re-injection path unchanged, deferred-start unchanged. Stay-green gates:
  the five two-finger test files.
- **3.2 Drag-on-unselected-layer selects-and-moves.** Seams named: claim surface extends to any
  eligible layer bbox (today _BodyDragSurface mounts only with a selection — an empty-selection drag
  currently goes to viewport pan; new rule: 1-finger drag starting ON a layer selects+moves it,
  starting on empty canvas pans). Hit-test + select at slop promotion.
- **3.3 Tap latency + double-tap + long-press.** Immediate-accept tap recognizer at canvas level;
  double-tap window logic lives in `_handleTap` so BOTH entry paths share it (canvas detector AND
  body-surface re-injection — the seam the draft missed). Double-tap opens the text editor from
  selected AND unselected states (no narrowing; text_double_tap_edit_test stays green). Long-press on
  selected layer: option (a) — defer-start applies on-bbox too (arena still claimed; only first
  DragPhase.start waits for slop), so the long-press timer can fire. Blast radius: tap_cycling_test,
  multi_select_mode_test audited.
- **3.4 Paint: dots + navigation + safe exit.** Custom recognizer/Listener replaces the pan wiring
  (pointer-count tracked; second down cancels in-flight draft and drives viewportController
  gestureUpdate — verified NOT expressible in the existing pan arena). Tap behavior per kind:
  freestyle → dot (engine path verified); two-point/shape kinds → no-op; eraser miss-tap → no-op.
  Exit only via Done / pasteboard tap.
- **3.5 Multi-select surfaces.** Visible exit chip + count; drawer rows show `selection.contains`,
  tap toggles in multi mode. (Batch ops shipped in 2.7.)
- **3.6 Handles (D-a screenshot gate inside the stage).** Restore 4th resize corner, rotate relocates
  above-center (rotation math verified position-agnostic). Four seams + blast radius named:
  selection_handle_drag_test, selection_handle_size_test, resize_snap_test, single_layer overlay
  tests, capture variants.
- **3.7 Viewport guardrails.** Translation bounds (+ clamp-on-restore for persisted viewports),
  tappable zoom readout → fit/100%, fit fix for >7000px docs (minScale derived from fit), photo-import
  dimension-cap decision. reflowPreservingZoom interaction test.

**Gate C (you, on device):** feel pass fa+en, light+dark, phone + iPad (D-f).

## Stage 4 — Product completion (`tb4`, 14 commits)

- **4.1 «لوک» Look panel.** One surface: preset row = the FILTER presets (independent matrix channel —
  the cleanest of the three systems); fine-tune disclosure = adjustments sliders. Style tiles and
  Adjust preset chips die. Explicit rule: «بدون» resets filterPreset only; fine-tune never resets
  presets; both channels compose (unchanged engine semantics, zero doc migration). Blast radius:
  capture filter variants, image_tool_controller_test, entry_flows_test:114.
- **4.2 Gradient fill UI** — Solid/Gradient segmented + 2-stop presets + angle in shape Style and
  canvas Background. Engine untouched (0.5/0.6 fixed the commands). Stop-editor = backlog.
- **4.3 feat(engine): paint restyle post-commit.** UpdatePaintStyleCommand gains blurSigma/sides;
  kind-switch constrained to the box-kind subset (kind is copyAll-only today — verified);
  mergeWith field-parity extended in-commit. Paint layer gets its dock mode via registry; slot-hiding
  guard + dimmed size modal die. BREAKING-INTERNAL.
- **4.4 Canvas resize UI.** SetCanvasSizeCommand EXISTS (crop pipeline consumer) — new work is UI +
  viewport refit + anchor policy: apply() semantics untouched (crop depends on them;
  crop_photo_workflow_test is the canary); presets offer center-anchor via CompositeCommand
  (size + translate layers); custom keeps top-left with the shrink-strands-layers case documented.
  Shared size-form component (Home create / editor resize / export custom). Direct unit tests added
  (command has none today).
- **4.5 Save/IA.** Dirty chip (commit-version vs last save — designed for this); title menu
  (rename/resize/fit/save); Layers icon in top bar; New-document leaves the editor (Home creates).
- **4.6 Parity sweep.** Replace = one-shot chip, same tier, all modes; sticker size presets
  canvas-scaled; shape stroke precision slider; radius/shadow presets canvas-proportional; duplicate
  “opacity” controls disambiguated.
- **4.7 (stretch, D-g) Flip H/V.** Verified NOT a one-liner: no flip exists in LayerTransform
  ({x,y,w,h,r} wire shape). Requires a mini design doc first (AGENTS rule), a per-layer flag with
  omit-default serialization + new fixture + legacy-lift, per-module render support. Ships only if
  D-g approves the scope; otherwise backlog.
- **4.8 Export intent + fa parity.** Sheet CTA intent flows into preview primary; fa digits/labels;
  gradient-aware letterbox/flatten. Blast radius: export_background_test.
- **4.9 Mask promotion** — 'Selective' slot in the image registry.
- **4.10 Crop v2 (D-b).** Non-destructive source-window crop (NEW PERSISTED FIELD → fixture +
  schema-coverage + legacy-lift per standing rule), on-canvas token-styled session (mask-edit
  grammar), preview shows Look. Rotation/straighten deferred. Blast radius: crop suite migration named.
- **4.11 Templates: placeholder image layers** (asset-sourced pixels verified end-to-end through
  codec/render/export/replace) + 'tap to replace' + Playfair font fallback fix. Widget test for
  asset render + replace. Registration per traps checklist.
- **4.12-4.14 buffer:** font-panel backlog surfaces reserved (weight/favorites), long-text hardening
  from 2.1 policy, follow-through items Gate C generates.

## Stage 5 — Polish & hardening (`tb5`, 9 commits)

- 5.1 Tokens: crop overlay (~12), guides (#FF2D95 dies), HUD, checkerboard (cached raster — kills the
  per-tile drawRect storm), drawer stragglers.
- 5.2 Semantics: layers/handles/mode chips; PrecisionDisclosure expanded state + RTL chevron;
  textScaler clamp policy (D-e).
- 5.3 Motion: one duration/curve source; reduced-motion audit.
- 5.4 Tests: **capture variants + deterministic byte-compare** (Look, gradient, multi, resize,
  capsule, iPad-wide) — NOT goldens: repo has zero golden infra and CI renders on ubuntu vs macOS dev;
  goldens only if a dedicated infra commit is approved later. Invert-harness + codec-diff harness
  (old roadmap 5.1/5.2 absorbed).
- 5.5 editor_canvas split (viewport host / gesture router / board / chrome). Stay-green gate: the
  entire test/widget gesture suite.
- 5.6 TextToolController split (DockUi / StyleWriter (exists since 2.12) / TextMetrics shared with
  renderer — kills `_translateFontSizeForVisualScale` / insertion policy). Gate:
  text_tool_controller_test.
- 5.7 Docs: architecture doc; stale-lore fixes (chevrons DO auto-mirror); audit doc committed;
  stale banners cleaned.
- 5.8 Hygiene: stale TextFloatingToolbar comment, sync existsSync → async, decode-cap helper
  (5 duplicate mappings), zoomBy/panBy dead-API decision, low-storage journal-write warning surface.

## Edge-case matrix (expanded per critic; every stage tests against it)

Per tool: undo/redo mid-panel/mid-session/mid-drag · locked/hidden layers · base-photo protection ·
template gradient content (71/183) · missing/relink source · empty doc · >7000px docs ·
**200-layer doc** (drawer, tap-cycle, prune, rebuild counts — 1.16 fixture) ·
**very long text layers** (composer, font-preview latency, capsule anchoring — 2.12) ·
**app pause/interruption mid-drag & mid-session** (overlay commits on pause — 2.1 policy) ·
**low storage / journal write failure** (0.9 + 5.8 warning) ·
**undo during export render** (2.8/2.13) ·
**mid-session locale/direction switch** (readouts, strip order, swipe, pill — one widget test) ·
keyboard insets · compact + landscape · **iPad/wide** (1.17 breakpoint, 5.4 variant, Gate C pass) ·
fa/RTL + en/LTR · project switch / journal recovery · multi with protected base · eyedropper under
new chrome · export during dirty state.

## Decisions

| id | decision | when | recommendation |
|---|---|---|---|
| D-a | rotate-handle relocation | 3.6 screenshot gate | above-center |
| D-b | crop v2 scope (non-destructive + on-canvas) | before 4.10 | yes, rotation deferred |
| D-c | phase4 §1 parked items unparked | now (this approval) | yes |
| D-d | RTL undo/redo rail order | 1.2 pins it | keep mirrored |
| D-e | textScaler clamp policy | 5.2 | clamp 1.0–1.3 in editor chrome |
| D-f | tablet policy | 1.17 | wide breakpoint + iPad capture + Gate C iPad pass |
| D-g | flip H/V scope | before 4.7 | mini design doc first; stretch |

## Gates

Gate 0 = this roadmap (approved 2026-07-23). Gate A = end Stage 1 (architecture; pixels unchanged
except 1.17 RTL). Gate C = end Stage 3 (device feel, phone + iPad). Final = end Stage 5.
Stages 0/2/4: screenshot review in-thread, no hard stop.
