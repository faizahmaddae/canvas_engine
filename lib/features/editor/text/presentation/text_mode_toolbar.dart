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

part 'text_layout_panel.dart';
part 'text_panel_primitives.dart';
part 'text_resize_tiles.dart';
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

String _localizedFontCategoryLabel(
  AppLocalizations l10n,
  FontScript script,
  FontCategory category,
) {
  return switch (category) {
    FontCategory.sans =>
      script == FontScript.arabic
          ? l10n.fontCategoryModern
          : l10n.fontCategorySans,
    FontCategory.display => l10n.fontCategoryDisplay,
    FontCategory.script => l10n.fontCategoryScript,
    FontCategory.mono => l10n.fontCategoryMono,
    FontCategory.traditional => l10n.fontCategoryTraditional,
    FontCategory.nastaliq => l10n.fontCategoryNastaliq,
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

  /// Broad safety clamp for direct font-size mutation (stepper +
  /// exact slider). Intentionally far wider than the named-preset
  /// range so A+ can climb past XXL and A- can shrink below S.
  static const double _absoluteMinFontSize = 4;
  static const double _absoluteMaxFontSize = 2000;

  /// Computes the S/M/L/XL/XXL chip values for [doc] and [content].
  /// Combines a canvas factor (shorter side of the doc) with a
  /// length factor (longer text → smaller chips) so the preset that
  /// reads as "XL" stays visually balanced against both canvas and
  /// content. Output is clamped to [8, 600] px so chips remain
  /// usable on any canvas without overflowing the slider/stepper
  /// range.
  static List<({String label, double value})> _canvasAwareSizePresets(
    EditorDocument doc,
    String content,
  ) {
    final base = math.min(doc.width, doc.height);
    final lengthFactor = _lengthFactor(content);
    double p(double f) =>
        (base * f * lengthFactor).clamp(8.0, 600.0).toDouble();
    return [
      (label: 'S', value: p(0.06)),
      (label: 'M', value: p(0.10)),
      (label: 'L', value: p(0.16)),
      (label: 'XL', value: p(0.24)),
      (label: 'XXL', value: p(0.34)),
    ];
  }

  /// Length-aware shrink factor: short labels keep full-size
  /// presets, sentence-length text is dialed back to 80 %, and
  /// paragraph-length text drops to 60 % so XXL never pushes a
  /// long block past the canvas edges. Whitespace is intentionally
  /// included — leading/trailing spaces visually consume room too.
  static double _lengthFactor(String content) {
    final n = content.length;
    if (n <= 10) return 1.0;
    if (n <= 25) return 0.8;
    return 0.6;
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

/// Label style shared by every migrated flat-row slider in the
/// Background/Border/Shadow precision disclosures — larger and
/// bolder than [EditorSliderRow]'s shape/image default, so the
/// text-panel row keeps its existing look after unifying onto the
/// shared primitive.
TextStyle? _flatSliderLabelStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.bodyMedium?.copyWith(
    color: theme.colorScheme.onSurface,
    fontWeight: FontWeight.w600,
    fontSize: 13,
  );
}

/// Readout style shared by the same rows — tabular figures keep the
/// digits from jittering width while dragging.
TextStyle? _flatSliderReadoutStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.labelMedium?.copyWith(
    color: theme.colorScheme.onSurfaceVariant,
    fontWeight: FontWeight.w600,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// "Adjust precisely" disclosure for the Background panel. Same
/// flat header treatment as `_SizePrecisionAdvanced` and the
/// Layout cards: whole row is tappable, single chevron, no nested
/// arrows. Hosts four [EditorSliderRow]s when expanded.
class _BackgroundPrecisionAdvanced extends ConsumerWidget {
  const _BackgroundPrecisionAdvanced({required this.style});
  final TextStyleSpec style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final bg = style.backgroundColor;
    final labelStyle = _flatSliderLabelStyle(context);
    final readoutStyle = _flatSliderReadoutStyle(context);
    return PrecisionDisclosure(
      titleClosed: context.l10n.adjustPrecisely,
      titleOpen: context.l10n.hidePreciseControls,
      chevronSize: 18,
      children: [
        _PrecisionDivider(scheme: scheme),
        EditorSliderRow(
          label: context.l10n.roundnessLabel,
          labelWidth: 96,
          // backgroundRadius is a percent (0..1) of the box's
          // shorter side; UI drives 0..100 directly.
          value: (style.backgroundRadius * 100).clamp(0.0, 100.0),
          max: 100,
          format: (v) => '${v.toStringAsFixed(0)}%',
          onChanged: (v) => ctrl.setBackgroundRadius(v / 100),
          onDragStart: ctrl.beginStyleDrag,
          onDragEnd: ctrl.endStyleDrag,
          haptics: EditorSliderHaptics.startTickEnd,
          labelStyle: labelStyle,
          readoutStyle: readoutStyle,
        ),
        EditorSliderRow(
          label: context.l10n.verticalPaddingLabel,
          labelWidth: 96,
          value: style.backgroundPaddingY,
          max: 64,
          format: (v) => '${v.toStringAsFixed(0)}px',
          onChanged: ctrl.setBackgroundPaddingY,
          onDragStart: ctrl.beginStyleDrag,
          onDragEnd: ctrl.endStyleDrag,
          haptics: EditorSliderHaptics.startTickEnd,
          labelStyle: labelStyle,
          readoutStyle: readoutStyle,
        ),
        EditorSliderRow(
          label: context.l10n.horizontalPaddingLabel,
          labelWidth: 96,
          value: style.backgroundPaddingX,
          max: 64,
          format: (v) => '${v.toStringAsFixed(0)}px',
          onChanged: ctrl.setBackgroundPaddingX,
          onDragStart: ctrl.beginStyleDrag,
          onDragEnd: ctrl.endStyleDrag,
          haptics: EditorSliderHaptics.startTickEnd,
          labelStyle: labelStyle,
          readoutStyle: readoutStyle,
        ),
        if (bg != null)
          EditorSliderRow(
            label: context.l10n.opacityLabel,
            labelWidth: 96,
            value: bg.a * 100,
            max: 100,
            format: (v) => '${v.toStringAsFixed(0)}%',
            onChanged: (v) =>
                ctrl.setBackgroundColor(bg.withValues(alpha: v / 100)),
            onDragStart: ctrl.beginStyleDrag,
            onDragEnd: ctrl.endStyleDrag,
            haptics: EditorSliderHaptics.startTickEnd,
            labelStyle: labelStyle,
            readoutStyle: readoutStyle,
          ),
      ],
    );
  }
}

/// "Adjust precisely" disclosure for the Border panel. Same
/// flat header treatment as `_BackgroundPrecisionAdvanced`: whole
/// row tappable, single chevron, no nested arrows. Hosts thickness
/// and opacity sliders inline when expanded.
class _BorderPrecisionAdvanced extends ConsumerWidget {
  const _BorderPrecisionAdvanced({required this.style});
  final TextStyleSpec style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final outline = style.outlineColor;
    final labelStyle = _flatSliderLabelStyle(context);
    final readoutStyle = _flatSliderReadoutStyle(context);
    return PrecisionDisclosure(
      titleClosed: context.l10n.adjustPrecisely,
      titleOpen: context.l10n.hidePreciseControls,
      chevronSize: 18,
      children: [
        _PrecisionDivider(scheme: scheme),
        EditorSliderRow(
          label: context.l10n.thicknessLabel,
          labelWidth: 96,
          value: style.outlineWidth,
          max: 12,
          format: (v) => '${v.toStringAsFixed(0)}px',
          onChanged: ctrl.setOutlineWidth,
          onDragStart: ctrl.beginStyleDrag,
          onDragEnd: ctrl.endStyleDrag,
          haptics: EditorSliderHaptics.startTickEnd,
          labelStyle: labelStyle,
          readoutStyle: readoutStyle,
        ),
        if (outline != null)
          EditorSliderRow(
            label: context.l10n.opacityLabel,
            labelWidth: 96,
            value: outline.a * 100,
            max: 100,
            format: (v) => '${v.toStringAsFixed(0)}%',
            onChanged: (v) =>
                ctrl.setOutlineColor(outline.withValues(alpha: v / 100)),
            onDragStart: ctrl.beginStyleDrag,
            onDragEnd: ctrl.endStyleDrag,
            haptics: EditorSliderHaptics.startTickEnd,
            labelStyle: labelStyle,
            readoutStyle: readoutStyle,
          ),
      ],
    );
  }
}

/// "Adjust precisely" disclosure for the Shadow panel. Mirrors the
/// Background/Border treatment — single chevron, whole-row tappable,
/// no nested arrows. Hosts blur and opacity sliders inline.
class _ShadowPrecisionAdvanced extends ConsumerWidget {
  const _ShadowPrecisionAdvanced({required this.style});
  final TextStyleSpec style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final shadow = style.shadowColor;
    final labelStyle = _flatSliderLabelStyle(context);
    final readoutStyle = _flatSliderReadoutStyle(context);
    return PrecisionDisclosure(
      titleClosed: context.l10n.adjustPrecisely,
      titleOpen: context.l10n.hidePreciseControls,
      chevronSize: 18,
      children: [
        _PrecisionDivider(scheme: scheme),
        EditorSliderRow(
          label: context.l10n.blurLabel,
          labelWidth: 96,
          value: style.shadowBlur,
          max: 40,
          format: (v) => '${v.toStringAsFixed(0)}px',
          onChanged: ctrl.setShadowBlur,
          onDragStart: ctrl.beginStyleDrag,
          onDragEnd: ctrl.endStyleDrag,
          haptics: EditorSliderHaptics.startTickEnd,
          labelStyle: labelStyle,
          readoutStyle: readoutStyle,
        ),
        if (shadow != null)
          EditorSliderRow(
            label: context.l10n.opacityLabel,
            labelWidth: 96,
            value: shadow.a * 100,
            max: 100,
            format: (v) => '${v.toStringAsFixed(0)}%',
            onChanged: (v) =>
                ctrl.setShadowColor(shadow.withValues(alpha: v / 100)),
            onDragStart: ctrl.beginStyleDrag,
            onDragEnd: ctrl.endStyleDrag,
            haptics: EditorSliderHaptics.startTickEnd,
            labelStyle: labelStyle,
            readoutStyle: readoutStyle,
          ),
      ],
    );
  }
}

