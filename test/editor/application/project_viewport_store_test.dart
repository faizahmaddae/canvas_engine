import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canvas_engine/features/editor/application/project_viewport_store.dart';
import 'package:canvas_engine/features/editor/engine/core/viewport_state.dart';

/// Round-trip + degraded-input tests for [ProjectViewportStore].
/// The store's public contract is "best-effort" — corrupt entries
/// must not crash the editor; they must read as `null` so the
/// fallback auto-fit takes over silently.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('save then load round-trips', () async {
    final store = ProjectViewportStore();
    const projectId = 'p-1';
    const v = ViewportState(scale: 2.5, translation: Offset(120, -40));
    await store.save(projectId, v);
    final loaded = await store.load(projectId);
    expect(loaded, isNotNull);
    expect(loaded!.scale, 2.5);
    expect(loaded.translation, const Offset(120, -40));
  });

  test('load returns null when no entry exists', () async {
    final store = ProjectViewportStore();
    expect(await store.load('missing'), isNull);
  });

  test('load returns null on corrupt entry', () async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{'viewport.bad': 'not|enough'});
    final store = ProjectViewportStore();
    expect(await store.load('bad'), isNull);
  });

  test('load returns null when a field is non-finite', () async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{'viewport.inf': 'inf|0|0'});
    final store = ProjectViewportStore();
    expect(await store.load('inf'), isNull);
  });

  test('clear removes the saved viewport', () async {
    final store = ProjectViewportStore();
    await store.save('p', const ViewportState(scale: 1, translation: Offset.zero));
    await store.clear('p');
    expect(await store.load('p'), isNull);
  });
}
