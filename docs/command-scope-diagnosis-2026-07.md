# Command scope — diagnosis and migration record (July 2026)

> Evidence base for §10 of `editor-interaction-contract-2026-07.md`.
> The contract states the rules; this file records what the code did
> before them, why the rules are shaped the way they are, and what
> was deliberately not built. Audit register — cites lines, and will
> go stale. The contract does not.

## What was reported

On a newly created empty canvas the main strip shows the five Add
tools first and Crop · Look · Canvas past the horizontal fold, with
Crop and Look dimmed. After adding an image the two appear to move
to the front. With two or more images and nothing selected, opening
Crop or Look edited the first image the user had imported, with no
indication that image was special.

Three separate mechanisms, only one of which was a defect.

## What the code actually did

**The strip never reordered itself.** Group order keyed off
`projectKind`, deliberately — `editor_screen.dart:443-456`, *"keying
off layer contents reshuffled the strip on undo/redo of ANY image
add"* — pinned by `toolbar_group_order_test.dart:126`. What the
reporter saw was a mode swap: `_addImage` ends by selecting the new
layer (`editor_screen.dart:961`), which replaces the whole strip
with `ImageModeToolbar`, whose first two entries are Look then Crop
(`image_tool_controller.dart:59-60`). Deselecting restored the
original order.

**The tiles were never disabled.** Crop and Look were the only two
users of `availableBuilder` (`editor_screen.dart:525,533`) —
dimmed but tappable, with a recovery snackbar on tap
(`editor_screen.dart:1163-1189`). At `baedd22` the dim treatment was
pixel-identical to disabled (`final dim = !enabled ||
widget.unavailable;` at alpha 0.35), which is why it read as
disabled. Split to 0.35/0.70 with measured contrast in the same
working tree that carries this change.

**The target was chosen by invisible import history.** This was the
real defect, and it had four parts:

| # | Mechanism | Where |
|---|---|---|
| D1 | `basePhotoLayerId` written in every project kind, read in every project kind, rendered only in photo projects | `editor_screen.dart:935` (ungated) vs `editor_document.dart:162-163` (`projectKind == ProjectKind.photo && …`) |
| D2 | The resolver filtered by layer TYPE only, never `visible` | `image_target_resolver.dart:69`; every pointer path filters (`canvas_hit_testing.dart:35`) |
| D3 | Image strip drew three tier hairlines instead of one | four `tier: SlotTier.tier2` marks at `image_mode_toolbar.dart:146,170,186,203` against `kImageStripOrder` |
| D5 | The unavailable state was invisible to assistive tech | `dock_tool_tile.dart` Semantics node passes `enabled`, never `unavailable` |

D1 is the one the reporter hit. The pointer was claimed on first
import regardless of kind (only the *lock* was kind-gated,
`editor_screen.dart:936-937`), so a design document silently carried
a marker that steered Crop and Look, survived save/reload, had no
chrome anywhere, and could not be re-aimed short of deleting the
layer.

## Why the ladder was removed rather than fixed

The shipped resolver had five outcomes: selection → sole image →
base-photo pointer → chooser sheet → none. Three findings retired it.

1. **Its first rung was unreachable from the main strip.**
   `editorToolModeProvider` returns `idle` only when nothing is
   selected, and the idle strip is the sole host of those eight
   tiles — any live single selection swaps the dock to that layer's
   mode. So every main-strip Crop/Look invocation was a guess, and
   the rationale defending the base-photo rung
   (`image_target_resolver.dart:50-55`, *"the current selection is a
   sticker / text overlay"*) described a state its only main-strip
   caller could not occupy.
2. **Its chooser rung was unreachable in practice.** Because the
   pointer was always claimed, no sequence of ordinary imports
   reached `ImageTargetAmbiguous`. Across all shipped templates the
   maximum image-layer count is one and none sets a base pointer, so
   the sheet was reachable only after deleting the claimant while two
   or more images remained.
3. **The rungs it could reach were the guesses.** A ladder whose
   certain rungs are dead and whose guessing rung is the default is
   not a resolution policy; it is a default with extra steps.

Rather than make the guess legible, §10 removes the guess: a
command's target is named by the selection, by the project role, or
by the act of creation, and a control with no named target says so.

## Deviations from §10 present at the time it was written

Each is closed by the implementing commit; listed so the diff has a
checklist.

- `resolveImageTarget` read `basePhotoLayerId` with no kind gate
  (§10.1) and filtered on kind without `visible` (§10.2).
- `shouldClaimBase` claimed the pointer in every project kind while
  the lock beside it was kind-gated (§10.1).
- Design projects rendered `crop` and `look` on the main strip
  (§10.1).
- `DockToolTile`'s Semantics node did not surface `unavailable`
  (§10.3).
- Two readers of the raw `basePhotoLayerId` field inline their own
  kind gate rather than calling `isProtectedBasePhoto`
  (`layers_panel.dart:87-89`, `canvas_gesture_router.dart:617-618`).
  Correct today; noted because §10.1 makes the predicate the single
  admissible reader.

**Coverage before the change.** Exactly one test reached the
base-photo rung, and it did so with a `ShapeLayer` selected
(`image_target_resolver_test.dart:185-202`) — a state in which the
main-strip tiles do not render at all, because a shape selection
swaps the dock to `ShapeModeToolbar`. `selectedId == null` reached
that rung nowhere in the suite, and it was the only route the main
strip had. D2, D3 and D5 had no coverage of any kind.

## Deliberately not built

- **A user-facing "Set as base photo" command.** An earlier draft
  required it: if a resolver may consult a persisted designation,
  that designation must be user-changeable. §10 does not consult one
  — the base photo's role is fixed by the project kind — so the
  requirement lapsed with the ladder. Not worth a feature to satisfy
  a taxonomy.
- **A generic scope-resolution ladder for future layer kinds.** No
  shipped workflow needs one. When a second kind acquires a
  role-scoped tool, §10 gets amended; it does not get a framework in
  advance.
- **Hiding the unavailable state.** `availableBuilder`'s doctrine —
  *"A disabled slot is inert: it does not fire [onTap], so it can
  neither explain itself nor offer a way out"*
  (`toolbar_slot.dart:104-119`) — is unchanged and is now §10.3.
  §10.1's absence rule is narrower than it looks: it removes `crop`
  and `look` from the design strip because the SCOPE is inadmissible
  there, not because the target is missing.

## Cost accepted

Design-project users lose the main-strip entry point to Crop and
Look and must select the image first. That is the point — the entry
point was only ever correct when the document held exactly one
image — but it is a real reduction in reachability for a
one-image design, and it is the trade this change makes knowingly.
