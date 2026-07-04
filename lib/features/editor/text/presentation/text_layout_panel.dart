// Layout sub-tool panel for the text-mode toolbar, split out of
// text_mode_toolbar.dart. Part file: every symbol resolves via the
// library root's imports — add imports there, never here.
part of 'text_mode_toolbar.dart';

// ─── Layout panel (mobile-first redesign) ───────────────────────────
//
// Owns the "which precision slider is open" state so opening one
// closes the other (spec: only one slider expanded at a time).

typedef _LayoutPreset = ({String label, double value});

class _LayoutPanel extends ConsumerStatefulWidget {
  const _LayoutPanel({required this.layer});
  final TextLayer layer;

  @override
  ConsumerState<_LayoutPanel> createState() => _LayoutPanelState();
}

class _LayoutPanelState extends ConsumerState<_LayoutPanel> {
  // null | 'lineHeight' | 'letterSpacing'
  String? _openId;

  void _setOpen(String id, bool open) {
    setState(() => _openId = open ? id : (_openId == id ? null : _openId));
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final style = widget.layer.style;
    final isLeft =
        style.alignment == TextAlign.left || style.alignment == TextAlign.start;
    final isCenter = style.alignment == TextAlign.center;
    final isRight =
        style.alignment == TextAlign.right || style.alignment == TextAlign.end;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        // Alignment — centered segmented pill. No icon-prefix
        // row, no "Align" duplicate label: the three glyphs ARE
        // the affordance, the section is self-explanatory. Cuts
        // ~38dp of vertical chrome vs the old `_SegmentToggleRow`.
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
        const SizedBox(height: 14),
        // No "SPACING" header — the two rows below are the only
        // remaining group on the panel, so a section label is
        // pure ceremony. Each row's leading icon disambiguates
        // line-height vs letter-spacing at a glance.
        _LayoutSliderCard(
          icon: Icons.format_line_spacing_rounded,
          label: context.l10n.lineHeightLabel,
          value: style.lineHeight,
          format: (v) => v.toStringAsFixed(2),
          presets: [
            (label: context.l10n.tightOption, value: 1.0),
            (label: context.l10n.normalOption, value: 1.25),
            (label: context.l10n.relaxedOption, value: 1.6),
            (label: context.l10n.looseOption, value: 2.0),
          ],
          min: 0.8,
          max: 3.0,
          expanded: _openId == 'lineHeight',
          onExpandedChanged: (v) => _setOpen('lineHeight', v),
          onChange: ctrl.setLineHeight,
        ),
        _LayoutSliderCard(
          icon: Icons.space_bar_rounded,
          label: context.l10n.letterSpacingLabel,
          value: style.letterSpacing,
          format: (v) => v.toStringAsFixed(1),
          presets: [
            (label: context.l10n.tightOption, value: -0.5),
            (label: context.l10n.normalOption, value: 0.0),
            (label: context.l10n.wideOption, value: 1.5),
            (label: context.l10n.looseOption, value: 4.0),
          ],
          min: -5,
          max: 20,
          expanded: _openId == 'letterSpacing',
          onExpandedChanged: (v) => _setOpen('letterSpacing', v),
          onChange: ctrl.setLetterSpacing,
        ),
      ],
    );
  }
}

/// Compact centered alignment picker — three icon buttons in a
/// soft pill. Replaces the wider `_SegmentToggleRow` (icon +
/// label + control) on the Layout panel: removes the redundant
/// "Align" label and the leading prefix icon, cuts ~38dp of
/// vertical chrome, and keeps the affordance unmistakable.
///
/// Selected state matches the rest of the editor's pilot grammar
/// (primary @ 14% fill + 45% border) so users don't relearn.
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleSegment(
            icon: Icons.format_align_left_rounded,
            selected: isLeft,
            onTap: onLeft,
          ),
          _ToggleSegment(
            icon: Icons.format_align_center_rounded,
            selected: isCenter,
            onTap: onCenter,
          ),
          _ToggleSegment(
            icon: Icons.format_align_right_rounded,
            selected: isRight,
            onTap: onRight,
          ),
        ],
      ),
    );
  }
}

