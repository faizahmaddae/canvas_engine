// Size sub-tool panel for the text-mode toolbar, split out of
// text_mode_toolbar.dart. Part file: every symbol resolves via the
// library root's imports — add imports there, never here.
part of 'text_mode_toolbar.dart';

/// Broad safety clamp for direct font-size mutation (stepper +
/// exact slider). Intentionally far wider than the named-preset
/// range so A+ can climb past XXL and A- can shrink below S.
///
/// Used to live as `_TextBodies._absoluteMinFontSize` — moved here
/// with the rest of the size-preset math since this panel is its
/// only caller (Phase 4 plan §5.1).
const double _absoluteMinFontSize = 4;
const double _absoluteMaxFontSize = 2000;

/// Computes the S/M/L/XL/XXL chip values for [doc] and [content].
/// Combines a canvas factor (shorter side of the doc) with a
/// length factor (longer text → smaller chips) so the preset that
/// reads as "XL" stays visually balanced against both canvas and
/// content. Output is clamped to [8, 600] px so chips remain
/// usable on any canvas without overflowing the slider/stepper
/// range.
List<({String label, double value})> _canvasAwareSizePresets(
  EditorDocument doc,
  String content,
) {
  final base = math.min(doc.width, doc.height);
  final lengthFactor = _lengthFactor(content);
  double p(double f) =>
      (base * f * lengthFactor).clamp(8.0, 600.0).toDouble();
  return [
    (label: 'S', value: p(0.06)),
    (label: 'M', value: p(0.10)),
    (label: 'L', value: p(0.16)),
    (label: 'XL', value: p(0.24)),
    (label: 'XXL', value: p(0.34)),
  ];
}

/// Length-aware shrink factor: short labels keep full-size
/// presets, sentence-length text is dialed back to 80 %, and
/// paragraph-length text drops to 60 % so XXL never pushes a
/// long block past the canvas edges. Whitespace is intentionally
/// included — leading/trailing spaces visually consume room too.
double _lengthFactor(String content) {
  final n = content.length;
  if (n <= 10) return 1.0;
  if (n <= 25) return 0.8;
  return 0.6;
}

/// Body for the Text Size sub-tool. Owns no local state — the
/// "sticky preset" highlight lives on `TextSession` so it survives
/// rebuilds/remounts that can otherwise drop a `StatefulWidget`'s
/// state (e.g. when the selected layer flickers null between a
/// `setFontSize` write and the resulting auto-resize, the panel
/// briefly returns `SizedBox.shrink` and any local `_selectedPreset`
/// is lost). Keying the pin by layer id ensures switching to a
/// different text layer does not inherit the previous layer's
/// highlight.
class _SizeBody extends ConsumerWidget {
  const _SizeBody({required this.layer});
  final TextLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final style = layer.style;
    final doc = ref.watch(renderedDocumentProvider);
    final pin = ref.watch(
      textToolControllerProvider.select((s) => s.selectedSizePreset),
    );
    final presets = _canvasAwareSizePresets(doc, layer.content);
    final selectedLabel = (pin != null && pin.layerId == layer.id)
        ? pin.label
        : null;

    // Tolerance scales with current size so the nearest-fallback
    // selection feels right at 12 px and at 200 px alike. Only
    // applies when no sticky pin is active.
    final tolerance = math.max(1.0, style.fontSize * 0.03);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Match the Layout panel rhythm: no all-caps section
        // labels (the stepper IS the value, the chip row IS the
        // presets — both self-explanatory). The disclosure below
        // gives precise access without a header.
        const SizedBox(height: 6),
        _SizeStepperRow(
          value: style.fontSize,
          min: _absoluteMinFontSize,
          max: _absoluteMaxFontSize,
          onChange: ctrl.setFontSize,
        ),
        const SizedBox(height: 12),
        _WordChipRow(
          options: presets,
          current: style.fontSize,
          selectedLabel: selectedLabel,
          tolerance: tolerance,
          onPick: (value) {
            // Look the tapped value back up to recover its label;
            // identical instance equality holds because the chip
            // hands back the exact double from the same `presets`
            // list this build computed.
            final hit = presets.firstWhere(
              (p) => p.value == value,
              orElse: () => (label: '', value: value),
            );
            if (hit.label.isEmpty) {
              ctrl.setFontSize(value);
            } else {
              ctrl.setFontSizeFromPreset(
                size: value,
                presetLabel: hit.label,
                layerId: layer.id,
              );
            }
          },
        ),
        const SizedBox(height: 6),
        _SizePrecisionAdvanced(
          value: style.fontSize,
          min: _absoluteMinFontSize,
          max: _absoluteMaxFontSize,
          onChange: ctrl.setFontSize,
        ),
      ],
    );
  }
}

