# Canvas Engine — Agent Instructions

> This file is read automatically by AI coding agents (Claude Code, Cursor,
> Copilot, Aider, …) before every task. It is the **single source of
> truth** for how to work in this repository. If anything here conflicts
> with code you find, the code is the bug — flag it, do not silently
> match the code.

---

## What this project is

A **modular Flutter photo editor engine**. The current focus is photo
editing (Snapseed / Lightroom Mobile class). The architecture is
designed to extend to design-tool and animation features later, so
**every change must keep that future open** — never collapse generic
machinery into photo-specific shortcuts.

The product target shapes priorities:

* **Pixel quality matters more than layer count.** Users have 5–15
  layers, not 200. Optimise for image fidelity, not document size.
* **Non-destructive editing is sacred.** Adjustments are stored as
  data on layers, never baked into pixels until export.
* **Effects compose.** A blur on top of a brightness on top of a
  curve must produce identical output regardless of which order the
  user applied them in the UI, as long as the resulting stack order
  is the same.

---

## Architecture (read `docs/architecture.md` first)

Three layers, strict direction of dependency:

```
engine  ──▶  application  ──▶  presentation
```

* **`lib/features/editor/engine/`** — provider-free and
  presentation-free. Holds the math, data model, commands, codec, and
  the narrow layer-render contract. `core/` may import Flutter widgets
  only for `EditorLayer.buildContent`; `modules/` may render their own
  content. Commands, interaction math, and serialization stay free of
  app/provider/presentation dependencies.
* **`lib/features/editor/*/application/`** — Riverpod controllers.
  The **only** layer allowed to dispatch engine commands.
* **`lib/features/editor/*/presentation/`** — widgets. Capture
  gestures, render state, contain zero transform math.

**Inverted imports are bugs.** A file in `engine/` must not import
anything from `application/` or `presentation/`. A file in
`application/` must not import from `presentation/`. CI enforces both
directions path-wise (`tool/check_import_direction.sh`, run by
`.github/workflows/ci.yml`). The finer "application should not import
widgets at all" preference remains convention — several controllers
legitimately use `TextPainter`/`BuildContext` today.

### Engine subfolders

| Folder | What lives there |
|---|---|
| `engine/core/` | `EditorDocument`, `EditorLayer` (abstract), `LayerTransform`, `SelectionState`, `LayerCapabilities`, `BackgroundFill`, `LayerMask` |
| `engine/commands/` | `EditorCommand` + concretes + `HistoryStack` |
| `engine/effects/` | `EditorEffect` (sealed) + `EffectStack`; concrete colour adjustments, `VignetteEffect`, `UnknownEffect` forward-compat carrier |
| `engine/modules/<type>/` | One folder per layer type — data + render widget |
| `engine/interaction/` | Pure-math helpers: `InteractionEngine`, `SnapEngine`, `AlignmentEngine`, `GroupEngine` |
| `engine/rendering/` | Thin widgets that turn engine state into Flutter |
| `engine/serialization/` | `DocumentCodec` — the only place that imports every module |
| `engine/export/` | PNG/JPG exporters |

---

## Hard rules (never violate)

1. **`EditorDocument` is immutable.** Every mutation returns a new
   instance via `copyWith`. Never mutate `layers` in place. Never
   add a setter.

2. **Commands are pure.** `apply(doc) → doc`. No side effects, no
   provider reads, no UI calls. The undo stack stores commands, not
   diffs — this is what makes serialization, history, and future
   collaboration possible.

3. **`invert()` takes the document BEFORE apply.** Never the
   document after. Never `null`. If the inverse is genuinely a
   no-op (the target was already gone), return `_NoopCommand()`.

4. **`withTransform()` must preserve every subclass field.** This
   is the most-broken contract by AI agents. When you add a field
   to a `Layer` subclass, audit `withTransform`, `withVisibility`,
   `withLocked`, `withOpacity`, and `copyWith`. Missing one
   silently corrupts the document mid-drag.

5. **Backward-compat in serialization.** When a default value is
   serialised, omit the field. Existing on-disk documents must
   round-trip byte-for-byte after a refactor. If you must change
   the wire format, bump `schemaVersion` and add a reader for the
   old version — never silently break old documents.

6. **No `flutter/material.dart` in engine tests.** Engine tests live
   in `test/engine/` and stay pure. If a test needs Material, it
   belongs in `test/widget/`.

7. **No magic numbers in math code.** Every threshold,
   minimum/maximum, snap distance, animation duration goes in
   `lib/core/constants/engine_constants.dart` with a comment explaining
   the choice.

8. **Coordinate spaces are explicit.** Every gesture handler and
   geometry helper documents whether it works in **canvas space**,
   **screen space**, or **layer-local space**. Mixing them is the
   #1 source of "object jumps when I drag" bugs.

---

## Soft rules (prefer, but justify exceptions)

* Comments explain **why**, not **what**. The existing codebase has
  excellent examples (see `InteractionEngine.updateGesture` for the
  ~20-line comment on focal-point math). Match that bar.
* When a file passes ~600 lines, consider splitting along a clean
  axis — usually data vs. render vs. serialization.
* Prefer `sealed` classes over enums when variants carry data
  (see `BackgroundFill`).
* Public API stability over internal cleverness. Rename internals
  freely; renaming a public type is a breaking change.

---

## How to add a new layer type (the canonical recipe)

