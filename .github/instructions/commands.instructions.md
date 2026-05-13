---
applyTo: "lib/features/editor/engine/commands/**/*.dart"
description: "Rules for the command pattern. Commands are how the document changes."
---

# Command Pattern Rules

Every mutation to an `EditorDocument` happens through an
`EditorCommand`. Direct mutation does not exist by design — that is
how undo/redo, serialization, and future collaborative editing
become possible.

## The contract

```dart
abstract class EditorCommand {
  String get label;
  EditorDocument apply(EditorDocument document);
  EditorCommand invert(EditorDocument documentBeforeApply);
  EditorCommand? mergeWith(EditorCommand previous) => null;
}
```

Five rules govern every concrete command.

### 1. `apply` is pure

* No side effects. No file IO, no provider reads, no UI calls.
* No reading from anything except the input `document` and the
  command's own fields.
* Same input → same output. Always.

### 2. `apply` is "no-op safe"

If applying would not change the document (e.g. the target layer
no longer exists, the new value equals the current value), return
the input document **identically** (`return document;`). Never
return a fresh copy that happens to be equal — `HistoryStack`
checks `identical(next, document)` to decide whether to record
the entry.

### 3. `invert` takes the document **before** apply

```dart
EditorCommand invert(EditorDocument documentBeforeApply);
```

* Read the field you are about to overwrite **from the parameter**,
  not from `apply()`'s input.
* Capture enough state to fully restore. If you are setting
  `layer.opacity = 0.5`, the inverse needs to remember the previous
  opacity, not assume `1.0`.
* If the target is gone (defensive case), return `_NoopCommand()`.
  Never throw, never return `null`.

### 4. `mergeWith` is opt-in and conservative

`mergeWith` collapses a stream of fast successive edits (slider
drags, repeated nudges) into a single undo step. The default is
`null` (no merge). Implement it only when:

* The previous command targets **the same layer** (or same set).
* The previous command sets **the same fields** you are about to
  set.
* No other command has been pushed in between (the stack only
  exposes the immediate top).

Returning a merged command means: "use this as the new forward,
keep the existing inverse from the previous entry, so undo jumps
back to the state before the stream began."

If unsure, return `null`. The cost of an extra undo step is far
less than the cost of swallowing an unrelated edit.

### 5. Composite commands are linear

`CompositeCommand` exists for grouped operations. When you build
one:

* Ordered execution — commands run in list order.
* `invert` walks the original document forward through each
  command in order to capture each inverse, then reverses the
  inverse list. This is how you get correct undo for an N-step
  bundle.
* Don't nest composites unless you have a real reason — flatten
  during construction.

## Common command shapes

### "Set field on layer"

```dart
class SetFooCommand extends EditorCommand {
  const SetFooCommand({required this.layerId, required this.foo});
  final String layerId;
  final Foo foo;

  @override
  String get label => 'Set foo';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! MyLayer) return doc;          // Not our type — no-op
    if (layer.foo == foo) return doc;            // No change — no-op
    return doc.replaceLayer(layer.copyWith(foo: foo));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! MyLayer) return const _NoopCommand();
    return SetFooCommand(layerId: layerId, foo: layer.foo);
  }

  @override
  EditorCommand? mergeWith(EditorCommand previous) {
    if (previous is! SetFooCommand) return null;
    if (previous.layerId != layerId) return null;
    return this;  // Same layer, same field — collapse.
  }
}
```

This template covers ~80 % of new commands. Match it.

### "Add / remove layer"

* `AddLayerCommand` — its inverse is `RemoveLayerCommand(id)`.
* `RemoveLayerCommand` — its inverse is `AddLayerCommand(prev)`,
  where `prev` is the captured layer instance from `before`. If the
  target was already gone, return `_NoopCommand`.

## Naming

* `Set<Field>Command` — replace one field on a layer.
* `Add<Type>Command` — add a layer to the document.
* `Remove<Type>Command` — remove by id.
* `Toggle<Field>Command` — boolean flip; the inverse is itself.
* `Reorder<Type>Command` — change z-order.
* `<Verb>LayerCommand` for transform-y verbs (`MoveLayerCommand`,
  `ResizeLayerCommand`, `RotateLayerCommand`).

## What goes in `application/` instead

Commands are atomic mutations. Anything **not atomic** belongs in
the controller, not the command:

* "Snap then commit on release" — controller orchestrates; the
  command at commit is just `SetLayerTransformCommand`.
* "Pick a colour from a sheet, then apply it" — controller; the
  command is just `SetFooCommand`.
* "Confirm before delete" — controller asks; the command runs only
  on yes.

If your command body has `if (userConfirmed) ... else ...` in it,
the logic is in the wrong layer.

## Tests for every new command

A commands test (`test/engine/<feature>_commands_test.dart`)
should cover:

1. **Forward** — `apply` produces the expected document.
2. **Inverse** — `invert(before).apply(after)` round-trips back.
3. **No-op** — apply on a document where the target is missing
   or already at the target value returns identically.
4. **Merge** — if `mergeWith` is implemented, two commands merge
   into one entry whose inverse still restores the original
   pre-merge state.
5. **Round-trip with history** — push, undo, redo, undo through
   a `HistoryStack` and check state matches at each step.
