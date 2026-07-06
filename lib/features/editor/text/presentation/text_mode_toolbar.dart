/// Text-mode toolbar module, split into `part` files by sub-tool
/// (Phase 4 plan §5.1). The library root keeps every import, the
/// tool registry (`_ToolSpec`), the dock strip, and the sheet host —
/// everything else lives in a part file grouped by the sub-tool it
/// serves. Part files never carry their own `import`s; add new
/// imports here.
library;

export '../../presentation/panels/text/font_picker/cards.dart'
    show fontSampleText;
export '../../presentation/panels/text/font_picker/inline_browser.dart'
    show recommendedFontEntries;


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/haptics.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import '../../../settings/application/settings_controller.dart';
import '../../application/live_overlay_controller.dart';
import '../../application/selection_controller.dart';
import '../../engine/modules/text/text_layer.dart';
import '../../presentation/widgets/dock_tool_strip.dart';
import '../../presentation/widgets/dock_tool_tile.dart';
import '../../ui/editor_tier_gap.dart';
import '../../toolbar/domain/sibling_swipe_strategy.dart';
import '../../toolbar/domain/sub_tools/widget_sub_tool.dart';
import '../../toolbar/presentation/sub_tool_sheet.dart';
import '../application/text_tool_controller.dart';
import '../domain/font_catalog.dart';
import 'text_bodies.dart';
import '../../presentation/panels/text/more_sheet.dart' show showTextMoreSheet;


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
      bodyBuilder: TextBodies.fontBody,
    ),
    _ToolSpec(
      id: 'size',
      icon: Icons.format_size_rounded,
      // No short dock variant: the strip tile reads simply "Size".
      // The numeric value lives inside the sheet body where it can
      // be read precisely without crowding the dock with bucket
      // words ("Body" / "Display" etc.) that varied as the user
      // dragged.
      bodyBuilder: TextBodies.sizeBody,
    ),
    _ToolSpec(
      id: 'color',
      icon: Icons.palette_rounded,
      bodyBuilder: TextBodies.colorBody,
    ),
    _ToolSpec(
      // One-tap visual style presets. Sits next to Font because
      // both are typeface-level, look-defining choices and users
      // who reach for one often want the other in the same flow.
      id: 'styles',
      icon: Icons.auto_awesome_rounded,
      bodyBuilder: TextBodies.stylesBody,
    ),
    _ToolSpec(
      id: 'layout',
      icon: Icons.format_align_center_rounded,
      bodyBuilder: TextBodies.layoutBody,
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
      bodyBuilder: TextBodies.backgroundBody,
    ),
    _ToolSpec(
      id: 'border',
      icon: Icons.border_outer_rounded,
      bodyBuilder: TextBodies.borderBody,
    ),
    _ToolSpec(
      id: 'shadow',
      icon: Icons.blur_on_rounded,
      bodyBuilder: TextBodies.shadowBody,
    ),
    _ToolSpec(
      // Sheet id is kept as 'behavior' so any persisted session
      // state (TextSession.openSheet) keeps routing correctly. Only
      // the user-visible label changed: "Behavior" → "Resize".
      id: 'behavior',
      icon: Icons.aspect_ratio_rounded,
      bodyBuilder: TextBodies.behaviorBody,
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
                  ? fontEntry?.labelFor(
                      Localizations.localeOf(context).languageCode,
                    )
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

