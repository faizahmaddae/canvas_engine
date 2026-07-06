// Layout sub-tool panel for the text-mode toolbar, split out of
// text_mode_toolbar.dart. Part file: every symbol resolves via the
// library root's imports — add imports there, never here.
part of 'text_mode_toolbar.dart';

// ─── Layout panel (mobile-first redesign) ───────────────────────────
//
// Owns the "which precision slider is open" state so opening one
// closes the other (spec: only one slider expanded at a time).

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
        LayoutSliderCard(
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
        LayoutSliderCard(
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
/// (accent @ 14% fill + 45% border) so users don't relearn.
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
    return Container(
      decoration: BoxDecoration(
        color: AppTokens.of(context).surfaceMuted.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
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
      ),
    );
  }
}

