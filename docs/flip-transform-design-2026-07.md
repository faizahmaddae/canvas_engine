# Flip H/V — design note — July 2026

> Decision D-g of `toolbar-redesign-roadmap-2026-07.md`. AGENTS.md
> requires a design note before a new persisted field; this is it.
> Verdict: **ship**, at the cost the roadmap feared but at a fraction
> of the surface it assumed.

## The gap

Every other editor's most-used transform is missing. A user who
imports a portrait facing the wrong way, or wants a mirrored arrow,
has no move. The audit found no workaround either: negative sizes are
rejected by the resize clamp, and rotating 180° is not a flip (it
mirrors both axes at once *and* turns text upside down).

## Why the roadmap over-estimated it

The roadmap assumed "per-module render support" — five layer types
each teaching themselves to draw mirrored. That is not how this
renderer is built.

`LayerTransform` is documented as the single source of truth for a
layer's pose, and exactly one widget consumes it:
`LayerRenderer.build` positions the layer and applies
`Transform.rotate`. Every layer type renders inside that one wrapper,
and the exporter renders the same widget tree. So a flip applied
there is a flip everywhere — canvas, thumbnails, PNG and JPG export —
with no per-module work at all.

The real cost is in the two places that map canvas coordinates into
layer-local space (`layer_space_mapper.dart`), which must mirror the
same axes or hit-testing and handle drags land on the wrong side of a
flipped layer.

## The field

`LayerTransform` gains two bools:

```dart
final bool flipH;   // mirrored across the vertical axis
final bool flipV;   // mirrored across the horizontal axis
```

Serialized as `'fx'` / `'fy'`, **omitted when false**, so every
existing document round-trips byte-identically and the fixture corpus
stays valid. Decode treats a missing key as `false` — the legacy lift
is the absence itself, which is why it needs a fixture that proves an
old document still decodes rather than a migration step.

Order of operations: flip is applied in the layer's own local frame,
*inside* rotation. Mirroring a rotated layer therefore mirrors the
artwork, not the rotation — which is what "flip this photo" means to
a person looking at it. The alternative (mirror the whole pose) makes
a rotated layer jump across the canvas.

## Why bools and not a negative scale

A `scaleX: -1` in the transform would express the same thing and
compose more generally. It also silently invites non-unit values,
which would duplicate `size` as a second scale channel and force
every consumer to decide which one wins. Two booleans cannot drift.

## Interaction

* **Where it lives:** the layer overflow sheet (More), next to the
  other whole-layer operations, for every layer type. It is not a
  strip tile — flipping is decisive and infrequent, not a value the
  user tunes.
* **Undo:** one `FlipLayerCommand` per tap, inverting to itself
  (flipping twice on the same axis is the identity, so `invert`
  returns the same command — the simplest possible inverse and one
  that cannot drift from `apply`).
* **Multi-select:** flips each selected layer about its OWN centre,
  bundled in a `CompositeCommand`. Mirroring a group about the group
  centre would move layers, which is a different (unasked-for)
  operation.
* **Text:** mirrored text is unreadable, which is exactly what the
  user asked for when they flip a text layer deliberately. No special
  case; the operation is reversible in one tap.

## What this does NOT include

Flip as a *gesture* (dragging a resize handle past the opposite edge)
stays out. It reads as an accident more often than as an intent, and
the resize clamp that currently prevents it is also what stops a
layer collapsing to zero.
