import '../../../../core/utils/editor_value_format.dart';
import '../../../../core/utils/haptics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import '../../../settings/application/settings_controller.dart';
import '../../engine/modules/paint/paint_layer.dart';
import '../../presentation/widgets/editor_breakpoints.dart';
import '../../toolbar/domain/toolbar_slot.dart';
import '../../toolbar/presentation/slot_strip.dart';
import '../application/paint_tool_controller.dart';
import '../domain/paint_tool_type.dart';
import 'bodies/paint_tool_body.dart';
import 'paint_tool_specs.dart';

/// Bottom dock for paint mode.
///
/// Mirrors the text-mode shell so muscle memory transfers 1:1:
/// a flat horizontally-scrollable strip of [DockToolTile]s with
/// edge-fade gradients, auto-scrolling the active tile into view,
/// and horizontal-swipe sibling navigation between sheets.
///
/// All tools — primary and secondary — live in a single ordered
/// strip ([paintToolSpecs]), ranked by frequency of use. No "More"
/// grid: every tool is reachable in ≤ 1 tap.
class PaintModeToolbar extends ConsumerStatefulWidget {
  const PaintModeToolbar({super.key});

  @override
  ConsumerState<PaintModeToolbar> createState() => _PaintModeToolbarState();

  static PaintSpec? specById(String id) {
    for (final s in paintToolSpecs) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Ordered list of sibling tool ids — used by sheet swipe
  /// navigation to jump to the prev/next tool. Filtered by the
  /// currently-active tool so swipe-prev/next never lands on a
  /// slot the strip is hiding.
  /// The sibling-swipe order — the slots a left/right swipe on an open
  /// sheet can page through.
  ///
  /// Excludes `eraser`, which is on the strip but has no sheet: it is
  /// a mode toggle, not a sub-tool. Paging onto it would open nothing
  /// and silently swap the user's tool mid-swipe.
  static List<String> toolIdsFor({PaintToolType? tool, PaintKind? layerKind}) {
    return paintStripSlotIds(tool: tool, layerKind: layerKind)
        .where((id) {
          if (id == 'eraser') return false;
          // In restyle mode Tool is an instant "New stroke" escape, not
          // a sheet. Sibling swipes must stay among actual style panels.
          if (layerKind != null && id == 'tool') return false;
          return true;
        })
        .toList(growable: false);
  }
}

class _PaintModeToolbarState extends ConsumerState<PaintModeToolbar> {
  // External controller lets the shared strip auto-scroll the open
  // slot without owning another controller lifecycle.
  final _scroll = ScrollController();

