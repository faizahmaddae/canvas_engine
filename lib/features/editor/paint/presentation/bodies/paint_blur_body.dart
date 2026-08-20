import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/editor_value_format.dart';
import '../../../../../l10n/l10n.dart';
import '../../../toolbar/presentation/widgets/preset_slider_control.dart';
import '../../application/paint_tool_controller.dart';

/// Blur sheet — the blur patch's one parameter, on the canonical
/// preset+slider control. Values are reference-canvas px; the
/// controller scales to document px at the command boundary.
class PaintBlurBody extends ConsumerWidget {
  const PaintBlurBody({super.key, required this.view});

  final PaintStyleView view;

  static const List<double> _presets = [0, 10, 32];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    return PresetSliderControl(
      label: l10n.blurLabel,
      value: view.blurRadius,
      min: 0,
      max: 64,
      presets: _presets,
      presetLabels: [l10n.noneOption, l10n.softOption, l10n.strongOption],
      formatValue: (v) => EditorValueFormat.of(context).digits(v.round()),
      onPreview: ctrl.previewBlurRadius,
      onCommit: ctrl.commitBlurRadius,
    );
  }
}
