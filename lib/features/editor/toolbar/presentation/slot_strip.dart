import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/haptics.dart';
import '../../presentation/widgets/dock_tool_strip.dart';
import '../../presentation/widgets/dock_tool_tile.dart';
import '../../presentation/widgets/editor_breakpoints.dart';
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

  /// Horizontal padding wrapped around EACH tile, per side. With the
  /// tile's own 1px internal chrome this yields the unified 70dp
  /// per-tile footprint every strip shares (tb2 16/16 — the Stage-1
  /// `tileGap` escape hatch that let text/paint keep their historical
  /// 68dp extents is retired).
  static const double _tileGap = 1;

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

  /// Resolves the right-handed dock preference to a **physical**
  /// [fitAlignment]. "Right-handed" means the user's right thumb —
  /// a physical fact — while `MainAxisAlignment.end` resolves
  /// logically inside the row, which under RTL put the tools on the
  /// physical LEFT (the pre-17/17 bug pinned by
  /// rtl_strip_pins_test). Under RTL the physical right edge is the
  /// row's logical *start*. Single resolution point for every strip
  /// that honors the setting; tool ORDER is never touched.
  static MainAxisAlignment handedFitAlignment(
    BuildContext context, {
    required bool rightHanded,
  }) {
    if (!rightHanded) return MainAxisAlignment.center;
    return Directionality.of(context) == TextDirection.rtl
        ? MainAxisAlignment.start
        : MainAxisAlignment.end;
  }

  @override
  State<SlotStrip> createState() => _SlotStripState();
}

class _SlotStripState extends State<SlotStrip> {
  ScrollController? _ownController;

  ScrollController get _controller =>
      widget.controller ?? (_ownController ??= ScrollController());

  @override
  void didUpdateWidget(SlotStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sibling-swipe (and any programmatic activation) can move the
    // active slot to a tile that is scrolled out of view; without
    // this, an 11-tile strip loses its highlight off-screen after a
    // few swipes. Mirrors the auto-scroll paint/text always had.
    if (widget.activeId != null && widget.activeId != oldWidget.activeId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureActiveVisible();
      });
    }
  }

  void _ensureActiveVisible() {
    final index = widget.slots.indexWhere((s) => s.id == widget.activeId);
    if (index < 0 || !_controller.hasClients) return;
    final position = _controller.position;
    if (position.maxScrollExtent <= 0) return;
    final compact = EditorBreakpoints.isCompact(context);
    // Tile card + its 1px-per-side internal chrome + this strip's
    // per-tile gap — the real 70dp footprint (the old hardcoded
    // `+ 2` undershot it by 2dp per tile).
    final tileExtent =
        (compact ? kDockToolTileWidthCompact : kDockToolTileWidth) +
        2 +
        2 * SlotStrip._tileGap;
    // Tier dividers occupy their own extent before the target tile.
    var dividersBefore = 0;
    for (var i = 1; i <= index; i++) {
      if (widget.slots[i].tier != widget.slots[i - 1].tier) dividersBefore++;
    }
    final tileStart =
        widget.padding.horizontal / 2 +
        index * tileExtent +
        dividersBefore * 20.0;
    final viewport = position.viewportDimension;
    final target = (tileStart - (viewport - tileExtent) / 2).clamp(
      0.0,
      position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = EditorBreakpoints.isCompact(context);

    final children = <Widget>[];
    SlotTier? prevTier;
    for (final slot in widget.slots) {
      // Insert a hairline group divider whenever consecutive slots
      // belong to different tiers. The grouping is data-driven so
      // reorders can't drift the divider position.
      if (prevTier != null && slot.tier != prevTier) {
        children.add(const _TierDivider());
      }
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SlotStrip._tileGap),
          child: DockToolTile(
            icon: slot.icon,
            label: slot.label,
            valueText: slot.valueLabel?.call(),
            swatchColor: slot.swatchColor?.call(),
            fontFamily: slot.fontFamily?.call(),
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

/// Thin vertical hairline that separates two tiers in [SlotStrip]:
/// 20dp gutter, 1×30 hairline at the border token α 0.7, so the
/// divider reads as an INTENTIONAL group boundary (add-tools vs
/// edit-tools), not an accidental gap between tiles. This is the
/// single tier divider now — the standalone `EditorTierGap` copy
/// retired with the paint strip migration (tb1 14/17); its only
/// delta was a sub-pixel 0.5 corner radius on the hairline, dropped
/// here so the byte-gated main-toolbar captures stay untouched.
class _TierDivider extends StatelessWidget {
  const _TierDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      child: Center(
        child: Container(
          width: 1,
          height: 30,
          color: AppTokens.of(context).border.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
