import 'package:flutter/widgets.dart';

import 'mode_id.dart';
import 'toolbar_slot.dart';

/// Declarative description of a single editor mode (paint, text,
/// crop, filters, …).
///
/// Phase 1 declares the type only; the registry that holds concrete
/// `EditorMode` literals lands in a later phase together with the
/// migration of paint/text mode toolbars.
@immutable
class EditorMode {
  const EditorMode({
    required this.id,
    required this.icon,
    required this.label,
    required this.slots,
  });

  final ModeId id;
  final IconData icon;
  final String label;

  /// Slots in priority order (most-used first). Right-handed users
  /// see this list reversed at render time so high-priority slots
  /// sit closest to the right thumb.
  final List<ToolbarSlot> slots;
}
