import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Points path_provider's application-documents directory at a fresh
/// temp dir (deleted after the test) so code using
/// `getApplicationDocumentsDirectory` — EditJournal, thumbnails —
/// runs in plain tests without platform channels.
Directory installFakeDocumentsDir() {
  final dir = Directory.systemTemp.createTempSync('canvas_engine_docs_test');
  PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._docsPath);

  final String _docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => _docsPath;
}
