import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Editor-wide MRU store of colours the user has picked from
/// `showColorPickerSheet` across **any** colour panel — Text,
/// Shape, Image, Canvas, Paint.
///
/// Exists because colour panels used to each carry their own
/// recents (or none at all): Text & Paint persisted recents in
/// their tool controllers, Shape / Image / Canvas threw the
/// picked colour away. Result: "Recent" only appeared in Text /
/// Paint, and a custom colour you just dialled in for Shape Fill
/// did not surface when you reopened the panel.
///
/// Centralising means:
///   * Custom picks made in any panel persist for all panels.
///   * The "Recent" row in `InlineColorBody` is fed by one source
///     of truth, so its visibility rules behave the same
///     everywhere.
///
/// Behaviour mirrors the original per-controller implementations:
///   * Dedupe by full ARGB (alpha matters — a faded red and an
///     opaque red are intentionally different recents).
///   * Most-recent-first.
///   * Hard cap of [_cap] entries.
///   * Presets / palette swatches are *not* added; the caller
///     only invokes [remember] from the custom-picker flow.
class RecentColorsController extends Notifier<List<Color>> {
  static const int _cap = 8;

  @override
  List<Color> build() => const <Color>[];

  /// Record a colour the user picked from the custom picker.
  /// Idempotent across re-picks of the same ARGB value (just
  /// promotes to most-recent).
  void remember(Color color) {
    final argb = color.toARGB32();
    final next = <Color>[
      color,
      for (final c in state)
        if (c.toARGB32() != argb) c,
    ];
    if (next.length > _cap) {
      next.removeRange(_cap, next.length);
    }
    state = List<Color>.unmodifiable(next);
  }
}

/// Editor-wide recent colours. Non-autoDispose by design — the
/// list outlives any single panel so re-opening a tool restores
/// the user's history.
final recentColorsControllerProvider =
    NotifierProvider<RecentColorsController, List<Color>>(
  RecentColorsController.new,
);
