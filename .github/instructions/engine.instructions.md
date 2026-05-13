---
applyTo: "lib/features/editor/engine/**/*.dart"
description: "Hard rules for the engine layer — provider-free core, scoped rendering exceptions."
---

# Engine Layer Rules

These rules apply to **every file under `lib/features/editor/engine/`**.
They are stricter than the general project guide because the engine is
the part that future features (animation, collaboration, plugins) will
build on.

## Imports

| Subfolder | Allowed imports |
|---|---|
| `engine/core/` | `dart:*`, `package:flutter/foundation.dart`, `package:flutter/painting.dart`, `package:flutter/widgets.dart` (only `Widget`, `BuildContext`, `Matrix4` — see exception below) |
| `engine/commands/` | `dart:*`, plus `engine/core/` |
| `engine/interaction/` | `dart:*`, plus `engine/core/`, plus `core/` (utils/constants) |
| `engine/serialization/` | `dart:convert`, plus `engine/core/`, plus every `engine/modules/*` |
| `engine/modules/<type>/` | `dart:*`, `package:flutter/material.dart` is allowed (rendering lives here), plus `engine/core/` |
| `engine/rendering/` | Anything Flutter — these are widgets by definition |
| `engine/export/` | Anything needed for export |

**No `engine/*` file ever imports from `application/`, `presentation/`,
or `app/`.** That direction is one-way.

## Mutability

* Every class is `@immutable`.
* Every field is `final`.
* Mutation = return a new instance via `copyWith` or a `with*` method.
* Lists are constructed with `growable: false` when they are returned
  from a public API to make accidental mutation crash early.

## Equality

* Implement `==` and `hashCode` for every value type. Use `Object.hash`
  for compounds and `Object.hashAll` / `listEquals` for collections.
* Don't rely on Dart's default reference equality — the history stack
  and Riverpod's caching depend on real value equality.

## Subclass contract for `EditorLayer`

When you add a field to a layer subclass, **all four** of these need
to preserve it:

1. `withTransform(LayerTransform)` — used during interaction
2. `withVisibility(bool)` — used by the layers panel
3. `withLocked(bool)` — used by the layers panel
4. `withOpacity(double)` — used by the opacity slider
5. `copyWith(...)` — used by feature-specific commands

Missing one means a mid-drag transform silently drops the user's
recent style change. This is the single most common bug class in
this codebase. **Audit all five every time you touch a layer
subclass.**

## Coordinate spaces

Three spaces exist. Mixing them is the source of "object jumps" bugs.

* **Canvas space** — the logical document coordinates. `(0, 0)` is the
  top-left of the document. This is what `LayerTransform.position`
  uses. Persisted in JSON.
* **Screen space** — pixels on the device after viewport zoom and
  pan. Gestures arrive in screen space. The `EditorCanvas` widget
  converts screen → canvas before forwarding to engine.
* **Layer-local space** — coordinates inside a layer's box, where
  `(0, 0)` is the layer's top-left **before** rotation is applied.
  Used by rotated-resize math.

Every public method that takes an `Offset` or `Rect` must say which
space in its doc comment. If a method bridges spaces (e.g.
`screenToCanvas`), say it in the name.

## Floating-point gotchas

* Two angles that should be equal can differ by `1e-16` after a
  `% 2π`. Use small `eps` in cardinal-snap detection (already done in
  `_thresholdFor`).
* Never compare floats with `==`. Use `closeTo` in tests, explicit
  tolerance in code.
* Don't divide by `width` / `height` without checking they are
  positive. A degenerate zero-size rect during transient empty
  states is a real possibility.

## Performance considerations

* Engine code runs every frame during interaction (60 fps target).
  Operations that are O(n) per layer are fine. Operations that are
  O(n²) need a comment explaining why.
* `copyWith` on `EditorDocument` rebuilds `_layerIndex`. That is
  O(n) — deliberate, documented, currently fine for n ≤ ~500. If
  you find profiling evidence this is hot, see the persistent-data
  TODO in the roadmap; do not optimise without evidence.
* No allocations inside interaction inner loops if you can help
  it. Reuse `Offset` / `Size` results; don't build maps in the
  hot path.

## Do not

* Add fields to `EditorDocument` without thinking about
  serialization defaults. Every new field needs an
  "omit when default" rule in `DocumentCodec.toJson`.
* Throw plain `Exception`. Throw `DocumentDecodeException`,
  `FormatException`, or `StateError` with a message that names
  the contract violated.
* Reach into `private _members` from outside the class. If you
  need it, make it `@protected` or refactor.