/// Background preset matcher (extracted from the Phase-A widget so
/// the new tile-row code path can re-use the same tolerance rules).
bool _bgMatches(TextStyleSpec style, _BgPreset p) {
  // Radius is a percent (0..1) now — "Pill" matches anything at
  // (or essentially at) full roundness.
  final pillish = p.id == 'pill' && style.backgroundRadius >= 0.99;
  final radiusEq = pillish || (style.backgroundRadius - p.radius).abs() < 0.02;
  return radiusEq &&
      (style.backgroundPaddingX - p.padX).abs() < 0.5 &&
      (style.backgroundPaddingY - p.padY).abs() < 0.5;
}

void _applyBgPreset(WidgetRef ref, _BgPreset p) {
  final ctrl = ref.read(textToolControllerProvider.notifier);
  ctrl.beginStyleDrag();
  final r = p.id == 'pill' ? 1.0 : p.radius;
  ctrl.setBackgroundRadius(r);
  ctrl.setBackgroundPaddingX(p.padX);
  ctrl.setBackgroundPaddingY(p.padY);
  ctrl.endStyleDrag();
}

bool _shadowMatches(TextStyleSpec style, _ShadowPreset p) {
  final c = style.shadowColor;
  if (c == null) return false;
  return (style.shadowBlur - p.blur).abs() < 0.5 &&
      (c.a - p.opacity).abs() < 0.02;
}

void _applyShadowPreset(
  WidgetRef ref,
  _ShadowPreset p, {
  required Color baseColor,
}) {
  final ctrl = ref.read(textToolControllerProvider.notifier);
  ctrl.beginStyleDrag();
  ctrl.setShadowBlur(p.blur);
  ctrl.setShadowColor(baseColor.withValues(alpha: p.opacity));
  ctrl.endStyleDrag();
}

