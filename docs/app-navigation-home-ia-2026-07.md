# App Navigation & Home IA — Scalable Structure — July 2026

> Fixes the real problem behind "Home is too long / how will it scale?": Home is
> currently both a launcher AND a full template browser. This splits those
> roles, so Home stays short forever and content growth lives in dedicated,
> scalable browser tabs.

---

## The problem

A full (even capped) template **grid** on Home makes it very long, and it can't
scale — you can't grid hundreds of templates on a launcher. Mixing every
category into one flat "همه" grid also isn't scannable.

## The solution: launcher + browser tabs + a bottom tab bar

- **Bottom tab bar:** خانه · قالب‌ها · پروژه‌ها. (Settings stays a Home header
  icon.)
- **Home = a short launcher.** Create row + **horizontal rails** (recent,
  suggested, optionally a category rail), each with «مشاهده همه» → the relevant
  tab. **Home's length is bounded no matter how much content exists.**
- **Templates tab = the full browser.** Search + category chips + language
  chips + a lazy/paginated 2-col grid. Scales to any number.
- **Projects tab = the full projects grid.** Recency sort, scales.

**Why it scales:** all growth lives in the browser tabs (grid + search +
pagination); Home is a fixed set of rails. Adding templates/projects never
lengthens Home.

**Navigation choice:** a bottom tab bar (recommended — one-tap access, right for
a browse-heavy app) vs. a lighter "see all" push-navigation with no tab bar.
This doc assumes the tab bar. The *essential* fix (launcher rails + dedicated
browsers) holds either way.

---

## Home layout (launcher)

Header («کانواس» + saffron diamond + settings) · greeting «امروز چه بسازیم؟» ·
create row («طرحِ جدید» ink / «ویرایش عکس» surface) · «کارهای اخیر» rail
(horizontal → Projects) · «پیشنهادی» rail (horizontal → Templates) · optionally
1–2 category rails. Rails scroll horizontally; the «جدید» create tile sits at
the **start** (right, RTL) of the recent rail.

## Templates tab

«قالب‌ها» + search + category chips (استوری / پست / پوستر / شعر / …) + language
chips (همه / فارسی / انگلیسی / ترکیبی) + a lazy 2-col `TemplateThumb` grid.
**Reuse the existing browse screen**, restyled to v2 tokens.

## Projects tab

Full `ProjectThumb` grid, recency-sorted, with an empty state. **Reuse the
existing projects screen**, restyled to v2.

---

## Fixes carried from the current Home

- Project thumbnails must render the real design preview; for a still-empty new
  project show a subtle placeholder (mark/label), **never a blank white card**.
- The «جدید» tile goes at the **start** of the recent rail (first, right in
  RTL), not the end.

---

## Tokens / components / dark

Tokens only (paper/ink/saffron), no `WarmPalette`. Tab bar: paper bg, hairline
top, active = saffron icon + ink label, inactive = muted; dark-aware. Reuse
`AppFilterChip`, `TemplateThumb`, `ProjectThumb`; add `BottomTabBar` +
`NavShell`. Every new Persian string → an l10n key (fa + en), never hardcoded.

---

## Build sequence (commits)

1. **NavShell + BottomTabBar** (خانه / قالب‌ها / پروژه‌ها); Home as tab 1. Wire
   in the existing browse + projects screens as tabs 2 and 3 (restyle later).
2. **Slim Home → launcher:** vertical template grid → horizontal rails (recent +
   suggested) with «مشاهده همه» → tabs. Apply the two fixes above.
3. **Templates tab:** restyle the existing browse screen to v2 (search +
   category + language chips + lazy grid); keep the filter logic.
4. **Projects tab:** restyle the existing projects screen to a v2 grid + empty
   state.

Check in with light + dark screenshots after each commit.

---

## Discipline

Tokens only (no hardcoded colours or strings — l10n keys, fa/en parity), dark
verified, one concept per commit, screenshot-iterate.
