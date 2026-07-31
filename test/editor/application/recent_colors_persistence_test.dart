// RecentColorsController persistence contract: recents survive app
// restarts via one SharedPreferences string-list (ARGB ints,
// most-recent-first), malformed entries self-heal to "dropped",
// and the in-memory MRU semantics (dedupe by full ARGB, cap 8) are
// unchanged.

import 'dart:ui' show Color;

import 'package:canvas_engine/features/editor/application/recent_colors_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The controller hydrates from prefs in a microtask kicked off by
/// build(); a couple of event-loop turns lets getInstance + the
/// list parse land.
Future<void> _settleHydration() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('remember() writes the MRU list to SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final store = container.read(recentColorsControllerProvider.notifier);
    store.remember(const Color(0xFF111111));
    store.remember(const Color(0x80FF0000));
    await _settleHydration();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(RecentColorsController.prefsKey), [
      const Color(0x80FF0000).toARGB32().toString(),
      const Color(0xFF111111).toARGB32().toString(),
    ]);
  });

  test('a fresh container hydrates persisted recents in order', () async {
    SharedPreferences.setMockInitialValues({
      RecentColorsController.prefsKey: [
        const Color(0x80FF0000).toARGB32().toString(),
        const Color(0xFF123456).toARGB32().toString(),
      ],
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Trigger build(), then let the async hydration land.
    expect(container.read(recentColorsControllerProvider), isEmpty);
    await _settleHydration();

    expect(container.read(recentColorsControllerProvider), const [
      Color(0x80FF0000),
      Color(0xFF123456),
    ]);
  });

  test('malformed entries are dropped, valid ones kept', () async {
    SharedPreferences.setMockInitialValues({
      RecentColorsController.prefsKey: [
        'not-a-number',
        const Color(0xFF123456).toARGB32().toString(),
        '',
      ],
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(recentColorsControllerProvider);
    await _settleHydration();

    expect(container.read(recentColorsControllerProvider), const [
      Color(0xFF123456),
    ]);
  });

  test('in-session picks made before hydration stay most-recent', () async {
    SharedPreferences.setMockInitialValues({
      RecentColorsController.prefsKey: [
        const Color(0xFF111111).toARGB32().toString(),
      ],
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(recentColorsControllerProvider.notifier)
        .remember(const Color(0xFF222222));
    await _settleHydration();

    expect(container.read(recentColorsControllerProvider), const [
      Color(0xFF222222),
      Color(0xFF111111),
    ]);
  });

  test('dedupes by full ARGB and caps at 6, persisted too', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final store = container.read(recentColorsControllerProvider.notifier);
    for (var i = 1; i <= 10; i++) {
      store.remember(Color(0xFF000000 + i));
    }
    // Re-pick an existing colour — promotes, no duplicate.
    store.remember(const Color(0xFF000009));
    await _settleHydration();

    final state = container.read(recentColorsControllerProvider);
    // 6, not 8: the cap matches the picker shelf's reserved first
    // row, so the store can never hold a colour the user cannot see.
    expect(state, hasLength(6));
    expect(state.first, const Color(0xFF000009));
    expect(state.map((c) => c.toARGB32()).toSet(), hasLength(6));

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList(RecentColorsController.prefsKey),
      state.map((c) => c.toARGB32().toString()).toList(),
    );
  });
}
