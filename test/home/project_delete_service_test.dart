import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canvas_engine/features/home/application/project_delete_service.dart';
import 'package:canvas_engine/features/home/application/project_store.dart';
import 'package:canvas_engine/features/home/domain/project.dart';

import '../support/temp_projects_dir.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('delete removes the record, thumbnail file, and viewport key',
      () async {
    SharedPreferences.setMockInitialValues({
      'viewport.doomed': '1.0|0.0|0.0',
    });
    final dir = tempProjectsDir();
    final thumb = File('${dir.path}${Platform.pathSeparator}doomed_thumb.png')
      ..writeAsBytesSync(const [1, 2, 3]);

    final c = ProviderContainer(overrides: [
      projectsDirectoryProvider.overrideWith((ref) async => dir),
    ]);
    addTearDown(c.dispose);
    await c.read(projectStoreProvider.future);
    await c.read(projectStoreProvider.notifier).upsert(Project(
          id: 'doomed',
          name: 'Doomed',
          width: 100,
          height: 100,
          createdAt: DateTime.utc(2026, 1, 1),
          lastModified: DateTime.utc(2026, 1, 1),
          documentJson: '{}',
          thumbnailPath: thumb.path,
        ));

    // Journal cleanup is exercised too, but path_provider has no
    // platform implementation under test — the service treats that
    // as a best-effort failure and must still complete the delete.
    await c.read(projectDeleteServiceProvider).delete('doomed');

    expect(c.read(projectStoreProvider).value, isEmpty);
    expect(thumb.existsSync(), isFalse,
        reason: 'thumbnail PNG must not leak after delete');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('viewport.doomed'), isNull,
        reason: 'viewport key must not accumulate for deleted projects');
  });

  test('delete of a record without artifacts is clean and idempotent',
      () async {
    SharedPreferences.setMockInitialValues(const {});
    final dir = tempProjectsDir();
    final c = ProviderContainer(overrides: [
      projectsDirectoryProvider.overrideWith((ref) async => dir),
    ]);
    addTearDown(c.dispose);
    await c.read(projectStoreProvider.future);
    await c.read(projectStoreProvider.notifier).upsert(Project(
          id: 'plain',
          name: 'Plain',
          width: 100,
          height: 100,
          createdAt: DateTime.utc(2026, 1, 1),
          lastModified: DateTime.utc(2026, 1, 1),
          documentJson: '{}',
        ));

    await c.read(projectDeleteServiceProvider).delete('plain');
    expect(c.read(projectStoreProvider).value, isEmpty);
    // Second delete: no record, no artifacts — must not throw.
    await c.read(projectDeleteServiceProvider).delete('plain');
  });
}
