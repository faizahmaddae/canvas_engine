import 'package:flutter/foundation.dart';

/// Reusable prev/next walker for slot-based panels.
///
/// Both the controller-driven panels (Image, Shape, …) and the
/// `SubToolSheet` host (Text, Paint) need the same behaviour: from
/// the currently open slot, jump to the next or previous **panel**
/// in the strip, wrap around at the ends, and skip slots that
/// don't open a panel.
///
/// Centralising the walk here removes the duplicated `_shiftSlot`
/// logic in the per-mode controllers and makes "what does swipe
/// do?" answerable in one place.
@immutable
class SiblingSwipeStrategy<T> {
  const SiblingSwipeStrategy({required this.order, this.excluded = const {}});

  /// Canonical left→right order driving sibling navigation.
  final List<T> order;

  /// Slots present in [order] but skipped during prev/next walks.
  /// Empty by default; populate per-feature when a slot stays in
  /// the strip but should not be reachable by swipe.
  final Set<T> excluded;

  /// Slot to jump to when the user swipes "forward". Returns
  /// `null` when no jump is possible (current is null, current is
  /// not in [order], or every slot is excluded).
  T? next(T? current) => _shift(current, 1);

  /// Slot to jump to when the user swipes "backward".
  T? prev(T? current) => _shift(current, -1);

  T? _shift(T? current, int delta) {
    if (current == null) return null;
    final i = order.indexOf(current);
    if (i < 0) return null;
    final n = order.length;
    if (n == 0) return null;
    // Count of reachable (non-excluded, non-current) candidates —
    // used to distinguish "single-slot list, swipe is a legit
    // no-op" from "every slot is excluded, contract violation".
    final reachable = order
        .where((e) => e != current && !excluded.contains(e))
        .length;
    if (reachable == 0) {
      assert(
        order.length <= 1,
        'SiblingSwipeStrategy: no reachable sibling — every slot in '
        'order ($n) is excluded.',
      );
      return null;
    }
    // Walk in [delta] direction, skipping excluded slots. Bounded
    // by [n] iterations to guarantee termination.
    for (var step = 1; step <= n; step++) {
      final candidate = order[(i + delta * step) % n];
      if (candidate == current) continue;
      if (excluded.contains(candidate)) continue;
      return candidate;
    }
    return null;
  }
}
