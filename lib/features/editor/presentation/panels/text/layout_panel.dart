// Layout panel — compactness pass 2026-07: line height and letter
// spacing are ONE always-visible slider row each (label + slider +
// live readout on the shared EditorSliderRow), replacing the
// expandable preset-chip cards. Cuts the panel from ~314dp to
// ~150dp so the canvas keeps clear majority of the screen. The
// slider IS the primary affordance now; preset values live within
// easy reach of the track.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../l10n/l10n.dart';
import '../../../engine/modules/text/text_layer.dart';
import '../../../text/application/text_tool_controller.dart';
import '../../../ui/editor_slider_row.dart';
import '../../widgets/controls/slider_row.dart';
import '../../widgets/controls/toggle_segment.dart';

class LayoutPanel extends ConsumerWidget {
  const LayoutPanel({super.key, required this.layer});
  final TextLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final style = layer.style;
    final isLeft =
        style.alignment == TextAlign.left || style.alignment == TextAlign.start;
    final isCenter = style.alignment == TextAlign.center;
    final isRight =
        style.alignment == TextAlign.right || style.alignment == TextAlign.end;
    final labelStyle = flatSliderLabelStyle(context);
    final readoutStyle = flatSliderReadoutStyle(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        // Alignment — centered segmented pill. The three glyphs ARE
        // the affordance; no duplicate "Align" label.
        Center(
          child: _AlignmentSegmentedControl(
            isLeft: isLeft,
            isCenter: isCenter,
            isRight: isRight,
            onLeft: () => ctrl.setAlignment(TextAlign.left),
            onCenter: () => ctrl.setAlignment(TextAlign.center),
            onRight: () => ctrl.setAlignment(TextAlign.right),
          ),
        ),
        const SizedBox(height: 10),
        EditorSliderRow(
          label: context.l10n.lineHeightLabel,
          labelWidth: 96,
          value: style.lineHeight,
          min: 0.8,
          max: 3.0,
          format: (v) => v.toStringAsFixed(2),
          onChanged: ctrl.setLineHeight,
          onDragStart: ctrl.beginStyleDrag,
          onDragEnd: ctrl.endStyleDrag,
          haptics: EditorSliderHaptics.startTickEnd,
          labelStyle: labelStyle,
          readoutStyle: readoutStyle,
        ),
        EditorSliderRow(
          label: context.l10n.letterSpacingLabel,
          labelWidth: 96,
          value: style.letterSpacing,
          min: -5,
          max: 20,
          format: (v) => v.toStringAsFixed(1),
          onChanged: ctrl.setLetterSpacing,
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

/// Compact centered alignment picker — three icon buttons in a
/// soft pill. Selected state matches the rest of the editor's pilot
/// grammar (accent @ 14% fill + 45% border) so users don't relearn.
class _AlignmentSegmentedControl extends StatelessWidget {
  const _AlignmentSegmentedControl({
    required this.isLeft,
    required this.isCenter,
    required this.isRight,
    required this.onLeft,
    required this.onCenter,
    required this.onRight,
  });

  final bool isLeft;
  final bool isCenter;
  final bool isRight;
  final VoidCallback onLeft;
  final VoidCallback onCenter;
  final VoidCallback onRight;

  @override
  Widget build(BuildContext context) {
    // Kit group wrapper — the pill styling used to be re-rolled here.
    return ToggleSegmentGroup(
      children: [
        ToggleSegment(
          icon: Icons.format_align_left_rounded,
          selected: isLeft,
          onTap: onLeft,
        ),
        ToggleSegment(
          icon: Icons.format_align_center_rounded,
          selected: isCenter,
          onTap: onCenter,
        ),
        ToggleSegment(
          icon: Icons.format_align_right_rounded,
          selected: isRight,
          onTap: onRight,
        ),
      ],
    );
  }
}
