# Canvas Engine — Architecture

A modular Flutter photo editor engine. The current focus is photo editing
(Snapseed / Lightroom Mobile class), while the architecture stays generic
enough to support design-tool and animation features later.

## Layering

```
engine  →  application  →  presentation
```

* **engine/** — provider-free and presentation-free. Holds the document,
  transform math, commands, serialization, interaction math, and the narrow
  layer-render contract. `core/` may reference Flutter's `Widget` /
  `BuildContext` for `EditorLayer.buildContent`, and `modules/` may render
  their own content. Commands, interaction, and serialization must not import
  widgets, providers, application, or presentation code.
* **application/** — Riverpod controllers. Orchestrates commands and owns
  ephemeral interaction state. The ONLY layer allowed to call into engine
  commands.
* **presentation/** — widgets. Captures gestures, forwards raw coordinates,
  renders state. Contains zero transform math.

### Engine subfolders

| Folder | Responsibility |
|---|---|
| `engine/core/` | `EditorDocument`, `EditorLayer` (abstract), `LayerTransform`, `SelectionState`, `LayerCapabilities`, `BackgroundFill`, `LayerMask` |
| `engine/commands/` | `EditorCommand` + concrete commands + `HistoryStack` |
| `engine/effects/` | `EditorEffect` (sealed) + `EffectStack` — colour adjustments, vignette, unknown-effect forward compat (see `docs/effects.md`) |
| `engine/modules/<type>/` | Layer-type specific data + rendering (`TextLayer`, `ImageLayer`, `ShapeLayer`, `PaintLayer`) |
| `engine/interaction/` | Pure-math helpers such as `InteractionEngine`, `SnapEngine`, `AlignmentEngine`, `GroupEngine` |
| `engine/rendering/` | Thin widgets that turn a `LayerTransform` into Flutter |
| `engine/serialization/` | `DocumentCodec`, the only place that imports every module |
| `engine/export/` | PNG/JPG exporters |

## State separation

Three controllers, never merged:

* `documentControllerProvider` — the document + undo/redo history.
* `selectionControllerProvider` — which layer is selected.
* `interactionControllerProvider` — live drag session + uncommitted transform.

Mid-gesture we mutate only the interaction controller (60fps), then commit a
single `SetLayerTransformCommand` on gesture end. This keeps the undo stack
flat and the document immutable most of the time.

## How to add a new layer type

1. Create `engine/modules/<type>/<type>_layer.dart`.
2. Extend `EditorLayer`:
   - unique `type` string,
   - your own immutable fields + `copyWith`,
   - implement `withTransform()`, `withVisibility()`, `withLocked()`,
     and `withOpacity()`, preserving every subclass field,
   - implement `buildContent(BuildContext)` to render inside a box of
     `transform.size` (translation + rotation are applied for you),
   - implement `toJson()` spreading `baseJson()`,
   - add a static `fromJson()` factory.
3. Expose a `LayerCapabilities` value — default is `movable/resizable/rotatable`.
   Use `keepsAspectRatio: true` for images, for example.
4. Register `<type>: MyLayer.fromJson` in `DocumentCodec._layerFactories`.
5. Add round-trip tests in `test/engine/<type>_layer_test.dart`.
6. If the layer is user-facing, add an application action that constructs
   your layer and dispatches `AddLayerCommand`, then wire presentation UI to
   that action.

That's it. Selection, move, resize, rotate and undo/redo all work for free
because none of them read subclass-specific data.

## Engine rules (strict)

1. **Math lives in `engine/interaction` or focused engine helpers.** If you
   find yourself calling `math.sin` in a presentation widget, stop.
2. **UI forwards raw coordinates.** Handle widgets hand `globalPosition` to
   the canvas, which converts to canvas-local before calling the interaction
   controller.
3. **No god providers.** If a provider grows past one responsibility, split
   it.
4. **Commands are pure.** `apply(doc) -> doc`. No side effects. This is why
   history, serialization, and future collaboration work.
5. **The document is immutable.** All mutations return a new instance.
6. **No invented engine concepts.** Effects and masks now exist
   (`engine/effects/`, `core/layer_mask.dart` — designed in
   `docs/effects.md`); extend them through their own recipes, not ad
   hoc. For any *new* cross-cutting concept (blend modes, groups,
   plugin hooks, …), read the design doc first or ask. Keep generic
   machinery generic; do not collapse it into a photo-specific
   shortcut.

## Interaction pipeline

```
Gesture (widget) ──global px──► EditorCanvas._toCanvas() ──canvas px──►
InteractionController.start/update/end
        │
        ▼
InteractionEngine (pure math)
        │
        ▼
LayerTransform (live)  ── on end ──► SetLayerTransformCommand ──► HistoryStack
```

## Testing

* `test/engine/` holds engine tests. They never import `flutter/material.dart`.
* Transform math is covered for axis-aligned and rotated resize, rotation,
  and move.
* Commands + history round-trip.
