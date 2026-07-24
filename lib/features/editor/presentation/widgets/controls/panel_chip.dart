// Shared control kit (Phase 2A §1): extracted from the
// text_mode_toolbar library so every tool's panels can reuse it.
// tb2 15/16 (chip-grammar unification): the `LayoutPresetChip`
// implementation this file used to own is deleted — [WordChipRow]
// now renders the ONE canonical [PresetChip] family.

import 'package:flutter/material.dart';

import '../../../toolbar/presentation/widgets/preset_chip.dart';

/// Word-preset chip row (e.g. Tight / Normal / Wide) — replaces a
/// numeric slider with a 1-tap human-readable choice. Each preset
/// commits via the caller-supplied write function.
///
/// Selection is **nearest-match**, not range/threshold based:
/// exactly one chip — the one whose value is closest to [current]
/// — is highlighted at all times. This guarantees a single
/// selected chip even when canvas-aware preset values collapse
/// onto the same clamped value, and it gives the user a clear
/// "this is the closest named size" anchor while they nudge with
/// the stepper or slider.
class WordChipRow extends StatelessWidget {
  const WordChipRow({
    super.key,
    required this.options,
    required this.current,
    required this.onPick,
    this.selectedLabel,
    this.tolerance,
  });

  final List<({String label, double value})> options;
  final double current;
  final ValueChanged<double> onPick;

  /// Explicit selection override. When non-null and matches one of
  /// the option labels, exactly that chip is highlighted regardless
  /// of [current]. Used for sticky preset selection (e.g. "user
  /// just tapped M") that must not flip to a different chip when
  /// canvas-aware clamping makes preset values numerically close.
  final String? selectedLabel;

  /// Optional max distance from [current] to the nearest preset for
  /// the nearest fallback to count as "selected". When null, the
  /// nearest chip is always highlighted (legacy line-height /
  /// letter-spacing behaviour).
  final double? tolerance;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedIndex();
    // The ONE canonical chip family (tb2 15/16): 44dp pill, unified
    // selected treatment. 44 (was 36) is the intended hit-floor
    // reflow for every word/px preset row.
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final o = options[i];
          return PresetChip(
            label: o.label,
            selected: i == selectedIndex,
            onTap: () => onPick(o.value),
          );
        },
      ),
    );
  }

  /// Resolves which chip index (if any) is selected. Explicit
  /// [selectedLabel] wins; otherwise falls back to nearest-by-value
  /// — gated by [tolerance] when provided so manual edits that
  /// land far from any preset clear the selection entirely.
  int _selectedIndex() {
    if (selectedLabel != null) {
      for (var i = 0; i < options.length; i++) {
        if (options[i].label == selectedLabel) return i;
      }
    }
    if (options.isEmpty) return -1;
    var bestIndex = 0;
    var bestDelta = (current - options.first.value).abs();
    for (var i = 1; i < options.length; i++) {
      final delta = (current - options[i].value).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        bestIndex = i;
      }
    }
    if (tolerance != null && bestDelta > tolerance!) return -1;
    return bestIndex;
  }
}
