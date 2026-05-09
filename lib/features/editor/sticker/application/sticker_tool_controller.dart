import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every chip in `StickerModeToolbar`, in left→right strip order.
///
/// Sticker intentionally opts out of sibling-swipe (only three
/// slots, the chip strip is faster than swipe and the mis-swipe
/// cost is high), so there is no `SiblingSwipeStrategy` for this
/// mode and every value is panel-bearing.
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

/// Display order of every Sticker chip.
const List<StickerToolSlot> kStickerStripSlotOrder =
    StickerToolSlot.values;

/// Snapshot of the in-dock state for the Sticker sub-tool. The
/// selected emoji-sticker layer is owned by the document/selection
/// controllers — this state only tracks which Sticker sub-tab
/// (Style, Size, Replace) is currently expanded above the strip.
///
/// Mirrors [ImageToolSession] one-for-one so the dock plumbing in
/// `editor_screen.dart` can treat both modes the same way.
@immutable
class StickerToolSession {
  const StickerToolSession({this.openSlot});

  static const StickerToolSession initial = StickerToolSession();

  /// Currently expanded panel, or `null` when only the chip strip
  /// is visible.
  final StickerToolSlot? openSlot;

  StickerToolSession copyWith({
    StickerToolSlot? openSlot,
    bool clearOpenSlot = false,
  }) {
    return StickerToolSession(
      openSlot: clearOpenSlot ? null : (openSlot ?? this.openSlot),
    );
  }
}

class StickerToolController extends Notifier<StickerToolSession> {
  @override
  StickerToolSession build() => StickerToolSession.initial;

  void toggleSlot(StickerToolSlot slot) {
    if (state.openSlot == slot) {
      state = state.copyWith(clearOpenSlot: true);
    } else {
      state = state.copyWith(openSlot: slot);
    }
  }

  void closePanel() {
    if (state.openSlot == null) return;
    state = state.copyWith(clearOpenSlot: true);
  }
}

final stickerToolControllerProvider =
    NotifierProvider<StickerToolController, StickerToolSession>(
  StickerToolController.new,
);
