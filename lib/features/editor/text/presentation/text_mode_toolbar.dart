/// Text-mode toolbar module, split into `part` files by sub-tool
/// (Phase 4 plan §5.1). The library root keeps every import, the
/// tool registry (`_ToolSpec`), the dock strip, and the sheet host —
/// everything else lives in a part file grouped by the sub-tool it
/// serves. Part files never carry their own `import`s; add new
/// imports here.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/haptics.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import '../../../color_picker/presentation/color_picker_sheet.dart';
import '../../../settings/application/settings_controller.dart';
import '../../application/live_overlay_controller.dart';
import '../../application/selection_controller.dart';
import '../../engine/core/editor_document.dart';
import '../../engine/modules/text/text_layer.dart';
import '../../presentation/widgets/dock_tool_strip.dart';
import '../../presentation/widgets/dock_tool_tile.dart';
import '../../presentation/widgets/inline_color_body.dart';
import '../../presentation/widgets/panel_option_tile.dart';
import '../../ui/editor_slider_row.dart';
import '../../ui/editor_tier_gap.dart';
import '../../ui/panel_direction_pad.dart';
import '../../ui/precision_disclosure.dart';
import '../../application/recent_colors_controller.dart';
import '../../toolbar/domain/sibling_swipe_strategy.dart';
import '../../toolbar/domain/sub_tools/widget_sub_tool.dart';
import '../../toolbar/presentation/sub_tool_sheet.dart';
import '../application/text_tool_controller.dart';
import '../domain/font_catalog.dart';
import '../domain/text_style_presets.dart';
import 'text_floating_toolbar.dart' show showTextMoreSheet;

part 'text_decoration_panels.dart';
part 'text_font_picker.dart';
part 'text_layout_panel.dart';
part 'text_panel_primitives.dart';
part 'text_resize_tiles.dart';
part 'text_size_panel.dart';
part 'text_style_browser.dart';

/// Bottom dock for text mode — Canva-style.
///
/// The dock is a single horizontally scrollable strip of large
/// icon+label tiles. Each tile opens an in-dock compact panel so
/// the canvas stays visible while the user edits.
///
/// Tiles (left → right):
///   * Font — opens the typeface picker.
///   * Size — opens a slider sheet with presets.
///   * Color — opens the colour picker (live preview on the layer).
///   * Style — one-tap visual style presets.
///   * Align — alignment, line height, letter spacing.
///   * More — structural text actions shared with the floating bar.
///   * Background — fill, padding, corner radius.
///   * Border — glyph outline (color + width).
///   * Shadow — color, blur, offset.
///   * Resize — resize mode (scale text vs resize box).
///
/// Bold / Italic / Underline live in the floating bar's More sheet
/// and inside the Style body that the input-flow sheet renders, not
/// on the bottom dock — they're toggle actions, not category sheets.
class TextModeToolbar extends ConsumerStatefulWidget {
  const TextModeToolbar({super.key});

  // Width of a DockToolTile + its horizontal margin. Kept in sync
  // with dock_tool_tile.dart (66 + 2*2).
  static const double _tileExtent = 70;

  @override
  ConsumerState<TextModeToolbar> createState() => _TextModeToolbarState();

