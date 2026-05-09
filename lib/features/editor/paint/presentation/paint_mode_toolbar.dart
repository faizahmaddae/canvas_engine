import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/haptics.dart';
import '../../../color_picker/presentation/color_picker_sheet.dart';
import '../../../settings/application/settings_controller.dart';
import '../../application/selection_controller.dart';
import '../../presentation/widgets/dock_tool_strip.dart';
import '../../presentation/widgets/dock_tool_tile.dart';
import '../../presentation/widgets/inline_color_body.dart';
import '../../presentation/widgets/recent_colors_controller.dart';
import '../../toolbar/domain/sibling_swipe_strategy.dart';
import '../../toolbar/domain/sub_tool.dart';
import '../../toolbar/domain/sub_tools/slider_sub_tool.dart';
import '../../toolbar/domain/sub_tools/widget_sub_tool.dart';
import '../../toolbar/presentation/sub_tool_sheet.dart';
import '../../toolbar/presentation/widgets/preset_chip.dart';
import '../application/paint_tool_controller.dart';
import '../domain/paint_tool_type.dart';
import 'paint_size_body.dart';

// ─── Per-tool capability matrix ───────────────────────────────────
//
// Drives which sub-tool tiles the strip renders once a tool is
// armed. `tool` is always present so re-picking is one tap. Pure
// data, no enum changes — this lives next to the toolbar because
// it's a UI-layer decision, not a domain rule.
Set<String> _allowedSlotsFor(PaintToolType? tool) {
  if (tool == null) return const {'tool'};
  switch (tool) {
    case PaintToolType.freestyle:
      return const {'tool', 'color', 'size', 'opacity'};
    case PaintToolType.arrow:
      return const {'tool', 'color', 'size', 'opacity'};
    // Style is wired to the line-family tools (Solid=line,
    // Dashed=dashLine, Dotted=dashDotLine). Picking a style in
    // the sheet calls selectTool() — so the slot is meaningful
    // only on these three kinds. Shapes don't expose Style
    // because there is no per-layer dash on the engine side.
    case PaintToolType.line:
    case PaintToolType.dashLine:
    case PaintToolType.dashDotLine:
      return const {'tool', 'color', 'size', 'opacity', 'dash'};
    case PaintToolType.rectangle:
    case PaintToolType.circle:
    case PaintToolType.hexagon:
      return const {'tool', 'color', 'size', 'fill', 'opacity'};
    case PaintToolType.polygon:
      return const {
        'tool',
        'color',
        'size',
        'fill',
        'opacity',
        'polygon',
      };
    case PaintToolType.eraser:
      return const {'tool', 'size'};
    case PaintToolType.blur:
      return const {'tool', 'blur'};
  }
}

// ─── Human-friendly value labels ──────────────────────────────────
//
// Tile `valueText` shows a word, not a number. Numbers stay inside
// the sub-tool sheet for power users.
String _strokeWord(double w) {
  if (w <= 4) return 'Thin';
  if (w <= 12) return 'Medium';
  if (w <= 24) return 'Thick';
  return 'Heavy';
}

String _opacityWord(double alpha01) {
  final p = (alpha01.clamp(0.0, 1.0) * 100).round();
  if (p <= 35) return 'Light';
  if (p <= 75) return 'Normal';
  return 'Strong';
}

String _blurWord(double r) {
  if (r < 1) return 'None';
  if (r <= 16) return 'Soft';
  return 'Strong';
}

String _dashWordForTool(PaintToolType? tool) {
  switch (tool) {
    case PaintToolType.dashLine:
      return 'Dashed';
    case PaintToolType.dashDotLine:
      return 'Dotted';
    case PaintToolType.line:
      return 'Solid';
    default:
      return 'Solid';
  }
}

/// Bottom dock for paint mode.
///
/// Mirrors the text-mode shell so muscle memory transfers 1:1:
/// a flat horizontally-scrollable strip of [DockToolTile]s with
/// edge-fade gradients, auto-scrolling the active tile into view,
/// and horizontal-swipe sibling navigation between sheets.
///
/// All tools — primary and secondary — live in a single ordered
/// strip ([_tools]), ranked by frequency of use. No "More" grid:
/// every tool is reachable in ≤ 1 tap.
class PaintModeToolbar extends ConsumerStatefulWidget {
  const PaintModeToolbar({super.key});

