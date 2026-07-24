import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../toolbar/application/dock_tool_controller.dart';

/// Every chip in `StickerModeToolbar`, in left→right strip order.
///
/// Sticker intentionally opts out of sibling-swipe (only three
/// slots, the chip strip is faster than swipe and the mis-swipe
/// cost is high), so the provider passes no `SiblingSwipeStrategy`
/// and every value is panel-bearing.
enum StickerToolSlot {
  style,
  size,
  replace;

  /// Safe lookup by enum name; returns `null` for unknown / null
  /// strings. Provided for boundaries that still receive untyped
  /// slot ids (e.g. snapshot restoration).
  static StickerToolSlot? tryByName(String? name) {
    if (name == null) return null;
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// Single source of truth for the Sticker strip: every chip, in
/// rendered left→right order. `StickerModeToolbar` builds its chips
/// by iterating THIS list. Sticker has no swipe walk (see above) —
/// the list still exists so the strip shares the same single-source
/// grammar as Image/Shape.
const List<DockStripEntry<StickerToolSlot>> kStickerStripOrder =
    <DockStripEntry<StickerToolSlot>>[
      DockStripEntry.slot(StickerToolSlot.style),
      DockStripEntry.slot(StickerToolSlot.size),
      DockStripEntry.slot(StickerToolSlot.replace),
    ];

/// Display order of every Sticker chip — the [kStickerStripOrder]
/// projection.
final List<StickerToolSlot> kStickerStripSlotOrder = List.unmodifiable(
  kStickerStripOrder.map((e) => e.slot).whereType<StickerToolSlot>(),
);

/// In-dock state for the Sticker sub-tool — see [DockToolSession].
/// Mirrors Image/Shape one-for-one so the dock plumbing in
/// `editor_screen.dart` can treat all three modes the same way.
typedef StickerToolSession = DockToolSession<StickerToolSlot>;

final stickerToolControllerProvider =
    NotifierProvider<DockToolController<StickerToolSlot>, StickerToolSession>(
      // No swipe strategy: openPrevSlot/openNextSlot are no-ops —
      // the sticker dock's swipe opt-out.
      DockToolController<StickerToolSlot>.new,
    );
