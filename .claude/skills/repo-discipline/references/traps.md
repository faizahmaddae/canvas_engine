# Known traps — each of these has already cost a debugging session

Read the section matching the surface you're touching. Everything here was
verified against the code; if code has since moved, trust the code and update
this file in the same commit.

## Templates (authoring + registration)

**Registration requires FOUR touches** (miss one and a gate fails):

1. Create `assets/templates/<id>/` with `template.json` + `document.json` +
   `thumbnail.png` (thumbnail aspect must match the document within ±0.02,
   long side ~640–720 px).
2. Add the directory as its own line under `flutter.assets` in `pubspec.yaml`
   (asset entries don't recurse — every template dir is listed individually).
3. Append `"assets/templates/<id>/template.json"` to the `templates` array in
   `assets/templates/manifest.json` — this is what the app actually reads.
4. Two docs are test-gated:
   - `docs/template-system-audit.md` is GENERATED and byte-asserted by
     `test/editor/templates/template_system_audit_test.dart`. Unlike the
     engine fixture generators, NOTHING regenerates this doc for you — the
     test only asserts, never writes. Workflow: run it, take the expected
     report from the failure diff (built by `_formatMarkdownReport`), update
     the doc byte-for-byte.
   - `docs/template-quality-audit.md` must mention every manifest template's
     backticked `` `id` `` under one of its four quality headings
     (`## Ready` etc.) — add new ids to the right section.

   Optional curation: `template_presentation_order.dart`; the Home rail reads
   `kHomeRecommendedTemplateIds`.

**Authoring facts (document.json):**

- **`fillOpacity` trap:** `ShapeLayer` computes
  `solidColor = color.withValues(alpha: fillOpacity)` — `fillOpacity`
  (default 1.0) OVERWRITES the fillColor's own alpha. Transparent-fill shapes
  (hairline frames, rings) need `"fillOpacity": 0.0`; an alpha-0 fillColor
  renders opaque.
- Rotation is **radians**. `scaleText` = FittedBox-contain, no wrap, `\n` only.
- `effects`/`stackMask` render ONLY on image layers — forbidden elsewhere.
- Gradient `fill` is ignored on stroked shape kinds (line/arrow/check/cross);
  `cornerRadius` applies only to rect/roundedRect.
- **Persian text:** `letterSpacing` must stay 0 (nonzero breaks cursive
  joining). Nastaliq needs `lineHeight` ≈ 1.8–2.0. IranNastaliq + Shabnam is
  the canonical "Persian Classic" pairing (`template_tokens.dart`).
- **Glyph coverage:** `٪` (U+066A) is missing from ~25 decorative Persian faces
  (BTitrBd, BNazanin, B_Yekan, Mj_*, SOGAND, Shams, …). Safe for ٪ and digits:
  Vazir_Regular, Shabnam, Samim_Bold, IranianSans, Dirooz, ARezvan,
  DimaTahriri, Fedra, Lalezar, IranNastaliq, Gandom, Neirizi, Dima_Shekaste.
  `W_hesam` has NO Persian digits. `﷼` (U+FDFC) is missing from the
  decorative faces (covered only by ~12 fonts incl. Vazir_Regular, Shabnam,
  Samim_Bold, IranianSans, Lalezar) — write تومان for consistent rendering
  across all faces.
- Capture recipe for template screenshots:
  `test/widget/persian_export_verification_test.dart` is the golden pattern
  (FontLoader per family used, DocumentView in a RepaintBoundary,
  `DocumentPngExporter.captureBoundary` inside `tester.runAsync`, write to
  `build/test_exports/`). One-off thumbnail-generator tests must be DELETED
  before commit — tests assert their absence.

## Fonts

Each family is a separate `flutter.fonts` entry; the family name is the
underscore-normalized file name (`Hanken_Grotesk`, `Vazir_Regular`,
`B_Koodak_Bold_0`). English fonts under `assets/fonts/english/<Family>/`,
Persian under `assets/fonts/farsi/` (some paths contain literal spaces).
Locale wiring (`lib/app/theme/app_theme.dart`): UI family is `Vazir_Regular`
for fa, `Hanken_Grotesk` otherwise, and the Latin fallback chain deliberately
LEADS with Vazir so Persian glyphs render identically under an English locale
(Hanken has no Arabic-script glyphs). Don't "optimize" that chain order.

## RTL layout

- Default direction is RTL. Use `EdgeInsetsDirectional` /
  `PositionedDirectional` / `AlignmentDirectional`; physical-edge insets in
  app-shell code are treated as bugs.
- **Chevrons DO auto-mirror — do not mirror them by hand.** Material's
  `*_rounded` directional glyphs carry `matchTextDirection: true`, as does
  `AppIcons.drillIn`, so Flutter flips them at paint time. Picking
  `chevron_left_rounded` under RTL yourself mirrors an already-mirroring
  glyph and the drill-in arrow ends up aimed at the screen edge — a bug this
  repo has already shipped and fixed once. Always name the FORWARD glyph.
  (Anything that ROTATES such a caret is the exception and must rotate the
  other way under RTL — see `AppIcons.disclosureOpenTurns`.)
- Custom-PAINTED arrows carry no such flag and do need manual mirroring.
- **Deliberately NOT directional:** `PanelDirectionPad` pins its 3×3 grid to
  LTR and `PanelOffsetPad` emits physical screen-space Offsets (positive dx =
  right) regardless of ambient direction — they represent physical geometry,
  and "fixing" them to be directional reintroduces the bug where the visually
  left cell moved the target right. Both document this in their headers.

## Theme / design system

- Tokens only in app-shell presentation code: `AppTokens.of(context)`.
  21 colour fields; `brand`/`onBrand` SWAP across modes (ink CTA on light,
  cream CTA on dark); rose/saffron/teal category accents are identical hex in
  both modes; `accent` (saffron) is per-mode tuned.
- **`scheme.primary` is brand ink now, not saffron.** For accent colouring use
  `tokens.accent` / `tokens.accentDeep`. Violet anywhere = bug (only the
  'Modern Gradient' template family may contain it — user content, deliberate).
- `workspace` token is editor-only (one step deeper than `surfaceMuted`);
  ordinary screens use `pageBg`/`surfaceMuted`.
- `AppSpacing` = {xs:4, sm:8, md:12, lg:16, xl:24, xxl:32, pageGutter:20};
  `AppRadii` = {button:12, card:16, hero:24, pill:999, primaryButton:14,
  sheetTop:26}. Compose existing values rather than inventing new ones.
- `AppTypeScale` roles (display/titleLg/title/body/caption) deliberately omit
  `fontFamily` and `color` — family comes from the theme, colour from tokens
  at the call site.
- `WarmPalette` (`lib/app/theme/warm_palette.dart`) is a separate
  brightness-resolved palette shared by Home/Onboarding/Templates-Browse —
  distinct from AppTokens; don't merge them.
- There are TWO `SectionLabel` classes on purpose (app-wide token-driven in
  `lib/app/ui/`, editor-scoped scheme-driven in
  `lib/features/editor/presentation/widgets/`). Never imported into the same
  file; don't unify.
- `ProjectThumb` and `EmptyDesignPlaceholder` live in
  `lib/features/home/presentation/widgets/project_thumb.dart` (not
  `lib/app/ui/`, despite CLAUDE.md's summary).
- Shared app-shell components: `lib/app/ui/` (AppContentSheet, AppFilterChip,
  AppPrimaryButton, BottomTabBar, SectionLabel, SaffronDiamond,
  TemplateThumb, …). Editor-scoped primitives: `lib/features/editor/ui/`
  (EditorSliderRow, EditorTierGap, PanelDirectionPad, PanelOffsetPad,
  PrecisionDisclosure). The two sets are deliberately separate.
- `EditorSliderRow` NEVER dispatches commands — the caller decides commit
  strategy via `onChanged`/`onDragStart`/`onDragEnd`.

## Editor chrome invariants

- **No scrim behind control panels** — the user must see the live effect while
  dragging sliders. `editor_scrim.dart` was deleted; do not reintroduce.
  (Typing sheet keeps a light barrier; that's the sanctioned exception.)
- Panel height cap: `min(34% of screen, 380dp)` with internal scroll,
  contract-locked by `test/editor/widget/editor_panel_height_cap_test.dart` —
  which also asserts the text panels fit with ZERO internal vertical scroll at
  worst-case style. Adding content to a panel means fitting the cap, not
  raising it.
- Workspace behind the floating canvas is `tokens.workspace` — never pure
  black.
- Home is a bounded launcher: never add unbounded vertical content to it; all
  content growth belongs in the Templates/Projects tabs.
- NavShell keeps tabs in an `IndexedStack`, built lazily on first visit
  (`Set<int> _visited`); Home's "see all" links jump tabs via
  `navShellIndexProvider` — don't push routes to those tabs.

## Colour picker

- `ColorPickerBody`
  (`lib/features/color_picker/presentation/color_picker_body.dart`; the sheet
  host is in the same file, `color_picker_sheet.dart` is a re-export) is THE
  picking surface everywhere. Don't build a new one.
- **The custom wheel never scrolls.** It is all drag controls, so it must
  never sit in a scrollable or height-capped container. Embedded panels render
  level 1 only; «سفارشی» hands off to
  `showColorPickerSheet(startAtCustom: true, …)` — the content-sized sheet is
  the wheel's only home and the one exception to the dock height cap. Pinned
  by `test/editor/widget/color_picker_custom_no_scroll_test.dart`.
- Alpha rule (centralised): swatch/recent/eyedropper picks = hue choice, alpha
  preserved; an 8-char hex = explicit alpha.
- Recents persist to prefs key `editor.recent_colors.v1` through a serialised
  persist chain — don't call `setStringList` concurrently.
- Eyedropper samples a RepaintBoundary keyed by
  `canvasBoardBoundaryKeyProvider` INSIDE the viewport transform
  (`toImage(pixelRatio: 1)` = 1 px per logical canvas unit). The button
  auto-hides when the boundary is unmounted.
- Sheet uses `barrierColor: transparent`; the resulting plain `ModalBarrier`
  (vs `AnimatedModalBarrier`) is itself the no-dim test pin.

## Engine / serialization quick list

(Full law in AGENTS.md — these are the most-violated items.)

- New field on a `Layer` subclass → audit `withTransform`, `withVisibility`,
  `withLocked`, `withOpacity`, AND `copyWith`. Missing one silently corrupts
  the document mid-drag.
- `invert()` receives the document BEFORE apply; return `_NoopCommand()` for
  genuine no-ops, never null.
- Serialize: omit default-valued fields, or byte-identity breaks. Command
  inverses must restore the exact prior value (including null) — capturing a
  derived "effective" value breaks round-trips.
- `EffectStack.isEmpty` deliberately reads only the effects list (never
  `stackMask`) — folding the mask in would emit `"effects": []` and break
  legacy byte-identity.
- Coordinate spaces are explicit (canvas / screen / layer-local). Gesture
  focal points: use `localFocalPoint`, not global.
