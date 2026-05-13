import 'package:flutter/material.dart';

import '../../toolbar/presentation/widgets/preset_chip.dart';

/// Generic numeric-slider bottom sheet used by the text mode toolbar
/// for font size, letter spacing, and line height.
///
/// Live mutation: every change to the slider invokes [onChange]
/// immediately so the canvas (and the toolbar pill) reflect the value
/// while the sheet is open. Returns `null` when dismissed; callers
/// don't need to do anything special on cancel because `onChange`
/// already pushed the user's intent.
Future<void> showTextValueSheet(
  BuildContext context, {
  required String title,
  required double initial,
  required double min,
  required double max,
  required ValueChanged<double> onChange,
  List<double> presets = const <double>[],
  String unit = '',
  int decimals = 0,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TextValueSheet(
      title: title,
      initial: initial,
      min: min,
      max: max,
      onChange: onChange,
      presets: presets,
      unit: unit,
      decimals: decimals,
    ),
  );
}

class _TextValueSheet extends StatefulWidget {
  const _TextValueSheet({
    required this.title,
    required this.initial,
    required this.min,
    required this.max,
    required this.onChange,
    required this.presets,
    required this.unit,
    required this.decimals,
  });

  final String title;
  final double initial;
  final double min;
  final double max;
  final ValueChanged<double> onChange;
  final List<double> presets;
  final String unit;
  final int decimals;

  @override
  State<_TextValueSheet> createState() => _TextValueSheetState();
}

class _TextValueSheetState extends State<_TextValueSheet> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial.clamp(widget.min, widget.max);
  }

  void _set(double v) {
    final clamped = v.clamp(widget.min, widget.max);
    if (clamped == _value) return;
    setState(() => _value = clamped);
    widget.onChange(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${_value.toStringAsFixed(widget.decimals)}${widget.unit}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Slider(
              value: _value,
              min: widget.min,
              max: widget.max,
              onChanged: _set,
            ),
            if (widget.presets.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in widget.presets)
                    PresetChip(
                      label:
                          '${p.toStringAsFixed(widget.decimals)}'
                          '${widget.unit}',
                      selected: (p - _value).abs() < 0.001,
                      onTap: () => _set(p),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
