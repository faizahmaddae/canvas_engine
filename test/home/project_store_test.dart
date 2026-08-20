import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canvas_engine/features/home/application/project_store.dart';
import 'package:canvas_engine/features/home/domain/project.dart';

import '../support/fake_path_provider.dart';
import '../support/temp_projects_dir.dart';

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

  Future<ProjectContainer> container({Directory? dir}) async {
    final d = dir ?? tempProjectsDir();
    final c = ProviderContainer(
      overrides: [projectsDirectoryProvider.overrideWith((ref) async => d)],
    );
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

  test('rename updates the name WITHOUT bumping lastModified', () async {
    // Recents sort on lastModified; a rename is a metadata edit, so
    // bumping it teleported old projects to the front of the grid
    // (ux-audit P3-7). "Modified" means the design changed.
    final c = await container();
    final original = _make('id', 'before', when: DateTime.utc(2025, 1, 1));
    await c.notifier.upsert(original);
    await c.notifier.rename('id', 'after');
    final updated = c.list.firstWhere((p) => p.id == 'id');
    expect(updated.name, 'after');
    expect(updated.lastModified, original.lastModified);
  });

  test('rename does not reorder the Recents sort', () async {
    final c = await container();
    await c.notifier.upsert(_make('old', 'Old', when: DateTime.utc(2025, 1)));
    await c.notifier.upsert(_make('new', 'New', when: DateTime.utc(2025, 6)));
    expect(c.list.map((p) => p.id), ['new', 'old']);

    await c.notifier.rename('old', 'Old renamed');
    expect(
      c.list.map((p) => p.id),
      ['new', 'old'],
      reason: 'renaming must not move a project up the grid',
    );
  });

  test(
    'persists across container instances via the shared directory',
    () async {
      final sharedDir = tempProjectsDir();
      final c1 = await container(dir: sharedDir);
      await c1.notifier.upsert(_make('persist', 'PP'));

      final c2 = await container(dir: sharedDir);
      expect(c2.list.map((p) => p.id), contains('persist'));
    },
  );

  // ─── file-store specifics ────────────────────────────────────────

  test('one file per project; writes are atomic (no stray .tmp)', () async {
    final dir = tempProjectsDir();
    final c = await container(dir: dir);
    await c.notifier.upsert(_make('a', 'A'));
    await c.notifier.upsert(_make('b', 'B'));

    final names =
        dir
            .listSync()
            .map((e) => e.path.split(Platform.pathSeparator).last)
            .toList()
          ..sort();
    expect(names, ['a.json', 'b.json']);
  });

  test(
    'a corrupt file is quarantined; the rest of the library survives',
    () async {
      final dir = tempProjectsDir();
      File(
        '${dir.path}${Platform.pathSeparator}good.json',
      ).writeAsStringSync(jsonEncode(_make('good', 'Good').toJson()));
      File(
        '${dir.path}${Platform.pathSeparator}bad.json',
      ).writeAsStringSync('{not json');

      final c = await container(dir: dir);
      expect(
        c.list.map((p) => p.id),
        ['good'],
        reason: 'one corrupt byte must cost one project, not the library',
      );
      final names = dir
          .listSync()
          .map((e) => e.path.split(Platform.pathSeparator).last)
          .toList();
      expect(
        names.where((n) => n.startsWith('bad.json.corrupt')),
        hasLength(1),
        reason: 'corrupt bytes are quarantined for recovery, not deleted',
      );
    },
  );

  test('delete removes the project file from disk', () async {
    final dir = tempProjectsDir();
    final c = await container(dir: dir);
    await c.notifier.upsert(_make('x', 'X'));
    expect(
      File('${dir.path}${Platform.pathSeparator}x.json').existsSync(),
      isTrue,
    );
    await c.notifier.delete('x');
    expect(
      File('${dir.path}${Platform.pathSeparator}x.json').existsSync(),
      isFalse,
    );
  });

  // ─── legacy prefs migration ──────────────────────────────────────

  test('migrates the legacy prefs blob to files and removes the key', () async {
    final legacy = [
      _make('m1', 'One', when: DateTime.utc(2025, 3, 1)).toJson(),
      _make('m2', 'Two', when: DateTime.utc(2025, 4, 1)).toJson(),
    ];
    SharedPreferences.setMockInitialValues({
      'home.projects.v1': jsonEncode(legacy),
    });

    final c = await container();
    expect(c.list.map((p) => p.id), ['m2', 'm1']);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('home.projects.v1'),
      isNull,
      reason: 'key removed only after every file verifiably reads back',
    );
  });

  test(
    'unreadable legacy blob is kept for forensics, store starts empty',
    () async {
      SharedPreferences.setMockInitialValues({
        'home.projects.v1': '{definitely not a list',
      });
      final c = await container();
      expect(c.list, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('home.projects.v1'),
        isNotNull,
        reason: 'never destroy bytes we could not migrate',
      );
    },
  );

  test('existing files win over the legacy blob on migration', () async {
    final dir = tempProjectsDir();
    // File version is newer authority than the blob's copy of m1.
    File(
      '${dir.path}${Platform.pathSeparator}m1.json',
    ).writeAsStringSync(jsonEncode(_make('m1', 'File wins').toJson()));
    SharedPreferences.setMockInitialValues({
      'home.projects.v1': jsonEncode([_make('m1', 'Blob loses').toJson()]),
    });

    final c = await container(dir: dir);
    expect(c.list.single.name, 'File wins');
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
      ),
    );
    final newId = await c.notifier.duplicate('src', 'dup');
    expect(newId, 'dup');
    final dup = c.list.firstWhere((p) => p.id == 'dup');
    expect(dup.name, 'Original (copy)');
    expect(dup.documentJson, '{"layers":[]}');
    expect(c.list.length, 2);
    // Thumbnail ownership is covered by the dedicated group below.
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

  test('LastOpenedProjectController.set works before the first build '
      'completes (cold-start open crashed on a late prefs field)', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // Deliberately NO `await ...future` first: opening a project
    // straight from a cold home screen calls set() while build() is
    // still resolving SharedPreferences.
    await c.read(lastOpenedProjectIdProvider.notifier).set('cold-open');
    expect(c.read(lastOpenedProjectIdProvider).value, 'cold-open');

    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    expect(await c2.read(lastOpenedProjectIdProvider.future), 'cold-open');
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

  test('legacy Project JSON without createdAt falls back to lastModified', () {
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
    expect(
      loaded.createdAt,
      modified,
      reason: 'fallback keeps the record sortable + non-null',
    );
  });

  test('duplicate stamps a fresh createdAt independent of source', () async {
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

  test(
    '#13 duplication shares the canonical image reference without copying',
    () async {
      final c = await container();
      // documentJson carries a portable `imported_images/<file>`
      // reference. ProjectStore.duplicate copies the string verbatim, so
      // both projects point at the same physical file — no image copy,
      // and the reference stays portable.
      const canonical =
          '{"version":1,"width":100,"height":100,'
          '"layers":[{"type":"image","id":"i",'
          '"source":{"file":"imported_images/pic.png"}}]}';
      await c.notifier.upsert(
        Project(
          id: 'src',
          name: 'Photo',
          width: 100,
          height: 100,
          createdAt: DateTime.utc(2025, 1, 1),
          lastModified: DateTime.utc(2025, 1, 1),
          documentJson: canonical,
        ),
      );
      await c.notifier.duplicate('src', 'dup');
      final dup = c.list.firstWhere((p) => p.id == 'dup');
      expect(dup.documentJson, canonical);
      expect(dup.documentJson, contains('imported_images/pic.png'));
    },
  );

  // ─── duplicate thumbnail ownership + reference-aware cleanup ──────
  //
  // Invariant: every duplicate owns a unique thumbnail file, and a
  // thumbnail is unlinked only when no remaining project references it.
  // Save cleanup is exercised through `releaseThumbnailIfUnreferenced`,
  // the exact seam `ProjectSaveService.save` delegates to after upsert
  // (the full save() path needs an editor Overlay to render, so its
  // reference-aware cleanup contract is verified here instead).
  group('thumbnail ownership', () {
    Directory thumbsDir(Directory docs) =>
        Directory('${docs.path}/project_thumbs');

    // Seed a real thumbnail PNG under the (faked) app-documents dir at the
    // same project_thumbs/ location the app uses, so copies land beside it
    // and file counts are meaningful.
    File seedThumb(Directory docs, String name, List<int> bytes) {
      final dir = thumbsDir(docs)..createSync(recursive: true);
      return File('${dir.path}/$name')..writeAsBytesSync(bytes);
    }

    Project src(String id, String? thumbPath, {int version = 1}) => Project(
      id: id,
      name: 'Original',
      width: 100,
      height: 100,
      createdAt: DateTime.utc(2025, 1, 1),
      lastModified: DateTime.utc(2025, 1, 1),
      documentJson: '{"layers":[]}',
      thumbnailPath: thumbPath,
      thumbnailVersion: version,
    );

    test(
      'duplicate gets its own path with equal, valid bytes (#1, #2)',
      () async {
        final docs = installFakeDocumentsDir();
        final thumb = seedThumb(docs, 'src.png', const [1, 2, 3, 4, 5]);
        final c = await container();
        await c.notifier.upsert(src('src', thumb.path));

        await c.notifier.duplicate('src', 'dup');
        final dup = c.list.firstWhere((p) => p.id == 'dup');

        expect(dup.thumbnailPath, isNotNull);
        expect(dup.thumbnailPath, isNot(thumb.path));
        expect(
          File(dup.thumbnailPath!).readAsBytesSync(),
          thumb.readAsBytesSync(),
          reason: 'copied bytes are byte-identical to the source thumbnail',
        );
        expect(
          dup.thumbnailVersion,
          1,
          reason: 'identical bytes carry the source renderer version',
        );
        expect(thumb.existsSync(), isTrue, reason: 'source file untouched');
      },
    );

    test('null source thumbnail degrades to none (#9)', () async {
      final c = await container();
      await c.notifier.upsert(src('src', null, version: 1));
      await c.notifier.duplicate('src', 'dup');
      final dup = c.list.firstWhere((p) => p.id == 'dup');
      expect(dup.thumbnailPath, isNull);
      expect(
        dup.thumbnailVersion,
        0,
        reason: 'no cached PNG => stale version so the grid live-renders',
      );
    });

    test(
      'missing source thumbnail file degrades to none, never shared (#9)',
      () async {
        final docs = installFakeDocumentsDir();
        final ghost = '${thumbsDir(docs).path}/ghost.png'; // never written
        final c = await container();
        await c.notifier.upsert(src('src', ghost));
        await c.notifier.duplicate('src', 'dup');
        final dup = c.list.firstWhere((p) => p.id == 'dup');
        expect(dup.thumbnailPath, isNull);
        expect(dup.thumbnailPath, isNot(ghost));
      },
    );

    test('saving the duplicate keeps the source thumbnail (#5)', () async {
      // Mirrors ProjectSaveService: publish a new thumb for the duplicate,
      // then release the old one. The source thumb is a different file.
      final docs = installFakeDocumentsDir();
      final srcThumb = seedThumb(docs, 'src.png', const [1]);
      final c = await container();
      await c.notifier.upsert(src('src', srcThumb.path));
      await c.notifier.duplicate('src', 'dup');
      final dupOld = File(
        c.list.firstWhere((p) => p.id == 'dup').thumbnailPath!,
      );

      final dupNew = seedThumb(docs, 'dup_new.png', const [2]);
      final dup = c.list.firstWhere((p) => p.id == 'dup');
      await c.notifier.upsert(dup.copyWith(thumbnailPath: dupNew.path));
      await c.notifier.releaseThumbnailIfUnreferenced(dupOld.path);

      expect(dupOld.existsSync(), isFalse, reason: 'old dup thumb reclaimed');
      expect(dupNew.existsSync(), isTrue);
      expect(srcThumb.existsSync(), isTrue, reason: 'source untouched by save');
    });

    test(
      'legacy shared path survives until its final reference (#6, #8)',
      () async {
        final docs = installFakeDocumentsDir();
        final shared = seedThumb(docs, 'shared.png', const [5, 5]);
        final c = await container();
        // Two pre-fix projects that share ONE thumbnail path.
        await c.notifier.upsert(src('a', shared.path));
        await c.notifier.upsert(src('b', shared.path));

        // Save 'a' with its own new thumbnail (copy-on-write); 'b' still
        // references `shared`, so releasing it must be a no-op.
        final aNew = seedThumb(docs, 'a_new.png', const [1]);
        final a = c.list.firstWhere((p) => p.id == 'a');
        await c.notifier.upsert(a.copyWith(thumbnailPath: aNew.path));
        await c.notifier.releaseThumbnailIfUnreferenced(shared.path);
        expect(
          shared.existsSync(),
          isTrue,
          reason: 'b still references the shared legacy file',
        );

        // Remove 'b'; nothing references `shared` now => reclaimed.
        await c.notifier.delete('b');
        await c.notifier.releaseThumbnailIfUnreferenced(shared.path);
        expect(
          shared.existsSync(),
          isFalse,
          reason: 'final reference removed -> file reclaimed',
        );
      },
    );

    test(
      'persistence failure rolls back copied thumbnail + record (#10)',
      () async {
        final docs = installFakeDocumentsDir();
        final srcThumb = seedThumb(docs, 'src.png', const [3, 3, 3]);
        final projectsDir = tempProjectsDir();
        final c = await container(dir: projectsDir);
        await c.notifier.upsert(src('src', srcThumb.path));

        // Force _writeProjectFile to fail: a directory occupies dup.json's
        // atomic rename target.
        Directory('${projectsDir.path}/dup.json').createSync();

        await expectLater(
          c.notifier.duplicate('src', 'dup'),
          throwsA(anything),
        );

        expect(
          c.list.where((p) => p.id == 'dup'),
          isEmpty,
          reason: 'no duplicate metadata after a failed persist',
        );
        final pngs = thumbsDir(docs)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.png'))
            .map((f) => f.path)
            .toList();
        expect(
          pngs,
          [srcThumb.path],
          reason: 'the copied thumbnail must be rolled back (no partial file)',
        );
        expect(
          File('${projectsDir.path}/dup.json.tmp').existsSync(),
          isFalse,
          reason: 'record temp must be rolled back too',
        );
      },
    );

    test('thumbnail copy failure aborts the duplicate cleanly (#10)', () async {
      final docs = installFakeDocumentsDir();
      // Source lives outside project_thumbs so that directory can be blocked.
      final srcThumb = File('${docs.path}/src_ext.png')
        ..writeAsBytesSync(const [4, 4]);
      // A FILE where the project_thumbs directory must be created makes the
      // copy fail inside ProjectThumbnailStore.
      File('${docs.path}/project_thumbs').writeAsBytesSync(const [0]);
      final c = await container();
      await c.notifier.upsert(src('src', srcThumb.path));

      await expectLater(c.notifier.duplicate('src', 'dup'), throwsA(anything));
      expect(
        c.list.where((p) => p.id == 'dup'),
        isEmpty,
        reason: 'a copy failure must leave no duplicate metadata',
      );
    });
  });
}

/// Convenience wrapper so test bodies stay terse.
class ProjectContainer {
  ProjectContainer(this.container);
  final ProviderContainer container;
  ProjectStore get notifier => container.read(projectStoreProvider.notifier);
  List<Project> get list => container.read(projectStoreProvider).value!;
}