  // ─── Tool registry ─────────────────────────────────────────────
  //
  // Flat, scrollable strip ordered by expected frequency of use so
  // the first viewport carries Font / Size / Color / Style / Align /
  // More. Deeper text decoration tools remain one short swipe away.
  //
  // Bold / Italic / Underline are deliberately NOT a tile here —
  // they're toggle actions (not category sheets) and live in the
  // floating bar's "More" sheet.
  static final List<_ToolSpec> _tools = <_ToolSpec>[
    _ToolSpec(
      id: 'font',
      icon: Icons.text_fields_rounded,
      bodyBuilder: _TextBodies.fontBody,
    ),
    _ToolSpec(
      id: 'size',
      icon: Icons.format_size_rounded,
      // No short dock variant: the strip tile reads simply "Size".
      // The numeric value lives inside the sheet body where it can
      // be read precisely without crowding the dock with bucket
      // words ("Body" / "Display" etc.) that varied as the user
      // dragged.
      bodyBuilder: _TextBodies.sizeBody,
    ),
    _ToolSpec(
      id: 'color',
      icon: Icons.palette_rounded,
      bodyBuilder: _TextBodies.colorBody,
    ),
    _ToolSpec(
      // One-tap visual style presets. Sits next to Font because
      // both are typeface-level, look-defining choices and users
      // who reach for one often want the other in the same flow.
      id: 'styles',
      icon: Icons.auto_awesome_rounded,
      bodyBuilder: _TextBodies.stylesBody,
    ),
    _ToolSpec(
      id: 'layout',
      icon: Icons.format_align_center_rounded,
      bodyBuilder: _TextBodies.layoutBody,
    ),
    _ToolSpec(id: 'more', icon: Icons.more_horiz_rounded),
    _ToolSpec(
      id: 'background',
      // Filled-rectangle glyph reads as a *shape with fill*; clearly
      // distinct from the Color tile's circular swatch so the two
      // adjacent tiles never blur together at a glance.
      //
      // Dock tile is space-constrained — the full word ellipsises to
      // "Backgrou…" which reads like a typo, so this id gets the "BG"
      // short dock label (see _localizedToolDockLabel); the panel
      // header still shows the full word.
      icon: Icons.rectangle_rounded,
      bodyBuilder: _TextBodies.backgroundBody,
    ),
    _ToolSpec(
      id: 'border',
      icon: Icons.border_outer_rounded,
      bodyBuilder: _TextBodies.borderBody,
    ),
    _ToolSpec(
      id: 'shadow',
      icon: Icons.blur_on_rounded,
      bodyBuilder: _TextBodies.shadowBody,
    ),
    _ToolSpec(
      // Sheet id is kept as 'behavior' so any persisted session
      // state (TextSession.openSheet) keeps routing correctly. Only
      // the user-visible label changed: "Behavior" → "Resize".
      id: 'behavior',
      icon: Icons.aspect_ratio_rounded,
      bodyBuilder: _TextBodies.behaviorBody,
    ),
  ];

  /// Resolve a tool id → its spec. Used by [TextModeSheetPanel] to
  /// pick the body builder for the currently-open sheet, and by
  /// the sheet chrome to navigate to the prev/next tool.
  // ignore: library_private_types_in_public_api
  static _ToolSpec? specById(String id) {
    for (final s in _tools) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Ordered list of sibling tool ids — used by sheet swipe
  /// navigation to jump to the prev/next tool.
  static List<String> get toolIds => _tools
      .where((s) => s.bodyBuilder != null)
      .map((s) => s.id)
      .toList(growable: false);

  static TextLayer? _selectedTextLayer(WidgetRef ref) {
    final selection = ref.watch(selectionControllerProvider);
    if (!selection.hasSelection) return null;
    final layer = ref
        .watch(renderedDocumentProvider)
        .layerById(selection.selectedId!);
    // Emoji stickers are TextLayer instances but must not surface
    // the Text floating toolbar / font / colour controls.
    if (layer is TextLayer && !layer.isSticker) return layer;
    return null;
  }
}

class _TextModeToolbarState extends ConsumerState<TextModeToolbar> {
  final _scroll = ScrollController();
  String? _lastOpen;

  // Session-scoped guard so the discovery peek fires at most once
  // per app run — first-time users see hidden tier-2 tools exist;
  // returning users aren't pestered.
  static bool _peekedThisSession = false;

  @override
  void initState() {
    super.initState();
    if (!_peekedThisSession) {
      _peekedThisSession = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _runPeek());
    }
  }

