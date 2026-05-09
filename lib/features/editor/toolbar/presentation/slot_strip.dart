import 'package:flutter/material.dart';

import '../../../../core/utils/haptics.dart';
import '../../presentation/widgets/dock_tool_strip.dart';
import '../../presentation/widgets/dock_tool_tile.dart';
import '../domain/toolbar_slot.dart';

/// Renders a list of [ToolbarSlot]s as a horizontally scrollable
/// strip of [DockToolTile]s inside a [DockToolStrip].
///
/// This is the **shared toolbar strip** for the editor. Every mode
/// — current and future — should render its tiles through this
/// widget so visual chrome (edge fades, compact behavior, active
/// state, haptics) stays consistent across modes.
///
/// Phase 1 wires this into the main toolbar only. Paint and text
/// mode toolbars keep their existing strips for now and migrate
/// onto [SlotStrip] in later phases without changing this widget.
class SlotStrip extends StatefulWidget {
  const SlotStrip({
    super.key,
    required this.slots,
    this.activeId,
    this.controller,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.centerWhenFits = true,
    this.fitAlignment = MainAxisAlignment.center,
  });

  /// When true, if the slots fit in the viewport they are aligned
  /// per [fitAlignment]. Useful for short toolbars (e.g. Sticker's
  /// 3-tab strip) so the tiles don't cling to the leading edge.
  final bool centerWhenFits;

  /// Alignment used when [centerWhenFits] applies. Defaults to
  /// center; pass [MainAxisAlignment.end] for a right-handed dock.
  /// The slot order itself must remain stable across handedness —
  /// callers must not reverse [slots].
  final MainAxisAlignment fitAlignment;

  /// Slots in render order (left → right). Order must be stable
  /// regardless of left/right handed mode — handedness only shifts
  /// alignment via [fitAlignment], never the sequence of tools.
  final List<ToolbarSlot> slots;

  /// Id of the slot that should appear active. `null` for none.
  final String? activeId;

  /// Optional external scroll controller. When omitted the strip
  /// owns its own controller for the lifetime of the state.
  final ScrollController? controller;

  final EdgeInsets padding;

  @override
  State<SlotStrip> createState() => _SlotStripState();
}

class _SlotStripState extends State<SlotStrip> {
  ScrollController? _ownController;

  ScrollController get _controller =>
      widget.controller ?? (_ownController ??= ScrollController());

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.shortestSide < 380 ||
        media.orientation == Orientation.landscape;
    final scheme = Theme.of(context).colorScheme;

    final children = <Widget>[];
    SlotTier? prevTier;
    for (final slot in widget.slots) {
      // Insert a hairline group divider whenever consecutive slots
      // belong to different tiers. The grouping is data-driven so
      // reorders can't drift the divider position.
      if (prevTier != null && slot.tier != prevTier) {
        children.add(_TierDivider(scheme: scheme));
      }
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: DockToolTile(
            icon: slot.icon,
            label: slot.label,
            valueText: slot.valueLabel?.call(),
            enabled: slot.isEnabled,
            active: slot.id == widget.activeId,
            compact: compact,
            onTap: () {
              EditorHaptics.tap();
              slot.onTap();
            },
          ),
        ),
      );
      prevTier = slot.tier;
    }

    return DockToolStrip(
      controller: _controller,
      padding: widget.padding,
      centerWhenFits: widget.centerWhenFits,
      fitAlignment: widget.fitAlignment,
      children: children,
    );
  }
}

/// Thin vertical hairline that separates two tiers in [SlotStrip].
/// Visually consistent with `_TierGap` in text/paint toolbars
/// (13dp wide gutter, 28dp tall 1dp hairline at outlineVariant α
/// 0.45) so the entire editor feels like one design system.
class _TierDivider extends StatelessWidget {
  const _TierDivider({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 13,
      child: Center(
        child: Container(
          width: 1,
          height: 28,
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}
