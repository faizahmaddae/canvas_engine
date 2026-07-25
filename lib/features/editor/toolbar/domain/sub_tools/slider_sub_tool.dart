import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/widgets/preset_slider_control.dart';
import '../sub_tool.dart';

/// Config-driven [SubTool] that renders a [PresetSliderControl].
///
/// Adding a numeric tool now reduces to **one constructor literal**.
/// No new widget classes, no per-tool sheet boilerplate.
///
/// Example:
/// ```dart
/// SliderSubTool(
///   headerTitle: 'Size',
///   headerIcon: AppIcons.strokeWeight,
///   min: 1, max: 80,
///   presets: const [2, 4, 6, 10, 18, 30],
///   readValue: (ref) => ref.watch(paintToolControllerProvider).strokeWidth,
///   writeValue: (ref, v) =>
///       ref.read(paintToolControllerProvider.notifier).setStrokeWidth(v),
///   format: (v) => '${v.round()}',
/// );
/// ```
class SliderSubTool extends SubTool {
  const SliderSubTool({
    required this.headerTitle,
    required this.headerIcon,
    required this.min,
    required this.max,
    required this.presets,
    required this.readValue,
    required this.writeValue,
    required this.format,
    this.leadingBuilder,
    bool supportsSiblingSwipe = true,
    this.presetLabels,
  }) : _supportsSiblingSwipe = supportsSiblingSwipe;

  @override
  final String headerTitle;
  @override
  final IconData headerIcon;

  // Backing field for the [SubTool.supportsSiblingSwipe] override.
  // Kept private + getter override so this never *shadows* the
  // base getter — it implements it.
  final bool _supportsSiblingSwipe;
  @override
  bool get supportsSiblingSwipe => _supportsSiblingSwipe;

  final double min;
  final double max;
  final List<double> presets;

  /// Optional human-friendly chip labels (e.g. 'Light',
  /// 'Normal', 'Strong'). 1:1 with [presets].
  final List<String>? presetLabels;

  /// Reads the live value via Riverpod. Allowed to use `ref.watch`
  /// — the surrounding [SubTool.build] is wrapped in a Consumer
  /// scope by the host.
  final double Function(WidgetRef ref) readValue;

  /// Commits a value change. Should route through the owning
  /// controller so undo coalescing / mirror-to-selection logic
  /// stays in one place.
  final void Function(WidgetRef ref, double value) writeValue;

  /// Formats the live readout (e.g. `(v) => '${v.round()}'`).
  final String Function(double value) format;

  /// Optional leading widget for the slider row (e.g. a brush-size
  /// dot whose diameter tracks the live value).
  final Widget Function(BuildContext, double value)? leadingBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = readValue(ref);
    return PresetSliderControl(
      value: value,
      min: min,
      max: max,
      presets: presets,
      presetLabels: presetLabels,
      formatValue: format,
      leading: leadingBuilder?.call(context, value),
      onCommit: (v) => writeValue(ref, v),
    );
  }
}
