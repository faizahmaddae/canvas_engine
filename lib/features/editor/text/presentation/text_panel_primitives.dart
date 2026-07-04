// Small shared primitives used by more than one text-mode sub-tool
// panel, split out of text_mode_toolbar.dart. This cluster has
// shrunk considerably since most cross-panel primitives migrated to
// lib/features/editor/ui/ in Phase 4 Steps 2-3 — only the pieces
// still local to this file remain here. Part file: every symbol
// resolves via the library root's imports — add imports there,
// never here.
part of 'text_mode_toolbar.dart';

/// Pill chip used inside `_LayoutSliderCard` (Layout panel) and the
/// Size panel's px-preset row / `_WordChipRow`. Compact, flat — no
/// border or fill on idle so the chip strip reads as the primary
/// row, not a settings card.
class _LayoutPresetChip extends StatelessWidget {
  const _LayoutPresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.14)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected
              ? scheme.primary.withValues(alpha: 0.45)
              : Colors.transparent,
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          EditorHaptics.snap();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? scheme.primary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Hairline divider rendered above an "Adjust precisely" expanded
/// body so the appearing sliders read as a clearly-bounded new
/// block rather than a sudden vertical jump. Shared by Size,
/// Background, Border, and Shadow precision disclosures.
class _PrecisionDivider extends StatelessWidget {
  const _PrecisionDivider({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
      child: Container(
        height: 1,
        color: scheme.outlineVariant.withValues(alpha: 0.35),
      ),
    );
  }
}
