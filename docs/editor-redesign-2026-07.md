# Editor Redesign — July 2026

> The editor is the heart of the app and where users spend all their time — and
> it's the weakest screen: stark black letterbox voids around the canvas, an
> unthemed top bar, a disjointed set of ad-hoc toolbars (a tool dock + a
> per-tool bottom bar + a floating pill over the selection + one-off sheets),
> redundant controls (the floating pill duplicates the bottom bar), and violet
> selection handles. This brings it onto the paper/ink identity AND fixes the
> structure into one coherent system.
>
> Companion to `design-direction-v2-calligraphy-2026-07.md`. It also finally
> tackles the `text_mode_toolbar.dart` god-file (≈4,400 lines) — the new panel
> system is where it gets broken up.

---

## The professional structure (the target)

A clear hierarchy, four layers:

1. **A slim, themed top bar** — close · title (tap to rename) + dims · undo/redo
   · export · «⋮» overflow (layers, save, resize, …). Decluttered: primary
   actions visible, secondary in the overflow. `surface`, ink, hairline bottom.
2. **A maximized canvas floating on a calm workspace** — the workspace is
   `surfaceMuted` (warm neutral in light / deep ink in dark), **never pure
   black**. The canvas floats centered with a soft shadow + slight rounding. The
   canvas is the star; give it room.
3. **ONE context-aware bottom bar** — it *swaps*, it doesn't compete:
   - **Nothing selected →** the TOOL bar (add: متن · عکس · شکل · استیکر · طراحی
     · …).
   - **An object selected →** that object's CONTEXTUAL bar (text: فونت · اندازه
     · رنگ · تراز · استایل · بیشتر; image: برش · فیلتر · تنظیم · حذف پس‌زمینه;
     shape: پرکردن · خط · …). One bar, one grammar. **Kill the redundant
     floating pill** — its actions live here.
4. **Consistent panels** — tapping a contextual action (رنگ / فونت / اندازه /
   فیلتر / تنظیم) opens a consistent bottom sheet built on `AppContentSheet`
   (drag handle, title, the control), canvas dimmed behind. Same component
   everywhere — this retires the one-off sheets.

**Identity:** `pageBg`/`surface` bars, ink icons, **saffron** for the active
tool + selection handles + selected states. Dark-native (workspace = deep ink).

---

## Phased plan

The editor is large, so ship the transformation in stages — a fast visual win
first, then the structural UX work, then per-tool polish. Screenshot light +
dark and iterate at each step.

### Phase 1 — Recolour + workspace framing (fast, high-impact, low-risk)
The look changes dramatically without restructuring anything:
- Theme the top bar (slim, `surface`, ink, hairline; declutter primary vs «⋮»).
- **Replace the black letterbox** with the `surfaceMuted` workspace + a floating
  canvas (soft shadow, slight radius). This alone fixes the biggest "unfinished"
  tell.
- **Saffron selection handles** (replace violet) + saffron bounding box.
- Recolour the EXISTING bottom bars / panels / sheets to tokens (keep their
  current structure for now — just on-brand colours + the global Persian font).
- No god-file restructuring yet. Screenshot; this is the visible turnaround.

### Phase 2 — Unify the toolbar system (the structural UX work)
- Build the **one context-aware bottom bar**: a `EditorToolBar` (idle) that
  swaps to a `SelectionToolBar` (object selected), sharing one visual grammar.
- Consolidate the floating-pill actions into the contextual bar (remove the
  duplicate pill; keep at most a tiny on-selection "edit" affordance if it earns
  its place).
- Move deep controls into `AppContentSheet` **panels** (color, font, size,
  align, style, filters, adjust) — one panel component, consistent.
- **This is where `text_mode_toolbar.dart` (≈4,400 lines) gets broken up** —
  each control becomes a small panel/section widget feeding the new system.
  Behaviour-preserving, one concept per commit, tests green (the A1 playbook).

### Phase 3 — Per-tool polish
Refine each tool's contextual bar + panels (text, image, shape, sticker, draw)
— spacing, iconography, empty/loading states, gestures — iterating with
screenshots. Text + image first (most used).

---

## Discipline

Tokens only (no hardcoded colours), the global Persian font (never the system
font), dark verified, one concept per commit, `flutter test` green, screenshot
light + dark and iterate. In Phase 2, treat the god-file split as behaviour-
preserving: if a previously-green test breaks, stop and decide real-regression
vs. stale-test — never edit a test to pass.
