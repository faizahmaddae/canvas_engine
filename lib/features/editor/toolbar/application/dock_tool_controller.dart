import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/sibling_swipe_strategy.dart';

/// Snapshot of the in-dock state for a slot-strip mode (Image /
/// Shape / Sticker). The selected layer is owned by the document/
/// selection controllers — this state only tracks which sub-tab is
/// currently expanded above the strip.
@immutable
class DockToolSession<T> {
  const DockToolSession({this.openSlot});

  /// Currently expanded panel, or `null` when only the chip strip
  /// is visible.
  final T? openSlot;

  DockToolSession<T> copyWith({T? openSlot, bool clearOpenSlot = false}) {
    return DockToolSession<T>(
      openSlot: clearOpenSlot ? null : (openSlot ?? this.openSlot),
    );
  }
}

/// One rendered chip in a mode's strip, in display order: either a
/// dock [slot] (an entry of the mode's slot enum — panel-bearing or
/// one-shot) or a strip-only [DockStripEntry.action] chip that lives
/// outside the slot enum entirely (e.g. `'opacity'` → the
/// ContextToolPanel host, `'more'` → the actions sheet).
///
/// Modes declare ONE ordered `List<DockStripEntry<T>>` in their
/// application layer. The mode toolbar renders its chips by
/// iterating that list, and the sibling-swipe order is derived from
/// the same list (panel-bearing slots, in list order) — a single
/// source, so the strip order and the swipe order cannot drift.
@immutable
class DockStripEntry<T> {
  const DockStripEntry.slot(T this.slot) : actionId = null;
  const DockStripEntry.action(String this.actionId) : slot = null;

  /// The dock slot this chip drives, or `null` for action chips.
  final T? slot;

  /// Stable id of a strip-only action chip, or `null` for slots.
  final String? actionId;
}

/// Generic single-open-slot controller shared by the slot-strip
/// dock modes (Image / Shape / Sticker). Exactly one panel can be
/// expanded at a time:
///
///   * [toggleSlot] — re-tapping the open slot closes it; tapping a
///     different slot switches to it. Mirrors the text-tool sheet
///     toggle so users can dismiss a panel by re-tapping its tab.
///   * [closePanel] — idempotent close.
///   * [openPrevSlot] / [openNextSlot] — sibling-swipe navigation
///     through the mode's [SiblingSwipeStrategy]; wraps at the ends
///     and is a no-op when nothing is open. A mode passes no
///     strategy to opt out of swipe entirely (Sticker: only three
///     slots, the chip strip is faster than swipe and the mis-swipe
///     cost is high) — the two methods are then no-ops.
class DockToolController<T> extends Notifier<DockToolSession<T>> {
  DockToolController({SiblingSwipeStrategy<T>? swipe}) : _swipe = swipe;

  final SiblingSwipeStrategy<T>? _swipe;

  @override
  DockToolSession<T> build() => DockToolSession<T>();

  /// Toggle [slot] — if it's already open, close it; otherwise
  /// switch to it.
  void toggleSlot(T slot) {
    if (state.openSlot == slot) {
      state = state.copyWith(clearOpenSlot: true);
    } else {
      state = state.copyWith(openSlot: slot);
    }
  }

  /// Close whatever panel is open. Idempotent.
  void closePanel() {
    if (state.openSlot == null) return;
    state = state.copyWith(clearOpenSlot: true);
  }

  /// Open the slot before the current one in the swipe order.
  /// Wraps. No-op when no slot is open or the mode opts out of
  /// swipe.
  void openPrevSlot() {
    final next = _swipe?.prev(state.openSlot);
    if (next != null) state = state.copyWith(openSlot: next);
  }

  /// Open the slot after the current one in the swipe order.
  /// Wraps. No-op when no slot is open or the mode opts out of
  /// swipe.
  void openNextSlot() {
    final next = _swipe?.next(state.openSlot);
    if (next != null) state = state.copyWith(openSlot: next);
  }
}
