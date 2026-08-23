import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_icons.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/editor_value_format.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import '../../../color_picker/presentation/color_picker_body.dart'
    show kColorPickerPalette;
import '../../engine/modules/paint/paint_layer.dart';
import '../../presentation/widgets/editor_breakpoints.dart';
import '../application/paint_tool_controller.dart';
import '../domain/paint_bench_slot.dart';
import '../domain/paint_tool_type.dart';

/// The paint bench — paint mode's persistent dock surface
/// (`docs/paint-redesign-2026-08.md` §2).
///
/// Two rows, always the same two questions answered:
///
///  * **style row** (top) — *with what ink*: quick swatches, the
///    current-colour dot (→ colour sheet) and contextual value pills
///    (size / fill / line style / sides / blur radius). Contents
///    follow the armed tool or, in the adjust posture, the bound
///    stroke's kind; the eraser and an unbound adjust posture show a
///    one-line hint instead of controls that would do nothing.
///  * **tool rack** (bottom) — *what the next touch does*: seven
///    fixed slots ([PaintBenchSlot]). Tap arms; tap-again on the
///    active slot opens its options sheet. Inking tools draw their
///    glyph in the live ink colour at a weight that follows the
///    stroke width, so the rack itself is the state display.
///
/// The bench replaces the generic property-tile strip
/// (`PaintModeToolbar`) — drawing is a live activity, not a form.
class PaintBench extends ConsumerWidget {
  const PaintBench({super.key});

  /// Dock strip height while paint mode owns it. Taller than the
  /// regular strip: the bench carries two rows. The dock's own
  /// mode-switch animation absorbs the reflow.
  static double dockHeight(BuildContext context) =>
      EditorBreakpoints.isCompact(context) ? 108 : 124;

  /// The options sheet a rack slot opens on tap-again, `null` for
  /// slots with no sheet (adjust is a posture, the eraser has no
  /// parameters yet).
  static String? sheetFor(PaintBenchSlot slot) => switch (slot) {
    PaintBenchSlot.pen || PaintBenchSlot.arrow => 'pen',
    PaintBenchSlot.line => 'line',
    PaintBenchSlot.shape => 'shape',
    PaintBenchSlot.blur => 'blur',
    PaintBenchSlot.adjust || PaintBenchSlot.eraser => null,
  };

