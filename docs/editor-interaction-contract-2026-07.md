# Editor Interaction Contract — July 2026

> Binding contract for how every editor surface previews, commits,
> cancels, and groups undo. Lands as roadmap item tb2 1/16
> (`toolbar-redesign-roadmap-2026-07.md`); Stage 2 commits enforce it
> and cite the section they implement. Tests are the arbiter: each
> rule names its pinning suite once one exists. When code must
> deviate, the deviation is recorded here in the same commit.

## 1. The three surface classes

Every editing surface is exactly one of these. New tools pick a
class; they do not invent hybrids.

**L — Live panel** (dock sub-tool sheets, context panels, canvas
panel). Controls apply instantly against a preview channel (§2);
release/settle commits ONE undoable command. Closing (✕, handle,
swipe-down, re-tap tile, tap-empty) never reverts — undo is the
escape hatch. The canvas is never dimmed: the whole point is seeing
the live change.

**D — Draft session** (crop, mask edit, text content composing;
export render+save registers as a session too, §6). An explicit
modal state with its own Done/Cancel affordances. Gestures and
controls mutate only the session's draft; **Done = exactly one
command; Cancel = zero document effect, including any styling
tweaked mid-session**; system back = Cancel. Undo/redo affordances
are disabled while a session is open (§6). Sessions restore the
prior selection on exit.

**M — Modal picker** (font browser, custom color, pickers, export
sheet, list sheets, dialogs). Hosted by the single modal host
(tb2 8/16) with one chrome grammar and a 3-value barrier policy:
`none` (surface live-previews the canvas and must not obscure it),
`whisper` (6% — keep context visible), `full` (default; also
mandatory for export while bytes are being produced). Tapping a
value either applies live (then behaves like L) or commits on pick;
"closing without choosing" must equal the state at open UNLESS the
surface is class L in disguise — then it must say so by keeping the
canvas visible (barrier none/whisper).

## 2. Preview channels (one per input kind)

- **Pointer transforms** (drag/pinch/rotate/handles) →
  `InteractionController` live state. Zero document writes
  mid-gesture; one `SetLayerTransformCommand`/composite on release.
- **Layer property edits** (sliders, pads, swatch drags) →
  `LiveOverlay` staging + ONE non-live command on release/settle
  (`layer_opacity_control` is the canonical template; text routes
  through its style-drag session which is the same channel).
- **Canvas background** — EXEMPT: it is a document property the
  overlay cannot express. It keeps gesture-fenced `live:true`
  command merging. This is the only sanctioned per-tick committed
  write, and it must stay gesture-fenced (§3).
- `DocumentController.liveReplace` is deleted; there is no fourth
  channel. Adding one requires amending this contract first.

## 3. Undo grouping = gesture fencing

One user gesture — a full slider drag, a pad drag, an eraser sweep,
a draft session — is ONE history entry. Two discrete taps are TWO
entries, regardless of how close in time. Mechanics:

- Continuous controls stream previews (§2) and commit once on
  release → fencing is structural, not time-based.
- Stepper/nudge buttons (A+/A−, ±10%) are the sanctioned use of
  `live:true` command merging: a burst coalesces; the merge chain
  breaks when a DIFFERENT control writes. After tb2 6/16,
  `UpdateTextCommand`/`UpdatePaintStyleCommand` merge ONLY with
  `live: true`; swatch taps and toggles pass `live: false`.
- Post-Stage-2 fate of `live:true` merging (roadmap decision):
  permitted for steppers and the canvas background only. Everything
  else must not rely on the 1s wall-clock window, which survives
  solely as the coalescer for those two cases.
- No net-zero entries: an interaction that ends where it started
  commits nothing (0.25px/epsilon guards stay).

## 4. Exit semantics — the three levels

| Level | Meaning | Affordances mapped to it |
|---|---|---|
| E1 close-panel | Collapse the open sub-tool; mode + selection stay | panel ✕, drag-handle tap, swipe-down, re-tap active tile |
| E2 exit-mode | End the mode/session; selection per session rules | Done pill (paint/text), session Done/Cancel, PopScope back in a session |
| E3 clear-selection | Deselect; dock returns to idle | tap empty canvas/pasteboard (also implies E1+E2 for live panels) |

Rules: every affordance maps to exactly one level; E3 always
implies E1; the Done pill is E2 (it must also close that mode's
panels — E1 — before clearing); a canvas-panel must obey E3
(tap-empty closes it and it must NOT resurrect on the next
deselect — tb2 10/16 fixes the known violation). Crop's Done/Cancel
restore `priorSelectionId`; Filters/Adjust entered from the main
strip must restore prior selection the same way (tb2 10/16).

## 5. The claim-decision table (Stage 3 implements; recorded now)

Pointer-owner resolution, in order, per FIRST pointer landing:

| # | Pointer origin | Selection state | Mode | Owner |
|---|---|---|---|---|
| 1 | anywhere | — | crop/mask session | the session overlay |
| 2 | anywhere, 2nd finger joins | — | paint | viewport (cancel in-flight stroke) |
| 3 | on canvas | — | paint | stroke (tap = dot; freestyle only) |
| 4 | selected layer's chrome quad (outset) | single | any | transform session (eager) |
| 5 | another **pointer-eligible** layer's bbox | any | not paint | select-then-move that layer (start deferred to slop) |
| 6 | anywhere, 2nd finger joins, not started on chrome quad | any | any | viewport pinch |
| 7 | empty canvas | any | any | tap→E3; drag→viewport pan |

