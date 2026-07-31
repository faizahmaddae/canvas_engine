// Extracted verbatim from paint_mode_toolbar.dart (tb1 4/17); behaviour-preserving.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_motion.dart';
import '../../../../../app/theme/app_tokens.dart';
import '../../../../../core/utils/haptics.dart';
import '../../../../../l10n/l10n.dart';
import '../../../../color_picker/presentation/color_picker_sheet.dart';
import '../../application/paint_tool_controller.dart';

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
class PaintFillBody extends ConsumerWidget {
  const PaintFillBody({
    super.key,
    required this.enabled,
    required this.current,
  });

  final bool enabled;
  final Color current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(paintToolControllerProvider);
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    final stroke = session.strokeColor;
    final fill = session.fillColor;

    final isNone = fill == null;
    final isSameAsStroke = fill != null && fill.toARGB32() == stroke.toARGB32();
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
                label: context.l10n.noFillOption,
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
                label: context.l10n.sameColorOption,
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
                label: context.l10n.customLabel,
                selected: isCustom,
                preview: isCustom
                    ? _FillPreviewSolid(color: fill)
                    : const _FillPreviewSweep(),
                onTap: () async {
                  EditorHaptics.tap();
                  // Custom fill goes straight to the shared picker's
                  // custom level — the card itself is the "custom"
                  // affordance, so landing on swatches would be a
                  // detour.
                  // Contract §2 (tb2 4/16): live changes preview
                  // through the fill-colour channel; committed
                  // picks seal ONE undoable command.
                  await showColorPickerSheet(
                    context,
                    initial: fill ?? stroke,
                    onLiveChange: ctrl.previewFillColor,
                    onCommitted: (_) => ctrl.commitFillColor(),
                    title: context.l10n.fillColorTitle,
                    startAtCustom: true,
                  );
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
    final tokens = AppTokens.of(context);
    final fg = selected ? tokens.accentText : tokens.textPrimary;
    // Flat: soft tint when selected, faint surface when resting.
    // No border, no elevation — same grammar as Text `_StyleTile`.
    final bg = selected
        ? tokens.accent.withValues(alpha: 0.12)
        : tokens.surfaceMuted.withValues(alpha: 0.35);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.standard,
          curve: AppMotion.curve,
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
    return CustomPaint(
      painter: _NoneIconPainter(color: AppTokens.of(context).textSecondary),
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
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: AppTokens.of(context).border.withValues(alpha: 0.6),
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
          color: AppTokens.of(context).border.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
    );
  }
}
