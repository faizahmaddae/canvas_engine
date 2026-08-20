// Layout panel — چیدمان: how the text sits. Alignment, line height
// and letter spacing (the compactness-pass slider rows), plus the
// two paragraph-level choices that used to hide behind the
// full-scrim «بیشتر» list as pop-then-dialog rows: base direction
// (auto/RTL/LTR) and resize behaviour (scale text / resize box) —
// moved home by the Text Studio redesign
// (`docs/text-studio-redesign-2026-08.md` §4).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/editor_value_format.dart';
import '../../../../../l10n/l10n.dart';
import '../../../engine/modules/text/text_layer.dart';
import '../../../text/application/text_tool_controller.dart';
import '../../../toolbar/presentation/widgets/preset_chip.dart';
import '../../../ui/editor_slider_row.dart';
import '../../widgets/controls/slider_row.dart';
import '../../widgets/controls/toggle_segment.dart';
import '../../../../../app/theme/app_icons.dart';

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
          format: (v) =>
              EditorValueFormat.of(context).mapDigits(v.toStringAsFixed(2)),
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
          format: (v) =>
              EditorValueFormat.of(context).mapDigits(v.toStringAsFixed(1)),
          onChanged: ctrl.setLetterSpacing,
          onDragStart: ctrl.beginStyleDrag,
          onDragEnd: ctrl.endStyleDrag,
          haptics: EditorSliderHaptics.startTickEnd,
          labelStyle: labelStyle,
          readoutStyle: readoutStyle,
        ),
        const SizedBox(height: 8),
        // Base paragraph direction. A discrete pick — one
        // SetTextDirectionModeCommand per change, its own undo entry.
        _OptionChipRow(
          label: context.l10n.textDirectionTitle,
          labelStyle: labelStyle,
          options: [
            (
              key: const ValueKey('layout-direction-auto'),
              label: context.l10n.textDirectionAutoTitle,
              selected: layer.textDirectionMode == TextDirectionMode.auto,
              onTap: () => ctrl.setTextDirectionMode(TextDirectionMode.auto),
            ),
            (
              key: const ValueKey('layout-direction-rtl'),
              label: context.l10n.textDirectionRtlTitle,
              selected: layer.textDirectionMode == TextDirectionMode.rtl,
              onTap: () => ctrl.setTextDirectionMode(TextDirectionMode.rtl),
            ),
            (
              key: const ValueKey('layout-direction-ltr'),
              label: context.l10n.textDirectionLtrTitle,
              selected: layer.textDirectionMode == TextDirectionMode.ltr,
              onTap: () => ctrl.setTextDirectionMode(TextDirectionMode.ltr),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Resize behaviour — what a corner drag means for this layer.
        _OptionChipRow(
          label: context.l10n.resizeBehaviorTitle,
          labelStyle: labelStyle,
          options: [
            (
              key: const ValueKey('layout-resize-scale'),
              label: context.l10n.scaleTextTitle,
              selected: layer.resizeMode == TextResizeMode.scaleText,
              onTap: () => ctrl.setResizeMode(TextResizeMode.scaleText),
            ),
            (
              key: const ValueKey('layout-resize-box'),
              label: context.l10n.resizeBoxTitle,
              selected: layer.resizeMode == TextResizeMode.resizeBox,
              onTap: () => ctrl.setResizeMode(TextResizeMode.resizeBox),
            ),
          ],
        ),
      ],
    );
  }
}

/// One labelled row of mutually-exclusive option chips — the same
/// preset-chip grammar the effect sections use, with the panel's
/// slider-row label column so the whole sheet keeps one left edge.
class _OptionChipRow extends StatelessWidget {
  const _OptionChipRow({
    required this.label,
    required this.labelStyle,
    required this.options,
  });

  final String label;
  final TextStyle? labelStyle;
  final List<({Key key, String label, bool selected, VoidCallback onTap})>
  options;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: labelStyle,
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: options.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) => KeyedSubtree(
                key: options[i].key,
                child: PresetChip(
                  label: options[i].label,
                  selected: options[i].selected,
                  onTap: options[i].onTap,
                ),
              ),
            ),
          ),
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
    final l10n = context.l10n;
    return ToggleSegmentGroup(
      // Spatially literal: the buttons mean the screen's left, centre
      // and right, so the row must not mirror with the paragraph.
      spatial: true,
      children: [
        Semantics(
          label: l10n.alignLeftAction,
          button: true,
          selected: isLeft,
          child: ToggleSegment(
            icon: AppIcons.textAlignLeft,
            selected: isLeft,
            onTap: onLeft,
          ),
        ),
        Semantics(
          label: l10n.alignCenterAction,
          button: true,
          selected: isCenter,
          child: ToggleSegment(
            icon: AppIcons.textAlignCenter,
            selected: isCenter,
            onTap: onCenter,
          ),
        ),
        Semantics(
          label: l10n.alignRightAction,
          button: true,
          selected: isRight,
          child: ToggleSegment(
            icon: AppIcons.textAlignRight,
            selected: isRight,
            onTap: onRight,
          ),
        ),
      ],
    );
  }
}
