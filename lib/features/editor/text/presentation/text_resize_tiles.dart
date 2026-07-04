// Resize sheet tiles for the text-mode toolbar, split out of
// text_mode_toolbar.dart. Part file: every symbol resolves via the
// library root's imports — add imports there, never here.
part of 'text_mode_toolbar.dart';

/// Inline two-option tile used by the Resize sheet. Replaces the
/// prior modal dialog so the user sees both choices and the active
/// selection without an extra hop. Same visual grammar as the
/// dialog's `option()` builder it superseded — primary tint + ring
/// when selected, trailing checkmark, hint subtitle in the muted
/// tone. Selected option lifts on a subtle 1.02 scale + soft glow
/// so the choice feels physical, not flat.
class _ResizeOptionTile extends StatelessWidget {
  const _ResizeOptionTile({
    required this.icon,
    required this.title,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          EditorHaptics.snap();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              // Leading radio: primary-tinted ring + filled dot when
              // selected, plain outline otherwise. Cheaper than the
              // old check-switch and reads as a single-pick group.
              _RadioDot(selected: selected),
              const SizedBox(width: 12),
              Icon(
                icon,
                size: 18,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: selected ? scheme.primary : scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      hint,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact radio dot used by [_ResizeOptionTile]. Plain outline ring
/// in the resting state; primary-tinted ring + filled inner dot when
/// selected. Sized to read at a glance without dominating the row.
class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: 0.7),
          width: selected ? 2 : 1.2,
        ),
      ),
      alignment: Alignment.center,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        scale: selected ? 1 : 0,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.primary,
          ),
        ),
      ),
    );
  }
}
