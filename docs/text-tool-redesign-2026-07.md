# Text Tool Redesign (Phase 2B — text first) — July 2026

> Best-in-class Persian text editing: one unified text bar, a consistent
> professional panel grammar, and the pro-depth that's currently missing. This
> is Phase 2B applied to the text tool first (the most-used), built on the
> modular pieces 2A produces. Companion to
> `editor-phase2-toolbar-system-2026-07.md`.

---

## 1. One text bar (remove the duplicate floating pill)

Text currently has BOTH a floating pill over the selection AND a bottom bar —
they duplicate each other (color, size in both). Collapse to ONE bottom bar:

**فونت · اندازه · رنگ · استایل · تراز · بیشتر**

The selection keeps its saffron handles + a small on-canvas affordance
(double-tap to edit the text). Everything else lives on the one bar. Delete
`text_floating_toolbar.dart`.

## 2. Panel grammar (consistent, compact, canvas-bright)

Every text panel: a header (title + × and/or a value chip), compact controls, an
elevated sheet (rounded top + shadow + hairline, NO scrim), capped height.
**Rich panels use internal category chips** to offer depth while staying compact
(one category's controls visible at a time).

## 3. The panels

- **فونت (Font):** script tabs (فارسی / انگلیسی) + category filter + specimen
  cards. ADD: a font **weight** selector (when the face has weights), ★
  favorites, and recents.
- **اندازه (Size):** a clean **slider** + −/+ + preset chips (S/M/L/XL/XXL) + a
  value chip. Replaces the clunky A+/px/A- three-box layout.
- **رنگ (Color):** solid swatches + custom picker + recents + eyedropper. ADD:
  **gradient** (two-colour) fill + an **opacity** slider.
- **استایل و افکت (Style & Effects)** — the depth. A preset row
  (Classic/Neon/Highlight/Shadow/Contrast) as quick-starts, PLUS category chips →
  granular controls:
  - **خط دور (Stroke):** width + colour
  - **سایه (Shadow):** colour + distance + blur (+ direction)
  - **درخشش (Glow):** colour + intensity
  - **زمینه (Background/Highlight):** colour + padding + corner radius
  - **گرادیان (Gradient):** two colours + angle
- **تراز و فاصله (Align & Spacing):** alignment (right/center/left/justify) +
  line-height slider + letter-spacing slider. ADD: **کشیده (Kashida)** — Persian
  justification (stretch connectors) as a toggle/amount.
- **بیشتر (More):** opacity, weight, **متنِ منحنی/قوسی (curved/arc text)**,
  vertical text, duplicate, delete, rename.

## 4. New capabilities to ADD (the "what's missing")

Stroke · real Shadow (offset/blur/colour) · Glow · Gradient fill ·
Background/Highlight · **Curved/arc text** · **Kashida justification** · Font
weight · Opacity as first-class. These are **text-layer rendering** additions
(text painter: `Paint.style` for stroke, `TextStyle.shadows`, a shader for
gradient, a path-following painter for curve, shaping for kashida) — separate
from the image effect stack. Each = a `TextStyleSpec` field + a render path + a
panel control, **serialized additively** (defaults omitted → byte-identity safe).

The Persian-specific ones — **kashida, curved nastaliq, the Persian font depth**
— are the differentiator; lean into them.

## 5. Build sequence (Phase 2B, after 2A modularization)

1. **Unify the bar** — remove the floating pill; drive the one bottom bar via
   `context_toolbar_controller`. Screenshot.
2. **Panel grammar** — apply the consistent header/compact/elevated grammar +
   the 2A shared control kit to all text panels.
3. **Redesign each panel** to the grammar: size slider, colour + gradient +
   opacity, effects with category chips, align + kashida.
4. **Add each missing effect** (stroke / shadow / glow / gradient / background /
   curve / kashida / weight / opacity) — one per commit: `TextStyleSpec` field +
   render path + control + additive serialization + round-trip test.

## Discipline

Tokens only, global Persian font, dark verified, one concept per commit,
`flutter test` green, **additive serialization** for every new style field
(v3-safe, defaults omitted, fixtures stay byte-identical), screenshot light +
dark and iterate. Text + the Persian-typography depth first.
