import 'package:flutter/widgets.dart';

/// Every icon the app draws, named by ROLE rather than by picture.
///
/// Replaces a direct dependency on `Icons.*`, which had grown to 171
/// distinct glyphs drawn from THREE different Material styles at once
/// (219 `_rounded`, 87 `_outlined`, 22 bare filled). Mixing those in
/// one strip means mixing stroke weights and fill rules, which is
/// what made the toolbars read as unconsidered: a heavy filled `Tt`
/// sat directly beside a hairline outlined brush.
///
/// Everything here is one family at one weight (Phosphor Regular), so
/// the strips finally look drawn by one hand.
///
/// Two properties are load-bearing:
///
///  * **Every entry is a literal `const IconData`.** Release builds run
///    `--tree-shake-icons`, which hard-fails on a non-const IconData —
///    so a `filled(icon)` style helper is not an option, and the
///    codepoints are inlined rather than read off the package.
///  * **`matchTextDirection` is decided per icon, here.** Phosphor sets
///    it to `true` on EVERY glyph. Under RTL that would mirror
///    `textAlignLeft` into something that lies about what it does. Only
///    glyphs whose meaning IS the reading direction (drill-in, back,
///    undo/redo) mirror; everything else is pinned false.
abstract final class AppIcons {
  static const _family = 'PhosphorRegular';
  static const _package = 'phosphor_flutter';

