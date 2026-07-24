import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/haptics.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import '../../../settings/application/settings_controller.dart';
import '../../application/selection_controller.dart';
import '../../presentation/widgets/dock_tool_strip.dart';
import '../../presentation/widgets/dock_tool_tile.dart';
import '../../ui/editor_tier_gap.dart';
import '../application/paint_tool_controller.dart';
import '../domain/paint_tool_type.dart';
import 'bodies/paint_tool_body.dart';
import 'paint_mode_expansion.dart';
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
  static List<String> toolIdsFor(PaintToolType? tool) {
    final allowed = allowedPaintSlotsFor(tool);
    return paintToolSpecs
        .map((s) => s.id)
        .where(allowed.contains)
        .toList(growable: false);
  }

  static const double _tileExtent = 68;
}

class _PaintModeToolbarState extends ConsumerState<PaintModeToolbar> {
  final _scroll = ScrollController();
  String? _lastOpen;

  // Session-scoped guard so the discovery peek fires at most once
  // per app run.
  static bool _peekedThisSession = false;

  // Per-mount guard: auto-open the Tool picker exactly once when
  // paint mode is freshly entered with no active tool. After the
  // user closes the picker manually (or picks a tool), we never
  // re-open it in this session — re-entry to picking is a single
  // tap on the Tool tile.
  bool _autoOpenedPicker = false;

  @override
  void initState() {
    super.initState();
    if (!_peekedThisSession) {
      _peekedThisSession = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _runPeek());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoOpenPicker());
  }

  void _maybeAutoOpenPicker() {
    if (!mounted || _autoOpenedPicker) return;
    final session = ref.read(paintToolControllerProvider);
    if (session.activeTool != null || session.openSlot != null) {
      // Tool already armed (e.g. coming back from another mode) or
      // some other slot is open — respect that and stay quiet.
      _autoOpenedPicker = true;
      return;
    }
    _autoOpenedPicker = true;
    ref.read(paintToolControllerProvider.notifier).openSlot('tool');
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
    final tile = PaintModeToolbar._tileExtent;
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
    final session = ref.watch(paintToolControllerProvider);
    // Watch selection so the strip rebuilds when a paint layer is
    // selected/deselected (drives the blur/polygon safety guard
    // below).
    ref.watch(selectionControllerProvider);
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    final tool = session.activeTool ?? PaintToolType.freestyle;
    final fillEnabled = session.fillColor != null;
    // The strip always reflects the active tool's full capability
    // surface. Opening any slot (including 'tool') never hides the
    // others; the open slot is highlighted, siblings stay tappable
    // so users can switch panels in one tap.
    var allowed = allowedPaintSlotsFor(session.activeTool);
    // Safety guard: setBlurRadius / setPolygonSides update session
    // defaults only — they don't yet mirror to a selected paint
    // layer like setStrokeColor / setStrokeWidth do. Hide those
    // slots while a paint layer is selected so the controls can't
    // appear to do nothing. Layer-targeted edits flow through the
    // floating toolbar and the size sheet, both of which already
    // mirror correctly.
    if (ctrl.selectedPaintLayer() != null) {
      // Dash also belongs here — `PaintDashBody` calls `selectTool`
      // which only flips the session default; the selected line's
      // dash pattern doesn't change, but the tile label would still
      // update. Hide the slot so the UI never lies.
      allowed = allowed.difference(const {'blur', 'polygon', 'dash'});
    }

    final open = session.openSlot;
    if (open != _lastOpen) {
      _lastOpen = open;
      if (open != null) {
        final idx = paintToolSpecs.indexWhere((s) => s.id == open);
        if (idx >= 0) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _ensureVisible(idx),
          );
        }
      }
    }

    return SizedBox(
      height: _stripHeight(context),
      child: DockToolStrip(
        controller: _scroll,
        centerWhenFits: true,
        // Handedness affects alignment only — never tile order.
        fitAlignment:
            ref.watch(appSettingsProvider.select((s) => s.rightHandedToolbar))
            ? MainAxisAlignment.end
            : MainAxisAlignment.center,
        children: [
          for (final i in _toolOrder(context, ref))
            if (allowed.contains(paintToolSpecs[i].id)) ...[
              if (_isTierBoundary(ref, i)) const EditorTierGap(),
              DockToolTile(
                icon: paintToolSpecs[i].id == 'tool'
                    ? tool.icon
                    : paintToolSpecs[i].icon,
                label: paintToolSpecs[i].id == 'tool'
                    ? paintToolLabel(context.l10n, session.activeTool) ??
                          context.l10n.toolLabel
                    : paintSpecLabel(context.l10n, paintToolSpecs[i]),
                valueText: paintToolSpecs[i].id == 'tool'
                    ? null
                    : _paintValueText(
                        context.l10n,
                        paintToolSpecs[i],
                        session,
                        tool,
                      ),
                swatchColor: paintToolSpecs[i].id == 'color'
                    ? session.strokeColor
                    : paintToolSpecs[i].id == 'fill' && fillEnabled
                    ? session.fillColor
                    : null,
                active: session.openSlot == paintToolSpecs[i].id,
                compact: _isCompact(context),
                onTap: () {
                  EditorHaptics.tap();
                  // Toggling: re-tap of active tile dismisses the
                  // sheet; tapping a different tile switches.
                  ctrl.toggleSlot(paintToolSpecs[i].id);
                },
                // Long-press peek removed — too easy to undo by
                // accident. Peek lives on the Undo chip in the sheet
                // header.
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
  /// of left/right handed mode. Right-handed mode only shifts the
  /// row's alignment via [DockToolStrip.fitAlignment]; it never
  /// reverses tools.
  List<int> _toolOrder(BuildContext ctx, WidgetRef ref) {
    return List<int>.generate(paintToolSpecs.length, (i) => i);
  }

  bool _isTierBoundary(WidgetRef ref, int rawIndex) {
    // Boundary always sits before tool index 4 (after Tool / Color
    // / Size / Opacity ▸ Layout / Background / …). Stable across
    // left/right handed mode.
    return rawIndex == 4;
  }
}

// ─────────────────────────────────────────────────────────────────
// Internal: tile value-word resolver. Everything else lives in
// paint_tool_specs.dart / bodies/ / paint_mode_expansion.dart.
// ─────────────────────────────────────────────────────────────────

String? _paintValueText(
  AppLocalizations l10n,
  PaintSpec spec,
  PaintSession session,
  PaintToolType tool,
) {
  return switch (spec.id) {
    'size' => paintStrokeWord(l10n, session.strokeWidth),
    'fill' => session.fillColor == null ? l10n.offOption : l10n.onOption,
    'opacity' => paintOpacityWord(l10n, session.strokeColor.a),
    'blur' => paintBlurWord(l10n, session.blurRadius),
    'polygon' => l10n.sidesCount(session.polygonSides),
    'dash' => paintDashWordForTool(l10n, tool),
    _ => null,
  };
}