  // Per-mount guard: auto-open the Tool picker exactly once when
  // paint mode is freshly entered with no active tool. After the
  // user closes the picker manually (or picks a tool), we never
  // re-open it in this session — re-entry to picking is a single
  // tap on the Tool tile.
  bool _autoOpenedPicker = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoOpenPicker());
  }

  void _maybeAutoOpenPicker() {
    if (!mounted || _autoOpenedPicker) return;
    final session = ref.read(paintToolControllerProvider);
    // A selected stroke means the strip mounted to RESTYLE, not to
    // draw (tb4 3/14) — opening the tool picker over it would both
    // hide the capsule and answer a question the user didn't ask.
    final restyling = ref.read(paintStyleViewProvider).layerKind != null;
    if (session.activeTool != null || session.openSlot != null || restyling) {
      // Tool already armed (e.g. coming back from another mode) or
      // some other slot is open — respect that and stay quiet.
      _autoOpenedPicker = true;
      return;
    }
    _autoOpenedPicker = true;
    ref.read(paintToolControllerProvider.notifier).openSlot('tool');
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(paintToolControllerProvider);
    // What the tiles DISPLAY: the selected layer's committed style
    // when one is selected, else the session defaults (tb4 3/14).
    final view = ref.watch(paintStyleViewProvider);
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    final tool = session.activeTool ?? PaintToolType.freestyle;
    final drawTool = ctrl.drawTool;
    final erasing = session.activeTool == PaintToolType.eraser;
    final fillEnabled = view.fillColor != null;
    // The strip always reflects the active tool's full capability
    // surface. Opening any slot (including 'tool') never hides the
    // others; the open slot is highlighted, siblings stay tappable
    // so users can switch panels in one tap.
    // An armed tool describes what the NEXT stroke can be; a
    // selected layer describes what THIS stroke can still become.
    // Arming wins, because selectTool() clears the selection anyway.
    //
    // (The old guard here subtracted blur/polygon/dash whenever a
    // layer was selected, because those setters only moved session
    // defaults. They mirror onto the layer now — tb4 3/14 — so the
    // matrix can be honest instead of defensive.)
    final layerKind = view.layerKind;
    final restyling = session.activeTool == null && layerKind != null;
    final visibleIds = paintStripSlotIds(
      tool: session.activeTool,
      layerKind: session.activeTool == null ? layerKind : null,
    );
    final allowed = visibleIds.toSet();

    final slots = <ToolbarSlot>[
      for (var i = 0; i < paintToolSpecs.length; i++)
        if (allowed.contains(paintToolSpecs[i].id))
          ToolbarSlot(
            id: paintToolSpecs[i].id,
            // The Tool tile mirrors the active DRAW tool's icon so the
            // strip reads as state. Deliberately not the eraser: that
            // has its own tile beside this one, and a tool tile
            // wearing an eraser next to an eraser tile said the same
            // thing twice while hiding what you would return to.
            icon: paintToolSpecs[i].id == 'tool'
                ? drawTool.icon
                : paintToolSpecs[i].icon,
            label: paintToolSpecs[i].id == 'tool'
                ? restyling
                      ? context.l10n.newShortLabel
                      : paintToolLabel(context.l10n, drawTool) ??
                            context.l10n.toolLabel
                : paintSpecLabel(context.l10n, paintToolSpecs[i]),
            semanticLabel: switch (paintToolSpecs[i].id) {
              'eraser' => context.l10n.eraseStrokesTool,
              'tool' when restyling => context.l10n.newStrokeTool,
              _ => null,
            },
            valueLabel: paintToolSpecs[i].id == 'tool'
                ? null
                : () => _paintValueText(
                    context.l10n,
                    EditorValueFormat.of(context),
                    paintToolSpecs[i],
                    view,
                    tool,
                  ),
            swatchColor: paintToolSpecs[i].id == 'color'
                ? () => view.strokeColor
                : paintToolSpecs[i].id == 'fill' && fillEnabled
                ? () => view.fillColor
                : null,
            tier:
                paintToolSpecs[i].id == 'tool' ||
                    paintToolSpecs[i].id == 'eraser'
                ? SlotTier.tier1
                : SlotTier.tier2,
            onTap: () {
              // The eraser is a MODE, not a panel: it flips straight
              // to erasing and back, with no sheet in between. Every
              // other tile opens its sub-tool.
              if (paintToolSpecs[i].id == 'eraser') {
                EditorHaptics.toggle();
                ctrl.toggleEraser();
                return;
              }
              // While erasing, the draw tile is READING as its tool
              // («Pen»), so tapping it should go there. Opening the
              // picker instead answered a question the user had not
              // asked. A second tap still opens it, from the pen.
              if (paintToolSpecs[i].id == 'tool' && erasing) {
                EditorHaptics.toggle();
                ctrl.toggleEraser();
                return;
              }
              // In restyle context this is an explicit escape hatch,
              // not a misleading tool picker that still edits the
              // selected stroke. Arm the last drawing tool and clear
              // selection in one tap; a second tap opens the picker.
              if (paintToolSpecs[i].id == 'tool' && restyling) {
                EditorHaptics.toggle();
                ctrl.selectTool(drawTool);
                return;
              }
              // Toggling: re-tap of active tile dismisses the
              // sheet; tapping a different tile switches.
              ctrl.toggleSlot(paintToolSpecs[i].id);
            },
            // Long-press peek removed — too easy to undo by
            // accident. Peek lives on the Undo chip in the sheet
            // header.
          ),
    ];

    return SizedBox(
      height: EditorBreakpoints.stripHeight(context),
      child: SlotStrip(
        slots: slots,
        // SlotStrip auto-scrolls the active tile into view on
        // openSlot changes — replaces the _ensureVisible plumbing
        // this widget used to carry.
        // The eraser tile lights from the armed TOOL; every other
        // tile lights from its open sheet. Without this the eraser
        // would look unselected the whole time it was erasing.
        activeId:
            session.openSlot ??
            (erasing
                ? 'eraser'
                : session.activeTool != null
                ? 'tool'
                : null),
        controller: _scroll,
        // Unified strip grammar (tb2 16/16): the default 70dp tile
        // extent + 12dp strip padding every other mode uses — the
        // Stage-1 bare-tile geometry override is retired, so all
        // five strips read identically.
        centerWhenFits: true,
        // Handedness affects alignment only — never tile order.
        // Resolved PHYSICALLY (right thumb = physical right, in
        // both text directions) by the shared helper.
        fitAlignment: SlotStrip.handedFitAlignment(
          context,
          rightHanded: ref.watch(
            appSettingsProvider.select((s) => s.rightHandedToolbar),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Internal: tile value-word resolver. Everything else lives in
// paint_tool_specs.dart / bodies/ / paint_mode_expansion.dart.
// ─────────────────────────────────────────────────────────────────

String? _paintValueText(
  AppLocalizations l10n,
  EditorValueFormat values,
  PaintSpec spec,
  PaintStyleView view,
  PaintToolType tool,
) {
  return switch (spec.id) {
    // Numbers, not adjectives. The value REPLACES the category label
    // on a tile, so «Medium» and «Strong» were the whole caption — a
    // tile that said «Strong» under a droplet, with nothing anywhere
    // saying it meant opacity. A number carries its own unit, and it
    // moves while you drag the slider.
    'size' => values.px(view.strokeWidth.round()),
    'fill' => view.fillColor == null ? l10n.offOption : l10n.onOption,
    'opacity' => values.percent((view.strokeColor.a * 100).round()),
    'blur' => paintBlurWord(l10n, view.blurRadius),
    'polygon' => l10n.sidesCount(view.sides),
    'dash' =>
      paintDashWordForKind(l10n, view.layerKind) ??
          paintDashWordForTool(l10n, tool),
    _ => null,
  };
}