1. Create `engine/modules/<type>/<type>_layer.dart`.
2. Extend `EditorLayer`:
   * unique `type` string discriminator
   * immutable fields + `copyWith`
   * implement `withTransform()`, `withVisibility()`,
     `withLocked()`, `withOpacity()`
   * implement `buildContent(BuildContext)` rendering inside a box
     of `transform.size`
   * implement `toJson()` spreading `baseJson()`
   * static `fromJson()` factory
3. Expose a `LayerCapabilities` value (defaults are usually fine).
4. Register `<type>: MyLayer.fromJson` in `DocumentCodec._layerFactories`.
5. Add round-trip tests in `test/engine/<type>_layer_test.dart`.
6. If the layer is user-facing, add the application action that
  constructs it and dispatches `AddLayerCommand`, then wire the
  presentation toolbar or picker to that action. Keep this UI wiring
  outside `engine/`.

That is the entire integration. Selection, transform, undo/redo,
serialization, group operations all work for free because none of
them read subclass-specific data.

---

## How to add a new effect (the photo-editor recipe)

The effect system is **shipped** and lives in
`lib/features/editor/engine/effects/`. Read `docs/effects.md` (the
design record — its status block lists where the as-built system
deliberately diverges) before touching it. The shape that shipped:

1. `EditorEffect` is a **sealed** class with `paint(Canvas, Rect)`
   and an `EffectKind` dual dispatch: `colorMatrix` effects compose
   into ONE 4×5 matrix applied via `ColorFiltered`;
   `customPaint` effects (e.g. vignette) draw an overlay on top.
   There is no per-effect rasterize step.
2. A new effect extends the sealed class in `engine/effects/`,
   registers its `fromJson` in the part-file registry, and follows
   the serialization discipline: default-valued fields omitted,
   round-trip byte-identity proven against the fixture corpus.
3. Effects mutate through **idempotent replace-in-stack commands**
   (`SetImageAdjustmentsCommand` surgically edits the live instance
   in place and must never touch disabled or masked effects;
   `Reorder`/`Toggle`/`DeleteEffectCommand` are structural). Live
   slider streams merge via the `live` flag + field-set match.
4. Rendering currently happens only in `ImageLayer.buildContent`,
   even though `EffectStack` lives on every layer. Per-effect masks
   and the stack mask have model + serialization but no render path
   yet (stack-mask render integration is in flight — see
   `docs/effects-a3-scoped-plan-2026-07.md`). Do not invent a
   renderer for them ad hoc; follow that plan.

---

## Definition of done for any change

1. **Tests pass.** Run `flutter test` locally. Engine tests must
   stay green; if one breaks, it is either a real regression or a
   wrong test — stop and discuss, do not "fix" the test to match
   new behaviour.
2. **No new lints.** `dart analyze` clean.
3. **Schema unchanged or version-bumped.** If you touched anything
   under `engine/serialization/`, run round-trip tests with both
   old and new schema versions.
4. **Comments updated.** If the *why* changed, the comment changed.
5. **One concept per commit.** Splitting a file, renaming a
   symbol, and changing behaviour in the same commit is three
   reverts away from a sane history.

---

## How to ask for help (when you are an agent reading this)

When something is ambiguous, **stop and ask** rather than guess.
The cost of one extra question is far less than the cost of
inventing an API that conflicts with future plans. Specifically:

* New engine concept (effect, mask, blend, group, …) → ask for the
  design doc before coding.
* Cross-cutting refactor (touching > 5 files) → propose the plan
  in chat, get approval, then execute one file at a time.
* Anything that would change `EditorCommand`, `EditorLayer`, or
  `EditorDocument` API → flag it as a breaking change explicitly.

---

## Naming conventions (do not drift)

* `EditorCommand`, `EditorLayer`, `EditorDocument` — keep the
  `Editor` prefix. There are other `Command`/`Layer`/`Document`
  types in the Flutter universe.
* `LayerTransform` is **not** `Transform` (Flutter's widget) and
  **not** `Matrix4`. It's our affine-like POJO.
* Coordinates: `position` for top-left, `center` for centre,
  `pointer` for raw input, `focalPoint` for gesture focal.
* Method prefixes: `with*` returns a copy with one field changed;
  `copyWith` returns a copy with any combination; `apply` is for
  commands; `update*` is for live interaction frames.

---

## Files Claude Code / Copilot should always re-read

When opening a session that touches these areas, load these files
into context **before** writing code:

* Any engine change → `docs/architecture.md`, this file
* Effect work → `docs/effects.md` (design + as-built status block)
  and `docs/effects-a3-scoped-plan-2026-07.md` (in-flight stackMask)
* New layer type → `lib/features/editor/engine/core/editor_layer.dart`
  and one existing module (e.g. `modules/text/text_layer.dart`)
* Command work → `lib/features/editor/engine/commands/editor_command.dart`,
  `commands/history_stack.dart`, and one existing concrete command
* Any editing surface (panel, sheet, session, preview, undo
  grouping) → `docs/editor-interaction-contract-2026-07.md` — the
  binding contract for surface classes, preview channels, gesture
  fencing, and exit semantics

---

## When this file is wrong

This file is policy. Policy can be wrong. If you find a rule that
contradicts a deliberate decision in code, **flag it in chat** —
do not silently update either the rule or the code. The fix is
always a deliberate choice, recorded in a commit message that
explains the reversal.