/// Flattened "Adjust precisely" disclosure used by the Size body:
/// one arrow, one tap to reveal value + px-presets + fine-tune
/// slider — no nested expand, no second arrow.
///
/// Style writes still route through the same controller setter
/// the dock uses (`setFontSize`), so undo coalescing, the
/// scale-aware translation in `_translateFontSizeForVisualScale`,
/// and the box auto-fit behaviour are all preserved verbatim.
class _SizePrecisionAdvanced extends ConsumerWidget {
  const _SizePrecisionAdvanced({
    required this.value,
    required this.min,
    required this.max,
    required this.onChange,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChange;

  static const List<double> _pxPresets = [12, 16, 24, 32, 48, 64, 96];

  String _format(double v) => '${v.toStringAsFixed(0)}px';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final clampedValue = value.clamp(min, max).toDouble();
    return PrecisionDisclosure(
      titleClosed: context.l10n.adjustPrecisely,
      titleOpen: context.l10n.hidePreciseControls,
      headerValue: _format(clampedValue),
      chevronSize: 18,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const _PrecisionDivider(),
              const SizedBox(height: 8),
              // px presets reuse the Layout chip so the two
              // panels share one visual vocabulary.
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in _pxPresets)
                    _LayoutPresetChip(
                      label: _format(p),
                      selected: (p - clampedValue).abs() < 0.001,
                      onTap: () => onChange(p.clamp(min, max).toDouble()),
                    ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                ),
                child: EditorSliderRow(
                  value: clampedValue,
                  min: min,
                  max: max,
                  showReadout: false,
                  format: _format,
                  onChanged: onChange,
                  onDragStart: ctrl.beginStyleDrag,
                  onDragEnd: ctrl.endStyleDrag,
                  haptics: EditorSliderHaptics.startTickEnd,
                  semanticLabel: context.l10n.sizeTool,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "A−" / "A+" double-button stepper used in the Size sub-tool. Each
/// tap nudges the live font size by a perceptual step so the user
/// gets visible change without having to drag a slider. Long-press
/// repeats. The buttons round-trip through the controller so undo
/// coalescing and box auto-fit behaviour stay identical to the
/// slider path.
class _SizeStepperRow extends StatelessWidget {
  const _SizeStepperRow({
    required this.value,
    required this.min,
    required this.max,
    required this.onChange,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChange;

  /// Perceptual step: ~10% of the current value (rounded), with a
  /// floor so very small sizes still nudge by at least 1 px.
  double get _step {
    final s = (value * 0.1).roundToDouble();
    return s < 1 ? 1 : s;
  }

  void _bump(int dir) {
    final next = (value + dir * _step).clamp(min, max).toDouble();
    if ((next - value).abs() < 0.01) return;
    EditorHaptics.tap();
    onChange(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    Widget btn({required IconData icon, required VoidCallback onTap}) {
      return Material(
        color: tokens.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 56,
            height: 44,
            child: Center(child: Icon(icon, size: 22, color: tokens.accent)),
          ),
        ),
      );
    }

    return Row(
      children: [
        btn(icon: Icons.text_decrease_rounded, onTap: () => _bump(-1)),
        // Live value pill in the middle — same vocabulary as the
        // Layout panel's value pill so the two panels feel like
        // one family. Tabular figures so 12 → 24 → 120 doesn't
        // shift the centred layout.
        Expanded(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: tokens.surfaceMuted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${value.round()} px',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
        btn(icon: Icons.text_increase_rounded, onTap: () => _bump(1)),
      ],
    );
  }
}

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
class _WordChipRow extends StatelessWidget {
  const _WordChipRow({
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
    // Same chip vocabulary as the Layout panel (compact pill, no
    // hero shadow). Lets Size and Layout read as one family — and
    // the row sheds ~10dp of vertical weight vs the old
    // `PresetChip`.
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final o = options[i];
          return _LayoutPresetChip(
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
