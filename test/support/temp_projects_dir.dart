import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Fresh temp directory for the project file store, deleted after the
/// test. Wire it into a container with:
///
/// ```dart
/// final dir = tempProjectsDir();
/// final c = ProviderContainer(overrides: [
///   projectsDirectoryProvider.overrideWith((ref) async => dir),
/// ]);
/// ```
///
/// Deliberately synchronous (createTempSync): `testWidgets` bodies run
/// in a fake-async zone where real `dart:io` futures never complete —
/// an async variant of this helper deadlocks widget tests. For the
/// same reason, widget tests must hydrate the store inside
/// `tester.runAsync(...)`:
///
/// ```dart
/// await tester.runAsync(() async {
///   await container.read(projectStoreProvider.future);
///   await container.read(projectStoreProvider.notifier).upsert(p);
/// });
/// ```
///
/// Reuse one directory across several containers in a test to
/// simulate persistence across app restarts.
Directory tempProjectsDir() {
  final dir = Directory.systemTemp.createTempSync(
    'canvas_engine_projects_test',
  );
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}