const List<IconData> _shadowPresetIcons = [
  Icons.cloud_outlined, // Soft
  Icons.crop_din_rounded, // Hard
  Icons.flare_rounded, // Glow
  Icons.vertical_align_top_rounded, // Lift
];

// ─── In-dock panel host ─────────────────────────────────────────────
//
// Replaces the old `_showCompactSheet` modal. Renders inside the
// dock's `expanded` slot, so the canvas above is never overlayed —
// the canvas just gets a slightly shorter viewport.
//
// Layout choices:
//   * Capped at 35 % of screen height (≈ 30 % of the canvas, leaving
//     ≥ 70 % for editing) — matches the spec.
//   * Top header: icon + title + collapse-down arrow. The down
//     arrow collapses the panel without losing the active selection,
//     so the user can quickly free up canvas space and re-expand.
//   * Body scrolls internally when content exceeds the height cap;
//     otherwise the panel auto-sizes to its intrinsic height so a
//     2-row category isn't padded out to 35 %.

/// Compact category strip — doubles as the panel header.
///
/// UX choices:
///   * Inactive tabs are **icon-only** (32dp wide), so all 7 fit
///     comfortably on phone widths without horizontal scrolling.
///   * The **active** tab pill expands to show its label, giving
///     the user persistent context for what they're editing
///     (replaces the old separate panel header, freeing canvas).

/// Result of the font picker. We need a tri-state because the user
/// can either:
///   * pick a family (`family != null`)
///   * pick "system default" (`family == null`, but a real choice)
///   * dismiss the sheet without picking — we must not overwrite.
class _FontPickResult {
  const _FontPickResult._(this.family, this._dismissed);
  final String? family;
  final bool _dismissed;

  static const unchanged = _FontPickResult._(null, true);
  static const systemDefault = _FontPickResult._(null, false);

  bool get isDismissed => _dismissed;
}

/// Bottom-sheet picker that lists the families in [kFontCatalog]
/// for **one script at a time**. The sheet opens scoped to
/// [initialScript] (the tab the user was browsing in the inline
/// panel) so taps never produce a mixed-language list. Users can
/// still switch script inside the sheet via the header tab
/// switcher — the sheet is the same data source as the inline
/// panel, just at full height with category headers visible.
Future<_FontPickResult> _showFontPickerSheet(
  BuildContext context, {
  required String? current,
  required FontScript initialScript,
}) async {
  final result = await showModalBottomSheet<_FontPickResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.06),
    builder: (sheetCtx) {
      final scheme = Theme.of(sheetCtx).colorScheme;
      final media = MediaQuery.of(sheetCtx);
      final maxHeight = media.size.height * 0.7;
      return Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 520, maxHeight: maxHeight),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: _FontPickerSheet(
              current: current,
              initialScript: initialScript,
            ),
          ),
        ),
      );
    },
  );
  return result ?? _FontPickResult.unchanged;
}

/// Stateful body of the All-fonts sheet. Owns the in-sheet script
/// tab so the user can browse one language at a time without
/// dismissing — initialised to the tab the inline panel was on.
class _FontPickerSheet extends StatefulWidget {
  const _FontPickerSheet({required this.current, required this.initialScript});

  final String? current;
  final FontScript initialScript;

  @override
  State<_FontPickerSheet> createState() => _FontPickerSheetState();
}

class _FontPickerSheetState extends State<_FontPickerSheet> {
  late FontScript _script;

  @override
  void initState() {
    super.initState();
    _script = widget.initialScript;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Icon(
                Icons.font_download_outlined,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.allFontsTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // In-sheet script switcher — same widget the inline panel
        // uses, so users carry the same mental model.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: _ScriptTabSwitcher(
            value: _script,
            onChanged: (s) {
              if (s == _script) return;
              EditorHaptics.tap();
              setState(() => _script = s);
            },
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: _FontPickerList(current: widget.current, script: _script),
        ),
      ],
    );
  }
}

class _FontPickerList extends StatelessWidget {
  const _FontPickerList({required this.current, required this.script});
  final String? current;

