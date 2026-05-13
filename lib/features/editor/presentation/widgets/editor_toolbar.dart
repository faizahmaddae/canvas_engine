import 'package:flutter/material.dart';

import '../../toolbar/domain/toolbar_slot.dart';
import '../../toolbar/presentation/slot_strip.dart';

/// Horizontal scrollable row of icon+label tools used as the
/// **default content** of the bottom [EditorToolDock].
///
/// Phase 1: this widget is now a thin adapter over [SlotStrip] so
/// the main toolbar shares the same renderer (DockToolStrip +
/// DockToolTile, edge fades, compact behavior, haptics) as every
/// other mode. The mode-specific paint/text toolbars migrate onto
/// [SlotStrip] in later phases.
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({super.key, required this.items, this.activeId});

  /// Tools shown in the dock (left → right).
  final List<ToolbarSlot> items;

  /// Optional id of the currently-active tool. Items whose
  /// [ToolbarSlot.id] matches receive the active visual treatment.
  final String? activeId;

  @override
  Widget build(BuildContext context) {
    return SlotStrip(slots: items, activeId: activeId);
  }
}

/// Backwards-compatible alias for callers that still use the legacy
/// `ToolbarItem` name. Prefer [ToolbarSlot] for new code — it
/// carries the extra fields (valueLabel, valueBadge, presentation,
/// tier) the system needs in later phases.
@Deprecated('Use ToolbarSlot from toolbar/domain/toolbar_slot.dart')
typedef ToolbarItem = ToolbarSlot;