  /// Create/add/increment: home create button, empty project thumb,
  /// add-text-block, font-size stepper up. Symmetric.
  static const add = IconData(
    0xe3d4,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// AlignAxis.bottom. Literal spatial meaning — never mirror.
  static const alignBottom = IconData(
    0xe506,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// AlignAxis.centerX (l10n.alignCenterAction). Rendered check:
  /// alignCenterHorizontal is the vertical guide line with bars centred
  /// on it, so the Material and Phosphor names agree for once.
  static const alignHorizontalCenter = IconData(
    0xe50a,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Literal align-left action in the align panel, and also the
  /// panel/section header for Align generally (context_tool_panel:32,
  /// multi_select:50, overflow rows). MUST NOT mirror — flipping it
  /// would make it claim align-right in Persian, and it sits in a row
  /// beside align-center/align-right.
  static const alignLeft = IconData(
    0xe50e,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// AlignAxis.right. CRITICAL false: Phosphor's default
  /// matchTextDirection would draw a left-flush glyph in Persian while
  /// the command still aligns right — the icon would lie.
  static const alignRight = IconData(
    0xe510,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// AlignAxis.top. Literal spatial meaning — never mirror.
  static const alignTop = IconData(
    0xe512,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// AlignAxis.centerY (l10n.alignMiddleAction). Verified by rendering
  /// the font: alignCenterVertical is the horizontal guide line with
  /// bars centred on it. Do not swap with alignCenterHorizontal.
  static const alignVerticalCenter = IconData(
    0xe50c,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// App language row in settings (distinct from
  /// settingsContentLanguagesTitle, which uses language_rounded →
  /// `globe`).
  static const appLanguage = IconData(
    0xe4a2,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// 4:5 portrait preset in size_picker_dialog and canvas_panel_body.
  /// Phosphor has NO portrait rectangle — `rectangle` renders
  /// landscape, so it will read identically to crop_landscape_rounded.
  /// Recommend the wrapper rotate this one 90deg, or accept that the
  /// label carries orientation.
  static const aspectPortrait = IconData(
    0xe3f0,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Color picker's return-from-custom-level button
  /// (backButtonTooltip). Genuine reading-direction back.
  static const back = IconData(
    0xe058,
    fontFamily: _family,
    fontPackage: _package,
    matchTextDirection: true,
  );

  /// Blur is the dominant role (paint Blur tool, paint_tool_specs, the
  /// blur SliderSubTool header with l10n.blurLabel). Phosphor ships no
  /// blur glyph; drop is the long-standing blur-tool convention
  /// (Photoshop droplet). FLAG: shape_mode_toolbar.dart:123 uses this
  /// for label l10n.shadowTool and sticker_style_body:47 for the
  /// 'softShadow' preset — those are shadow, not blur, and should move
  /// to the dedicated shadow glyph chosen for layers_outlined's shadow
  /// sites.
  static const blur = IconData(
    0xe210,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Bold toggle in the text compose sheet and the layer overflow
  /// sheet. A Latin B beside a Persian label (پررنگ) is a known
  /// weakness, but Phosphor has no weight-based bold mark.
  static const bold = IconData(
    0xe5be,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// The Border/stroke tool (label l10n.borderTool) on the shape and
  /// image docks + their panel headers. Phosphor has no border-outer;
  /// boundingBox is the closest 'outline around the layer' read and
  /// stays distinct from square (shape) and frameCorners (canvas).
  static const borderTool = IconData(
    0xe6ce,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// BrandMark placeholder glyph. diamondsFour echoes the saffron-
  /// diamond identity (see SaffronDiamond in lib/app/ui) instead of a
  /// generic mosaic.
  static const brandMark = IconData(
    0xe8f4,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// BrightnessEffect row in image_effects_body.
  static const brightness = IconData(
    0xe472,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// layer_overflow_sheet.dart:221 — 'Bring forward' row, calls
  /// LayerActions.bringForward. Phosphor's selectionForeground is the
  /// purpose-built z-order glyph (solid square in front of a dashed
  /// one) and is far clearer than Material's flip_to_front, which reads
  /// as a flip. Z-depth, not reading order — no mirroring.
  static const bringForward = IconData(
    0xeaf6,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// 'Take a photo' row in the image source sheet and the image replace
  /// flow. Direct equivalent.
  static const camera = IconData(
    0xe10e,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// settings_screen.dart:59 — _SwitchTile for enableCanvasPanTitle
  /// ('Drag the canvas to reposition it'). handGrabbing is the
  /// canonical pan/drag-tool hand and reads better than Material's
  /// pointing hand. mirror false — tool handedness is not reading
  /// direction.
  static const canvasPan = IconData(
    0xe57c,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// 'Enable canvas rotation' switch — the two-finger gesture rotating
  /// the CANVAS, not device orientation, so `deviceRotate` (a phone)
  /// would mislead. Slight risk of reading as refresh; refresh_rounded
  /// here uses the single-arrow arrowCounterClockwise, so they stay
  /// distinct.
  static const canvasRotation = IconData(
    0xe094,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Canvas tool (tier-3 main toolbar), Resize-canvas menu item, export
  /// size chips, and the scale/size row in layer_overflow_sheet.
  /// frameCorners reads as 'the canvas frame + its dimensions'. Kept
  /// distinct from resize (sticker size) and crop (crop tool).
  static const canvasSize = IconData(
    0xe626,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// settings_screen.dart:263 — _categoryIcon for
  /// TemplateCategory.instagramStory (the 9:16 story format).
  /// deviceMobile is the plain bezel phone; deviceMobileCamera adds a
  /// notch that reads as 'take a photo' instead of 'story format'.
  static const categoryInstagramStory = IconData(
    0xe1e0,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Goal tile for TemplateCategory.poetryPost. Kept off `quotes`
  /// deliberately — the grid also has a separate `quote` category that
  /// wants that glyph. `feather` (quill) is the on-brand calligraphy
  /// alternative if you want more character.
  static const categoryPoetry = IconData(
    0xe0e6,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// settings_screen.dart:265 — _categoryIcon for
  /// TemplateCategory.poetryPost. Phosphor `quotes` is the symmetric
  /// double-quote pair; decorative, so no mirroring.
  static const categoryPoetryPost = IconData(
    0xe660,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Settings category glyph for TemplateCategory.promotionalPoster.
  /// The horn's handedness is tool-like, not reading-direction — do not
  /// flip.
  static const categoryPoster = IconData(
    0xe324,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Goal-screen tile for TemplateCategory.social, i.e. a square photo
  /// post. A bare square said nothing; imageSquare says "square image
  /// post" and stays distinct from shadowPresetHard.
  static const categorySocial = IconData(
    0xe2cc,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Goal tile for TemplateCategory.instagramStory. A phone is the
  /// clearest "vertical story" mark and unifies with settings'
  /// phone_iphone_rounded / size-picker's smartphone_outlined for the
  /// same category.
  static const categoryStory = IconData(
    0xe1e0,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// settings_screen.dart:264 — _categoryIcon for
  /// TemplateCategory.youtubeThumbnail. mirror false is load-bearing: a
  /// play triangle is a universal media symbol and must keep pointing
  /// right in Persian.
  static const categoryYoutubeThumbnail = IconData(
    0xe3d2,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Dismiss/clear: sheet close buttons, export preview,
  /// dock_sheet_chrome close chip, canvas chrome chip. Symmetric.
  static const close = IconData(
    0xe4f6,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Colour tool: paint colour spec, shape Style slot (label
  /// l10n.colorLabel), text Color tile. Direct equivalent.
  static const colorTool = IconData(
    0xe6c8,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Selected-state tick in pickers (font, text direction, resize mode,
  /// fill mode, color) and the mode Done button. Symmetric.
  static const confirm = IconData(
    0xe182,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// settings_screen.dart:45 — 'Content languages' nav tile (which
  /// template languages appear). Distinct from the tile directly above
  /// it (Icons.translate_rounded → app UI language), so keep these two
  /// glyphs different; Material's language_rounded is already a globe.
  static const contentLanguages = IconData(
    0xe288,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// ContrastEffect row in image_effects_body; the half-filled circle
  /// is the canonical contrast glyph.
  static const contrast = IconData(
    0xe18c,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Color picker's copy-hex-to-clipboard button (copyColorTooltip).
  static const copyValue = IconData(
    0xe1ca,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Corner-radius accelerator in the shape quick-capsule. Phosphor has
  /// no corner-radius glyph at all; frameCorners (four rounded corner
  /// marks) is the closest and the Semantics label carries the meaning.
  /// Flag for design review.
  static const cornerRadius = IconData(
    0xe1d0,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Crop mode entry from the main toolbar, image dock and quick
  /// capsule (label l10n.cropTool / cropImageAction). Phosphor crop
  /// drops the rotate hint, which is fine — rotation is a control
  /// inside crop mode, not part of the entry point's meaning.
  static const cropTool = IconData(
    0xe1d4,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Dash-line tool + the 'Style' dash-pattern spec. Phosphor has no
  /// dashed-line glyph; circleDashed is the only 'dashed stroke' mark
  /// that won't collide with dotsThree (which more_horiz_rounded needs
  /// for the dash-dot tool AND the 'more' slot).
  static const dashStyle = IconData(
    0xe602,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Font-size decrease nudge in size_panel; pairs with add_rounded →
  /// `plus`.
  static const decrement = IconData(
    0xe32a,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Destructive delete (project card menu, layer overflow single +
  /// batch, remove effect, multi-select delete tile). Rendered in
  /// scheme.error at several sites.
  static const delete = IconData(
    0xe4a6,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// layers_panel.dart:424 — _IconAction routed through
  /// LayerActions.delete (which enforces base-photo protection).
  /// `trash` keeps the lid; `trashSimple` drops it and gets muddy at
  /// 16-18px. Icons.delete_outline_rounded in
  /// recent_projects_grid.dart:368 is a different role (delete PROJECT)
  /// but the same picture — the parent may want to collapse both onto
  /// one AppIcons entry.
  static const deleteLayer = IconData(
    0xe4a6,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Distribute horizontally in the align panel (paired with the
  /// vertical tile) and the 'show spacing guides' settings switch —
  /// both mean horizontal spacing. Horizontal axis is spatial, not
  /// reading order, so no mirror.
  static const distributeHorizontal = IconData(
    0xeb06,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Distribute vertically in the align panel (context_tool_panel:129),
  /// paired with the horizontal tile. Also the 'Lift' shadow preset
  /// (layer_shadow_body:309), where a vertical double arrow still reads
  /// as 'raised' — acceptable reuse. Vertical axis, never mirrored.
  static const distributeVertical = IconData(
    0xeb04,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// image_effects_body.dart:351 — inside a
  /// ReorderableDragStartListener for the effect stack rows.
  /// dotsSixVertical is the canonical reorder grip; Material's two-bar
  /// drag_handle is weaker as a grab affordance. Symmetric, never
  /// mirrored.
  static const dragHandle = IconData(
    0xeae2,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Header icon of the paint-mode tool chooser sheet — same
  /// "paint/draw" role as the toolbar Draw tile, so both share one
  /// semantic.
  static const drawTool = IconData(
    0xe6f0,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Drill-in / next: settings rows, the layer sheet's trailing
  /// affordance, the size picker's presets, the panel header's
  /// next-sibling chip. A genuine reading-direction glyph, so it
  /// mirrors.
  ///
  /// Anything that ROTATES this caret has to rotate it the other way
  /// under RTL — see `disclosureOpenTurns`. A fixed +0.25 turn only
  /// reaches "down" from the right-pointing state; from the mirrored
  /// one it lands on UP, and an expanded section then claims to be
  /// collapsed.
  static const drillIn = IconData(
    0xe13a,
    fontFamily: _family,
    fontPackage: _package,
    matchTextDirection: true,
  );

  /// Duplicate layer / duplicateMany (overflow sheet single + batch,
  /// multi-select tile). Two offset sheets, exact match.
  static const duplicate = IconData(
    0xe1cc,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// home_screen.dart:129 — QuickActionCard 'Edit a photo' (home-edit-
  /// photo), onTap actions.importPhoto. Phosphor `image` is the
  /// rounded-square mountain glyph, a direct match.
  static const editPhoto = IconData(
    0xe2ca,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// 'Edit text' in the layer overflow sheet and the text quick-
  /// capsule. Keep pencilSimple for this primary edit action; give
  /// drive_file_rename_outline_rounded (rename) `notePencil` or
  /// `pencil` instead.
  static const editText = IconData(
    0xe3b4,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// WRONG TODAY: this is the image Effects slot/panel (brightness,
  /// saturation, exposure, warmth, vignette), not layers — and it
  /// collides with the real Layers drawer (Icons.layers_outlined).
  /// magicWand is the effects/filters glyph; leave `stack` for the
  /// actual layers drawer.
  static const effects = IconData(
    0xe6b6,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Empty-state mark in recent_projects_grid ("no projects yet") — a
  /// stack of saved designs.
  static const emptyProjects = IconData(
    0xe836,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Settings tile opening the enabled-template-categories picker; a
  /// 2x2 tile grid reads as "which categories show".
  static const enabledCategories = IconData(
    0xe464,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// WRONG TODAY: PaintToolType.eraser is drawn with a cleaning brush.
  /// Phosphor has a literal eraser — take it.
  static const eraserTool = IconData(
    0xe21e,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// settings_screen.dart:82 — 'Default export quality' nav tile,
  /// subtitle shows the label plus the resolution multiplier
  /// (1x/2x/4x). Phosphor has no HQ badge. `gauge` reads as a graded
  /// level setting and stays clear of `highDefinition` (reserved below
  /// for the literal HD preset) and of `sparkle` (which
  /// Icons.auto_awesome_rounded will almost certainly claim in another
  /// slice).
  static const exportQuality = IconData(
    0xe628,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// export_action_sheet.dart:218 — the FilledButton 'Preview & Save'
  /// (export-sheet-save) that calls _openPreview(ExportIntent.save).
  /// image_search is wrong here: it says 'inspect an image' and gives
  /// no hint of the outcome, while its sibling 'Preview & Share' uses
  /// an eye — so both buttons currently read 'preview' and neither
  /// reads its verb. Mapping to downloadSimple makes it match the save
  /// CTA in export_preview_screen.dart:419 (same semantic). If the
  /// parent wants literal fidelity instead, `magnifyingGlass` is the
  /// only close Phosphor glyph and there is no image+magnifier.
  static const exportSave = IconData(
    0xe20c,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Exposure effect row (l10n.exposureLabel) in the effects list. Also
  /// reused for the 'Glow' shadow preset (layer_shadow_body:301) and
  /// the sticker 'Glow' style preset — sun works for both since glow is
  /// light; if you want them separated, keep sun for exposure and give
  /// the glow presets sparkle or lightbulb.
  static const exposure = IconData(
    0xe5b6,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Eyedropper button in ColorPickerBody (both layouts, key color-
  /// picker-eyedropper). eyedropperSample adds a swatch if a richer
  /// glyph is wanted.
  static const eyedropper = IconData(
    0xe568,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Estimated output file-size chip in export_preview_screen.
  /// `floppyDisk` reads as 'save' (wrong verb here); `database` is the
  /// other option.
  static const fileSize = IconData(
    0xe2a0,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Corners pointing IN = bring the content in to fit. Was the same
  /// glyph as canvasSize, one menu row apart.
  static const fitToScreen = IconData(
    0xe1ce,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// MUST NOT mirror — a mirrored flip-horizontal glyph is self-
  /// contradicting. FLAG: the app currently uses the SAME icon for both
  /// flip rows (layer_overflow_sheet:205/212 and 389/404 —
  /// flipHorizontalAction and flipVerticalAction). Phosphor has
  /// flipVertical; give the vertical rows flipVertical so the two
  /// actions stop being visually identical.
  static const flipHorizontal = IconData(
    0xed6a,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Flip-vertical drew the flip-HORIZONTAL glyph, so the two adjacent
  /// rows in the layer sheet were visually identical.
  static const flipVertical = IconData(
    0xed6c,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// picker_sheet.dart:186 — accent-tinted header icon of the 'All
  /// fonts' sheet (font family list). textAa is spoken for by fontSize
  /// above, so textT carries typeface here. Icons.text_fields_rounded
  /// (text_mode_toolbar 'font' tile, another slice) is the SAME role
  /// and should share the fontFamily semantic — flag that to whoever
  /// owns it. `textbox` is visually closer to Material's boxed A but
  /// means 'text input field'.
  static const fontFamily = IconData(
    0xe48a,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// text_mode_toolbar.dart:76 — the 'size' tile (TextBodies.sizeBody).
  /// Material format_size is literally big-A/small-a, which is exactly
  /// what Phosphor textAa draws.
  static const fontSize = IconData(
    0xe6ee,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Two roles: 'Adjust region' (opens the mask editor) and the Free
  /// option of the scale/free resize toggle. `selection` (marching-ants
  /// box) fits both. Avoided `crop`, which crop_rotate_rounded needs.
  static const freeRegion = IconData(
    0xe69a,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Freestyle paint tool + the generic 'Tool' picker spec.
  /// `scribbleLoop` is closer to Material's loop but noisier at 18px.
  /// Tool handedness must not flip per locale.
  static const freehandTool = IconData(
    0xe806,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// WEAK TODAY: this is the onboarding goal card for
  /// TemplateCategory.quote, and 'text fields' says nothing about
  /// quotes. `quotes` names the category directly and doesn't clash
  /// with poetryPost (auto_stories).
  static const goalQuote = IconData(
    0xe660,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Templates tab active icon + the 'All fonts' grid card. Pair with
  /// grid_view_outlined (other slice) under the same semantic; Regular
  /// weight can't express active/inactive, so the tab must vary weight
  /// or colour instead.
  static const gridView = IconData(
    0xe464,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Effect row is disabled. Same role as visibility_off_outlined, so
  /// one semantic covers both.
  static const hidden = IconData(
    0xe224,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Document history sheet + menu item, and the 'last modified' stamp
  /// on project cards. Not a reading-direction glyph (Material's own
  /// Icons.history carries no matchTextDirection) — leave it unmirrored
  /// so it does not read as a redo arrow in Persian.
  static const history = IconData(
    0xe1a0,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Marks the current entry in the history browser timeline.
  /// radioButton is the same concentric ring+dot Material draws, and
  /// reads as "you are here".
  static const historyCurrentStep = IconData(
    0xeb08,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// nav_shell.dart:70 — BottomTabItem.activeIcon for the Home tab.
  /// Phosphor Regular has no filled twin, so the active state should
  /// come from PhosphorIconsFill.house (or colour), not a different
  /// glyph — hence the same name/semantic as home_outlined.
  /// BottomTabItem will need a weight-aware path.
  static const homeTab = IconData(
    0xe2c2,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// errorBuilder fallback in layer_thumbnail when the image provider
  /// fails.
  static const imageBroken = IconData(
    0xe7a8,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Passive image representation: empty project thumbnail, image-layer
  /// thumbnail fallback, export format row. Deliberately imageSquare so
  /// it stays distinguishable from the primary Photo tool (image) and
  /// the gallery picker (images).
  static const imagePlaceholder = IconData(
    0xe2cc,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// image_replace_flow.dart:103 — shown ONLY when
  /// imageSourceIsKnownUnavailable(layer.source) is true, with subtitle
  /// 'Image unavailable'. The current Material choice is wrong: an
  /// intact link glyph marks a BROKEN source. linkBreak states the
  /// actual condition.
  static const imageSourceUnavailable = IconData(
    0xe2e4,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// canvas_panel_body.dart:314 — the accent-tinted photoBackgroundHint
  /// banner. Phosphor `info` is the circled 'i'.
  static const info = IconData(
    0xe2ce,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Two uses, both 'a wide box': the 16:9 canvas aspect preset, and
  /// TextResizeMode.resizeBox ('corner drag changes the wrap width'). A
  /// plain landscape rectangle carries both.
  static const landscapeBox = IconData(
    0xe3f0,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// canvas_chrome.dart:788 — the base-photo badge pill ('Base photo',
  /// locked/protected). STATE indicator, not a toggle. Same role and
  /// glyph as Icons.lock in layers_panel, so they share the semantic.
  static const layerLocked = IconData(
    0xe2fa,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// layers_panel.dart:388 — the unlocked half of `layer.locked ?
  /// Icons.lock : Icons.lock_open`. layers_panel uses the STATE
  /// convention (glyph shows current state, tooltip carries the verb) —
  /// the opposite of layer_overflow_sheet.dart:242, which uses the
  /// ACTION convention. Keep both AppIcons entries so that split stays
  /// expressible.
  static const layerUnlocked = IconData(
    0xe306,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// SPLIT ROLE — current Material choice is wrong for half its sites.
  /// 6 uses are genuinely layers (editor_screen end-drawer button,
  /// layer_overflow_sheet rows 11, multi_select 'layers' tile,
  /// layer_thumbnail fallback, layers_panel header) → stack is correct.
  /// But shape_shadow_body:42, image_shadow_body:42 and
  /// image_mode_toolbar:117 use it for the SHADOW tool (label
  /// l10n.shadowTool). Shadow needs its own glyph — suggest
  /// squareHalfBottom (offset fill reads as a cast shadow) or
  /// copySimple. Note the app is already inconsistent:
  /// shape_mode_toolbar:123 uses blur_on_rounded for the same
  /// shadowTool label.
  static const layersPanel = IconData(
    0xe466,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// WRONG TODAY: this is the straight-Line drawing tool, but
  /// show_chart_rounded is a zigzag stock-chart glyph. lineSegment
  /// (straight line with endpoints) is what the tool actually draws.
  static const lineTool = IconData(
    0xe6d2,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Lock layer(s) — always paired with the unlock state in the same
  /// ternary (layer_overflow_sheet:244/422, multi_select:69).
  /// lockSimple/lockSimpleOpen is a matched pair with no keyhole
  /// detail, which survives the 20dp dock tile better than
  /// lock/lockOpen.
  static const lock = IconData(
    0xe308,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// The Look tool (filter presets + precision adjust) on the main
  /// toolbar, image dock, quick capsule, effects list and sticker Style
  /// slot. Material auto_awesome is sparkles; sparkle is the direct
  /// equivalent. magicWand was the alternative but reads as a discrete
  /// action rather than a look/effects category.
  static const lookTool = IconData(
    0xe6a2,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Overflow menu across home grid, every mode toolbar and
  /// quick_capsule. Horizontal ellipsis, symmetric. Minor mismatch:
  /// paint_tool_type.dart:35 reuses it for the 'Dash-dot' stroke tool —
  /// that one should get a stroke-pattern glyph, not the overflow icon
  /// (dotsThree will read as 'more' inside the tool grid).
  static const moreActions = IconData(
    0xe1fe,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Double tick = several selected. Was the same glyph as the per-row
  /// selected tick.
  static const multiSelectCount = IconData(
    0xe53a,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Sibling-panel paging chip in dock_sheet_chrome
  /// (previousPageTooltip). Pure reading-direction paging, so it must
  /// keep flipping under RTL exactly as the Material rounded chevron
  /// did.
  static const navPrevious = IconData(
    0xe138,
    fontFamily: _family,
    fontPackage: _package,
    matchTextDirection: true,
  );

  /// 'No templates found' empty state. Phosphor has no search-off
  /// glyph; magnifyingGlassMinus would misread as zoom-out, so `empty`
  /// (the literal nothing-here mark) is the honest pick. Flag for
  /// design review.
  static const noResults = IconData(
    0xedbc,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// "None" border-width chip in layer_border_body (l10n.noneOption).
  static const noneOption = IconData(
    0xe3de,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// The centre (dx=0,dy=0, no-offset) cell of the 3x3
  /// PanelDirectionPad.
  static const offsetCenter = IconData(
    0xe1d8,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// The 8 outer cells of PanelDirectionPad rotate this by math.atan2
  /// to set a shadow offset. Mirroring would corrupt the offset the
  /// button writes — mirror MUST be false.
  static const offsetDirection = IconData(
    0xe08e,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Layer opacity slider/panel/toolbar tile. Deliberately NOT a
  /// droplet: shape_mode_toolbar renders opacity (:74) and the
  /// blur/shadow tile (:123) in the SAME strip, and drop/dropHalf are
  /// indistinguishable at 20dp. circleHalf is the standard half-fill
  /// opacity glyph. If the contrast effect (Icons.contrast_rounded,
  /// other slice) also wants circleHalf, give contrast circleHalfTilt.
  static const opacity = IconData(
    0xe566,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// recent_projects_grid.dart:353 — 'Open' row in the project-card
  /// action sheet. arrowSquareOut is Phosphor's open-in-new. mirror
  /// false: Material's open_in_new does not mirror today, and the arrow
  /// means 'leave this surface', not 'forward in reading order'.
  static const openProject = IconData(
    0xe5de,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// paint_tool_specs.dart:157 — PaintSpec(id: 'fill', label: 'Fill')
  /// in the paint tool strip. paintBucket is the direct equivalent; its
  /// natural pour-handedness should not change per locale.
  static const paintFill = IconData(
    0xe392,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// 'Choose from library' row in the image source sheet and the image
  /// replace flow. Stacked images, exact match.
  static const photoLibrary = IconData(
    0xe836,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Primary Photo tool on the main toolbar, the image-source sheet
  /// title, and the empty photo-slot badge. Phosphor 2.1 has NO image-
  /// plus glyph (only cameraPlus, which would wrongly bias toward the
  /// camera branch of the source sheet), so the '+' affordance is lost
  /// — if it matters, overlay a small plus badge on the empty-slot site
  /// only.
  static const photoTool = IconData(
    0xe2ca,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Polygon paint tool (paint_tool_type.dart) + the 'Sides' side-count
  /// spec. phosphor `polygon` is the literal shape primitive.
  static const polygonTool = IconData(
    0xe6d0,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Always the 'Adjust precisely' / fine-tune disclosure header (image
  /// look, canvas panel, export preview, shadow body, border body).
  /// Horizontal sliders, exact match.
  static const precisionAdjust = IconData(
    0xe434,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// size_picker_dialog.dart:75 — the 2480x3508 A4 portrait 300dpi
  /// print preset. fileText (page with ruled lines) is the exact
  /// Material description equivalent. Its landscape sibling on the next
  /// line uses Icons.article_outlined (another slice) and should get a
  /// visibly different glyph so the two print presets stay
  /// distinguishable.
  static const presetA4Portrait = IconData(
    0xe23a,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// size_picker_dialog.dart:65 — the 1920x1080 landscape canvas preset
  /// (l10n.hd1080pPreset). highDefinition is the literal 'HD' badge, a
  /// 1:1 match for the labelled preset.
  static const presetHd1080p = IconData(
    0xea8e,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// LinkedIn post (1200x628) preset in size_picker_dialog.
  static const presetLinkedIn = IconData(
    0xe0ee,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// nav_shell.dart:80 — BottomTabItem.activeIcon for the Projects tab.
  /// Same glyph as the inactive variant; the selected state belongs in
  /// PhosphorIconsFill.folder, not in a different picture (folderOpen
  /// would change the meaning to 'browsing inside').
  static const projectsTab = IconData(
    0xe24a,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Matches undo's arrowUUpLeft — the two sit adjacent in the top bar
  /// and came from different arrow families.
  static const redo = IconData(
    0xe08c,
    fontFamily: _family,
    fontPackage: _package,
    matchTextDirection: true,
  );

  /// Rename: project card menu, document menu, layer overflow, layers
  /// panel row action. pencilSimpleLine (pencil over a baseline) is the
  /// rename-a-label glyph. Pen handedness is decorative — no mirror.
  static const rename = IconData(
    0xebc6,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Dominant role is Replace (image/sticker/shape replace slots, quick
  /// capsule, image_replace_flow) — 'swap' is the exchange glyph.
  /// Exchange is not reading direction, so no mirror. Secondary use in
  /// text_direction_mode_picker for TextDirectionMode.auto also must
  /// NOT flip (it sits next to literal RTL/LTR glyphs).
  static const replace = IconData(
    0xe83c,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// 'Reset crop / restore image' in crop_mode_overlay. Single counter-
  /// clockwise arrow is the reset convention; circular, so no mirror.
  static const reset = IconData(
    0xe038,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// 'Resume draft' card on Home. Clock rotation is universal, not
  /// reading-direction — do NOT mirror even though it resembles an undo
  /// curve.
  static const resumeDraft = IconData(
    0xe1a0,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// settings_screen.dart:113 — _SwitchTile for rightHandedToolbarTitle
  /// (aligns the bottom strip to the right edge for right-thumb reach).
  /// mirror MUST be false and this is the strongest case in the slice:
  /// flipping renders a LEFT hand while the label says right-handed.
  static const rightHandedToolbar = IconData(
    0xe298,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// selection_overlay.dart:614 — this is _RotateGlyph, the rotate knob
  /// on the selection frame (Transform.rotate 45deg over
  /// Icons.refresh). Not a reload. arrowClockwise is the single
  /// circular arrow. mirror MUST stay false: flipping would show the
  /// arrow going counter-clockwise, contradicting the drag direction.
  static const rotateHandle = IconData(
    0xe036,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// WRONG TODAY: the control is SaturationEffect, but a palette glyph
  /// reads as "pick a colour". A half-filled droplet is the standard
  /// "amount of colour" mark.
  static const saturation = IconData(
    0xe210,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// WRONG TODAY: the document menu item is editorSaveProject, but a
  /// bookmark-plus reads as "bookmark this". floppyDisk is unambiguous
  /// save.
  static const saveProject = IconData(
    0xe248,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// TextResizeMode.scaleText — 'corner drag scales the whole text'.
  /// Four diagonal arrows outward = uniform scale. Sits directly above
  /// the resizeBox row, so it must stay visually distinct from
  /// rectangle.
  static const scaleUniform = IconData(
    0xe0a2,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Search field prefix in templates_browse_screen. Magnifier
  /// handedness is decorative, not directional.
  static const search = IconData(
    0xe30c,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Chosen-goal badge on an onboarding card — "this option is picked",
  /// distinct from the multi-select count. Material used the FILLED
  /// variant here for emphasis; Phosphor Regular is outline only, so
  /// reach for PhosphorIconsFill.checkCircle if that weight is load-
  /// bearing.
  static const selectedCheck = IconData(
    0xe184,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Unselected state of a choice: multi-select row checkmarks in
  /// layers_panel (selected → check_circle_rounded → checkCircle) and
  /// the export-sheet option list. Plain circle.
  static const selectionUnchecked = IconData(
    0xe18a,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Marching-ants box with a plus = add a region, which is what the
  /// mask editor does.
  static const selectiveMask = IconData(
    0xe69c,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// layer_overflow_sheet.dart:231 — 'Send backward' row, calls
  /// LayerActions.sendBackward. Mirror image in meaning of
  /// bringForward; selectionBackground is its exact Phosphor
  /// counterpart.
  static const sendBackward = IconData(
    0xeaf8,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Settings button in home_header. gearSix's rounded teeth sit better
  /// in the quiet paper/ink chrome than `gear`.
  static const settings = IconData(
    0xe272,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// shadow_precision.dart:93 — third entry in shadowPresetIcons, the
  /// 'Glow' macro preset (blur + opacity). sunDim is the small disc
  /// with radiating rays, the closest thing to Material's flare.
  /// Deliberately not `sparkle` (auto_awesome territory) and not `sun`
  /// (Icons.wb_sunny_outlined, the sticker glow preset, will want that
  /// one).
  static const shadowPresetGlow = IconData(
    0xe474,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Text-shadow "Hard" preset in shadow_precision.dart; crisp square =
  /// hard edge. Same role as Icons.square_outlined in
  /// layer_shadow_body, so they should collapse to this one name.
  static const shadowPresetHard = IconData(
    0xeb16,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// 'Lift' shadow preset in shadow_precision (raised/elevated shadow).
  /// Vertical, so mirroring is meaningless — false.
  static const shadowPresetLift = IconData(
    0xe066,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Text-shadow "Soft" macro preset.
  static const shadowPresetSoft = IconData(
    0xe1aa,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Two offset plates read as a cast shadow. The shadow tool
  /// previously borrowed the LAYERS glyph on two toolbars and the BLUR
  /// glyph on a third — three icons for one tool, one of them identical
  /// to the layers drawer button beside it.
  static const shadowTool = IconData(
    0xe468,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// PaintToolType.arrow — the icon depicts the arrow the tool DRAWS on
  /// canvas, not a navigation direction. Phosphor's hardcoded
  /// matchTextDirection would flip it in Persian while the drawn stroke
  /// stays put, so the override matters here.
  static const shapeArrow = IconData(
    0xe06c,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// PaintToolType.circle — the shape the tool draws.
  static const shapeCircle = IconData(
    0xe18a,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// paint_tool_type.dart:38 — PaintToolType.hexagon in the paint shape
  /// registry. Literal shape glyph, exact match.
  static const shapeHexagon = IconData(
    0xe2ae,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Editor toolbar Shape tool; Phosphor's triangle+circle+square is a
  /// direct hit.
  static const shapeTool = IconData(
    0xec5e,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// AppBar export button + the Share export intent. phosphor `export`
  /// is the tray-with-up-arrow, i.e. the iOS share glyph. Arrow is
  /// vertical, not reading-direction, so no mirror (a `shareFat` choice
  /// WOULD need mirror:true).
  static const share = IconData(
    0xeaf0,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// 3508x2480 A4-landscape print preset. Pairs with fileText for the
  /// portrait A4 sibling — article's wider text block carries the
  /// landscape read where a second sheet glyph would not.
  static const sizePresetA4Landscape = IconData(
    0xe0a8,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// 1080x1080 Instagram-post preset in size_picker_dialog. Phosphor
  /// also ships instagramLogo if the team ever wants literal branding
  /// here.
  static const sizePresetInstagramPost = IconData(
    0xe10e,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Sticker Size tool — dock tile and panel header (label
  /// l10n.sizeTool). Phosphor resize (box with a corner resize arrow)
  /// is the clean 'change this object's size' read, and stays distinct
  /// from frameCorners used for canvas size.
  static const sizeTool = IconData(
    0xed6e,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// WEAK TODAY: the switch is 'Snap to guides', but straighten_rounded
  /// is a ruler (measuring, not snapping). magnet is the standard snap
  /// affordance and leaves space_bar_rounded (show spacing guides)
  /// unambiguous.
  static const snapToGuides = IconData(
    0xe680,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Square/rectangle geometry: paint Rectangle tool, image Shape
  /// (mask) panel + dock tile, 1:1 canvas preset, 1024x1024 size
  /// preset. Plain square is exactly right.
  static const squareShape = IconData(
    0xe45e,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// sticker_style_body.dart:53 — StickerStylePreset.outline (applies a
  /// stroke outline, clears shadow). Phosphor has no outlined-letter
  /// glyph; boundingBox is the dashed frame with corner marks, which
  /// both matches Material's text-box-with-handles and reads as
  /// 'outline'.
  static const stickerPresetOutline = IconData(
    0xe6ce,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// sticker_style_body.dart:49 — StickerStylePreset.pop. Phosphor
  /// `lightning` is the bolt; `lightningA` is the alternate slab form
  /// and reads busier at 18px.
  static const stickerPresetPop = IconData(
    0xe2de,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Sticker tool on the main toolbar, the sticker picker sheet, and
  /// the 'original' sticker style preset. Direct equivalent.
  static const stickerTool = IconData(
    0xe436,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// The 1080x1920 9:16 story preset in both size_picker_dialog and the
  /// canvas aspect presets. Phone-shaped tall format.
  static const storyPreset = IconData(
    0xe1e0,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// A dot in a ring reads as brush-tip size. Was the same glyph as the
  /// paint Line tool, in the same mode.
  static const strokeWeight = IconData(
    0xece0,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Text style presets slot in text_mode_toolbar; also the generic
  /// category fallback in settings. Keeping sparkle here and magicWand
  /// for image effects keeps the two 'magic' surfaces distinguishable.
  static const stylePresets = IconData(
    0xe5b8,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// shape_style_body.dart:118 — ShapePanelShell header for the shape
  /// STYLE panel (l10n.styleTool: fill colour, fill opacity, gradient,
  /// corner radius, stroke). Material already blurs this with
  /// Icons.palette_rounded, which is the pure COLOUR tool in
  /// text_mode_toolbar and paint_tool_specs. Recommending `swatches` so
  /// Style and Colour stop sharing one picture; use `palette` only if
  /// the parent wants a byte-faithful port.
  static const styleTool = IconData(
    0xe5b8,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// nav_shell.dart:74 — inactive Templates tab. Its activeIcon
  /// (Icons.grid_view_rounded) is in another slice; it must land on
  /// squaresFour too so the tab does not change shape when selected.
  static const templatesTab = IconData(
    0xe464,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Centre segment in layout_panel; ALSO doubles as the text-mode
  /// 'layout' slot icon — consider textAlignJustify for that slot so
  /// the slot and its own centre segment differ. Literal spatial
  /// meaning: never mirror.
  static const textAlignCenter = IconData(
    0xe480,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// layout_panel.dart:111 — left member of the same alignment group.
  /// Same rule as textAlignRight: literal spatial semantics, never
  /// mirror.
  static const textAlignLeft = IconData(
    0xe484,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// layout_panel.dart:121 — right member of the ToggleSegmentGroup
  /// (left/center/right) that sets text alignment. mirror MUST be
  /// false: this is a literal spatial meaning, and flipping it would
  /// make the button lie about the alignment it applies — the single
  /// most damaging wrong `true` in the app, since Persian is the
  /// default locale.
  static const textAlignRight = IconData(
    0xe486,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// LTR tile, same dialog. Must not mirror, for the same reason.
  /// Alternative: textIndent.
  static const textDirectionLtr = IconData(
    0xe064,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// RTL tile in the text-direction dialog. CRITICAL mirror:false —
  /// flipping this shows the LTR glyph to Persian users. Rejected
  /// textAlignRight (collides with the real align controls in
  /// layout_panel). textOutdent is a richer alternative if design
  /// prefers text-lines+arrow.
  static const textDirectionRtl = IconData(
    0xe062,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// layer_overflow_sheet.dart:557 — ToggleSegment for
  /// l10n.italicAction, calls _ctrl.setItalic. The slant is a
  /// typographic property, not reading direction — do not mirror.
  static const textItalic = IconData(
    0xe5c0,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Fallback thumbnail for an empty text layer. textT is the
  /// conventional text-layer mark; textAa is the alternative if a
  /// lighter glyph is wanted.
  static const textLayer = IconData(
    0xe48a,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Add-text on the main toolbar (label l10n.textTool) and the Font
  /// tile in text_mode_toolbar:71. textT covers the tool; if you want
  /// the Font tile to stop duplicating the tool glyph, give
  /// text_mode_toolbar's font spec textAa instead.
  static const textTool = IconData(
    0xe48a,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// layer_overflow_sheet.dart:569 — ToggleSegment for
  /// l10n.underlineAction, calls _ctrl.setUnderline. Exact Phosphor
  /// equivalent; symmetric glyph, no mirroring.
  static const textUnderline = IconData(
    0xe5c4,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Settings > Theme nav tile (system/light/dark). The tilted half-
  /// circle is the conventional light/dark mark, and leaves plain
  /// circleHalf free for Contrast.
  static const themeMode = IconData(
    0xe18e,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// 'Multi-finger undo/redo' switch in settings. Hand handedness is a
  /// drawing convention, not reading direction.
  static const touchGesture = IconData(
    0xec90,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Undo (editor app bar, dock_sheet_chrome undo chip). Genuine
  /// reading-direction glyph — Material's undo_rounded already auto-
  /// mirrors here, so keeping mirror true preserves current RTL
  /// behaviour. arrowUUpLeft is the U-turn shape and pairs exactly with
  /// arrowUUpRight for redo — map redo to that in whichever slice owns
  /// it.
  static const undo = IconData(
    0xe08a,
    fontFamily: _family,
    fontPackage: _package,
    matchTextDirection: true,
  );

  /// image_effects_body.dart:493 — EffectDisplay for UnknownEffect(),
  /// the forward-compat carrier for an effect written by a newer build.
  /// Not a help affordance: it labels an unrecognised entry so the user
  /// can still see and remove it. Phosphor `question` is the circled
  /// mark (`questionMark` is the bare glyph, too light next to the
  /// other effect rows).
  static const unknownEffect = IconData(
    0xe3e8,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Unlock state of the same ternary as lock_outline_rounded. Must
  /// stay the visual sibling of lockSimple.
  static const unlock = IconData(
    0xe30a,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// YouTube-thumbnail goal card in onboarding and the 1280x720
  /// landscape preset. monitorPlay (screen + play triangle) carries
  /// 'video' without using the youtubeLogo brand mark.
  static const videoPreset = IconData(
    0xe58c,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Vignette effect — the disclosure in image_look_body and the effect
  /// row in image_effects_body. Phosphor has a literal vignette icon;
  /// perfect match.
  static const vignette = IconData(
    0xeba2,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// Layer show/hide toggle (layers_panel, paired with visibility_off →
  /// eyeSlash in another slice) and the export sheet's Preview button.
  /// Symmetric.
  static const visible = IconData(
    0xe220,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// WarmthEffect row in the image effects list. thermometerSimple
  /// stays legible at 18px; `thermometer` if a fuller glyph is
  /// preferred.
  static const warmthEffect = IconData(
    0xe5cc,
    fontFamily: _family,
    fontPackage: _package,
  );

  /// 'Enable canvas zoom' switch in settings.
  static const zoom = IconData(
    0xe310,
    fontFamily: _family,
    fontPackage: _package,
  );
}
