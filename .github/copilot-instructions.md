# Copilot Instructions

The authoritative guide for AI assistants in this repository is
[`AGENTS.md`](../AGENTS.md) at the project root. Read it first.

This file mirrors a handful of points that Copilot specifically
benefits from having inline:

## Always

* Respect the three-layer architecture: `engine → application → presentation`.
  Engine is provider-free and presentation-free. `EditorLayer` has a narrow
  Flutter render contract, and module render code may import widgets; commands,
  interaction, and serialization must not.
* Treat `EditorDocument` and every `EditorLayer` subclass as
  immutable. Use `copyWith` / `withTransform`.
* Commands are `(doc) -> doc` pure functions. Implement `invert()`
  taking the document **before** apply.
* Keep backward-compatible serialization. When in doubt, omit
  default values from JSON.
* Run `flutter test` before declaring a task done. Engine tests in
  `test/engine/` must stay green.

## Never

* Add a setter to `EditorDocument` or `EditorLayer`.
* Call into Riverpod / providers from `engine/`.
* Import `flutter/material.dart` in a file under `engine/core/`,
  `engine/commands/`, `engine/interaction/`, or `engine/serialization/`.
* "Fix" a failing engine test by changing the expected value
  without first asking whether the new behaviour is intended.
* Inline a magic number — add it to `lib/core/constants/engine_constants.dart`
  with a rationale comment.

## When unsure

Ask. The standing rule from `AGENTS.md`: "the cost of one extra
question is far less than the cost of inventing an API that
conflicts with future plans."

## Linked files

* [`AGENTS.md`](../AGENTS.md) — full agent guide
* [`docs/architecture.md`](../docs/architecture.md) — architecture rationale
* [`.github/instructions/engine.instructions.md`](instructions/engine.instructions.md) — engine-specific rules
* [`.github/instructions/commands.instructions.md`](instructions/commands.instructions.md) — command pattern rules
* [`.github/instructions/tests.instructions.md`](instructions/tests.instructions.md) — test rules
