# Canvas Engine — Architecture

A modular Flutter editor engine. Initial focus: text on canvas. Designed to
expand to images, shapes, stickers, drawing, filters, etc. without rewrites.

## Layering

```
engine  →  application  →  presentation
```

* **engine/** — pure Dart. No widgets, no providers. Holds the document,
  transform math, commands, and interaction math. Trivially unit-testable.
* **application/** — Riverpod controllers. Orchestrates commands and owns
  ephemeral interaction state. The ONLY layer allowed to call into engine
  commands.
* **presentation/** — widgets. Captures gestures, forwards raw coordinates,
  renders state. Contains zero transform math.

### Engine subfolders

| Folder | Responsibility |
|---|---|
| `engine/core/` | `EditorDocument`, `EditorLayer` (abstract), `LayerTransform`, `SelectionState`, `LayerCapabilities` |
| `engine/commands/` | `EditorCommand` + concrete commands + `HistoryStack` |
| `engine/modules/<type>/` | Layer-type specific data + rendering (`TextLayer`) |
| `engine/interaction/` | `InteractionEngine` (pure math) + `InteractionSession` |
| `engine/rendering/` | Thin widgets that turn a `LayerTransform` into Flutter |

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
   - implement `withTransform()` preserving your fields,
   - implement `buildContent(BuildContext)` to render inside a box of
     `transform.size` (translation + rotation are applied for you).
3. Expose a `LayerCapabilities` value — default is `movable/resizable/rotatable`.
   Use `keepsAspectRatio: true` for images, for example.
4. Add a toolbar action that constructs your layer and dispatches
   `AddLayerCommand`.

That's it. Selection, move, resize, rotate and undo/redo all work for free
because none of them read subclass-specific data.

## Engine rules (strict)

1. **Math lives in `engine/`.** If you find yourself calling `math.sin` in a
   widget, stop.
2. **UI forwards raw coordinates.** Handle widgets hand `globalPosition` to
   the canvas, which converts to canvas-local before calling the interaction
   controller.
3. **No god providers.** If a provider grows past one responsibility, split
   it.
4. **Commands are pure.** `apply(doc) -> doc`. No side effects. This is why
   history, serialization, and future collaboration work.
5. **The document is immutable.** All mutations return a new instance.
6. **No premature generalization.** Until single-object move/resize/rotate
   feels perfect, we don't add multi-select, snapping, pan/zoom, or plugins.

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