  Future<void> _runPeek() async {
    if (!mounted || !_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.maxScrollExtent <= 0) return;
    await _scroll.animateTo(
      48,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
    if (!mounted || !_scroll.hasClients) return;
    await _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _ensureVisible(int index) {
    if (!_scroll.hasClients) return;
    final viewport = _scroll.position.viewportDimension;
    final tile = TextModeToolbar._tileExtent;
    final target = (index * tile) - (viewport / 2) + (tile / 2);
    final clamped = target.clamp(
      _scroll.position.minScrollExtent,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      clamped,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = TextModeToolbar._selectedTextLayer(ref);
    final hasSelectedText = selected != null;
    final session = ref.watch(textToolControllerProvider);

    final style = selected?.style ?? session.defaultStyle;
    final fontEntry = style.fontFamily == null
        ? null
        : kFontCatalog
              .where((e) => e.family == style.fontFamily)
              .cast<FontEntry?>()
              .firstWhere((_) => true, orElse: () => null);

    // When the open sheet changes (from anywhere — tile tap or
    // sibling swipe inside the sheet) scroll the matching tile
    // into view so the user always sees which tool is active.
    final open = session.openSheet;
    if (open != _lastOpen) {
      _lastOpen = open;
      if (open != null) {
        final idx = TextModeToolbar._tools.indexWhere((s) => s.id == open);
        if (idx >= 0) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _ensureVisible(idx),
          );
        }
      }
    }

    final rightHanded = ref.watch(
      appSettingsProvider.select((s) => s.rightHandedToolbar),
    );

    return SizedBox(
      height: _stripHeight(context),
      child: DockToolStrip(
        controller: _scroll,
        centerWhenFits: true,
        // Handedness affects alignment only — never tile order.
        fitAlignment: rightHanded
            ? MainAxisAlignment.end
            : MainAxisAlignment.center,
        children: [
          for (final i in _toolOrder(context, ref)) ...[
            if (_isTierBoundary(context, ref, i)) const EditorTierGap(),
            DockToolTile(
              icon: TextModeToolbar._tools[i].icon,
              label: _localizedToolDockLabel(
                context.l10n,
                TextModeToolbar._tools[i],
              ),
              valueText: TextModeToolbar._tools[i].id == 'font'
                  ? fontEntry?.label
                  : null,
              fontFamily: TextModeToolbar._tools[i].id == 'font'
                  ? fontEntry?.family
                  : null,
              swatchColor: TextModeToolbar._tools[i].id == 'color'
                  ? style.color
                  : null,
              enabled: hasSelectedText,
              active: session.openSheet == TextModeToolbar._tools[i].id,
              compact: _isCompact(context),
              onTap: () {
                EditorHaptics.tap();
                final spec = TextModeToolbar._tools[i];
                if (spec.id == 'more') {
                  ref.read(textToolControllerProvider.notifier).closeSheet();
                  if (selected != null) {
                    showTextMoreSheet(context, ref, selected);
                  }
                  return;
                }
                // Toggling: re-tapping the active tile dismisses
                // the sheet (in addition to drag-handle / swipe-
                // down / Done pill). Tapping a different tile
                // switches sheets.
                ref
                    .read(textToolControllerProvider.notifier)
                    .toggleSheet(spec.id);
              },
              // Long-press peek removed from tiles — too easy to
              // trigger an undo by resting a thumb on the strip.
              // Peek is now opt-in via the Undo chip in the sheet
              // header (DockSheetChrome.onUndo).
            ),
          ],
        ],
      ),
    );
  }

  // ── Layout helpers ──────────────────────────────────────────────
  bool _isCompact(BuildContext ctx) {
    final m = MediaQuery.of(ctx);
    return m.size.shortestSide < 380 || m.orientation == Orientation.landscape;
  }

  double _stripHeight(BuildContext ctx) => _isCompact(ctx) ? 64 : 80;

  /// Tile indices in display order. **Order is stable** regardless
  /// of left/right handed mode — Font is always first. Right-handed
  /// mode only shifts the row's alignment (handled by the parent
  /// [DockToolStrip] via `fitAlignment`); it never reverses tools.
  List<int> _toolOrder(BuildContext ctx, WidgetRef ref) {
    return List<int>.generate(TextModeToolbar._tools.length, (i) => i);
  }

  bool _isTierBoundary(BuildContext ctx, WidgetRef ref, int rawIndex) {
    // Boundary always sits before the deeper decoration tools
    // (Font / Size / Color / Style / Align / More ▸ Background / Border /
    // Shadow / Resize). Stable across left/right handed mode.
    return rawIndex == 6;
  }
}

/// In-dock sheet panel: routes the active sheet id → its body and
/// renders it inside the dock's `expanded` slot. Hosted by
/// [EditorToolDock] so the canvas reflows above the dock instead
/// of being overlaid (Canva-style: canvas stays visible, just a
/// little shorter while the sheet is open).
class TextModeSheetPanel extends ConsumerWidget {
  const TextModeSheetPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(textToolControllerProvider);
    final sheetId = session.openSheet;
    if (sheetId == null) return const SizedBox.shrink();
    final layer = TextModeToolbar._selectedTextLayer(ref);
    if (layer == null) return const SizedBox.shrink();
    final spec = TextModeToolbar.specById(sheetId);
    if (spec == null || spec.bodyBuilder == null) {
      return const SizedBox.shrink();
    }