Long-press (multi entry) requires deferred start — row 4 switches
to defer-at-slop in Stage 3 (3.3) so the timer can fire on-layer.
Double-tap on a TEXT layer opens the editor from selected AND
unselected states; the window logic lives in one place
(`_handleTap`) shared by both entry paths.

## 6. Session registry

One registry lists every open draft session (crop, mask, text
compose/edit, export render+persist). While non-empty: top-bar
undo/redo disabled, the multi-finger undo shortcut inert, the
Layers drawer edge-swipe disabled. The per-session document
listeners that CANCEL on external mutation are correctness
backstops and stay.

## 7. App-pause / interruption policy

Overlay previews COMMIT on pause (never discard): pause-time
`flushNow` must persist what the user sees. Draft sessions keep
their draft across pause; process death loses only the open draft,
never previously committed work. (The pre-Stage-2 behavior held
this property because sliders wrote per-tick; the overlay
migrations must preserve it explicitly — each migration commit
states how.)

## 8. Long-content policy

Very long text layers: the all-fonts live preview debounces
per-highlight re-layout and previews against a capped excerpt
(~200 chars); composer and measurement paths are uncapped. The cap
is a named constant with this rationale.

## 9. Barrier policy quick table

| Surface | Class | Barrier |
|---|---|---|
| Dock sub-tool sheets / context / canvas panels | L | none (in-dock, reflow) |
| Font browser | M(L-preview) | whisper |
| Custom color picker | M(L-preview) | none |
| Composer (text add/edit) | D | whisper (20% today, unify at 2.8) |
| Export sheet + preview | M + D(session) | full |
| List/overflow sheets, pickers, dialogs | M | full |

## 10. Command scope and target selection

§1 classifies a surface by WHEN its command lands. §10 classifies it
by WHAT the command lands on. §4's `priorSelectionId` clause
presumes an answer to that and never states one; this is it.

**No command searches for a target.** There is no priority ladder,
no fallback chain and no chooser: a control whose target is not
named by one of the four scopes below has no target, and says so
(10.3). Adding a fifth scope — or resolving a target from document
contents — requires amending this section first.

**W — world.** Targets the `EditorDocument`; no layer target.
Clears the selection on entry.

**A — author.** Targets a layer the command creates. Ends with that
layer selected.

**B — bound.** Targets the layer the current selection names.
Requires a selection and is unreachable without one.

**P — project role.** Targets the one layer the project kind
defines as its subject: the protected base photo. Exists only in
`ProjectKind.photo`.

| Control | Scope |
|---|---|
| `image`, `text`, `sticker`, `shape`, `paint` | A |
| `canvas` | W |
| every mode-strip slot, action chips included | B |
| main-strip `crop`, `look` | P |

Undo/redo, save, export and the zoom readout target no document
object and fall outside §10. The Layers drawer and the list sheets
name their target by direct manipulation — the row IS the
selection — so they are B.

## 10.1 P exists only where the role is visible

A P command discloses its target through the chrome the project
kind already renders for that role — the base-photo pill, the
layers-panel label, the delete confirm — every one of which routes
through `isProtectedBasePhoto`. P is admissible only where that
predicate can be true.

`ProjectKind.design` renders none of it. **A design project
therefore has no P controls**: `crop` and `look` are absent from its
main strip, and are reachable only as B slots on `ImageModeToolbar`
once the user selects a visible image. A design document does not
claim `basePhotoLayerId` either — state that no surface can render
and no command can re-aim does not get to exist because a reader
might want it.

## 10.2 A missing or hidden role target makes the command unavailable

The role target qualifies when it exists and is `visible`. `locked`
does not disqualify: the protected base photo is locked by
construction and is the intended Crop target. A hidden layer never
qualifies for any scope — a command whose result cannot be seen has
no honest preview.

When the role target is missing or hidden, the P control is
unavailable per 10.3. It does not fall back to another image and it
does not ask: in a photo project a second image is an overlay, not
a candidate.

This is deliberately not §5's "eligible", which excludes locked so
that a locked layer cannot be dragged. §5 row 5 is renamed
**pointer-eligible** in the commit that ratifies §10, so the two
definitions cannot drift.

## 10.3 Absence and unavailability mean different things

- **Absent** — the scope is inadmissible on this surface. A design
  project's main strip does not render `crop` or `look` at all.
- **Unavailable** — the scope is admissible but its target does not
  qualify. The control renders dimmed and STAYS tappable, so the tap
  can explain the precondition and offer to satisfy it.

Never the third thing: a control that is present, inert and silent.
Requirements on the unavailable state:

- Its dim treatment is distinguishable from disabled and clears the
  3:1 non-text contrast floor. An unavailable control is live and
  has to stay findable.
- Its accessibility node announces the unavailable state and names
  the precondition. A control that looks unavailable and reads as
  ordinary lies to exactly the users who cannot see the dim.
- The recovery its tap offers satisfies the stated precondition.

## 10.4 Availability and placement are separate questions

Availability is a scope property — does this control's named target
exist and qualify. Placement is a project-kind property:
`_isPhotoProject` orders the groups, defended because keying order
on layer contents reshuffles the strip as a side effect of
unrelated edits. Both are legitimate; they are not one predicate,
and a slot answers each once from its scope instead of each call
site re-deciding.

Pinning suites: `toolbar_group_order_test.dart` (placement),
`photo_tool_availability_test.dart` (availability and 10.3),
`image_target_test.dart` (10.1, 10.2). The evidence behind this
section, and the state of the code before it, are recorded in
`docs/command-scope-diagnosis-2026-07.md`.
