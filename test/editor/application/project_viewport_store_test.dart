import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canvas_engine/features/editor/application/project_viewport_store.dart';
import 'package:canvas_engine/features/editor/engine/core/viewport_state.dart';

/// Round-trip + degraded-input tests for [ProjectViewportStore].
/// The store's public contract is "best-effort" — corrupt entries
/// must not crash the editor; they must read as `null` so the
/// fallback auto-fit takes over silently. The store also records
/// whether the viewport is a genuine user adjustment or an automatic
/// fit, so a reopened project can re-fit vs preserve correctly.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('save then load round-trips the viewport and adjusted flag', () async {
    final store = ProjectViewportStore();
    const projectId = 'p-1';
    const v = ViewportState(scale: 2.5, translation: Offset(120, -40));
    await store.save(projectId, v, userAdjusted: true);
    final loaded = await store.load(projectId);
    expect(loaded, isNotNull);
    expect(loaded!.viewport.scale, 2.5);
    expect(loaded.viewport.translation, const Offset(120, -40));
    expect(loaded.userAdjusted, isTrue);
  });

  test('the user-adjusted flag round-trips false', () async {
    final store = ProjectViewportStore();
    await store.save(
      'p-fit',
      const ViewportState(scale: 0.4, translation: Offset(8, 8)),
      userAdjusted: false,
    );
    final loaded = await store.load('p-fit');
    expect(loaded, isNotNull);
    expect(loaded!.userAdjusted, isFalse);
    expect(loaded.viewport.scale, 0.4);
  });

  test('legacy three-field entry loads as NOT adjusted', () async {
    // Pre-flag entries were "scale|tx|ty". They must load with a valid
    // viewport but userAdjusted:false — the safe default, so a reopened
    // project re-fits rather than pinning a zoom of unknown origin.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'viewport.legacy': '3.0|10|20',
    });
    final store = ProjectViewportStore();
    final loaded = await store.load('legacy');
    expect(loaded, isNotNull);
    expect(loaded!.viewport.scale, 3.0);
    expect(loaded.viewport.translation, const Offset(10, 20));
    expect(loaded.userAdjusted, isFalse);
  });

  test('four-field entry parses the adjusted flag both ways', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'viewport.adj': '1.5|0|0|1',
      'viewport.noadj': '1.5|0|0|0',
    });
    final store = ProjectViewportStore();
    expect((await store.load('adj'))!.userAdjusted, isTrue);
    expect((await store.load('noadj'))!.userAdjusted, isFalse);
  });

  test('load returns null when no entry exists', () async {
    final store = ProjectViewportStore();
    expect(await store.load('missing'), isNull);
  });

  test('load returns null on a too-short entry', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'viewport.bad': 'not|enough',
    });
    final store = ProjectViewportStore();
    expect(await store.load('bad'), isNull);
  });

  test('load returns null when a field is non-finite', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'viewport.inf': 'inf|0|0|1',
    });
    final store = ProjectViewportStore();
    expect(await store.load('inf'), isNull);
  });

  test('clear removes the saved viewport', () async {
    final store = ProjectViewportStore();
    await store.save(
      'p',
      const ViewportState(scale: 1, translation: Offset.zero),
      userAdjusted: true,
    );
    await store.clear('p');
    expect(await store.load('p'), isNull);
  });
}
