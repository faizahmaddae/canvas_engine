import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Editor-wide MRU store of colours the user has picked from the
/// shared colour picker across **any** colour surface — Text,
/// Shape, Image, Canvas, Paint.
///
/// Centralised so a custom colour dialled in for Shape Fill
/// surfaces in the Text colour panel too, and **persisted** (one
/// SharedPreferences string-list, same pattern as
/// `ProjectViewportStore`) so recents survive app restarts.
///
/// Behaviour:
///   * Dedupe by full ARGB (alpha matters — a faded red and an
///     opaque red are intentionally different recents).
///   * Most-recent-first, hard cap of [_cap] entries.
///   * The picker records the final colour itself when it closes;
///     preset swatches never reach the store because the picker
///     hides recents that duplicate its preset grid anyway.
///   * Storage is best-effort: malformed entries are dropped on
///     load, write failures are swallowed — losing a recent colour
///     is better than surfacing a prefs error mid-edit.
class RecentColorsController extends Notifier<List<Color>> {
  static const int _cap = 8;
  static const String prefsKey = 'editor.recent_colors.v1';

  @override
  List<Color> build() {
    // Hydrate asynchronously; the provider is synchronous so every
    // panel can keep reading a plain List<Color>.
    Future<void>.microtask(_hydrate);
    return const <Color>[];
  }

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(prefsKey);
      if (raw == null) return;
      final loaded = <Color>[
        for (final entry in raw)
          if (int.tryParse(entry) != null) Color(int.parse(entry)),
      ];
      if (loaded.isEmpty) return;
      // Picks made in-session before hydration landed stay in
      // front; disk entries fill the remaining slots.
      final merged = <Color>[...state];
      final seen = merged.map((c) => c.toARGB32()).toSet();
      for (final c in loaded) {
        if (seen.add(c.toARGB32())) merged.add(c);
      }
      state = List<Color>.unmodifiable(merged.take(_cap));
    } catch (_) {
      // Intentional swallow — corrupted recents self-heal to empty.
    }
  }

  /// Persist writes are chained so rapid picks can't interleave
  /// (two concurrent setStringList calls complete in undefined
  /// order — the stale one would win). Each write snapshots the
  /// CURRENT state, so intermediate writes are harmless and the
  /// last one always reflects the final list.
  Future<void> _persistChain = Future<void>.value();

  void _schedulePersist() {
    _persistChain = _persistChain.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(prefsKey, [
          for (final c in state) c.toARGB32().toString(),
        ]);
      } catch (_) {
        // Intentional swallow — see class doc.
      }
    });
  }

  /// Record a colour the user picked. Idempotent across re-picks of
  /// the same ARGB value (just promotes to most-recent).
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
    _schedulePersist();
  }
}

/// Editor-wide recent colours. Non-autoDispose by design — the
/// list outlives any single panel so re-opening a tool restores
/// the user's history.
final recentColorsControllerProvider =
    NotifierProvider<RecentColorsController, List<Color>>(
      RecentColorsController.new,
    );
