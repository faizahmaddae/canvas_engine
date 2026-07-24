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

import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import '../../../settings/application/settings_controller.dart';
import '../../application/live_overlay_controller.dart';
import '../../application/selection_controller.dart';
import '../../engine/modules/text/text_layer.dart';
import '../../toolbar/domain/sibling_swipe_strategy.dart';
import '../../toolbar/domain/sub_tools/widget_sub_tool.dart';
import '../../presentation/widgets/editor_breakpoints.dart';
import '../../toolbar/domain/toolbar_slot.dart';
import '../../toolbar/presentation/slot_strip.dart';
import '../../toolbar/presentation/sub_tool_sheet.dart';
import '../application/text_tool_controller.dart';
import '../domain/font_catalog.dart';
import 'text_bodies.dart';
import '../../presentation/panels/text/more_sheet.dart' show showTextMoreSheet;

/// Bottom dock for text mode — Canva-style.
///
/// The dock is one non-scrolling strip of six large icon+label
/// tiles. Each tile opens an in-dock compact panel so the canvas
/// stays visible while the user edits.
///
/// Tiles (left → right):
///   * Font — opens the typeface picker.
///   * Size — opens a slider sheet with presets.
///   * Color — opens the colour picker (live preview on the layer).
///   * Style — one-tap visual style presets PLUS the effect
///     sections (خط دور / سایه / زمینه). The old standalone
///     Background / Border / Shadow tiles duplicated these chips
///     and forced the bar to scroll — consolidated 2026-07.
///   * Align — alignment, line height, letter spacing.
///   * More — structural text actions (edit, B/I/U, reorder, lock,
///     resize behaviour, text direction, delete).
///
/// Bold / Italic / Underline live in the More sheet and inside the
/// Style body that the input-flow sheet renders, not on the bottom
/// dock — they're toggle actions, not category sheets.
class TextModeToolbar extends ConsumerWidget {
  const TextModeToolbar({super.key});

  // ─── Tool registry ─────────────────────────────────────────────
  //
  // Six tiles, no scroll: Font / Size / Color / Style / Align /
  // More. Decoration (background / border / shadow) is reached via
  // the Style panel's effect chips; resize behaviour via More →
  // resize-behavior — no duplicate paths, no hidden tier-2 swipe.
  //
  // Bold / Italic / Underline are deliberately NOT a tile here —
  // they're toggle actions (not category sheets) and live in the
  // "More" sheet.
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
    // 'background' / 'border' / 'shadow' / 'behavior' specs removed
    // in the bar consolidation. A stale persisted
    // TextSession.openSheet with one of those ids resolves to no
    // spec and renders nothing — safe.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = _selectedTextLayer(ref);
    final hasSelectedText = selected != null;
    final session = ref.watch(textToolControllerProvider);

    final style = selected?.style ?? session.defaultStyle;
    final fontEntry = style.fontFamily == null
        ? null
        : kFontCatalog
              .where((e) => e.family == style.fontFamily)
              .cast<FontEntry?>()
              .firstWhere((_) => true, orElse: () => null);

    final rightHanded = ref.watch(
      appSettingsProvider.select((s) => s.rightHandedToolbar),
    );

    // Registry → shared slot model. The [_tools] order is the single
    // source for both the rendered strip and the sheet sibling-swipe
    // walk ([toolIds]), so the two cannot drift.
    final slots = <ToolbarSlot>[
      for (final spec in _tools)
        ToolbarSlot(
          id: spec.id,
          icon: spec.icon,
          label: _localizedToolLabel(context.l10n, spec),
          valueLabel: spec.id == 'font'
              ? () => fontEntry?.labelFor(
                  Localizations.localeOf(context).languageCode,
                )
              : null,
          fontFamily: spec.id == 'font' ? () => fontEntry?.family : null,
          swatchColor: spec.id == 'color' ? () => style.color : null,
          enabledBuilder: () => hasSelectedText,
          onTap: () {
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
            ref.read(textToolControllerProvider.notifier).toggleSheet(spec.id);
          },
          // Long-press peek removed from tiles — too easy to
          // trigger an undo by resting a thumb on the strip.
          // Peek is now opt-in via the Undo chip in the sheet
          // header (DockSheetChrome.onUndo).
        ),
    ];

    return SizedBox(
      height: EditorBreakpoints.stripHeight(context),
      child: SlotStrip(
        slots: slots,
        // SlotStrip auto-scrolls the active tile into view on
        // activeId changes (tile tap or sheet sibling-swipe) —
        // replaces the strip-owned controller + _ensureVisible
        // plumbing this widget used to carry.
        activeId: session.openSheet,
        // Bare-tile geometry: no per-tile gap and the historical
        // 10dp strip padding, so the migrated bar is byte-identical
        // to the old DockToolStrip rendering (Gate A).
        tileGap: 0,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        centerWhenFits: true,
        // Handedness affects alignment only — never tile order.
        // Resolved PHYSICALLY (right thumb = physical right, in
        // both text directions) by the shared helper.
        fitAlignment: SlotStrip.handedFitAlignment(
          context,
          rightHanded: rightHanded,
        ),
      ),
    );
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
    // No header value chips: the last holdout (Size px) moved into
    // the panel body as the tappable exact-size chip, so the header
    // is title + ✕ only.
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

String _localizedToolLabel(AppLocalizations l10n, _ToolSpec spec) {
  return switch (spec.id) {
    'font' => l10n.fontTool,
    'styles' => l10n.stylesTool,
    'color' => l10n.colorLabel,
    'size' => l10n.sizeTool,
    'layout' => l10n.alignAction,
    'more' => l10n.moreActionsSemantics,
    // Unreachable for the current registry (every id above has a
    // case) — the id itself is a more useful signal than a stale
    // hardcoded word if a future spec is added without its l10n case.
    _ => spec.id,
  };
}