  /// Restrict the list to families of this script. The sheet's
  /// header tab decides which one — the list itself never mixes.
  final FontScript script;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Sectioned list scoped to a single script:
    //   System default            (Latin tab only — no Persian system font)
    //     Sans                    (category header, small)
    //       Roboto, Lato, …
    //     Display
    //       Lobster, …
    //
    // Within each category bucket the order is whatever
    // `kFontCatalog` defines, which we keep alphabetical-ish there.
    final items = <_PickerItem>[
      // "System default" only makes sense for Latin — the platform
      // default is always a Latin face, so offering it under Farsi
      // would silently clear the Persian font.
      if (script == FontScript.latin) const _PickerItem.system(),
    ];
    final inScript = kFontCatalog.where((e) => e.script == script).toList();
    for (final category in FontCategory.values) {
      final inCat = inScript.where((e) => e.category == category).toList();
      if (inCat.isEmpty) continue;
      items.add(
        _PickerItem.categoryHeader(
          _localizedFontCategoryLabel(l10n, script, category),
        ),
      );
      items.addAll(inCat.map(_PickerItem.entry));
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        final scheme = Theme.of(ctx).colorScheme;
        if (item.kind == _PickerItemKind.categoryHeader) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text(
              item.headerLabel!.toUpperCase(),
              style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                fontSize: 11,
              ),
            ),
          );
        }
        final family = item.entry?.family;
        final label = item.entry?.label ?? ctx.l10n.systemDefaultFont;
        final selected = family == current;
        return Material(
          color: selected
              ? scheme.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Navigator.of(ctx).pop(
              item.entry == null
                  ? _FontPickResult.systemDefault
                  : _FontPickResult._(family, false),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: family,
                        fontSize: 18,
                        color: selected ? scheme.primary : scheme.onSurface,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_rounded, size: 18, color: scheme.primary),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _PickerItemKind { entry, categoryHeader }

class _PickerItem {
  const _PickerItem.system()
    : entry = null,
      headerLabel = null,
      kind = _PickerItemKind.entry;
  const _PickerItem.entry(FontEntry this.entry)
    : headerLabel = null,
      kind = _PickerItemKind.entry;
  const _PickerItem.categoryHeader(String this.headerLabel)
    : entry = null,
      kind = _PickerItemKind.categoryHeader;

  final FontEntry? entry;
  final String? headerLabel;
  final _PickerItemKind kind;
}

// ─────────────────────────────────────────────────────────────────────
// Compact sheet building blocks
// ─────────────────────────────────────────────────────────────────────
//
// All five category sheets are built from these primitives. The goal
// is uniformity and density: every row is ~44 px tall (vs ~64 px for
// a `ListTile`), so a 4-row sheet fits in ~190 px instead of ~320 px,
// leaving the canvas visible while the user adjusts values.

//
// Macro preset records used by the new tile-row sub-tools. Each
// preset is applied via the controller's [beginStyleDrag] /
// [endStyleDrag] coalescing window so the whole macro lands as a
// single undo entry.

/// Macro preset for the Background sub-tool. Each preset writes
/// radius + padding X + padding Y in one shot. Color and opacity
/// stay user-controlled.
///
/// [id] is a stable internal identity, never displayed — display
/// text is always looked up separately via l10n at the call site
/// (see `_backgroundPresets` consumers). Matching/apply logic keys
/// off [id], not a display string, so renaming a preset's shown
/// name can never silently break the "Pill" special-case below.
class _BgPreset {
  const _BgPreset({
    required this.id,
    required this.radius,
    required this.padX,
    required this.padY,
  });
  final String id;
  final double radius;
  final double padX;
  final double padY;
}

const List<_BgPreset> _backgroundPresets = [
  _BgPreset(id: 'none', radius: 0, padX: 0, padY: 0),
  _BgPreset(id: 'pill', radius: 1, padX: 24, padY: 8),
  _BgPreset(id: 'card', radius: 0.3, padX: 16, padY: 12),
  _BgPreset(id: 'tag', radius: 0.5, padX: 8, padY: 4),
];

/// Macro preset for the Shadow sub-tool. Writes blur + opacity in
/// one shot. Color and offset stay user-controlled (those are intent,
/// not aesthetic style).
///
/// [id] is a stable internal identity used only for matching/l10n
/// lookup (see [_shadowPresetLabel]) — never rendered directly.
class _ShadowPreset {
  const _ShadowPreset({
    required this.id,
    required this.blur,
    required this.opacity,
  });
  final String id;
  final double blur;
  final double opacity; // 0..1
}

const List<_ShadowPreset> _shadowPresets = [
  _ShadowPreset(id: 'soft', blur: 16, opacity: 0.30),
  _ShadowPreset(id: 'hard', blur: 2, opacity: 0.80),
  _ShadowPreset(id: 'glow', blur: 24, opacity: 0.60),
  _ShadowPreset(id: 'lift', blur: 8, opacity: 0.50),
];

String _shadowPresetLabel(AppLocalizations l10n, _ShadowPreset preset) {
  return switch (preset.id) {
    'soft' => l10n.softOption,
    'hard' => l10n.hardOption,
    'glow' => l10n.glowOption,
    'lift' => l10n.liftOption,
    _ => preset.id,
  };
}

// ─── Canva-style sub-tool helpers ───────────────────────────────────
//
// Shared widgets for the "presets-first, advanced-hidden" sub-tool
// redesign. The canvas above each sheet is the live preview, so these
// helpers focus on fast 1-tap choices instead of large preview tiles.

/// Single-select tile group for visual style presets (Background
/// shape, Shadow style, Border style, etc). Each tile renders
/// through the shared [PanelOptionTile] so selection / hover /
/// pressed states match the Adjust preset chip.
class _StyleTileRow extends StatelessWidget {
  const _StyleTileRow({required this.tiles});

  final List<_StyleTile> tiles;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: tiles.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final t = tiles[i];
          return PanelOptionTile(
            icon: t.icon,
            iconSize: t.iconSize,
            label: t.label,
            selected: t.selected,
            onTap: () {
              EditorHaptics.toggle();
              t.onTap();
            },
            width: 76,
          );
        },
      ),
    );
  }
}

/// Value spec consumed by [_StyleTileRow]. Keeps the call sites
/// declarative — actual chrome lives in [PanelOptionTile].
class _StyleTile {
  const _StyleTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.iconSize = 22,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Icon size override — e.g. border thickness presets render the
  /// same horizontal-rule glyph at 16/22/28 so the preview itself
  /// communicates Thin / Medium / Thick.
  final double iconSize;
}

/// Fixed magnitude for [PanelDirectionPad] direction taps on the
/// Shadow panel. Uses the current offset's own magnitude if the
/// user already dialled a distance, otherwise a sensible default
/// that reads as a real shadow on canvas.
double _shadowDirectionMagnitude(Offset offset) {
  final m = offset.distance;
  return m < 1.0 ? 6.0 : m.clamp(2.0, 24.0);
}

/// Body for the Text Size sub-tool. Owns no local state — the
/// "sticky preset" highlight lives on `TextSession` so it survives
/// rebuilds/remounts that can otherwise drop a `StatefulWidget`'s
/// state (e.g. when the selected layer flickers null between a
/// `setFontSize` write and the resulting auto-resize, the panel
/// briefly returns `SizedBox.shrink` and any local `_selectedPreset`
/// is lost). Keying the pin by layer id ensures switching to a
/// different text layer does not inherit the previous layer's
/// highlight.
class _SizeBody extends ConsumerWidget {
  const _SizeBody({required this.layer});
  final TextLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final style = layer.style;
    final doc = ref.watch(renderedDocumentProvider);
    final pin = ref.watch(
      textToolControllerProvider.select((s) => s.selectedSizePreset),
    );
    final presets = _TextBodies._canvasAwareSizePresets(doc, layer.content);
    final selectedLabel = (pin != null && pin.layerId == layer.id)
        ? pin.label
        : null;

