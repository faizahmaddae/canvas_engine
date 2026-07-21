import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canvas_engine/features/home/application/project_delete_service.dart';
import 'package:canvas_engine/features/home/application/project_store.dart';
import 'package:canvas_engine/features/home/domain/project.dart';

import '../support/fake_path_provider.dart';
import '../support/temp_projects_dir.dart';

Project _project(String id, String? thumb) => Project(
  id: id,
  name: id,
  width: 100,
  height: 100,
  createdAt: DateTime.utc(2026, 1, 1),
  lastModified: DateTime.utc(2026, 1, 1),
  documentJson: '{}',
  thumbnailPath: thumb,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('delete removes the record, thumbnail file, and viewport key', () async {
    SharedPreferences.setMockInitialValues({'viewport.doomed': '1.0|0.0|0.0'});
    final dir = tempProjectsDir();
    final thumb = File('${dir.path}${Platform.pathSeparator}doomed_thumb.png')
      ..writeAsBytesSync(const [1, 2, 3]);

    final c = ProviderContainer(
      overrides: [projectsDirectoryProvider.overrideWith((ref) async => dir)],
    );
    addTearDown(c.dispose);
    await c.read(projectStoreProvider.future);
    await c
        .read(projectStoreProvider.notifier)
        .upsert(
          Project(
            id: 'doomed',
            name: 'Doomed',
            width: 100,
            height: 100,
            createdAt: DateTime.utc(2026, 1, 1),
            lastModified: DateTime.utc(2026, 1, 1),
            documentJson: '{}',
            thumbnailPath: thumb.path,
          ),
        );

    // Journal cleanup is exercised too, but path_provider has no
    // platform implementation under test — the service treats that
    // as a best-effort failure and must still complete the delete.
    await c.read(projectDeleteServiceProvider).delete('doomed');

    expect(c.read(projectStoreProvider).value, isEmpty);
    expect(
      thumb.existsSync(),
      isFalse,
      reason: 'thumbnail PNG must not leak after delete',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('viewport.doomed'),
      isNull,
      reason: 'viewport key must not accumulate for deleted projects',
    );
  });

  test(
    'delete of a record without artifacts is clean and idempotent',
    () async {
      SharedPreferences.setMockInitialValues(const {});
      final dir = tempProjectsDir();
      final c = ProviderContainer(
        overrides: [projectsDirectoryProvider.overrideWith((ref) async => dir)],
      );
      addTearDown(c.dispose);
      await c.read(projectStoreProvider.future);
      await c
          .read(projectStoreProvider.notifier)
          .upsert(
            Project(
              id: 'plain',
              name: 'Plain',
              width: 100,
              height: 100,
              createdAt: DateTime.utc(2026, 1, 1),
              lastModified: DateTime.utc(2026, 1, 1),
              documentJson: '{}',
            ),
          );

      await c.read(projectDeleteServiceProvider).delete('plain');
      expect(c.read(projectStoreProvider).value, isEmpty);
      // Second delete: no record, no artifacts — must not throw.
      await c.read(projectDeleteServiceProvider).delete('plain');
    },
  );

  test('legacy shared thumbnail is kept while another project references it, '
      'and reclaimed when its final reference is deleted (#7, #8)', () async {
    SharedPreferences.setMockInitialValues(const {});
    final dir = tempProjectsDir();
    final shared = File('${dir.path}${Platform.pathSeparator}shared_thumb.png')
      ..writeAsBytesSync(const [1, 2, 3]);
    final c = ProviderContainer(
      overrides: [projectsDirectoryProvider.overrideWith((ref) async => dir)],
    );
    addTearDown(c.dispose);
    await c.read(projectStoreProvider.future);
    final store = c.read(projectStoreProvider.notifier);
    // Two legacy projects that share ONE thumbnail file (pre-fix state).
    await store.upsert(_project('a', shared.path));
    await store.upsert(_project('b', shared.path));

    await c.read(projectDeleteServiceProvider).delete('a');
    expect(c.read(projectStoreProvider).value!.map((p) => p.id), ['b']);
    expect(
      shared.existsSync(),
      isTrue,
      reason: 'b still references the shared file — must not be deleted',
    );

    await c.read(projectDeleteServiceProvider).delete('b');
    expect(
      shared.existsSync(),
      isFalse,
      reason: 'final reference gone -> shared thumbnail reclaimed',
    );
  });

  test('deleting a duplicate leaves the source thumbnail intact, and vice '
      'versa — the two own distinct files (#3, #4)', () async {
    SharedPreferences.setMockInitialValues(const {});
    final docs = installFakeDocumentsDir();
    Directory('${docs.path}/project_thumbs').createSync(recursive: true);
    final srcThumb = File('${docs.path}/project_thumbs/src.png')
      ..writeAsBytesSync(const [7, 7, 7]);
    final dir = tempProjectsDir();
    final c = ProviderContainer(
      overrides: [projectsDirectoryProvider.overrideWith((ref) async => dir)],
    );
    addTearDown(c.dispose);
    await c.read(projectStoreProvider.future);
    final store = c.read(projectStoreProvider.notifier);
    await store.upsert(_project('src', srcThumb.path));
    await store.duplicate('src', 'dup');
    final dup = c
        .read(projectStoreProvider)
        .value!
        .firstWhere((p) => p.id == 'dup');
    final dupThumb = File(dup.thumbnailPath!);
    expect(
      dupThumb.path,
      isNot(srcThumb.path),
      reason: 'duplicate owns a distinct thumbnail file',
    );

    // Delete the duplicate: its own thumb goes, the source thumb stays.
    await c.read(projectDeleteServiceProvider).delete('dup');
    expect(dupThumb.existsSync(), isFalse, reason: 'own thumb reclaimed');
    expect(
      srcThumb.existsSync(),
      isTrue,
      reason: 'deleting the duplicate must not touch the source thumbnail',
    );

    // Deleting the source now reclaims only the source thumb.
    await c.read(projectDeleteServiceProvider).delete('src');
    expect(srcThumb.existsSync(), isFalse);
  });
}