  @override
  ConsumerState<PaintModeToolbar> createState() => _PaintModeToolbarState();

  // ─── Tool registry ─────────────────────────────────────────────
  //
  // Flat single-tier strip — Tool · Color · Size · Fill · Opacity ·
  // Blur · Sides · Dash. Ordered by expected frequency of use.
  static final List<_PaintSpec> _tools = <_PaintSpec>[
    _PaintSpec(
      id: 'tool',
      icon: Icons.gesture_rounded,
      label: 'Tool',
      dynamicLabel: (_, tool) => tool.label,
    ),
    _PaintSpec(
      id: 'color',
      icon: Icons.palette_rounded,
      label: 'Color',
    ),
    _PaintSpec(
      id: 'size',
      icon: Icons.line_weight_rounded,
      label: 'Size',
      dynamicLabel: (s, _) => _strokeWord(s.strokeWidth),
    ),
    _PaintSpec(
      id: 'fill',
      icon: Icons.format_color_fill_rounded,
      label: 'Fill',
      dynamicLabel: (s, _) => s.fillColor == null ? 'Off' : 'On',
    ),
    _PaintSpec(
      id: 'opacity',
      icon: Icons.opacity_rounded,
      label: 'Opacity',
      dynamicLabel: (s, _) => _opacityWord(s.strokeColor.a),
    ),
    _PaintSpec(
      id: 'blur',
      icon: Icons.blur_on_rounded,
      label: 'Blur',
      dynamicLabel: (s, _) => _blurWord(s.blurRadius),
    ),
    _PaintSpec(
      id: 'polygon',
      icon: Icons.pentagon_outlined,
      label: 'Sides',
      dynamicLabel: (s, _) => '${s.polygonSides} sides',
    ),
    _PaintSpec(
      id: 'dash',
      icon: Icons.linear_scale_rounded,
      label: 'Style',
      // Label tracks the live *tool kind* so the strip never
      // lies about what the next stroke will look like.
      dynamicLabel: (_, tool) => _dashWordForTool(tool),
    ),
  ];

