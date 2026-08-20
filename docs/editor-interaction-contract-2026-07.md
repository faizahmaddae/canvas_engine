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
- **Canvas background** — rides the SAME `LiveOverlay` channel: the
  overlay carries a document-background override
  (`LiveOverlayController.stageBackground`), drags stage it, and ONE
  non-live `SetCanvasBackgroundCommand` commits on release/settle.
  *(Amended by the ux-audit P2-8 fix, 2026-08: this bullet used to
  exempt the background as "a document property the overlay cannot
  express", sanctioning per-tick `live:true` committed writes. That
  wiring made undo granularity wall-clock-dependent — two quick
  swatch taps merged into one entry, a paused drag split — so the
  overlay learned the override and the exemption is retired.
  `SetCanvasBackgroundCommand.live` remains only for command-level
  API stability; no UI host may pass it.)*
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
- Post-Stage-2 fate of `live:true` merging (roadmap decision;
  amended by the ux-audit P2-8 fix, 2026-08): permitted for steppers
  only. The canvas background — formerly the second sanctioned case —
  migrated onto the overlay channel (§2). Nothing else may rely on
  the 1s wall-clock window, which survives solely as the
  stepper-burst coalescer. Pinned by
  `color_commit_contract_test.dart` ("P2-8 migrated hosts").
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
| 7 | empty canvas | any | any | tap→E3; drag→ movable single selection: translate it (start deferred to slop); otherwise viewport pan |

Row 7 amendment (2026-07-30, drag-anywhere): a one-finger drag from
empty canvas or pasteboard moves the current selection when that
selection is a single, visible, unlocked, movable layer — precise
grabs fail exactly when the object is small, hidden under the
finger, or the canvas is zoomed out. The claim lives on the row-5
surface (same lazy arena): a sub-slop tap still deselects (E3), a
hold still long-presses, and a pre-slop second finger still abandons
to the viewport pinch (row 6). A locked or hidden layer's area is
pointer-INeligible and therefore counts as empty canvas — in a photo
project the whole base photo is a valid drag-anywhere start. The
retired active-transform-surface model's three failure modes stay
solved: zoom-while-selected (row 6), drag-another-layer (row 5); the
third — a habitual one-finger pan relocating the selection — is the
accepted trade: pan remains one gesture away (two fingers, or
deselect first), and multi-selections, locked/hidden selections and
the no-selection state keep the one-finger pan. Multi-select mode is
excluded deliberately: its tap-to-toggle grammar makes stray drags
costlier, and a group quad is rarely hard to hit.

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
named by one of the five scopes below has no target, and says so
(10.3). Adding a sixth scope — or resolving a target from document
contents — requires amending this section first.

**W — world.** Targets the `EditorDocument`; no layer target.
Clears the selection on entry.

**A — author.** Targets a layer the command creates. Ends with that
layer selected.

**B — bound.** Targets the layer the current selection names.
Requires a selection and is unreachable without one.

**N — next-authored.** Targets the layer the current selection
names, exactly like B, whenever one exists. Absent a selection,
targets the author's own defaults for the next A command of the
same kind instead — session state, not a document object, so
writing it commits nothing and produces no undo entry. This is not
the fallback chain the opening rule forbids: both targets are named
in advance by this paragraph, neither is found by searching document
contents, and a control never chooses among more than one candidate
layer. Exists only where a single control set both authors new
layers (A) and restyles already-committed ones — currently only
`paint`, whose mode-strip slots (Color, Size, Fill, Opacity, Blur,
Sides, Style) read and write through
`PaintToolController.selectedPaintLayer()` /
`PaintStyleView.isRestyling`, the shared predicate every one of them
must resolve through rather than re-deriving. See 10.5.

**P — project role.** Targets the one layer the project kind
defines as its subject: the protected base photo. Exists only in
`ProjectKind.photo`.

| Control | Scope |
|---|---|
| `image`, `text`, `sticker`, `shape`, `paint` (draw) | A |
| `canvas` | W |
| every mode-strip slot, action chips included, EXCEPT paint's | B |
| `paint`'s mode-strip slots (Color, Size, Fill, Opacity, Blur, Sides, Style) | N |
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

## 10.5 N never lacks a target, but must disclose which one it has

Unlike P, an N control has no absent or unavailable state (10.3):
one of its two named targets always exists, so N controls are
always present and always live — there is nothing to dim and no
precondition to explain. The requirement N carries instead is
disclosure: because the same tile, sheet and value can mean either
"defaults for the stroke you're about to draw" or "the stroke you
already drew," a control must state at the surface which one is
live right now. `PaintModeInlineExpansion`'s scope chip does this —
«خط بعدی» (next-authored) versus «ویرایش این خط» (bound) — and the
strip's own tiles follow the same predicate for their label/value/
capability set (`PaintStyleView.isRestyling`), so the sheet and the
strip that opened it never disagree about which target is live.

Resolution order is static, not searched: the bound target wins
whenever a selection exists, full stop — an armed tool does not
override it. This is what lets a tool stay armed for continuous
authoring while the layer just authored is immediately restylable:
every path that ARMS a tool clears the selection first, so a
selection can only coexist with an armed tool in the one case this
scope exists to serve. A fresh A command's OWN content is still
drawn from the author defaults directly, never through the bound
target, so a stale selection can never leak into what gets authored
next.

Pinning suites: `paint_restyle_dock_test.dart` ("a paint-layer
selection wins over an armed tool"), `paint_stroke_controller_test.dart`
("commitDot selects the layer it just added, tool stays armed").