    // Tolerance scales with current size so the nearest-fallback
    // selection feels right at 12 px and at 200 px alike. Only
    // applies when no sticky pin is active.
    final tolerance = math.max(1.0, style.fontSize * 0.03);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Match the Layout panel rhythm: no all-caps section
        // labels (the stepper IS the value, the chip row IS the
        // presets — both self-explanatory). The disclosure below
        // gives precise access without a header.
        const SizedBox(height: 6),
        _SizeStepperRow(
          value: style.fontSize,
          min: _TextBodies._absoluteMinFontSize,
          max: _TextBodies._absoluteMaxFontSize,
          onChange: ctrl.setFontSize,
        ),
        const SizedBox(height: 12),
        _WordChipRow(
          options: presets,
          current: style.fontSize,
          selectedLabel: selectedLabel,
          tolerance: tolerance,
          onPick: (value) {
            // Look the tapped value back up to recover its label;
            // identical instance equality holds because the chip
            // hands back the exact double from the same `presets`
            // list this build computed.
            final hit = presets.firstWhere(
              (p) => p.value == value,
              orElse: () => (label: '', value: value),
            );
            if (hit.label.isEmpty) {
              ctrl.setFontSize(value);
            } else {
              ctrl.setFontSizeFromPreset(
                size: value,
                presetLabel: hit.label,
                layerId: layer.id,
              );
            }
          },
        ),
        const SizedBox(height: 6),
        _SizePrecisionAdvanced(
          value: style.fontSize,
          min: _TextBodies._absoluteMinFontSize,
          max: _TextBodies._absoluteMaxFontSize,
          onChange: ctrl.setFontSize,
        ),
      ],
    );
  }
}

