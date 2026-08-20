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
import '../../../ui/editor_slider_row.dart';
import '../../../../../app/theme/app_tokens.dart';
import '../../widgets/controls/connected_track.dart';
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
        // ONE paragraph row: alignment beside base direction — the
        // two discrete "how the paragraph sits" choices share a row
        // instead of alignment floating alone over a wordy chip row.
        // Both are glyph segments; the canvas above is the live
        // explanation, and Semantics carries the words.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _AlignmentSegmentedControl(
              isLeft: isLeft,
              isCenter: isCenter,
              isRight: isRight,
              onLeft: () => ctrl.setAlignment(TextAlign.left),
              onCenter: () => ctrl.setAlignment(TextAlign.center),
              onRight: () => ctrl.setAlignment(TextAlign.right),
            ),
            const SizedBox(width: 14),
            // Base paragraph direction. A discrete pick — one
            // SetTextDirectionModeCommand per change, its own undo
            // entry.
            ToggleSegmentGroup(
              children: [
                Semantics(
                  label: context.l10n.textDirectionAutoTitle,
                  button: true,
                  selected: layer.textDirectionMode == TextDirectionMode.auto,
                  child: ToggleSegment(
                    key: const ValueKey('layout-direction-auto'),
                    icon: AppIcons.replace,
                    selected: layer.textDirectionMode == TextDirectionMode.auto,
                    onTap: () =>
                        ctrl.setTextDirectionMode(TextDirectionMode.auto),
                  ),
                ),
                Semantics(
                  label: context.l10n.textDirectionRtlTitle,
                  button: true,
                  selected: layer.textDirectionMode == TextDirectionMode.rtl,
                  child: ToggleSegment(
                    key: const ValueKey('layout-direction-rtl'),
                    icon: AppIcons.textDirectionRtl,
                    selected: layer.textDirectionMode == TextDirectionMode.rtl,
                    onTap: () =>
                        ctrl.setTextDirectionMode(TextDirectionMode.rtl),
                  ),
                ),
                Semantics(
                  label: context.l10n.textDirectionLtrTitle,
                  button: true,
                  selected: layer.textDirectionMode == TextDirectionMode.ltr,
                  child: ToggleSegment(
                    key: const ValueKey('layout-direction-ltr'),
                    icon: AppIcons.textDirectionLtr,
                    selected: layer.textDirectionMode == TextDirectionMode.ltr,
                    onTap: () =>
                        ctrl.setTextDirectionMode(TextDirectionMode.ltr),
                  ),
                ),
              ],
            ),
          ],
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
        // Resize behaviour — what a corner drag means for this layer.
        // A two-segment connected track on the slider rows' label
        // grid, so the whole sheet keeps one left edge.
        Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(
                context.l10n.resizeBehaviorTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: labelStyle,
              ),
            ),
            Expanded(
              child: SizedBox(
                height: 44,
                child: ConnectedTrack(
                  segments: [
                    TrackSegmentSpec(
                      key: const ValueKey('layout-resize-scale'),
                      semanticLabel: context.l10n.scaleTextTitle,
                      active: layer.resizeMode == TextResizeMode.scaleText,
                      onTap: () => ctrl.setResizeMode(TextResizeMode.scaleText),
                      child: _trackLabel(
                        context,
                        context.l10n.scaleTextTitle,
                        layer.resizeMode == TextResizeMode.scaleText,
                      ),
                    ),
                    TrackSegmentSpec(
                      key: const ValueKey('layout-resize-box'),
                      semanticLabel: context.l10n.resizeBoxTitle,
                      active: layer.resizeMode == TextResizeMode.resizeBox,
                      onTap: () => ctrl.setResizeMode(TextResizeMode.resizeBox),
                      child: _trackLabel(
                        context,
                        context.l10n.resizeBoxTitle,
                        layer.resizeMode == TextResizeMode.resizeBox,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static Widget _trackLabel(BuildContext context, String text, bool active) {
    final tokens = AppTokens.of(context);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: active ? tokens.accentText : tokens.textPrimary,
        letterSpacing: 0.1,
      ),
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
