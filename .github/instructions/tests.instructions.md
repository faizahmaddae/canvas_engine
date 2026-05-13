---
applyTo: "test/**/*.dart"
description: "Test-writing rules. Engine tests are pure; do not mix layers."
---

# Test Rules

Tests are not optional in this repository. Every public engine
method has a unit test. Every command has a forward + inverse +
no-op test. Every codec change has a round-trip + malformed-input
test.

## Structure

```
test/
├── engine/         # Pure Dart tests. NO flutter/material.dart imports.
├── application/    # Controller + Riverpod tests.
├── editor/         # Feature-level integration tests.
├── home/, settings/, widget/  # UI tests (allowed to use Material).
```

## Engine tests (`test/engine/**`)

### Imports — strict

✅ Allowed:
```dart
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:canvas_engine/...';
```

❌ Not allowed:
```dart
import 'package:flutter/material.dart';        // No Material in engine tests
import 'package:flutter/widgets.dart';         // Almost never needed
import 'package:flutter_riverpod/...';         // No providers in engine tests
import '../../lib/features/editor/.../widgets/...';  // No widget imports
```

If your engine test "needs" Material, it is testing the wrong
thing — move it to `test/widget/` or split the unit under test
so the pure logic can be exercised on its own.

### What an engine test looks like

```dart
import 'package:canvas_engine/features/editor/engine/...';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = InteractionEngine();
  final base = LayerTransform(
    position: const Offset(100, 100),
    size: const Size(200, 100),
  );

  group('move', () {
    test('translates by pointer delta', () {
      final session = engine.startMove(
        layerId: 'a',
        transform: base,
        pointer: const Offset(150, 150),
      );
      final next = engine.updateMove(session, const Offset(200, 180));
      expect(next.position, const Offset(150, 130));
      expect(next.size, base.size);
      expect(next.rotation, base.rotation);
    });
  });
}
```

Notes:
* `group` describes the unit under test or a behaviour cluster.
* `test` describes a single observable behaviour, **with** the
  expected outcome in the name. "translates by pointer delta" is
  good. "move test" is not.
* Compute expected values explicitly. Don't `expect(actual, actual)`
  by accident.

### Floating-point comparison

Never `expect(a.dx, b.dx)` for floats. Use `closeTo`:

```dart
expect(corner.dx, closeTo(300, 1e-6));
```

`1e-6` is the standard tolerance in this codebase. Tighter
tolerances should be justified with a comment.

### Coverage targets per kind

* **`engine/core/`** — 100 % of public methods. Equality,
  `copyWith`, JSON round-trip.
* **`engine/commands/`** — every command tested with the five
  patterns from `commands.instructions.md` (forward, inverse,
  no-op, merge, history round-trip).
* **`engine/interaction/`** — math correctness for the cardinal
  cases (axis-aligned, rotated by 0 / π/2 / π / 3π/2, and one
  arbitrary angle).
* **`engine/serialization/`** — every layer type round-trips,
  every malformed-input branch throws `DocumentDecodeException`.
* **`engine/modules/`** — at minimum, JSON round-trip + the
  module's own behaviour-defining methods.

## Don't "fix" failing tests by changing expectations

If an engine test you didn't write fails after your change, the
default assumption is **your change has a regression**. Steps:

1. Read the test. Understand what it asserts.
2. Read the production code at the assertion site.
3. Decide: is the new behaviour intentional, or is it a bug?
4. If intentional, **stop** and write up the rationale in chat.
   Test changes that document a deliberate behaviour shift are
   fine; test changes to mask a regression are not.
5. If a bug, fix the production code.

This rule exists because the engine is the foundation of the
project. A "fixed" test that hides a regression is a delayed bomb.

## Application + UI tests

* These live in `test/application/`, `test/widget/`, etc.
* They may import Material and pump widgets.
* Every controller method has a test.
* For UI tests, prefer `tester.pump()` over `tester.pumpAndSettle()`
  unless you really need to wait for animations — `pumpAndSettle`
  hides timing bugs.

## Test data

When you need a complex `EditorDocument` for a test, build it
with the actual `addLayer` / `replaceLayer` API rather than
constructing an internal state directly. This catches integration
issues that synthetic state would hide.

## Performance / regression tests

We will be adding a `test/engine/benchmarks/` folder. When you do:

* Tests there run the operation N times and assert a per-op time
  budget.
* Use generous budgets initially (2× current measured baseline) —
  CI runs on slow VMs.
* Benchmarks are about **detecting regression**, not absolute
  speed. A 10× slowdown should fail; a 5 % wobble should not.
