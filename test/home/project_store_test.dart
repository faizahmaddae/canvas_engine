import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canvas_engine/features/home/application/project_store.dart';
import 'package:canvas_engine/features/home/domain/project.dart';

Project _make(String id, String name, {DateTime? when, DateTime? created}) =>
    Project(
      id: id,
      name: name,
      width: 100,
      height: 100,
      createdAt: created ?? when ?? DateTime.utc(2026, 1, 1),
      lastModified: when ?? DateTime.utc(2026, 1, 1),
      documentJson: '{}',
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  Future<ProjectContainer> container() async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // Wait for AsyncNotifier.build() to resolve.
    await c.read(projectStoreProvider.future);
    return ProjectContainer(c);
  }

  test('starts empty when no prefs', () async {
    final c = await container();
    expect(c.list, isEmpty);
  });

  test('upsert inserts then updates', () async {
    final c = await container();
    await c.notifier.upsert(_make('1', 'A'));
    await c.notifier.upsert(_make('2', 'B'));
    expect(c.list.map((p) => p.id), containsAll(['1', '2']));

    await c.notifier.upsert(_make('1', 'A renamed'));
    expect(c.list.length, 2);
    expect(c.list.firstWhere((p) => p.id == '1').name, 'A renamed');
  });

  test('upsert sorts by lastModified desc', () async {
    final c = await container();
    await c.notifier.upsert(
      _make('old', 'old', when: DateTime.utc(2025, 1, 1)),
    );
    await c.notifier.upsert(
      _make('new', 'new', when: DateTime.utc(2026, 4, 1)),
    );
    expect(c.list.first.id, 'new');
  });

  test('delete removes by id and is idempotent', () async {
    final c = await container();
    await c.notifier.upsert(_make('x', 'X'));
    await c.notifier.delete('x');
    expect(c.list, isEmpty);
    await c.notifier.delete('x'); // no throw on missing.
    expect(c.list, isEmpty);
  });

  test('rename updates name + bumps lastModified', () async {
    final c = await container();
    final original =
        _make('id', 'before', when: DateTime.utc(2025, 1, 1));
    await c.notifier.upsert(original);
    await c.notifier.rename('id', 'after');
    final updated = c.list.firstWhere((p) => p.id == 'id');
    expect(updated.name, 'after');
    expect(updated.lastModified.isAfter(original.lastModified), isTrue);
  });

  test('persists across container instances via SharedPreferences',
      () async {
    final c1 = await container();
    await c1.notifier.upsert(_make('persist', 'PP'));

    final c2 = await container();
    expect(c2.list.map((p) => p.id), contains('persist'));
  });

  test('duplicate inserts a new project with " (copy)" suffix', () async {
    final c = await container();
    await c.notifier.upsert(
      Project(
        id: 'src',
        name: 'Original',
        width: 100,
        height: 100,
        createdAt: DateTime.utc(2025, 1, 1),
        lastModified: DateTime.utc(2025, 1, 1),
        documentJson: '{"layers":[]}',
        thumbnailPath: '/tmp/x.png',
      ),
    );
    final newId = await c.notifier.duplicate('src', 'dup');
    expect(newId, 'dup');
    final dup = c.list.firstWhere((p) => p.id == 'dup');
    expect(dup.name, 'Original (copy)');
    expect(dup.documentJson, '{"layers":[]}');
    expect(dup.thumbnailPath, '/tmp/x.png');
    expect(c.list.length, 2);
  });

  test('duplicate of missing id returns null and does nothing', () async {
    final c = await container();
    final result = await c.notifier.duplicate('nope', 'new');
    expect(result, isNull);
    expect(c.list, isEmpty);
  });

  test('LastOpenedProjectController persists id', () async {
    final c1 = ProviderContainer();
    addTearDown(c1.dispose);
    await c1.read(lastOpenedProjectIdProvider.future);
    await c1.read(lastOpenedProjectIdProvider.notifier).set('proj-1');

    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    final loaded = await c2.read(lastOpenedProjectIdProvider.future);
    expect(loaded, 'proj-1');
  });

  test('LastOpenedProjectController.set(null) clears value', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(lastOpenedProjectIdProvider.future);
    final n = c.read(lastOpenedProjectIdProvider.notifier);
    await n.set('x');
    await n.set(null);
    expect(c.read(lastOpenedProjectIdProvider).value, isNull);
  });

  // ─── createdAt metadata ──────────────────────────────────────────

  test('Project round-trips createdAt through JSON', () {
    final created = DateTime.utc(2025, 6, 1, 12);
    final modified = DateTime.utc(2026, 5, 1, 12);
    final p = Project(
      id: 'abc',
      name: 'Round-trip',
      width: 1080,
      height: 1920,
      createdAt: created,
      lastModified: modified,
      documentJson: '{}',
    );
    final round = Project.fromJson(p.toJson());
    expect(round.createdAt, created);
    expect(round.lastModified, modified);
  });

  test('legacy Project JSON without createdAt falls back to lastModified',
      () {
    final modified = DateTime.utc(2025, 1, 2);
    // Simulates a record persisted by an older app version that
    // didn't write `createdAt`.
    final legacy = <String, Object?>{
      'id': 'legacy',
      'name': 'Old',
      'width': 100.0,
      'height': 100.0,
      'lastModified': modified.toIso8601String(),
      'documentJson': '{}',
    };
    final loaded = Project.fromJson(legacy);
    expect(loaded.createdAt, modified,
        reason: 'fallback keeps the record sortable + non-null');
  });

  test('duplicate stamps a fresh createdAt independent of source',
      () async {
    final c = await container();
    await c.notifier.upsert(
      Project(
        id: 'src',
        name: 'Original',
        width: 100,
        height: 100,
        createdAt: DateTime.utc(2024, 1, 1),
        lastModified: DateTime.utc(2024, 1, 1),
        documentJson: '{}',
      ),
    );
    final before = DateTime.now();
    await c.notifier.duplicate('src', 'dup');
    final dup = c.list.firstWhere((p) => p.id == 'dup');
    expect(
      dup.createdAt.isAfter(before.subtract(const Duration(seconds: 1))),
      isTrue,
      reason: 'duplicate is a brand-new project, not a clone of history',
    );
  });
}

/// Convenience wrapper so test bodies stay terse.
class ProjectContainer {
  ProjectContainer(this.container);
  final ProviderContainer container;
  ProjectStore get notifier => container.read(projectStoreProvider.notifier);
  List<Project> get list => container.read(projectStoreProvider).value!;
}