  /// Quick-ink swatches: the drawing-biased head of the shared
  /// picker palette ([kColorPickerPalette]), so the bench and the
  /// full picker never disagree about what a "preset colour" is.
  static const List<Color> quickInks = <Color>[
    Color(0xFF000000), // ink
    Color(0xFFFFFFFF),
    Color(0xFFEF4444), // red
    Color(0xFFF59E0B), // amber
    Color(0xFF3B82F6), // blue
    Color(0xFF22C55E), // green
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    assert(
      quickInks.every(kColorPickerPalette.contains),
      'bench quick inks must be a subset of the shared picker palette',
    );
    final session = ref.watch(paintToolControllerProvider);
    final view = ref.watch(paintStyleViewProvider);
    final compact = EditorBreakpoints.isCompact(context);
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(12, compact ? 4 : 8, 12, 6),
      child: Column(
        key: const ValueKey('paint-bench'),
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: compact ? 38 : 42,
            child: _StyleRow(session: session, view: view),
          ),
          SizedBox(height: compact ? 2 : 6),
          Expanded(
            child: _ToolRack(session: session, view: view),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Style row
// ─────────────────────────────────────────────────────────────────

/// D-e (tb5 accessibility decision): editor chrome clamps its text
/// scale to 1.0–1.3 — the bench's fixed two-row envelope cannot grow
/// with the system setting, and unclamped 2×+ labels would overflow
/// every tile.
TextScaler _benchTextScaler(BuildContext context) => MediaQuery.textScalerOf(
  context,
).clamp(minScaleFactor: 1.0, maxScaleFactor: 1.3);

/// Which family of style controls the row shows right now: the armed
/// tool's while drawing, the bound stroke's kind in adjust posture.
PaintBenchSlot? _styleContext(PaintSession session, PaintStyleView view) {
  final tool = session.activeTool;
  if (tool != null) return benchSlotForTool(tool);
  final kind = view.layerKind;
  if (kind == null) return null;
  return switch (kind) {
    PaintKind.freestyle => PaintBenchSlot.pen,
    PaintKind.arrow => PaintBenchSlot.arrow,
    PaintKind.line ||
    PaintKind.dashLine ||
    PaintKind.dashDotLine => PaintBenchSlot.line,
    PaintKind.rectangle ||
    PaintKind.circle ||
    PaintKind.hexagon ||
    PaintKind.polygon => PaintBenchSlot.shape,
    PaintKind.blur => PaintBenchSlot.blur,
  };
}

class _StyleRow extends ConsumerWidget {
  const _StyleRow({required this.session, required this.view});

  final PaintSession session;
  final PaintStyleView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final tokens = AppTokens.of(context);
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    final context_ = _styleContext(session, view);

    // Hint states: controls that would do nothing are not shown
    // (contract §10.3 — no present-but-inert chrome). The hint says
    // what the canvas will respond to instead.
    if (session.activeTool == PaintToolType.eraser ||
        (context_ == null && session.activeTool == null)) {
      final hint = session.activeTool == PaintToolType.eraser
          ? l10n.paintEraserHint
          : l10n.paintTapStrokeHint;
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 6),
          child: Text(
            hint,
            key: const ValueKey('paint-style-hint'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: _benchTextScaler(context),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    final showInks = context_ != PaintBenchSlot.blur;
    final values = EditorValueFormat.of(context);

    // Fixed anchors (current-ink dot, value pills) never scroll away;
    // only the quick-swatch run flexes and scrolls on narrow phones.
    // The polygon sides control lives in the shape sheet the fill
    // pill opens — a second pill for it outgrew the row.
    final pills = <Widget>[
      if (showInks)
        _ValuePill(
          key: const ValueKey('paint-pill-size'),
          semanticLabel: l10n.strokeSizeSemantics,
          active: session.openSlot == 'pen',
          leading: _WidthDot(width: view.strokeWidth, color: view.strokeColor),
          label: values.px(view.strokeWidth.round()),
          onTap: () => ctrl.toggleSlot('pen'),
        ),
      if (context_ == PaintBenchSlot.line)
        _ValuePill(
          key: const ValueKey('paint-pill-line'),
          semanticLabel: l10n.styleLabel,
          active: session.openSlot == 'line',
          leading: SizedBox(
            width: 18,
            height: 12,
            child: CustomPaint(
              painter: _LineStylePainter(
                tool: session.activeTool != null
                    ? session.activeTool!
                    : _lineToolForKind(view.layerKind) ?? session.lastLineTool,
                color: tokens.textPrimary,
                strokeWidth: 2.2,
              ),
            ),
          ),
          label: null,
          onTap: () => ctrl.toggleSlot('line'),
        ),
      if (context_ == PaintBenchSlot.shape)
        _ValuePill(
          key: const ValueKey('paint-pill-fill'),
          semanticLabel: l10n.fillLabel,
          active: session.openSlot == 'shape',
          leading: _FillDot(color: view.fillColor, tokens: tokens),
          label: null,
          onTap: () => ctrl.toggleSlot('shape'),
        ),
      if (context_ == PaintBenchSlot.blur)
        _ValuePill(
          key: const ValueKey('paint-pill-blur'),
          semanticLabel: l10n.blurLabel,
          active: session.openSlot == 'blur',
          leading: Icon(AppIcons.blur, size: 16, color: tokens.textPrimary),
          label: '${l10n.blurLabel} ${values.digits(view.blurRadius.round())}',
          onTap: () => ctrl.toggleSlot('blur'),
        ),
    ];

    return Row(
      children: [
        if (showInks) ...[
          // Current ink + entry to the full picker. The dot always
          // shows the live colour, even one outside the quick row.
          _CurrentInkDot(
            color: view.strokeColor,
            onTap: () => ctrl.toggleSlot('color'),
            active: session.openSlot == 'color',
          ),
          const SizedBox(width: 4),
          _rowDivider(tokens),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsetsDirectional.only(start: 4, end: 4),
              itemCount: PaintBench.quickInks.length,
              separatorBuilder: (_, _) => const SizedBox(width: 2),
              itemBuilder: (_, i) {
                final ink = PaintBench.quickInks[i];
                return Center(
                  child: _InkSwatch(
                    ink: ink,
                    selected: view.strokeColor.toARGB32() == ink.toARGB32(),
                    onTap: () {
                      EditorHaptics.tap();
                      ctrl.setStrokeColor(ink);
                    },
                  ),
                );
              },
            ),
          ),
          _rowDivider(tokens),
          const SizedBox(width: 6),
        ] else
          const Spacer(),
        for (final pill in pills) ...[pill, const SizedBox(width: 6)],
      ],
    );
  }

  Widget _rowDivider(AppTokens tokens) => Container(
    width: 1,
    height: 20,
    color: tokens.border.withValues(alpha: 0.8),
  );
}

PaintToolType? _lineToolForKind(PaintKind? kind) => switch (kind) {
  PaintKind.line => PaintToolType.line,
  PaintKind.dashLine => PaintToolType.dashLine,
  PaintKind.dashDotLine => PaintToolType.dashDotLine,
  _ => null,
};

/// Live current-colour dot with a sweep ring — both the state display
/// for "the ink right now" and the door to the full colour sheet.
class _CurrentInkDot extends StatelessWidget {
  const _CurrentInkDot({
    required this.color,
    required this.onTap,
    required this.active,
  });

  final Color color;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      selected: active,
      label: context.l10n.strokeColorTitle,
      child: GestureDetector(
        key: const ValueKey('paint-ink-current'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          EditorHaptics.tap();
          onTap();
        },
        child: SizedBox(
          width: kMinHitTarget,
          height: kMinHitTarget,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              padding: const EdgeInsets.all(2.5),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
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
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(color: tokens.surface, width: 2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InkSwatch extends StatelessWidget {
  const _InkSwatch({
    required this.ink,
    required this.selected,
    required this.onTap,
  });

  final Color ink;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: context.l10n.strokeColorTitle,
      child: GestureDetector(
        key: ValueKey(
          'paint-ink-${ink.toARGB32().toRadixString(16).padLeft(8, '0')}',
        ),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: kMinHitTarget,
          child: Center(
            child: AnimatedContainer(
              duration: AppMotion.state,
              curve: AppMotion.curve,
              width: selected ? 28 : 24,
              height: selected ? 28 : 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ink,
                border: Border.all(
                  color: selected
                      ? tokens.accent
                      : tokens.border.withValues(alpha: 0.9),
                  width: selected ? 2 : 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small rounded value pill (size / fill / sides / blur). Reads as
/// state, taps into its sheet.
class _ValuePill extends StatelessWidget {
  const _ValuePill({
    super.key,
    required this.semanticLabel,
    required this.active,
    required this.leading,
    required this.label,
    required this.onTap,
  });

  final String semanticLabel;
  final bool active;
  final Widget? leading;
  final String? label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      selected: active,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          EditorHaptics.tap();
          onTap();
        },
        child: ExcludeSemantics(
          child: SizedBox(
            height: kMinHitTarget,
            child: Center(
              child: AnimatedContainer(
                duration: AppMotion.state,
                curve: AppMotion.curve,
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: active
                      ? tokens.accent.withValues(alpha: 0.14)
                      : tokens.textPrimary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: active
                        ? tokens.accent.withValues(alpha: 0.85)
                        : tokens.border.withValues(alpha: 0.8),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (leading != null) ...[
                      leading!,
                      if (label != null) const SizedBox(width: 6),
                    ],
                    if (label != null)
                      Text(
                        label!,
                        textScaler: _benchTextScaler(context),
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          color: active
                              ? tokens.accentText
                              : tokens.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The size pill's live dot: diameter follows the stroke width.
class _WidthDot extends StatelessWidget {
  const _WidthDot({required this.width, required this.color});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // 1..80 px mapped into a 4..16dp dot: legible at every value.
    final d = 4 + (width.clamp(1, 80) / 80) * 12;
    return SizedBox(
      width: 16,
      height: 16,
      child: Center(
        child: Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: tokens.border.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _FillDot extends StatelessWidget {
  const _FillDot({required this.color, required this.tokens});

  final Color? color;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    if (color == null) {
      // Hollow + slash: the universal "no fill".
      return SizedBox(
        width: 16,
        height: 16,
        child: CustomPaint(painter: _NoFillPainter(tokens.textSecondary)),
      );
    }
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: tokens.border.withValues(alpha: 0.7)),
      ),
    );
  }
}

class _NoFillPainter extends CustomPainter {
  _NoFillPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2 - 1;
    canvas.drawCircle(c, r, p);
    final d = r * 0.7071;
    canvas.drawLine(Offset(c.dx - d, c.dy - d), Offset(c.dx + d, c.dy + d), p);
  }

  @override
  bool shouldRepaint(covariant _NoFillPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────
// Tool rack
// ─────────────────────────────────────────────────────────────────

class _ToolRack extends ConsumerWidget {
  const _ToolRack({required this.session, required this.view});

  final PaintSession session;
  final PaintStyleView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    final active = benchSlotForTool(session.activeTool);
    return Row(
      children: [
        for (final slot in PaintBenchSlot.values) ...[
          if (slot != PaintBenchSlot.values.first) const SizedBox(width: 4),
          Expanded(
            child: _RackTile(
              slot: slot,
              session: session,
              view: view,
              active: slot == active,
              onTap: () {
                final sheet = PaintBench.sheetFor(slot);
                if (slot == active && sheet != null) {
                  // Tap-again: the active slot's options.
                  EditorHaptics.tap();
                  ctrl.toggleSlot(sheet);
                  return;
                }
                if (slot == active && slot != PaintBenchSlot.adjust) return;
                EditorHaptics.toggle();
                ctrl.armBenchSlot(slot);
              },
            ),
          ),
        ],
      ],
    );
  }
}

String _rackLabel(AppLocalizations l10n, PaintBenchSlot slot) => switch (slot) {
  PaintBenchSlot.pen => l10n.penTool,
  PaintBenchSlot.line => l10n.lineTool,
  PaintBenchSlot.arrow => l10n.arrowTool,
  PaintBenchSlot.shape => l10n.shapeTool,
  PaintBenchSlot.blur => l10n.blurLabel,
  PaintBenchSlot.adjust => l10n.adjustStrokesTool,
  PaintBenchSlot.eraser => l10n.eraserTool,
};

class _RackTile extends StatelessWidget {
  const _RackTile({
    required this.slot,
    required this.session,
    required this.view,
    required this.active,
    required this.onTap,
  });

  final PaintBenchSlot slot;
  final PaintSession session;
  final PaintStyleView view;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final label = _rackLabel(context.l10n, slot);
    final neutral = switch (slot) {
      PaintBenchSlot.blur ||
      PaintBenchSlot.adjust ||
      PaintBenchSlot.eraser => true,
      _ => false,
    };
    final ink = neutral
        ? (active ? tokens.accentText : tokens.textPrimary)
        : view.strokeColor;
    // The glyph's weight follows the live stroke width, so the rack
    // reads size at a glance without a single number.
    final glyphStroke = neutral
        ? 2.0
        : 2.0 + (view.strokeWidth.clamp(1, 80) / 80) * 2.5;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        key: ValueKey('paint-rack-${slot.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: AppMotion.state,
            curve: AppMotion.curve,
            decoration: BoxDecoration(
              color: active
                  ? tokens.accent.withValues(alpha: 0.13)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active
                    ? tokens.accent.withValues(alpha: 0.85)
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            // scaleDown: at the bench's own height this renders at
            // natural size; inside a tighter host (mode-switch
            // animation frames, exotic viewports) the tile shrinks
            // instead of striping an overflow.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 38,
                    height: 22,
                    child: CustomPaint(
                      painter: _RackGlyphPainter(
                        slot: slot,
                        session: session,
                        view: view,
                        ink: ink,
                        neutralColor: active
                            ? tokens.accentText
                            : tokens.textPrimary,
                        strokeWidth: glyphStroke,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    textScaler: _benchTextScaler(context),
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      color: active ? tokens.accentText : tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Line-style mini stroke for the style row's line pill.
class _LineStylePainter extends CustomPainter {
  _LineStylePainter({
    required this.tool,
    required this.color,
    required this.strokeWidth,
  });

  final PaintToolType tool;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    _paintLineVariant(canvas, size, tool, color, strokeWidth);
  }

  @override
  bool shouldRepaint(covariant _LineStylePainter old) =>
      old.tool != tool || old.color != color || old.strokeWidth != strokeWidth;
}

void _paintLineVariant(
  Canvas canvas,
  Size size,
  PaintToolType tool,
  Color color,
  double strokeWidth,
) {
  final p = Paint()
    ..color = color
    ..strokeWidth = strokeWidth
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  final y = size.height / 2;
  switch (tool) {
    case PaintToolType.dashLine:
      var x = 1.0;
      while (x < size.width - 1) {
        final end = (x + 6).clamp(0.0, size.width - 1).toDouble();
        canvas.drawLine(Offset(x, y), Offset(end, y), p);
        x = end + 4;
      }
    case PaintToolType.dashDotLine:
      var x = 1.0;
      var i = 0;
      while (x < size.width - 1) {
        if (i.isEven) {
          final end = (x + 6).clamp(0.0, size.width - 1).toDouble();
          canvas.drawLine(Offset(x, y), Offset(end, y), p);
          x = end + 4;
        } else {
          canvas.drawCircle(
            Offset(x + 1, y),
            strokeWidth * 0.55,
            Paint()..color = color,
          );
          x += 6;
        }
        i++;
      }
    default:
      canvas.drawLine(Offset(1, y), Offset(size.width - 1, y), p);
  }
}

/// Draws each rack slot's glyph — a live mini-preview of what the
/// slot produces, in the user's own ink where the tool inks.
class _RackGlyphPainter extends CustomPainter {
  _RackGlyphPainter({
    required this.slot,
    required this.session,
    required this.view,
    required this.ink,
    required this.neutralColor,
    required this.strokeWidth,
  });

  final PaintBenchSlot slot;
  final PaintSession session;
  final PaintStyleView view;
  final Color ink;
  final Color neutralColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = ink
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final w = size.width;
    final h = size.height;
    final cy = h / 2;

    switch (slot) {
      case PaintBenchSlot.pen:
        final path = Path()
          ..moveTo(2, cy + 5)
          ..cubicTo(w * 0.25, cy - 9, w * 0.45, cy + 9, w * 0.6, cy)
          ..cubicTo(w * 0.75, cy - 9, w * 0.9, cy + 7, w - 2, cy - 3);
        canvas.drawPath(path, stroke);
      case PaintBenchSlot.line:
        // The glyph is the armed/remembered VARIANT — the rack shows
        // the real line the next drag draws.
        final variant = kLineFamilyTools.contains(session.activeTool)
            ? session.activeTool!
            : session.lastLineTool;
        _paintLineVariant(canvas, size, variant, ink, strokeWidth);
      case PaintBenchSlot.arrow:
        canvas.drawLine(Offset(2, cy), Offset(w - 7, cy), stroke);
        final head = Path()
          ..moveTo(w - 2, cy)
          ..lineTo(w - 10, cy - 5)
          ..moveTo(w - 2, cy)
          ..lineTo(w - 10, cy + 5);
        canvas.drawPath(head, stroke);
      case PaintBenchSlot.shape:
        final variant = kShapeFamilyTools.contains(session.activeTool)
            ? session.activeTool!
            : session.lastShapeTool;
        switch (variant) {
          case PaintToolType.rectangle:
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromCenter(
                  center: Offset(w / 2, cy),
                  width: 24,
                  height: 16,
                ),
                const Radius.circular(3),
              ),
              stroke,
            );
          case PaintToolType.circle:
            canvas.drawCircle(Offset(w / 2, cy), 9.5, stroke);
          case PaintToolType.hexagon:
            canvas.drawPath(_polygonPath(w / 2, cy, 10.5, 6), stroke);
          case PaintToolType.polygon:
            canvas.drawPath(
              _polygonPath(w / 2, cy, 10.5, session.polygonSides),
              stroke,
            );
          default:
            canvas.drawRect(
              Rect.fromCenter(center: Offset(w / 2, cy), width: 22, height: 15),
              stroke,
            );
        }
      case PaintBenchSlot.blur:
        final halo = Paint()
          ..color = neutralColor.withValues(alpha: 0.25)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);
        canvas.drawCircle(Offset(w / 2, cy), 9, halo);
        canvas.drawCircle(
          Offset(w / 2, cy),
          6,
          Paint()
            ..color = neutralColor
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
      case PaintBenchSlot.adjust:
        // Selection-frame corners around a dot: "pick a stroke".
        final p = Paint()
          ..color = neutralColor
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        final r = Rect.fromCenter(
          center: Offset(w / 2, cy),
          width: 22,
          height: 18,
        );
        const len = 5.0;
        for (final (corner, dx, dy) in [
          (r.topLeft, 1.0, 1.0),
          (r.topRight, -1.0, 1.0),
          (r.bottomLeft, 1.0, -1.0),
          (r.bottomRight, -1.0, -1.0),
        ]) {
          canvas.drawLine(corner, corner + Offset(dx * len, 0), p);
          canvas.drawLine(corner, corner + Offset(0, dy * len), p);
        }
        canvas.drawCircle(
          Offset(w / 2, cy),
          2.4,
          Paint()..color = neutralColor,
        );
      case PaintBenchSlot.eraser:
        final p = Paint()
          ..color = neutralColor
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
        canvas.save();
        canvas.translate(w / 2, cy);
        canvas.rotate(-0.35);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: 19, height: 13),
            const Radius.circular(3),
          ),
          p,
        );
        // Split line: the classic two-part eraser silhouette.
        canvas.drawLine(const Offset(-3, -6.5), const Offset(-3, 6.5), p);
        canvas.restore();
    }
  }

  Path _polygonPath(double cx, double cy, double r, int sides) {
    final path = Path();
    final n = sides.clamp(3, 24);
    for (var i = 0; i < n; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i) / n;
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
  bool shouldRepaint(covariant _RackGlyphPainter old) =>
      old.slot != slot ||
      old.ink != ink ||
      old.neutralColor != neutralColor ||
      old.strokeWidth != strokeWidth ||
      old.session.activeTool != session.activeTool ||
      old.session.lastLineTool != session.lastLineTool ||
      old.session.lastShapeTool != session.lastShapeTool ||
      old.session.polygonSides != session.polygonSides;
}