/// Flattened "Adjust precisely" disclosure used by the Size body:
/// one arrow, one tap to reveal value + px-presets + fine-tune
/// slider — no nested expand, no second arrow.
///
/// Style writes still route through the same controller setter
/// the dock uses (`setFontSize`), so undo coalescing, the
/// scale-aware translation in `_translateFontSizeForVisualScale`,
/// and the box auto-fit behaviour are all preserved verbatim.
class _SizePrecisionAdvanced extends ConsumerWidget {
  const _SizePrecisionAdvanced({
    required this.value,
    required this.min,
    required this.max,
    required this.onChange,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChange;

  static const List<double> _pxPresets = [12, 16, 24, 32, 48, 64, 96];

  String _format(double v) => '${v.toStringAsFixed(0)}px';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final clampedValue = value.clamp(min, max).toDouble();
    return PrecisionDisclosure(
      titleClosed: context.l10n.adjustPrecisely,
      titleOpen: context.l10n.hidePreciseControls,
      headerValue: _format(clampedValue),
      chevronSize: 18,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _PrecisionDivider(scheme: scheme),
              const SizedBox(height: 8),
              // px presets reuse the Layout chip so the two
              // panels share one visual vocabulary.
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in _pxPresets)
                    _LayoutPresetChip(
                      label: _format(p),
                      selected: (p - clampedValue).abs() < 0.001,
                      onTap: () => onChange(p.clamp(min, max).toDouble()),
                    ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                ),
                child: EditorSliderRow(
                  value: clampedValue,
                  min: min,
                  max: max,
                  showReadout: false,
                  format: _format,
                  onChanged: onChange,
                  onDragStart: ctrl.beginStyleDrag,
                  onDragEnd: ctrl.endStyleDrag,
                  haptics: EditorSliderHaptics.startTickEnd,
                  semanticLabel: context.l10n.sizeTool,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "A−" / "A+" double-button stepper used in the Size sub-tool. Each
/// tap nudges the live font size by a perceptual step so the user
/// gets visible change without having to drag a slider. Long-press
/// repeats. The buttons round-trip through the controller so undo
/// coalescing and box auto-fit behaviour stay identical to the
/// slider path.
class _SizeStepperRow extends StatelessWidget {
  const _SizeStepperRow({
    required this.value,
    required this.min,
    required this.max,
    required this.onChange,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChange;

  /// Perceptual step: ~10% of the current value (rounded), with a
  /// floor so very small sizes still nudge by at least 1 px.
  double get _step {
    final s = (value * 0.1).roundToDouble();
    return s < 1 ? 1 : s;
  }

  void _bump(int dir) {
    final next = (value + dir * _step).clamp(min, max).toDouble();
    if ((next - value).abs() < 0.01) return;
    EditorHaptics.tap();
    onChange(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget btn({required IconData icon, required VoidCallback onTap}) {
      return Material(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 56,
            height: 44,
            child: Center(child: Icon(icon, size: 22, color: scheme.primary)),
          ),
        ),
      );
    }

    return Row(
      children: [
        btn(icon: Icons.text_decrease_rounded, onTap: () => _bump(-1)),
        // Live value pill in the middle — same vocabulary as the
        // Layout panel's value pill so the two panels feel like
        // one family. Tabular figures so 12 → 24 → 120 doesn't
        // shift the centred layout.
        Expanded(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${value.round()} px',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
        btn(icon: Icons.text_increase_rounded, onTap: () => _bump(1)),
      ],
    );
  }
}

/// Word-preset chip row (e.g. Tight / Normal / Wide) — replaces a
/// numeric slider with a 1-tap human-readable choice. Each preset
/// commits via the caller-supplied write function.
///
/// Selection is **nearest-match**, not range/threshold based:
/// exactly one chip — the one whose value is closest to [current]
/// — is highlighted at all times. This guarantees a single
/// selected chip even when canvas-aware preset values collapse
/// onto the same clamped value, and it gives the user a clear
/// "this is the closest named size" anchor while they nudge with
/// the stepper or slider.
class _WordChipRow extends StatelessWidget {
  const _WordChipRow({
    required this.options,
    required this.current,
    required this.onPick,
    this.selectedLabel,
    this.tolerance,
  });

  final List<({String label, double value})> options;
  final double current;
  final ValueChanged<double> onPick;

  /// Explicit selection override. When non-null and matches one of
  /// the option labels, exactly that chip is highlighted regardless
  /// of [current]. Used for sticky preset selection (e.g. "user
  /// just tapped M") that must not flip to a different chip when
  /// canvas-aware clamping makes preset values numerically close.
  final String? selectedLabel;

  /// Optional max distance from [current] to the nearest preset for
  /// the nearest fallback to count as "selected". When null, the
  /// nearest chip is always highlighted (legacy line-height /
  /// letter-spacing behaviour).
  final double? tolerance;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedIndex();
    // Same chip vocabulary as the Layout panel (compact pill, no
    // hero shadow). Lets Size and Layout read as one family — and
    // the row sheds ~10dp of vertical weight vs the old
    // `PresetChip`.
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final o = options[i];
          return _LayoutPresetChip(
            label: o.label,
            selected: i == selectedIndex,
            onTap: () => onPick(o.value),
          );
        },
      ),
    );
  }

  /// Resolves which chip index (if any) is selected. Explicit
  /// [selectedLabel] wins; otherwise falls back to nearest-by-value
  /// — gated by [tolerance] when provided so manual edits that
  /// land far from any preset clear the selection entirely.
  int _selectedIndex() {
    if (selectedLabel != null) {
      for (var i = 0; i < options.length; i++) {
        if (options[i].label == selectedLabel) return i;
      }
    }
    if (options.isEmpty) return -1;
    var bestIndex = 0;
    var bestDelta = (current - options.first.value).abs();
    for (var i = 1; i < options.length; i++) {
      final delta = (current - options[i].value).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        bestIndex = i;
      }
    }
    if (tolerance != null && bestDelta > tolerance!) return -1;
    return bestIndex;
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

// ─────────────────────────────────────────────────────────────────────
// Inline color body + secondary More grid
// ─────────────────────────────────────────────────────────────────────

/// In-dock font body — Persian-first font picker.
///
/// Layout (top → bottom):
///   * Two-tab script switcher [فارسی] [English]. Auto-detects from
///     the layer's content but respects an explicit user override.
///   * Personality filter chips (Recommended / Sans / Display /
///     Script / Mono for Latin; Recommended / Modern / Traditional
///     / Nastaliq / Display for Farsi). Lets the user narrow by
///     personality before scanning specimens.
///   * Horizontal strip of *type-specimen* cards. Each card shows a
///     real preview word ("Hello" / "POSTER" / "سلام دنیا") rendered
///     IN that face at display size, with the family name as a
///     small caption underneath. Variable width — wide-feeling
///     display fonts get more room than narrow sans, mirroring how
///     designers pick on a real specimen sheet.
///   * Trailing "All fonts" pill at the end of the strip opens the
///     full sectioned picker for power users. No bordered footer
///     row — the strip itself is the whole panel.
///
/// Selected state is intentionally *quiet*: a thin primary
/// underline + bolder caption. No background fill, no shadow, no
/// preview-text colour swap — the preview must read as the font's
/// real personality, not as a state badge.
class _InlineFontBody extends StatefulWidget {
  const _InlineFontBody({
    required this.layerId,
    required this.current,
    required this.content,
    required this.onPick,
    required this.onBrowseAll,
  });

  final String layerId;
  final String? current;
  final String content;
  final ValueChanged<String?> onPick;

  /// Invoked when the user taps the trailing "All fonts" card.
  /// Receives the currently-active script tab so the full picker
  /// can open scoped to the same language the user was browsing.
  final ValueChanged<FontScript> onBrowseAll;

  @override
  State<_InlineFontBody> createState() => _InlineFontBodyState();
}

class _InlineFontBodyState extends State<_InlineFontBody> {
  late FontScript _tab;

  /// Active personality filter. `null` = "Recommended" (the curated
  /// short list — what most users want first). A non-null value
  /// narrows the strip to that single [FontCategory] within the
  /// active script.
  FontCategory? _filter;

  /// Set to true once the user explicitly taps a tab. While true,
  /// out-of-band content/font edits will NOT auto-flip the tab —
  /// respecting the user's choice. Reset on selection change
  /// (different `layerId`) and on panel re-open (new State).
  bool _userOverride = false;

  /// Family to highlight as selected. When the user hasn't explicitly
  /// chosen a font (`current == null`) we fall back to the script-aware
  /// auto default so the picker doesn't look empty: Vazir for Persian
  /// content, Roboto for Latin. This is purely visual — controller
  /// state is unchanged.
  String? get _effectiveFamily {
    if (widget.current != null) return widget.current;
    return defaultFontFamilyForContent(widget.content);
  }

  /// Auto-detected tab. Driven ONLY by the layer's text content so
  /// the tab can never disagree with what the user actually typed
  /// (e.g. English text in a Persian face must still open English).
  /// Empty / punctuation-only content falls through to Latin via
  /// `textIsArabicScript`.
  FontScript get _autoTab =>
      textIsArabicScript(widget.content) ? FontScript.arabic : FontScript.latin;

  @override
  void initState() {
    super.initState();
    // Panel just opened — always honor the content's script.
    _tab = _autoTab;
  }

  @override
  void didUpdateWidget(covariant _InlineFontBody old) {
    super.didUpdateWidget(old);
    if (old.layerId != widget.layerId) {
      // Selection moved to a different text layer: forget any
      // manual tab choice and re-sync to the new layer's script.
      _userOverride = false;
      final next = _autoTab;
      if (next != _tab) setState(() => _tab = next);
      return;
    }
    if (_userOverride) return;
    if (old.current != widget.current || old.content != widget.content) {
      // Same layer, no manual override yet — keep tab in sync with
      // content/font edits so the active tile stays visible.
      final next = _autoTab;
      if (next != _tab) setState(() => _tab = next);
    }
  }

  /// Filtered + ordered entries for the active tab. Applies the
  /// personality filter (or the curated "Recommended" short list
  /// when [_filter] is null). Vazir is always surfaced first on the
  /// Farsi tab so the default is one tap away.
  List<FontEntry> _entriesForCurrentTab() {
    final inScript = kFontCatalog.where((e) => e.script == _tab).toList();
    final List<FontEntry> base;
    if (_filter == null) {
      base = recommendedFontEntries(_tab);
    } else {
      base = inScript.where((e) => e.category == _filter).toList();
    }
    if (_tab == FontScript.arabic) {
      base.sort((a, b) {
        if (a.family == 'Vazir_Regular') return -1;
        if (b.family == 'Vazir_Regular') return 1;
        return 0;
      });
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entriesForCurrentTab();
    final isFarsi = _tab == FontScript.arabic;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row: secondary filters on the left, quiet script
        // toggle on the right. Putting them on one line lowers the
        // panel's overall visual weight (the language switch used
        // to be a full-width segmented control above the chips,
        // which competed with the font previews — the actual
        // hero — for attention) and groups all "filtering" intent
        // into a single 32dp band, leaving the entire strip below
        // for the typeface specimens themselves.
        SizedBox(
          height: 32,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Categories scroll inside the remaining space so
              // adding a new bucket never pushes the script toggle
              // off-screen.
              Expanded(
                child: _FontCategoryFilter(
                  script: _tab,
                  value: _filter,
                  onChanged: (next) {
                    if (next == _filter) return;
                    EditorHaptics.tap();
                    setState(() => _filter = next);
                  },
                ),
              ),
              const SizedBox(width: 8),
              _ScriptTabSwitcher(
                value: _tab,
                onChanged: (s) {
                  if (s == _tab) return;
                  EditorHaptics.tap();
                  setState(() {
                    _tab = s;
                    _userOverride = true;
                    // Reset filter when switching scripts —
                    // categories differ between scripts and
                    // "Recommended" is the safe landing for the
                    // new tab.
                    _filter = null;
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Type-specimen strip — the panel's hero. Variable-width
        // selectable cards.
        //
        // Full-bleed: the strip extends edge-to-edge across the
        // panel, ignoring the body's horizontal gutter, so it
        // reads as a real horizontal carousel rather than a
        // boxed-in list. We achieve this by negative-margining the
        // wrapper by exactly the body padding
        // ([kEditorSubToolBodyPadding].horizontal / 2 = 20dp on
        // each side) and then re-introducing that gutter as the
        // ListView's own scroll-padding. Net effect: the cards
        // can scroll under the panel edges, the first/last card
        // still aligns flush with the title and chips above, and
        // the panel's outer rounded corners clip the overflow
        // cleanly so nothing visually leaks past the chrome.
        SizedBox(
          height: 84,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            child: KeyedSubtree(
              key: ValueKey('${_tab.name}:${_filter?.name ?? "rec"}'),
              // OverflowBox lets the strip render wider than its
              // parent without `Container`'s negative-margin
              // assertion. The +40 width matches the body's 20dp
              // gutter on each side, so the strip spans the full
              // panel width edge-to-edge.
              child: LayoutBuilder(
                builder: (_, c) {
                  final w = c.maxWidth + 40;
                  return OverflowBox(
                    minWidth: 0,
                    maxWidth: w,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: w,
                      child: _FontCardStrip(
                        tab: _tab,
                        entries: entries,
                        current: _effectiveFamily,
                        onPick: widget.onPick,
                        onBrowseAll: () {
                          EditorHaptics.tap();
                          widget.onBrowseAll(_tab);
                        },
                        isFarsi: isFarsi,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Curated short list per script — what we put on the Recommended
/// tab. Top 4-5 workhorse families that cover the most common needs
/// (clean sans + one display + one script). Other entries remain
/// reachable via the category filter or "All fonts".
List<FontEntry> recommendedFontEntries(FontScript script) {
  const latin = <String>[
    'Roboto', // neutral workhorse sans
    'Hanken_Grotesk', // modern editorial sans
    'Lobster', // classic display script
    'Lato', // friendly humanist sans
    'Bungee_Shade', // statement display
    'Dancing_Script', // handwritten flourish
  ];
  const arabic = <String>[
    'Vazir_Regular', // modern Persian default
    'Shabnam', // clean Persian sans
    'Lalezar', // bold poster face
    'BNazanin', // traditional Naskh
    'B_Koodak_Bold_0', // friendly chunky
    'Samim_Bold', // strong sans
  ];
  final wanted = script == FontScript.latin ? latin : arabic;
  final byFamily = {
    for (final e in kFontCatalog.where((e) => e.script == script)) e.family: e,
  };
  return [
    for (final f in wanted)
      if (byFamily[f] != null) byFamily[f]!,
  ];
}

/// Sample preview text used inside a [_FontCard]. Picks a string
/// that flatters the family's personality:
///   * sans / mono → "Hello"     (legibility check)
///   * display     → "POSTER"    (showcases statement weight)
///   * script      → "Hello"     (handwriting flow)
///   * Arabic *    → "سلام دنیا"  (full word, both directions)
String fontSampleText(FontEntry entry) {
  if (entry.script == FontScript.arabic) return 'سلام دنیا';
  switch (entry.category) {
    case FontCategory.display:
      return 'POSTER';
    case FontCategory.mono:
      return 'Hello 12';
    case FontCategory.sans:
    case FontCategory.script:
    case FontCategory.traditional:
    case FontCategory.nastaliq:
      return 'Hello';
  }
}

/// Two-pill script toggle (فارسی / English) sitting at the top-right
/// of the Font panel. Intentionally *quiet*: a tinted track with a
/// soft pill highlight on the active option. The previous design
/// was a full-width 38dp segmented control with onPrimary fill +
/// shadow, which competed with the font specimens for attention —
/// users perceived it as a primary action when it's actually a
/// preferences-level filter. Now sized for the language word
/// itself plus a small touch margin so it reads as a secondary
/// inline switch.
class _ScriptTabSwitcher extends StatelessWidget {
  const _ScriptTabSwitcher({required this.value, required this.onChanged});

  final FontScript value;
  final ValueChanged<FontScript> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget pill({
      required String label,
      required bool selected,
      required VoidCallback onTap,
      String? fontFamily,
      TextDirection? textDirection,
    }) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Directionality(
            textDirection: textDirection ?? Directionality.of(context),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          pill(
            label: context.l10n.fontScriptPersian,
            selected: value == FontScript.arabic,
            onTap: () => onChanged(FontScript.arabic),
            textDirection: TextDirection.rtl,
            // The Persian label MUST render in a Persian face — the
            // platform default is Latin and shapes "فارسی" with broken
            // joining. Vazir is the canonical Persian default we
            // already ship and use as the auto-fallback.
            fontFamily: 'Vazir_Regular',
          ),
          const SizedBox(width: 2),
          pill(
            label: context.l10n.fontScriptEnglish,
            selected: value == FontScript.latin,
            onTap: () => onChanged(FontScript.latin),
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }
}

/// Personality filter chip row. "Recommended" + the categories
/// that exist for the active script. Drives the filter state above.
/// Uses a horizontal scroll so additional categories never overflow.
class _FontCategoryFilter extends StatelessWidget {
  const _FontCategoryFilter({
    required this.script,
    required this.value,
    required this.onChanged,
  });

  final FontScript script;
  final FontCategory? value;
  final ValueChanged<FontCategory?> onChanged;

  /// Categories surfaced as filter chips for [script], in display
  /// order. Built from the catalog so we never advertise an empty
  /// bucket (e.g. Latin doesn't ship Nastaliq).
  List<FontCategory> _categoriesFor(FontScript s) {
    final present = kFontCatalog
        .where((e) => e.script == s)
        .map((e) => e.category)
        .toSet();
    // Stable order: keep display priority within each script.
    const latinOrder = <FontCategory>[
      FontCategory.sans,
      FontCategory.display,
      FontCategory.script,
      FontCategory.mono,
    ];
    const arabicOrder = <FontCategory>[
      FontCategory.sans, // labelled "Modern" for Arabic
      FontCategory.traditional,
      FontCategory.nastaliq,
      FontCategory.display,
    ];
    final order = s == FontScript.latin ? latinOrder : arabicOrder;
    return [
      for (final c in order)
        if (present.contains(c)) c,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final cats = _categoriesFor(script);
    // Secondary-weight chips: no resting border (the chip row used
    // to wear an outlineVariant border on every entry, which made
    // categories visually equal to the font specimens below). Now
    // resting reads as plain muted text; only the active chip
    // earns a soft primary tint pill — it's clearly a filter on
    // top of the hero strip, not a separate primary action.
    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          height: 26,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          // `maxLines: 1` + `overflow: visible` defends long
          // category names ("Nastaliq", "Traditional") against any
          // ancestor that imposes a width constraint — the row
          // scrolls horizontally so labels are allowed to take
          // their full intrinsic width without ever truncating
          // mid-word ("Na…").
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
              letterSpacing: 0.1,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      itemCount: cats.length + 1,
      separatorBuilder: (_, _) => const SizedBox(width: 4),
      itemBuilder: (_, i) {
        if (i == 0) {
          return chip(
            label: l10n.recommendedFontsLabel,
            selected: value == null,
            onTap: () => onChanged(null),
          );
        }
        final cat = cats[i - 1];
        return chip(
          label: _localizedFontCategoryLabel(l10n, script, cat),
          selected: value == cat,
          onTap: () => onChanged(cat),
        );
      },
    );
  }
}

/// Horizontally-scrollable strip of [_FontCard] specimens.
/// Trailing entry is an "All fonts" pill that opens the full
/// sectioned picker — replaces the old bordered footer row.
class _FontCardStrip extends StatelessWidget {
  const _FontCardStrip({
    required this.tab,
    required this.entries,
    required this.current,
    required this.onPick,
    required this.onBrowseAll,
    required this.isFarsi,
  });

  final FontScript tab;
  final List<FontEntry> entries;
  final String? current;
  final ValueChanged<String?> onPick;
  final VoidCallback onBrowseAll;
  final bool isFarsi;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      // 20dp matches the body padding the parent wrapper cancels
      // out via negative margin — keeps the first/last card flush
      // with the chrome above while letting middle cards scroll
      // edge-to-edge across the panel.
      padding: const EdgeInsets.symmetric(horizontal: 20),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      itemCount: entries.length + 1, // + trailing "All fonts"
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        if (i == entries.length) {
          return _AllFontsCard(onTap: onBrowseAll);
        }
        final entry = entries[i];
        final entryIsFarsi = entry.script == FontScript.arabic;
        return _FontCard(
          label: entry.label,
          family: entry.family,
          sample: fontSampleText(entry),
          previewDirection: entryIsFarsi
              ? TextDirection.rtl
              : TextDirection.ltr,
          selected: entry.family == current,
          onTap: () => onPick(entry.family),
        );
      },
    );
  }
}

/// Type-specimen card. Variable-width (sized to its sample word)
/// so wide display faces and narrow sans faces both feel right.
///
/// Selected state uses the same soft-fill grammar as
/// [PanelOptionTile] (the panel-wide preset chip): a `primary @
/// 12 %` fill plus a 1dp `primary @ 50 %` border. The previous
/// underline-only treatment was easy to miss when the strip was
/// scrolled — users couldn't tell at a glance which font was
/// active. The full-tile fill makes the active font obvious from
/// any scroll position while still keeping the preview text in
/// `onSurface` so the typeface's real personality reads truthfully
/// (we deliberately do NOT tint the sample text — the colour
/// would lie about how the font looks on the canvas).
class _FontCard extends StatelessWidget {
  const _FontCard({
    required this.label,
    required this.family,
    required this.sample,
    required this.previewDirection,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? family;
  final String sample;
  final TextDirection previewDirection;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = selected
        ? scheme.primary.withValues(alpha: 0.12)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.35);
    final border = selected
        ? scheme.primary.withValues(alpha: 0.5)
        : Colors.transparent;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          EditorHaptics.tap();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minWidth: 78),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: Directionality(
                    textDirection: previewDirection,
                    child: Text(
                      sample,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        fontFamily: family,
                        fontFamilyFallback: const <String>[],
                        fontSize: 28,
                        height: 1.0,
                        // Preview must read as the font's real
                        // personality — never tint it for selection.
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Trailing card that opens the full sectioned picker. Same height
/// as the specimen cards so the strip baseline stays flat. Visual
/// language matches the resting [_FontCard]: same soft surface
/// fill, same radius — but with a primary-tinted icon + label so
/// it reads as an entry point, not a selectable font.
class _AllFontsCard extends StatelessWidget {
  const _AllFontsCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          EditorHaptics.tap();
          onTap();
        },
        child: Container(
          width: 84,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: Icon(
                    Icons.grid_view_rounded,
                    size: 22,
                    color: scheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.allFontsTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