    // Sibling navigation — swipe left/right inside the sheet
    // jumps to the next/prev tool in the strip order, wrapping
    // around so the user can cycle without hitting a dead end.
    final swipe = SiblingSwipeStrategy<String>(order: TextModeToolbar.toolIds);
    final prevId = swipe.prev(sheetId);
    final nextId = swipe.next(sheetId);
    final ctrl = ref.read(textToolControllerProvider.notifier);

    // Wrap the bespoke body in a [WidgetSubTool] so every text
    // sheet inherits the same lifted SubToolSheet chrome paint
    // tools use — surface elevation, Done pill, sibling-swipe.
    // Body widget is unchanged; only the surrounding chrome is
    // unified.
    final subTool = WidgetSubTool(
      headerTitle: _localizedToolLabel(context.l10n, spec),
      headerIcon: spec.icon,
      builder: (ctx, _) => spec.bodyBuilder!(ctx, ref, layer),
    );

    return SubToolSheet(
      subTool: subTool,
      onClose: ctrl.closeSheet,
      // Undo lives on the persistent floating action in the editor
      // chrome — keeping a duplicate chip in every sheet header was
      // both visual noise and a footgun (sheet undo + floating undo
      // looked like two different histories).
      onUndo: null,
      onPrev: prevId == null ? null : () => ctrl.toggleSheet(prevId),
      onNext: nextId == null ? null : () => ctrl.toggleSheet(nextId),
      // Header chip is the canonical neutral ✕ close — same split
      // as paint. Mode-exit lives on the top-right floating pill.
    );
  }
}

/// Spec for a tile in the bottom strip.
///
/// [id] is the single source of identity: [specById] lookup, sheet
/// swipe navigation, and persisted `TextSession.openSheet` state all
/// key off it — never rename an existing id, only add new ones.
/// Display text is NOT stored here; [_localizedToolLabel] /
/// [_localizedToolDockLabel] are the single source for that, keyed
/// off [id]. This used to also carry hardcoded English `label`/
/// `dockLabel` fields that nothing actually displayed (every
/// registered id already had an l10n switch case) — dropped as a
/// Phase 4 pre-split cleanup so a future rename of the display copy
/// can never silently desync from a fallback string still baked in
/// here.
class _ToolSpec {
  const _ToolSpec({required this.id, required this.icon, this.bodyBuilder});

  final String id;
  final IconData icon;

  /// Body builder rendered by [TextModeSheetPanel] when this
  /// tool's sheet is open. `null` for tools that handle their
  /// interaction via a modal picker (Font, Color).
  final Widget Function(BuildContext, WidgetRef, TextLayer)? bodyBuilder;
}

String _localizedToolDockLabel(AppLocalizations l10n, _ToolSpec spec) {
  // Only the Background tile shortens on the dock strip ("BG" — the
  // full word ellipsises to "Backgrou…" at tile width).
  if (spec.id == 'background') return l10n.bgShortLabel;
  return _localizedToolLabel(l10n, spec);
}

String _localizedToolLabel(AppLocalizations l10n, _ToolSpec spec) {
  return switch (spec.id) {
    'font' => l10n.fontTool,
    'styles' => l10n.stylesTool,
    'color' => l10n.colorLabel,
    'size' => l10n.sizeTool,
    'layout' => l10n.alignAction,
    'more' => l10n.moreActionsSemantics,
    'background' => l10n.backgroundTool,
    'border' => l10n.borderTool,
    'shadow' => l10n.shadowTool,
    'behavior' => l10n.resizeTool,
    // Unreachable for the current registry (every id above has a
    // case) — the id itself is a more useful signal than a stale
    // hardcoded word if a future spec is added without its l10n case.
    _ => spec.id,
  };
}

/// Holder for the per-category body builders. Each method takes
/// (context, ref, layer) and returns a vertical column of compact
/// rows / sliders / segmented toggles.
class _TextBodies {
  const _TextBodies();