  // ignore: library_private_types_in_public_api
  static _PaintSpec? specById(String id) {
    for (final s in _tools) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Ordered list of sibling tool ids — used by sheet swipe
  /// navigation to jump to the prev/next tool. Filtered by the
  /// currently-active tool so swipe-prev/next never lands on a
  /// slot the strip is hiding.
  static List<String> toolIdsFor(PaintToolType? tool) {
    final allowed = _allowedSlotsFor(tool);
    return _tools
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
    var allowed = _allowedSlotsFor(session.activeTool);
    // Safety guard: setBlurRadius / setPolygonSides update session
    // defaults only — they don't yet mirror to a selected paint
    // layer like setStrokeColor / setStrokeWidth do. Hide those
    // slots while a paint layer is selected so the controls can't
    // appear to do nothing. Layer-targeted edits flow through the
    // floating toolbar and the size sheet, both of which already
    // mirror correctly.
    if (ctrl.selectedPaintLayer() != null) {
      // Dash also belongs here — `_PaintDashBody` calls `selectTool`
      // which only flips the session default; the selected line's
      // dash pattern doesn't change, but the tile label would still
      // update. Hide the slot so the UI never lies.
      allowed = allowed.difference(const {'blur', 'polygon', 'dash'});
    }

    final open = session.openSlot;
    if (open != _lastOpen) {
      _lastOpen = open;
      if (open != null) {
        final idx =
            PaintModeToolbar._tools.indexWhere((s) => s.id == open);
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
        fitAlignment: ref.watch(
          appSettingsProvider.select((s) => s.rightHandedToolbar),
        )
            ? MainAxisAlignment.end
            : MainAxisAlignment.center,
        children: [
          for (final i in _toolOrder(context, ref))
            if (allowed.contains(PaintModeToolbar._tools[i].id)) ...[
              if (_isTierBoundary(ref, i)) const _PaintTierGap(),
              DockToolTile(
                icon: PaintModeToolbar._tools[i].id == 'tool'
                    ? tool.icon
                    : PaintModeToolbar._tools[i].icon,
                label: PaintModeToolbar._tools[i].id == 'tool'
                    ? (session.activeTool?.label ?? 'Tool')
                    : PaintModeToolbar._tools[i].label,
                valueText: PaintModeToolbar._tools[i].id == 'tool'
                    ? null
                    : PaintModeToolbar._tools[i]
                        .dynamicLabel
                        ?.call(session, tool),
                swatchColor: PaintModeToolbar._tools[i].id == 'color'
                    ? session.strokeColor
                    : PaintModeToolbar._tools[i].id == 'fill' && fillEnabled
                        ? session.fillColor
                        : null,
                active: session.openSlot == PaintModeToolbar._tools[i].id,
                compact: _isCompact(context),
                onTap: () {
                  EditorHaptics.tap();
                  // Toggling: re-tap of active tile dismisses the
                  // sheet; tapping a different tile switches.
                  ctrl.toggleSlot(PaintModeToolbar._tools[i].id);
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
    return m.size.shortestSide < 380 ||
        m.orientation == Orientation.landscape;
  }

  double _stripHeight(BuildContext ctx) => _isCompact(ctx) ? 64 : 80;

  /// Tile indices in display order. **Order is stable** regardless
  /// of left/right handed mode. Right-handed mode only shifts the
  /// row's alignment via [DockToolStrip.fitAlignment]; it never
  /// reverses tools.
  List<int> _toolOrder(BuildContext ctx, WidgetRef ref) {
    return List<int>.generate(
      PaintModeToolbar._tools.length,
      (i) => i,
    );
  }

  bool _isTierBoundary(WidgetRef ref, int rawIndex) {
    // Boundary always sits before tool index 4 (after Tool / Color
    // / Size / Opacity ▸ Layout / Background / …). Stable across
    // left/right handed mode.
    return rawIndex == 4;
  }
}

/// In-dock sheet panel for paint mode. Routes [PaintSession.openSlot]
/// → its body and renders it inside the dock's `expanded` slot with
/// [DockSheetChrome]. Mirrors `TextModeSheetPanel`.
class PaintModeInlineExpansion extends ConsumerWidget {
  const PaintModeInlineExpansion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(paintToolControllerProvider);
    final openId = session.openSlot;
    if (openId == null) return const SizedBox.shrink();
    final spec = PaintModeToolbar.specById(openId);
    if (spec == null) return const SizedBox.shrink();

    final ctrl = ref.read(paintToolControllerProvider.notifier);

    // Resolve the [SubTool] for this slot. Slider tools come from
    // the data registry; everything else is wrapped by
    // [WidgetSubTool] so it inherits the lifted SubToolSheet
    // chrome (Done pill, surface elevation, padding) without
    // rewriting the body widget.
    //
    // The 'tool' slot gets a friendlier header so it reads as a
    // temporary chooser, not a persistent settings panel.
    final bool isPicker = openId == 'tool';
    final SubTool subTool = _paintSliderSubTools[openId] ??
        WidgetSubTool(
          headerTitle: isPicker ? 'Choose a tool' : spec.label,
          headerIcon: isPicker
              ? Icons.brush_rounded
              : spec.icon,
          builder: (ctx, _) => _buildPaintBody(openId, session),
        );

    final ids = PaintModeToolbar.toolIdsFor(session.activeTool);
    // Single-list, no exclusions — [SiblingSwipeStrategy] handles
    // wrap-around and the single-slot "swipe is a no-op" case so
    // we don't have to special-case it here.
    final swipe = SiblingSwipeStrategy<String>(order: ids);
    final prevId = swipe.prev(openId);
    final nextId = swipe.next(openId);

    return SubToolSheet(
      subTool: subTool,
      onClose: ctrl.closeSlot,
      // Undo lives on the persistent floating action in the editor
      // chrome — single source of history navigation.
      onUndo: null,
      onPrev: prevId == null ? null : () => ctrl.toggleSlot(prevId),
      onNext: nextId == null ? null : () => ctrl.toggleSlot(nextId),
      // Header chip is the canonical neutral ✕ close — same
      // destination as the drag-handle dismiss. Mode-exit lives
      // on the top-right floating pill.
    );
  }

  /// Bespoke body resolver. Kept as a static helper so the routing
  /// in [build] stays a single expression. Each case is a one-liner
  /// constructing the existing body widget unchanged \u2014 only the
  /// surrounding chrome is unified.
  Widget _buildPaintBody(String openId, PaintSession session) {
    switch (openId) {
      case 'tool':
        return const _PaintToolBody();
      case 'color':
        return _PaintColorBody(current: session.strokeColor);
      case 'fill':
        return _PaintFillBody(
          enabled: session.fillColor != null,
          current: session.fillColor ?? session.strokeColor,
        );
      case 'polygon':
        return _PaintPolygonBody(value: session.polygonSides);
      case 'dash':
        return const _PaintDashBody();
      case 'size':
        return _PaintSizeBody(session: session);
      default:
        return const SizedBox.shrink();
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Internal: spec & bodies
// ─────────────────────────────────────────────────────────────────

class _PaintSpec {
  const _PaintSpec({
    required this.id,
    required this.icon,
    required this.label,
    this.dynamicLabel,
  });

  final String id;
  final IconData icon;
  final String label;
  final String Function(PaintSession session, PaintToolType tool)? dynamicLabel;
}

/// Compact chooser of every paint tool, organised into three
/// human-readable groups (Draw / Shapes / Effects). Picking a tool
/// calls `selectTool` which arms the canvas and immediately
/// collapses the sheet (controller clears `openSlot`).
///
/// Each tile renders a **live mini-preview** of the tool's stroke
/// in the user's current paint colour, so the picker reads as a
/// visual catalogue, not a row of generic icons.
class _PaintToolBody extends ConsumerWidget {
  const _PaintToolBody();

  // ─── Group definitions ──────────────────────────────────────
  // Order is the catalogue order. Friendly labels override the
  // technical enum labels so non-designers don't see jargon like
  // "Dash-dot" / "Polygon".
  static const List<_ToolGroup> _groups = <_ToolGroup>[
    _ToolGroup(
      title: 'Draw',
      tools: [
        (PaintToolType.freestyle, 'Pen'),
        (PaintToolType.line, 'Line'),
        (PaintToolType.arrow, 'Arrow'),
        (PaintToolType.dashLine, 'Dashed'),
        (PaintToolType.dashDotLine, 'Dash dot'),
        (PaintToolType.eraser, 'Eraser'),
      ],
    ),
    _ToolGroup(
      title: 'Shapes',
      tools: [
        (PaintToolType.rectangle, 'Square'),
        (PaintToolType.circle, 'Circle'),
        (PaintToolType.hexagon, 'Hexagon'),
        (PaintToolType.polygon, 'Polygon'),
      ],
    ),
    _ToolGroup(
      title: 'Effects',
      tools: [
        (PaintToolType.blur, 'Blur'),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(paintToolControllerProvider);
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 360 ? 5 : 4;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var g = 0; g < _groups.length; g++) ...[
          if (g > 0) const SizedBox(height: 14),
          _GroupHeader(title: _groups[g].title),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.92,
            padding: EdgeInsets.zero,
            children: [
              for (final (tool, label) in _groups[g].tools)
                _PaintToolGridTile(
                  tool: tool,
                  label: label,
                  paintColor: session.strokeColor,
                  selected: session.activeTool == tool,
                  onTap: tool.available
                      ? () {
                          EditorHaptics.tap();
                          ctrl.selectTool(tool);
                        }
                      : null,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ToolGroup {
  const _ToolGroup({required this.title, required this.tools});
  final String title;
  final List<(PaintToolType, String)> tools;
}

/// Section label above each tool group. Aligned with Text's
/// `_PanelSectionLabel` (11sp, w700, letterSpacing 0.8, muted) for
/// a single editor-wide section-heading style. Caller still owns
/// outer spacing (this builder leaves the parent's vertical gaps
/// untouched and only adds a hairline left inset to match the
/// tool-grid alignment).
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _PaintToolGridTile extends StatelessWidget {
  const _PaintToolGridTile({
    required this.tool,
    required this.label,
    required this.paintColor,
    required this.selected,
    required this.onTap,
  });

  final PaintToolType tool;
  final String label;
  final Color paintColor;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final enabled = onTap != null;

    final bgColor = selected
        ? scheme.primary.withValues(alpha: 0.14)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.40);
    final borderColor = selected
        ? scheme.primary.withValues(alpha: 0.85)
        : scheme.outlineVariant.withValues(alpha: 0.35);
    final labelColor = !enabled
        ? scheme.onSurface.withValues(alpha: 0.32)
        : selected
            ? scheme.primary
            : scheme.onSurface.withValues(alpha: 0.88);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor,
              width: selected ? 1.4 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.20),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 38,
                height: 26,
                child: CustomPaint(
                  painter: _ToolPreviewPainter(
                    tool: tool,
                    color: enabled
                        ? paintColor
                        : scheme.onSurface.withValues(alpha: 0.25),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  fontSize: 10.5,
                  color: labelColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders a 1:1 mini-preview of each paint tool's stroke / shape
/// using the user's current paint colour. Faster than memorising
/// abstract icons \u2014 the user sees what the tool will draw.
class _ToolPreviewPainter extends CustomPainter {
  _ToolPreviewPainter({required this.tool, required this.color});

  final PaintToolType tool;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final w = size.width;
    final h = size.height;
    final cy = h / 2;

    switch (tool) {
      case PaintToolType.freestyle:
        // Hand-drawn squiggle.
        final path = Path()
          ..moveTo(2, cy + 4)
          ..cubicTo(w * 0.25, cy - 8, w * 0.45, cy + 8, w * 0.6, cy)
          ..cubicTo(w * 0.75, cy - 8, w * 0.9, cy + 6, w - 2, cy - 2);
        canvas.drawPath(path, stroke);
        break;
      case PaintToolType.line:
        canvas.drawLine(Offset(2, cy), Offset(w - 2, cy), stroke);
        break;
      case PaintToolType.arrow:
        canvas.drawLine(Offset(2, cy), Offset(w - 6, cy), stroke);
        final head = Path()
          ..moveTo(w - 2, cy)
          ..lineTo(w - 9, cy - 4)
          ..moveTo(w - 2, cy)
          ..lineTo(w - 9, cy + 4);
        canvas.drawPath(head, stroke);
        break;
      case PaintToolType.dashLine:
        _dashes(canvas, stroke, w, cy, dashOn: 5, dashOff: 3);
        break;
      case PaintToolType.dashDotLine:
        _dashDot(canvas, stroke, w, cy);
        break;
      case PaintToolType.eraser:
        // Tilted rounded eraser block.
        final r = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(w / 2, cy), width: 18, height: 12),
          const Radius.circular(2.5),
        );
        canvas.save();
        canvas.translate(w / 2, cy);
        canvas.rotate(-0.35);
        canvas.translate(-w / 2, -cy);
        canvas.drawRRect(r, stroke);
        canvas.restore();
        break;
      case PaintToolType.rectangle:
        final r = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(w / 2, cy), width: 22, height: 14),
          const Radius.circular(2.5),
        );
        canvas.drawRRect(r, stroke);
        break;
      case PaintToolType.circle:
        canvas.drawCircle(Offset(w / 2, cy), 9, stroke);
        break;
      case PaintToolType.hexagon:
        canvas.drawPath(_polygonPath(w / 2, cy, 10, 6), stroke);
        break;
      case PaintToolType.polygon:
        canvas.drawPath(_polygonPath(w / 2, cy, 10, 5), stroke);
        break;
      case PaintToolType.blur:
        // Soft blur halo: stacked translucent circles.
        final halo = Paint()
          ..color = color.withValues(alpha: 0.22)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
        canvas.drawCircle(Offset(w / 2, cy), 9, halo);
        canvas.drawCircle(Offset(w / 2, cy), 6, stroke);
        break;
    }
  }

  void _dashes(Canvas c, Paint p, double w, double y,
      {required double dashOn, required double dashOff}) {
    var x = 2.0;
    while (x < w - 2) {
      final end = (x + dashOn).clamp(0.0, w - 2).toDouble();
      c.drawLine(Offset(x, y), Offset(end, y), p);
      x = end + dashOff;
    }
  }

  void _dashDot(Canvas c, Paint p, double w, double y) {
    var x = 2.0;
    var i = 0;
    while (x < w - 2) {
      if (i.isEven) {
        final end = (x + 5).clamp(0.0, w - 2).toDouble();
        c.drawLine(Offset(x, y), Offset(end, y), p);
        x = end + 3;
      } else {
        c.drawCircle(Offset(x + 1, y), 1.1, Paint()..color = p.color);
        x += 5;
      }
      i++;
    }
  }

  Path _polygonPath(double cx, double cy, double r, int sides) {
    final path = Path();
    for (var i = 0; i < sides; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i) / sides;
      final x = cx + r * 0.95 * math.cos(angle);
      final y = cy + r * 0.95 * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _ToolPreviewPainter old) =>
      old.tool != tool || old.color != color;
}

/// Stroke-colour body. 12-swatch palette + recents + "More" modal
/// fallback — identical shape to the text colour body so users
/// learn it once.
class _PaintColorBody extends ConsumerWidget {
  const _PaintColorBody({required this.current});

  final Color current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    return InlineColorBody(
      current: current,
      recents: ref.watch(recentColorsControllerProvider),
      palette: InlineColorBody.defaultPalette,
      onPick: (c) {
        EditorHaptics.tap();
        // Preserve the current opacity — picking a colour chip is
        // a hue choice, not an alpha reset. Alpha changes go
        // through the Opacity sub-tool or the custom picker.
        ctrl.setStrokeColor(c.withValues(alpha: current.a));
      },
      onCustom: () async {
        final original = current;
        final picked = await showColorPickerSheet(
          context,
          initial: original,
          recents: ref.read(recentColorsControllerProvider),
          onLiveChange: ctrl.setStrokeColor,
          title: 'Stroke color',
        );
        if (picked != null) {
          ctrl.setStrokeColor(picked);
          ctrl.rememberRecentColor(picked);
        } else {
          ctrl.setStrokeColor(original);
        }
      },
    );
  }
}


/// Stroke-width body. Preset chips above a "Fine tune" slider with
/// a dot preview that grows/shrinks live.
/// Phase 2 registry: paint slots whose body is a generic
/// preset+slider. New numeric tools should be added here, not as
/// new private body widgets.
final Map<String, SubTool> _paintSliderSubTools = <String, SubTool>{
  'blur': SliderSubTool(
    headerTitle: 'Blur',
    headerIcon: Icons.blur_on_rounded,
    min: 0,
    max: 64,
    // Preset-first: 3 human choices users actually pick. Slider
    // covers everything in between for power users.
    presets: const [0, 10, 32],
    presetLabels: const ['None', 'Soft', 'Strong'],
    readValue: (ref) =>
        ref.watch(paintToolControllerProvider).blurRadius,
    writeValue: (ref, v) =>
        ref.read(paintToolControllerProvider.notifier).setBlurRadius(v),
    format: (v) => '${v.round()}',
  ),
  // Opacity drives the alpha channel of the active stroke colour.
  // Re-uses the colour-picker pathway ([setStrokeColor]) so undo,
  // recents, and layer-mirroring all keep working unchanged — the
  // slider is a faster surface for the same setter the picker calls.
  'opacity': SliderSubTool(
    headerTitle: 'Opacity',
    headerIcon: Icons.opacity_rounded,
    min: 0,
    max: 100,
    // Three plain-language steps cover ≥95% of intents.
    presets: const [25, 60, 100],
    presetLabels: const ['Light', 'Normal', 'Strong'],
    readValue: (ref) {
      final c = ref.watch(paintToolControllerProvider).strokeColor;
      return (c.a * 100).clamp(0.0, 100.0);
    },
    writeValue: (ref, v) {
      final session = ref.read(paintToolControllerProvider);
      final next = session.strokeColor
          .withValues(alpha: (v / 100).clamp(0.0, 1.0));
      ref.read(paintToolControllerProvider.notifier).setStrokeColor(next);
    },
    format: (v) => '${v.round()}%',
    leadingBuilder: (context, value) {
      // Mini swatch preview at the live opacity — instant proof
      // of what the stroke will look like before release.
      final session =
          ProviderScope.containerOf(context).read(paintToolControllerProvider);
      final scheme = Theme.of(context).colorScheme;
      final c = session.strokeColor
          .withValues(alpha: (value / 100).clamp(0.0, 1.0));
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
      );
    },
  ),
};

/// Fill body — toggle row + colour swatch grid. Enables/disables
/// fill while preserving the last-used fill colour.
/// Paint Size body wrapper — thin Riverpod adapter around the
/// shared `PaintSizeBody`. Source values come from the session;
/// commits route through `setStrokeWidth` so undo coalescing
/// (`UpdatePaintStyleCommand.mergeWith`) and selected-layer
/// mirroring stay verbatim.
class _PaintSizeBody extends ConsumerWidget {
  const _PaintSizeBody({required this.session});

  final PaintSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    return PaintSizeBody(
      value: session.strokeWidth,
      color: session.strokeColor,
      dashPattern: session.dashPattern,
      onChange: ctrl.setStrokeWidth,
    );
  }
}

/// Fill body — three large choice cards (No fill / Same color /
/// Custom). The grid + toggle from the old design was removed;
/// this surface is preset-first like every other Paint sheet.
///
/// Behavior:
/// - **No fill**: `setFillColor(null)` (matches `setFillEnabled(false)`).
/// - **Same color**: `setFillColor(strokeColor)` so fill mirrors
///   the current stroke. Live; updates if stroke colour changes.
/// - **Custom**: opens the shared color picker. Selecting a colour
///   becomes the active fill; cancel restores the prior value.
class _PaintFillBody extends ConsumerWidget {
  const _PaintFillBody({required this.enabled, required this.current});

  final bool enabled;
  final Color current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(paintToolControllerProvider);
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    final stroke = session.strokeColor;
    final fill = session.fillColor;

    final isNone = fill == null;
    final isSameAsStroke =
        fill != null && fill.toARGB32() == stroke.toARGB32();
    final isCustom = fill != null && !isSameAsStroke;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _FillChoice(
                label: 'No fill',
                selected: isNone,
                preview: const _FillPreviewNone(),
                onTap: () {
                  EditorHaptics.snap();
                  ctrl.setFillColor(null);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _FillChoice(
                label: 'Same color',
                selected: isSameAsStroke,
                preview: _FillPreviewSolid(color: stroke),
                onTap: () {
                  EditorHaptics.snap();
                  ctrl.setFillColor(stroke);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _FillChoice(
                label: 'Custom',
                selected: isCustom,
                preview: isCustom
                    ? _FillPreviewSolid(color: fill)
                    : const _FillPreviewSweep(),
                onTap: () async {
                  EditorHaptics.tap();
                  final original = fill;
                  final picked = await showColorPickerSheet(
                    context,
                    initial: fill ?? stroke,
                    recents: ref.read(recentColorsControllerProvider),
                    onLiveChange: ctrl.setFillColor,
                    title: 'Fill color',
                  );
                  if (picked != null) {
                    ctrl.setFillColor(picked);
                    ctrl.rememberRecentColor(picked);
                  } else {
                    ctrl.setFillColor(original);
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Equally-weighted choice card for the Fill sheet. Same visual
/// grammar as `_DashChoice` so users learn the pattern once.
class _FillChoice extends StatelessWidget {
  const _FillChoice({
    required this.label,
    required this.selected,
    required this.preview,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Widget preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.primary : scheme.onSurface;
    // Flat: soft tint when selected, faint surface when resting.
    // No border, no elevation — same grammar as Text `_StyleTile`.
    final bg = selected
        ? scheme.primary.withValues(alpha: 0.12)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.35);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 32, height: 32, child: preview),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hollow circle with a slash — universal "none" affordance.
class _FillPreviewNone extends StatelessWidget {
  const _FillPreviewNone();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _NoneIconPainter(color: scheme.onSurfaceVariant),
    );
  }
}

class _NoneIconPainter extends CustomPainter {
  _NoneIconPainter({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final r = size.shortestSide / 2 - 2;
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(c, r, p);
    final d = r * 0.72;
    canvas.drawLine(
      Offset(c.dx - d * 0.7071, c.dy - d * 0.7071),
      Offset(c.dx + d * 0.7071, c.dy + d * 0.7071),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _NoneIconPainter old) => old.color != color;
}

class _FillPreviewSolid extends StatelessWidget {
  const _FillPreviewSolid({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
    );
  }
}

class _FillPreviewSweep extends StatelessWidget {
  const _FillPreviewSweep();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: const SweepGradient(
          colors: [
            Color(0xFFEF4444),
            Color(0xFFF59E0B),
            Color(0xFF22C55E),
            Color(0xFF06B6D4),
            Color(0xFF8B5CF6),
            Color(0xFFEC4899),
            Color(0xFFEF4444),
          ],
        ),
        shape: BoxShape.circle,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
    );
  }
}

class _PaintPolygonBody extends ConsumerWidget {
  const _PaintPolygonBody({required this.value});

  final int value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 6),
        _Label(text: 'Polygon sides'),
        // Horizontal scroll mirrors the chip strip used by every
        // other preset surface in the editor (paint Size/Blur,
        // text sliders) — single layout grammar across modes.
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: 8,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              const sides = <int>[3, 4, 5, 6, 7, 8, 10, 12];
              final n = sides[i];
              return PresetChip(
                label: '$n',
                selected: n == value,
                onTap: () => ctrl.setPolygonSides(n),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PaintDashBody extends ConsumerWidget {
  const _PaintDashBody();

  // Three line styles map 1:1 to engine kinds. Picking a chip
  // calls selectTool() so the next stroke is genuinely solid /
  // dashed / dotted — no phantom session state.
  static const List<(String, PaintToolType)> _presets =
      <(String, PaintToolType)>[
    ('Solid', PaintToolType.line),
    ('Dashed', PaintToolType.dashLine),
    ('Dotted', PaintToolType.dashDotLine),
  ];

  // Cosmetic patterns used purely by the chip preview painter so
  // the user can sight-pick the style. The engine itself ignores
  // these and renders dashing from the PaintKind.
  static const Map<PaintToolType, List<double>?> _previewPatterns =
      <PaintToolType, List<double>?>{
    PaintToolType.line: null,
    PaintToolType.dashLine: <double>[10, 6],
    PaintToolType.dashDotLine: <double>[2, 5],
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(paintToolControllerProvider);
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    final active = session.activeTool;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < _presets.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _DashChoice(
                  label: _presets[i].$1,
                  pattern: _previewPatterns[_presets[i].$2],
                  selected: active == _presets[i].$2,
                  onTap: () => ctrl.selectTool(_presets[i].$2),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Tall, equally-weighted line-style choice card. Renders the
/// line preview *above* its label so the visual pattern is the
/// primary affordance — the word is just confirmation.
class _DashChoice extends StatelessWidget {
  const _DashChoice({
    required this.label,
    required this.pattern,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final List<double>? pattern;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.primary : scheme.onSurface;
    // Flat: same grammar as `_FillChoice` and Text `_StyleTile` —
    // soft tint on select, faint surface at rest, no border or
    // shadow. Preview line + label remain the affordance.
    final bg = selected
        ? scheme.primary.withValues(alpha: 0.12)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.35);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          EditorHaptics.snap();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 18,
                child: CustomPaint(
                  size: const Size(double.infinity, 18),
                  painter: _DashPreviewPainter(pattern: pattern, color: fg),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints a single horizontal stroke with the given dash pattern,
/// matching the actual [Paint] semantics the canvas uses (round caps,
/// 3px stroke). Used by the line-style choice cards.
class _DashPreviewPainter extends CustomPainter {
  _DashPreviewPainter({required this.pattern, required this.color});

  final List<double>? pattern;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final y = size.height / 2;
    if (pattern == null) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    var x = 0.0;
    var i = 0;
    var draw = true;
    while (x < size.width) {
      final seg = pattern![i % pattern!.length];
      final end = (x + seg).clamp(0.0, size.width).toDouble();
      if (draw) {
        canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      }
      x = end;
      draw = !draw;
      i++;
    }
  }

  @override
  bool shouldRepaint(covariant _DashPreviewPainter old) =>
      old.color != color || !_listEq(old.pattern, pattern);

  static bool _listEq(List<double>? a, List<double>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Section label aligned with the Text-panel `_PanelSectionLabel`
/// grammar (uppercase 11sp, w700, letterSpacing 0.8, muted) so
/// Paint and Text panels share the same visual heading rhythm.
/// Built-in `EdgeInsets.fromLTRB(4,4,4,6)` padding mirrors Text;
/// existing call-sites that wrapped this in their own SizedBox
/// gap can drop those without breaking the layout.
class _Label extends StatelessWidget {
  const _Label({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Visual gap inserted into the paint-mode strip after the 4
/// primary tools (Tool · Color · Size · Fill) to separate them
/// from the secondary cluster (Opacity · Blur · Sides · Dash).
class _PaintTierGap extends StatelessWidget {
  const _PaintTierGap();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 13,
      alignment: Alignment.center,
      child: Container(
        width: 1,
        height: 28,
        decoration: BoxDecoration(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(0.5),
        ),
      ),
    );
  }
}