/// Flat row used by the Layout panel for both Line height and
/// Letter spacing. Editor-feel (no card / shadow / border):
///   * Tap the header row anywhere to expand the inline slider.
///   * Preset chips sit directly below the header — they are the
///     primary affordance, the slider is secondary.
///   * Parent owns expand state so only one row is open at a time.
class _LayoutSliderCard extends ConsumerStatefulWidget {
  const _LayoutSliderCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.format,
    required this.presets,
    required this.min,
    required this.max,
    required this.expanded,
    required this.onExpandedChanged,
    required this.onChange,
  });

  /// Leading glyph that disambiguates the row at a glance — line
  /// height vs letter spacing read identically without it.
  final IconData icon;
  final String label;
  final double value;
  final String Function(double) format;
  final List<_LayoutPreset> presets;
  final double min;
  final double max;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;
  final ValueChanged<double> onChange;

  @override
  ConsumerState<_LayoutSliderCard> createState() => _LayoutSliderCardState();
}

class _LayoutSliderCardState extends ConsumerState<_LayoutSliderCard> {
  bool _dragInFlight = false;
  double? _lastTickValue;

  void _set(double v) {
    final clamped = v.clamp(widget.min, widget.max).toDouble();
    widget.onChange(clamped);
  }

  void _maybeTick(double v) {
    final span = widget.max - widget.min;
    if (span <= 0) return;
    final step = span / 20.0;
    final last = _lastTickValue;
    if (last == null || (v - last).abs() >= step) {
      _lastTickValue = v;
      EditorHaptics.snap();
    }
  }

  void _endDrag() {
    if (!_dragInFlight) return;
    _dragInFlight = false;
    _lastTickValue = null;
    ref.read(textToolControllerProvider.notifier).endStyleDrag();
  }

  int _selectedPresetIndex() {
    for (var i = 0; i < widget.presets.length; i++) {
      if ((widget.presets[i].value - widget.value).abs() < 0.001) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final clampedValue = widget.value.clamp(widget.min, widget.max).toDouble();
    final selectedIndex = _selectedPresetIndex();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Whole header row is tappable — no card, no border, no
        // shadow. Editor-feel: looks like a list row, not a setting.
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              EditorHaptics.tap();
              widget.onExpandedChanged(!widget.expanded);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    widget.icon,
                    size: 18,
                    color: widget.expanded ? scheme.primary : muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  // Value + chevron grouped into a small pill so
                  // the trailing affordance reads as one tap target,
                  // not a stray number next to a stray arrow. Pill
                  // tints when the row is expanded for clear state.
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: widget.expanded
                          ? scheme.primary.withValues(alpha: 0.1)
                          : scheme.surfaceContainerHighest.withValues(
                              alpha: 0.5,
                            ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.format(clampedValue),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: widget.expanded ? scheme.primary : muted,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 2),
                        AnimatedRotation(
                          turns: widget.expanded ? 0.25 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: widget.expanded ? scheme.primary : muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Always-visible preset chips — primary UI.
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < widget.presets.length; i++)
                _LayoutPresetChip(
                  label: widget.presets[i].label,
                  selected: i == selectedIndex,
                  onTap: () => _set(widget.presets[i].value),
                ),
            ],
          ),
        ),
        // Inline secondary slider, subtle visual weight.
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: widget.expanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                    ),
                    child: Listener(
                      onPointerCancel: (_) => _endDrag(),
                      child: Slider(
                        value: clampedValue,
                        min: widget.min,
                        max: widget.max,
                        onChangeStart: (v) {
                          _dragInFlight = true;
                          _lastTickValue = v;
                          EditorHaptics.toggle();
                          ref
                              .read(textToolControllerProvider.notifier)
                              .beginStyleDrag();
                        },
                        onChanged: (v) {
                          _set(v);
                          _maybeTick(v);
                        },
                        onChangeEnd: (_) {
                          if (!_dragInFlight) return;
                          EditorHaptics.confirm();
                          _endDrag();
                        },
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Compact 3-button segmented control. Used as the inner row of
/// `_AlignmentSegmentedControl` (Layout panel). Each segment is a
/// 36×32 pill with a primary-tint selected state.
///
/// **Editor toggle rule (paint + text):**
///   * Single on/off feature → `_CompactRow` + trailing
///     `Switch.adaptive` (paint Fill, text Background, Border,
///     Shadow).
///   * Tightly-grouped triple of related toggles → group
///     `_ToggleSegment`s inside a tinted pill (alignment).
/// Same rule across both modes. Picking the affordance based on
/// "single vs grouped" is what makes the chrome predictable.
class _ToggleSegment extends StatelessWidget {
  const _ToggleSegment({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected
            ? scheme.primary.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected
              ? scheme.primary.withValues(alpha: 0.45)
              : Colors.transparent,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            EditorHaptics.toggle();
            onTap();
          },
          child: SizedBox(
            width: 36,
            height: 32,
            child: Center(
              child: Icon(
                icon,
                size: 18,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