  // ─── Font ────────────────────────────────────────────────────────
  //
  // Inline font body: horizontal strip of typeface pills (each
  // rendered IN its own face so the user previews before tapping)
  // + a "Browse all" entry that opens the full sectioned picker
  // only when the user actually needs it. Keeps the canvas
  // visible for the most common case — picking from the last few
  // fonts used or the top of the catalog.
  static Widget fontBody(BuildContext context, WidgetRef ref, TextLayer layer) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final current = layer.style.fontFamily;
    return _InlineFontBody(
      layerId: layer.id,
      current: current,
      content: layer.content,
      onPick: (family) {
        EditorHaptics.tap();
        ctrl.setFontFamily(family);
      },
      // The All-fonts sheet opens scoped to whichever tab the user
      // is currently browsing. They can still switch script inside
      // the sheet — we just don't drop them into a mixed list.
      onBrowseAll: (script) async {
        final picked = await _showFontPickerSheet(
          context,
          current: current,
          initialScript: script,
        );
        if (picked == _FontPickResult.unchanged) return;
        EditorHaptics.confirm();
        ctrl.setFontFamily(picked.family);
      },
    );
  }

  // ─── Color ───────────────────────────────────────────────────────
  //
  // Inline color body — replaces the modal picker for the common
  // case. Renders the user's recent palette + a quick-pick row of
  // common defaults; "Custom" opens the full spectrum picker for
  // when none of the recents fit. Keeps the canvas visible the
  // whole time the user is auditioning colours.
  static Widget colorBody(
    BuildContext context,
    WidgetRef ref,
    TextLayer layer,
  ) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final current = layer.style.color;
    return InlineColorBody(
      current: current,
      recents: ref.watch(recentColorsControllerProvider),
      palette: InlineColorBody.defaultPalette,
      compactRecents: true,
      onPick: (c) {
        EditorHaptics.tap();
        // Preserve current alpha so a quick swatch tap doesn't
        // wipe a previously-dialed-in opacity. The custom picker
        // remains the authoritative entry point for changing alpha.
        ctrl.setColor(c.withValues(alpha: current.a));
      },
      onCustom: () async {
        final original = current;
        final picked = await showColorPickerSheet(
          context,
          initial: original,
          recents: ref.read(recentColorsControllerProvider),
          onLiveChange: ctrl.setColor,
          title: context.l10n.textColorTitle,
        );
        if (picked == null) {
          ctrl.setColor(original);
          return;
        }
        EditorHaptics.confirm();
        ctrl.setColor(picked);
        ctrl.rememberRecentColor(picked);
      },
    );
  }

  // ─── Size ────────────────────────────────────────────────────────
  //
  // Canva-style: a pair of big A−/A+ buttons for instant nudge,
  // a row of named size chips (S/M/L/XL/XXL) for confident jumps,
  // and the precise numeric slider tucked under "Advanced". The
  // canvas above shows the live result; no in-sheet hero needed.
  static Widget sizeBody(BuildContext context, WidgetRef ref, TextLayer layer) {
    return _SizeBody(layer: layer);
  }

  // ─── Styles (one-tap presets) ────────────────────────────────────
  //
  // Renders ready-made text looks as 2-column preview cards. Tap
  // applies the preset's full TextStyleSpec to the selected layer
  // (font + size + colour + decoration + shadow + outline +
  // background) in a single undoable step; layer content,
  // position, rotation, and resize-mode are left alone.
  static Widget stylesBody(
    BuildContext context,
    WidgetRef ref,
    TextLayer layer,
  ) {
    return _StylesBody(layer: layer);
  }

  // ─── Style ───────────────────────────────────────────────────────
  //
  // Removed in Phase 2: the Style tile is gone from the bottom dock.
  // Bold / Italic / Underline are toggle actions, not category sheets,
  // and now live in the floating bar's "More" sheet (see
  // showTextMoreSheet in text_floating_toolbar.dart). Opacity remains
  // adjustable via the Color picker's alpha channel.

  // ─── Background ──────────────────────────────────────────────────
  //
  // Style-first: 4 named shape tiles (None/Pill/Card/Tag) commit
  // radius+padding in one undo entry, then a curated swatch row
  // applies a fill colour. Numeric sliders (roundness, vertical /
  // horizontal padding, opacity) live under Advanced. The canvas
  // is the live preview — no in-sheet preview block.
  static Widget backgroundBody(
    BuildContext context,
    WidgetRef ref,
    TextLayer layer,
  ) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final style = layer.style;
    final hasBg = style.backgroundColor != null;

    void enableIfNeeded() {
      if (!hasBg) ctrl.setBackgroundEnabled(true);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelSectionLabel(context.l10n.shapeLabel),
        _StyleTileRow(
          tiles: [
            _StyleTile(
              icon: Icons.block_rounded,
              label: context.l10n.noneOption,
              selected: !hasBg,
              onTap: () => ctrl.setBackgroundEnabled(false),
            ),
            _StyleTile(
              icon: Icons.crop_16_9_rounded,
              label: context.l10n.pillOption,
              selected: hasBg && _bgMatches(style, _backgroundPresets[1]),
              onTap: () {
                enableIfNeeded();
                _applyBgPreset(ref, _backgroundPresets[1]);
              },
            ),
            _StyleTile(
              icon: Icons.crop_square_rounded,
              label: context.l10n.cardOption,
              selected: hasBg && _bgMatches(style, _backgroundPresets[2]),
              onTap: () {
                enableIfNeeded();
                _applyBgPreset(ref, _backgroundPresets[2]);
              },
            ),
            _StyleTile(
              icon: Icons.local_offer_outlined,
              label: context.l10n.tagOption,
              selected: hasBg && _bgMatches(style, _backgroundPresets[3]),
              onTap: () {
                enableIfNeeded();
                _applyBgPreset(ref, _backgroundPresets[3]);
              },
            ),
          ],
        ),
        if (hasBg) ...[
          const SizedBox(height: 10),
          // Pilot color UI — same compact layout the Text → Color
          // panel uses so the two text panels speak one visual
          // language. Behaviour (alpha-preserving picks, custom
          // sheet, recents) is unchanged.
          InlineColorBody(
            current: style.backgroundColor!,
            recents: ref.watch(recentColorsControllerProvider),
            palette: _curatedSwatches,
            compactRecents: true,
            onPick: (c) {
              // Preserve current alpha so the user keeps any opacity
              // they set in Advanced when swapping hues.
              final a = style.backgroundColor?.a ?? 0.85;
              ctrl.setBackgroundColor(c.withValues(alpha: a));
            },
            onCustom: () async {
              final original = style.backgroundColor!;
              final picked = await showColorPickerSheet(
                context,
                initial: original,
                recents: ref.read(recentColorsControllerProvider),
                onLiveChange: ctrl.setBackgroundColor,
                title: context.l10n.backgroundColorTitle,
              );
              if (picked == null) {
                ctrl.setBackgroundColor(original);
                return;
              }
              ctrl.setBackgroundColor(picked);
              ctrl.rememberRecentColor(picked);
            },
          ),
          const SizedBox(height: 6),
          _BackgroundPrecisionAdvanced(style: style),
        ],
      ],
    );
  }

  // ─── Border (glyph outline) ─────────────────────────────────────
  //
  // Style-first: 4 thickness tiles (None / Hairline / Solid / Bold)
  // commit width in one tap, then a swatch row picks the colour.
  // Exact width + opacity live under Advanced.
  static Widget borderBody(
    BuildContext context,
    WidgetRef ref,
    TextLayer layer,
  ) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final style = layer.style;
    final hasOutline = style.outlineColor != null;

    void enableIfNeeded() {
      if (!hasOutline) ctrl.setOutlineEnabled(true);
    }

    bool widthMatches(double target) =>
        hasOutline && (style.outlineWidth - target).abs() < 0.25;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mirror Background's breathing room above the first section
        // label so the STYLE header is not pinned to the sheet edge,
        // especially when the Adjust-precisely disclosure is open.
        const SizedBox(height: 6),
        _PanelSectionLabel(context.l10n.styleLabel),
        _StyleTileRow(
          tiles: [
            _StyleTile(
              icon: Icons.block_rounded,
              label: context.l10n.noneOption,
              selected: !hasOutline,
              onTap: () => ctrl.setOutlineEnabled(false),
            ),
            _StyleTile(
              icon: Icons.horizontal_rule_rounded,
              label: context.l10n.hairlineOption,
              iconSize: 16,
              selected: widthMatches(0.5),
              onTap: () {
                enableIfNeeded();
                ctrl.setOutlineWidth(0.5);
              },
            ),
            _StyleTile(
              icon: Icons.horizontal_rule_rounded,
              label: context.l10n.solidOption,
              iconSize: 22,
              selected: widthMatches(2),
              onTap: () {
                enableIfNeeded();
                ctrl.setOutlineWidth(2);
              },
            ),
            _StyleTile(
              icon: Icons.horizontal_rule_rounded,
              label: context.l10n.boldAction,
              iconSize: 30,
              selected: widthMatches(4),
              onTap: () {
                enableIfNeeded();
                ctrl.setOutlineWidth(4);
              },
            ),
          ],
        ),
        if (hasOutline) ...[
          const SizedBox(height: 10),
          // Approved compact color UI \u2014 same widget Text Color
          // and Background use, so all three text panels speak
          // one visual language. Behaviour (alpha-preserving
          // picks, custom sheet, recents) is unchanged.
          InlineColorBody(
            current: style.outlineColor!,
            recents: ref.watch(recentColorsControllerProvider),
            palette: _curatedSwatches,
            compactRecents: true,
            onPick: (c) {
              final a = style.outlineColor?.a ?? 1.0;
              ctrl.setOutlineColor(c.withValues(alpha: a));
            },
            onCustom: () async {
              final original = style.outlineColor!;
              final picked = await showColorPickerSheet(
                context,
                initial: original,
                recents: ref.read(recentColorsControllerProvider),
                onLiveChange: ctrl.setOutlineColor,
                title: context.l10n.borderColorTitle,
              );
              if (picked == null) {
                ctrl.setOutlineColor(original);
                return;
              }
              ctrl.setOutlineColor(picked);
              ctrl.rememberRecentColor(picked);
            },
          ),
          const SizedBox(height: 6),
          _BorderPrecisionAdvanced(style: style),
        ],
      ],
    );
  }

  // ─── Shadow ─────────────────────────────────────────────────────
  //
  // Style-first: 4 named shadow tiles (Soft / Hard / Glow / Lift)
  // commit blur+opacity macros, a 3×3 direction pad replaces the two
  // numeric Offset sliders, swatches pick colour. Numeric blur /
  // distance / opacity sit under Advanced.
  static Widget shadowBody(
    BuildContext context,
    WidgetRef ref,
    TextLayer layer,
  ) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final style = layer.style;
    final hasShadow = style.shadowColor != null;

    void enableIfNeeded() {
      if (!hasShadow) ctrl.setShadowEnabled(true);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Match Background/Border breathing room above first label.
        const SizedBox(height: 6),
        _PanelSectionLabel(context.l10n.styleLabel),
        _StyleTileRow(
          tiles: [
            _StyleTile(
              icon: Icons.block_rounded,
              label: context.l10n.noneOption,
              selected: !hasShadow,
              onTap: () => ctrl.setShadowEnabled(false),
            ),
            for (int i = 0; i < _shadowPresets.length; i++)
              _StyleTile(
                icon: _shadowPresetIcons[i],
                label: _shadowPresetLabel(context.l10n, _shadowPresets[i]),
                selected: hasShadow && _shadowMatches(style, _shadowPresets[i]),
                onTap: () {
                  enableIfNeeded();
                  _applyShadowPreset(
                    ref,
                    _shadowPresets[i],
                    baseColor: style.shadowColor ?? const Color(0xFF000000),
                  );
                },
              ),
          ],
        ),
        if (hasShadow) ...[
          const SizedBox(height: 10),
          // Approved compact color UI — same widget Color /
          // Background / Border use, so all four text panels
          // speak one visual language. Behaviour (alpha-
          // preserving picks, custom sheet, recents) is
          // unchanged. The compact swap also trims ~26-52dp off
          // the color section, comfortably absorbing the
          // direction pad below.
          InlineColorBody(
            current: style.shadowColor!,
            recents: ref.watch(recentColorsControllerProvider),
            palette: _curatedSwatches,
            compactRecents: true,
            onPick: (c) {
              final a = style.shadowColor?.a ?? 0.5;
              ctrl.setShadowColor(c.withValues(alpha: a));
            },
            onCustom: () async {
              final original = style.shadowColor!;
              final picked = await showColorPickerSheet(
                context,
                initial: original,
                recents: ref.read(recentColorsControllerProvider),
                onLiveChange: ctrl.setShadowColor,
                title: context.l10n.shadowColorTitle,
              );
              if (picked == null) {
                ctrl.setShadowColor(original);
                return;
              }
              ctrl.setShadowColor(picked);
              ctrl.rememberRecentColor(picked);
            },
          ),
          const SizedBox(height: 10),
          _PanelSectionLabel(context.l10n.directionLabel),
          // Constrain width so the pad reads as a secondary control,
          // not a hero element. Centred to keep the panel balanced.
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 168,
              child: PanelDirectionPad(
                offset: style.shadowOffset,
                magnitude: _shadowDirectionMagnitude(style.shadowOffset),
                size: 144,
                onPick: (off) {
                  EditorHaptics.toggle();
                  ctrl.setShadowOffset(off);
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
          _ShadowPrecisionAdvanced(style: style),
        ],
      ],
    );
  }

  // ─── Layout ──────────────────────────────────────────────────────
  //
  // Mobile-first redesign:
  //   * Alignment segmented control (always visible).
  //   * Two card-shaped blocks ("Line height", "Letter spacing")
  //     each with: label, current value, preset chips (always
  //     visible, 1-tap apply), and a chevron that expands a
  //     fine-tune slider INLINE inside that card only.
  //   * No `Advanced controls` wrapper, no nested arrows, no
  //     duplicated rows. Only one slider may be expanded at a
  //     time — opening one closes the other so the canvas never
  //     loses real estate to unused sliders.
  static Widget layoutBody(
    BuildContext context,
    WidgetRef ref,
    TextLayer layer,
  ) {
    return _LayoutPanel(layer: layer);
  }

  // ─── Resize ──────────────────────────────────────────────────────
  //
  // Two inline option tiles under a single `Behavior` section label
  // — same spacing rhythm as Background/Border/Shadow. Plain-language
  // labels: "Scale text" / "Reflow box", with corner-drag subtitles
  // so the user understands what the gesture will do.
  static Widget behaviorBody(
    BuildContext context,
    WidgetRef ref,
    TextLayer layer,
  ) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final mode = layer.resizeMode;
    final isScale = mode == TextResizeMode.scaleText;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        _PanelSectionLabel(context.l10n.behaviorLabel),
        _ResizeOptionTile(
          icon: Icons.zoom_out_map_rounded,
          title: context.l10n.scaleTextTitle,
          hint: context.l10n.cornerDragScalesTextHint,
          selected: isScale,
          onTap: () {
            if (mode == TextResizeMode.scaleText) return;
            ctrl.setResizeMode(TextResizeMode.scaleText);
          },
        ),
        const SizedBox(height: 2),
        _ResizeOptionTile(
          icon: Icons.crop_landscape_rounded,
          title: context.l10n.reflowBoxTitle,
          hint: context.l10n.cornerDragWrapWidthHint,
          selected: !isScale,
          onTap: () {
            if (mode == TextResizeMode.resizeBox) return;
            ctrl.setResizeMode(TextResizeMode.resizeBox);
          },
        ),
      ],
    );
  }
}

/// Small section label used by panels that group multiple
/// affordances (Background → Shape / Color / …). Same visual weight
/// as the old `_AdvancedGroupHeader` so the eye treats them as
/// peer-level dividers, not nested headers.
class _PanelSectionLabel extends StatelessWidget {
  const _PanelSectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 4, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Curated 8-swatch palette shared by Color / Background / Border /
/// Shadow sub-tools. Hand-picked so a normal user lands on a
/// visually-pleasing choice in 1 tap.
const List<Color> _curatedSwatches = [
  Color(0xFF000000), // Black
  Color(0xFFFFFFFF), // White
  Color(0xFFEF5350), // Red
  Color(0xFFFFB300), // Amber
  Color(0xFF66BB6A), // Green
  Color(0xFF42A5F5), // Blue
  Color(0xFFAB47BC), // Purple
  Color(0xFF8D6E63), // Brown
];

