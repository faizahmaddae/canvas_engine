// Extracted verbatim from paint_mode_toolbar.dart (tb1 4/17); behaviour-preserving.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_motion.dart';
import '../../../../../app/theme/app_tokens.dart';
import '../../../../../core/utils/haptics.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../../../l10n/l10n.dart';
import '../../application/paint_tool_controller.dart';
import '../../../engine/modules/paint/paint_layer.dart';
import '../../domain/paint_tool_type.dart';

String _dashPresetLabel(AppLocalizations l10n, String label) {
  return switch (label) {
    'Solid' => l10n.solidOption,
    'Dashed' => l10n.dashedOption,
    'Dotted' => l10n.dottedOption,
    _ => label,
  };
}

/// The line tool that draws [kind]. `null` for anything that isn't
/// a line style, so the caller falls back to the armed tool.
PaintToolType? _toolForKind(PaintKind? kind) => switch (kind) {
  PaintKind.line => PaintToolType.line,
  PaintKind.dashLine => PaintToolType.dashLine,
  PaintKind.dashDotLine => PaintToolType.dashDotLine,
  _ => null,
};

class PaintDashBody extends ConsumerWidget {
  const PaintDashBody({super.key});

  // Three line styles map 1:1 to engine kinds. Picking a chip
  // calls selectLineStyle(): it restyles a selected line layer in
  // place (the three kinds are geometry peers) and otherwise arms
  // the matching tool for the next stroke — no phantom state either
  // way.
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
    final view = ref.watch(paintStyleViewProvider);
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    // With a line layer selected the chips reflect THAT line's kind;
    // otherwise they reflect the armed tool (tb4 3/14).
    final activeTool = _toolForKind(view.layerKind) ?? session.activeTool;
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
                  label: _dashPresetLabel(context.l10n, _presets[i].$1),
                  pattern: _previewPatterns[_presets[i].$2],
                  selected: activeTool == _presets[i].$2,
                  onTap: () => ctrl.selectLineStyle(_presets[i].$2),
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
    final tokens = AppTokens.of(context);
    final fg = selected ? tokens.accent : tokens.textPrimary;
    // Flat: same grammar as `_FillChoice` and Text `_StyleTile` —
    // soft tint on select, faint surface at rest, no border or
    // shadow. Preview line + label remain the affordance.
    final bg = selected
        ? tokens.accent.withValues(alpha: 0.12)
        : tokens.surfaceMuted.withValues(alpha: 0.35);
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
          duration: AppMotion.standard,
          curve: AppMotion.curve,
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
