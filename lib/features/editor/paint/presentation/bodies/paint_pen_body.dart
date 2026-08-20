import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_tokens.dart';
import '../../../../../core/utils/editor_value_format.dart';
import '../../../../../l10n/l10n.dart';
import '../../../toolbar/presentation/widgets/preset_slider_control.dart';
import '../../application/paint_tool_controller.dart';

/// Pen sheet — the one stop for the two numeric ink parameters every
/// inking tool shares: stroke **size** and **opacity**. Opened by the
/// bench's size pill and by tap-again on the pen/arrow rack slots.
///
/// Both sections are the canonical [PresetSliderControl]; both write
/// through the contract-§2 preview channels, so a drag stages on the
/// live overlay for a bound stroke (or updates the pen defaults) and
/// commits exactly once on release. The bench's size pill and rack
/// glyph weights follow live, so the sheet needs no hero of its own.
class PaintPenBody extends ConsumerWidget {
  const PaintPenBody({super.key, required this.view});

  final PaintStyleView view;

  static const List<double> _sizePresets = [3, 8, 18, 36];
  static const List<double> _opacityPresets = [25, 60, 100];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final tokens = AppTokens.of(context);
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    final values = EditorValueFormat.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PresetSliderControl(
          label: l10n.sizeTool,
          value: view.strokeWidth,
          min: 1,
          max: 80,
          presets: _sizePresets,
          presetLabels: [
            l10n.thinOption,
            l10n.mediumOption,
            l10n.thickOption,
            l10n.heavyOption,
          ],
          formatValue: (v) => values.px(v.round()),
          liveLeadingBuilder: (context, v) => _InkDot(
            color: view.strokeColor.withValues(alpha: 1),
            diameter: 4 + (v.clamp(1, 80) / 80) * 18,
          ),
          onPreview: ctrl.previewStrokeWidth,
          onCommit: ctrl.commitStrokeWidth,
        ),
        const SizedBox(height: 14),
        PresetSliderControl(
          label: l10n.strokeOpacityLabel,
          value: (view.strokeColor.a * 100).clamp(0.0, 100.0),
          min: 0,
          max: 100,
          presets: _opacityPresets,
          presetLabels: [
            l10n.lightOption,
            l10n.normalOption,
            l10n.strongOption,
          ],
          formatValue: (v) => values.percent(v.round()),
          liveLeadingBuilder: (context, v) => Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: view.strokeColor.withValues(
                alpha: (v / 100).clamp(0.0, 1.0),
              ),
              shape: BoxShape.circle,
              border: Border.all(color: tokens.border.withValues(alpha: 0.6)),
            ),
          ),
          onPreview: ctrl.previewStrokeOpacity,
          onCommit: ctrl.commitStrokeOpacity,
        ),
      ],
    );
  }
}

class _InkDot extends StatelessWidget {
  const _InkDot({required this.color, required this.diameter});

  final Color color;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
