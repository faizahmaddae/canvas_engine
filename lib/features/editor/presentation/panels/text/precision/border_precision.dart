// Border precision panel pieces (Phase 2A commit 4): extracted
// verbatim from the text_mode_toolbar part-file library
// (text_decoration_panels.dart). Rename-only promotions — every
// symbol here is consumed by the library's sheet bodies.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../l10n/l10n.dart';
import '../../../../engine/modules/text/text_layer.dart';
import '../../../../text/application/text_tool_controller.dart';
import '../../../../ui/editor_slider_row.dart';
import '../../../../ui/precision_disclosure.dart';
import '../../../widgets/controls/precision_divider.dart';
import '../../../widgets/controls/slider_row.dart';

/// "Adjust precisely" disclosure for the Border panel. Same
/// flat header treatment as `BackgroundPrecisionAdvanced`: whole
/// row tappable, single chevron, no nested arrows. Hosts thickness
/// and opacity sliders inline when expanded.
class BorderPrecisionAdvanced extends ConsumerWidget {
  const BorderPrecisionAdvanced({super.key, required this.style});
  final TextStyleSpec style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final outline = style.outlineColor;
    final labelStyle = flatSliderLabelStyle(context);
    final readoutStyle = flatSliderReadoutStyle(context);
    return PrecisionDisclosure(
      titleClosed: context.l10n.adjustPrecisely,
      titleOpen: context.l10n.hidePreciseControls,
      chevronSize: 18,
      children: [
        const PrecisionDivider(),
        EditorSliderRow(
          label: context.l10n.thicknessLabel,
          labelWidth: 96,
          value: style.outlineWidth,
          max: 12,
          format: (v) => '${v.toStringAsFixed(0)}px',
          onChanged: ctrl.setOutlineWidth,
          onDragStart: ctrl.beginStyleDrag,
          onDragEnd: ctrl.endStyleDrag,
          haptics: EditorSliderHaptics.startTickEnd,
          labelStyle: labelStyle,
          readoutStyle: readoutStyle,
        ),
        if (outline != null)
          EditorSliderRow(
            label: context.l10n.opacityLabel,
            labelWidth: 96,
            value: outline.a * 100,
            max: 100,
            format: (v) => '${v.toStringAsFixed(0)}%',
            onChanged: (v) =>
                ctrl.setOutlineColor(outline.withValues(alpha: v / 100)),
            onDragStart: ctrl.beginStyleDrag,
            onDragEnd: ctrl.endStyleDrag,
            haptics: EditorSliderHaptics.startTickEnd,
            labelStyle: labelStyle,
            readoutStyle: readoutStyle,
          ),
      ],
    );
  }
}
