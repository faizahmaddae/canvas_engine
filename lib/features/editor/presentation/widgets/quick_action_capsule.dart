import 'package:flutter/material.dart';

import '../../../../core/utils/haptics.dart';

/// Shared, mode-agnostic dock content for the **Adaptive Dock**
/// (Option E). Renders a fixed-height capsule with three slots
/// (identity / color / tertiary), an exit chip on the left and a
/// "More" chip on the right.
///
/// ```
/// ┌─────────────────────────────────────────────────────────┐
/// │  ✕    ⟦slot1⟧   ⟦slot2⟧   ⟦slot3⟧             ⌄ / ⋯   │  80 dp
/// └─────────────────────────────────────────────────────────┘
/// ```
///
/// The capsule itself is mode-agnostic: text mode passes a font
/// pill / color dot / B-I-U triplet, paint mode passes a tool pill
/// / color dot / size pill. Slots are styled identically so muscle
/// memory transfers across modes.
///
/// Two expansion levels exist in Option E and the capsule renders
/// **neither** itself — both must be hosted by the parent through
/// the dock's `expanded` slot to avoid clipping inside the dock's
/// fixed-height chip strip:
///   * **Inline expansion** — small row above the capsule for
///     swatches / sliders / sub-tool pickers. Wrap your widget in
///     [QuickActionCapsule.inlineExpansion] before passing it to
///     the dock's `expanded` slot so it shares the capsule's
///     padding and styling.
///   * **Full panel** — tabbed panel hosted directly by the dock.
///     The capsule simply marks `moreActive: true` while it is
///     open and swaps the More icon to a collapse arrow.
class QuickActionCapsule extends StatelessWidget {
  const QuickActionCapsule({
    super.key,
    required this.onExit,
    required this.slots,
    this.onMore,
    this.moreActive = false,
    this.dimmed = false,
  }) : assert(slots.length <= 4, 'Capsule supports up to 4 slots');

  /// Wraps an [inlineExpansion] widget in the capsule's standard
  /// padding so it can be passed as the dock's `expanded` slot
  /// and visually align with the capsule below.
  static Widget inlineExpansion(Widget child) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: SizedBox(width: double.infinity, child: child),
    );
  }

  /// Pops the user out of the current mode (Done / Back).
  final VoidCallback onExit;

  /// Quick-action slots. Order is significant — left-to-right.
  /// Recommended set: [identity, color, tertiary]. A fourth slot
  /// is allowed but pushes the capsule toward the edge of the
  /// thumb zone, so prefer ⋯ More for the overflow.
  final List<QuickActionSlot> slots;

  /// Tap handler for the right-edge More button. When `null` the
  /// More button is hidden entirely.
  final VoidCallback? onMore;

  /// True while the parent's full panel expansion is showing.
  /// Swaps the More icon to a collapse-down arrow and tints it.
  final bool moreActive;

  /// Renders the capsule at reduced opacity and disables hit
  /// testing — used while the user is actively drawing on the
  /// canvas to avoid accidental tool changes mid-stroke.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 140),
      opacity: dimmed ? 0.55 : 1.0,
      child: IgnorePointer(
        ignoring: dimmed,
        child: SizedBox(
          height: 80,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 12,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _CapsuleIconChip(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Done',
                  onTap: onExit,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Center(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final slot in slots)
                          _SlotButton(slot: slot, scheme: scheme),
                      ],
                    ),
                  ),
                ),
                if (onMore != null) ...[
                  const SizedBox(width: 8),
                  _CapsuleIconChip(
                    icon: moreActive
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.more_horiz_rounded,
                    tooltip: moreActive ? 'Collapse' : 'More options',
                    onTap: onMore!,
                    active: moreActive,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One quick-action slot inside [QuickActionCapsule].
///
/// Supply [child] for fully custom content (e.g. a font-name pill
/// with a typeface preview, a color dot with a hex label, a B/I/U
/// segmented control). The capsule wraps it in a tappable surface
/// with the shared selected/disabled visuals so all slots feel
/// like one family.
@immutable
class QuickActionSlot {
  const QuickActionSlot({
    required this.id,
    required this.tooltip,
    required this.child,
    this.onTap,
    this.active = false,
  });

  /// Stable identifier — used as the inline-expansion key by
  /// callers, so switching from the color slot to the size slot
  /// triggers a cross-fade rather than an in-place rebuild.
  final String id;

  /// Tooltip shown on long-press. Required because slot contents
  /// are typically icon-only (color dot, size dot) and need a
  /// label for accessibility.
  final String tooltip;

  /// Slot content. Should be a compact pill ≤ 56 dp tall.
  final Widget child;

  /// Tap handler. `null` disables the slot (greyed out).
  final VoidCallback? onTap;

  /// Highlighted when the slot's inline expansion is open. The
  /// parent owns this state so it can drive the capsule's
  /// `inlineExpansion`.
  final bool active;
}

// ─────────────────────────────────────────────────────────────────
// Internals
// ─────────────────────────────────────────────────────────────────

class _SlotButton extends StatelessWidget {
  const _SlotButton({required this.slot, required this.scheme});

  final QuickActionSlot slot;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final disabled = slot.onTap == null;
    final fill = slot.active
        ? scheme.primary.withValues(alpha: 0.12)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.55);
    final border = slot.active
        ? scheme.primary.withValues(alpha: 0.35)
        : scheme.outlineVariant.withValues(alpha: 0.4);

    return Tooltip(
      message: slot.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Opacity(
        opacity: disabled ? 0.4 : 1.0,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: slot.onTap == null
                ? null
                : () {
                    EditorHaptics.tap();
                    slot.onTap!();
                  },
            borderRadius: BorderRadius.circular(20),
            splashColor: scheme.primary.withValues(alpha: 0.10),
            highlightColor: scheme.primary.withValues(alpha: 0.05),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              constraints: const BoxConstraints(
                minHeight: 40,
                minWidth: 40,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: border, width: 1),
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: slot.active
                      ? scheme.primary
                      : scheme.onSurface,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                  fontSize: 13,
                ),
                child: IconTheme.merge(
                  data: IconThemeData(
                    color: slot.active
                        ? scheme.primary
                        : scheme.onSurface,
                    size: 18,
                  ),
                  child: slot.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CapsuleIconChip extends StatelessWidget {
  const _CapsuleIconChip({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = active
        ? scheme.primary.withValues(alpha: 0.12)
        : Colors.transparent;
    final border = active
        ? scheme.primary.withValues(alpha: 0.35)
        : scheme.outlineVariant.withValues(alpha: 0.4);
    final btn = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          EditorHaptics.tap();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        splashColor: scheme.primary.withValues(alpha: 0.10),
        highlightColor: scheme.primary.withValues(alpha: 0.05),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: 1),
          ),
          child: Icon(
            icon,
            size: 20,
            color: active ? scheme.primary : scheme.onSurface,
          ),
        ),
      ),
    );
    return tooltip == null
        ? btn
        : Tooltip(
            message: tooltip!,
            waitDuration: const Duration(milliseconds: 400),
            child: btn,
          );
  }
}
