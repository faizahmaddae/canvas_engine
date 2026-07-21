// Platform-configuration regression guard for the iOS camera permission.
//
// The editor lets the user capture a photo with the device camera
// (`ImageSource.camera`) from both the add-image and replace-image flows.
// iOS hard-crashes the process the first time the camera is invoked unless
// `NSCameraUsageDescription` is present in `ios/Runner/Info.plist`, and App
// Store review rejects a binary that can reach the camera without it.
//
// This test locks that contract so the key cannot silently regress, keeps the
// existing photo-library usage strings from being dropped in passing, and ties
// the requirement to the source call sites so the permission is only demanded
// while camera capture is actually shipped.
//
// It reads plain files under the package root (no Flutter bindings, no
// widgets), so it stays fast and stable across platforms.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final infoPlist = File('ios/Runner/Info.plist');
  final libDir = Directory('lib');

  // Pull the <string> value that immediately follows a given <key> in the
  // plist. A deliberately small scan (no XML dependency): Info.plist is a
  // flat, hand-maintained dict, so key -> next-string is enough and reads
  // clearly. Keys passed in are constant literals with no regex-special
  // characters, so no escaping is required.
  String? plistStringFor(String key, String source) {
    final match = RegExp(
      '<key>$key</key>\\s*<string>(.*?)</string>',
      dotAll: true,
    ).firstMatch(source);
    return match?.group(1);
  }

  test('ios/Runner/Info.plist exists at the package root', () {
    expect(
      infoPlist.existsSync(),
      isTrue,
      reason: 'expected ${infoPlist.path} relative to the package root',
    );
  });

  test('NSCameraUsageDescription is present and non-empty', () {
    final value = plistStringFor(
      'NSCameraUsageDescription',
      infoPlist.readAsStringSync(),
    );
    expect(
      value,
      isNotNull,
      reason:
          'NSCameraUsageDescription is required: the editor invokes '
          'ImageSource.camera, which crashes on iOS and is rejected by App '
          'Store review without this usage string.',
    );
    expect(
      value!.trim(),
      isNotEmpty,
      reason:
          'NSCameraUsageDescription must be a human-readable, non-empty '
          'purpose string.',
    );
  });

  test('existing photo-library usage descriptions are preserved', () {
    final source = infoPlist.readAsStringSync();
    for (final key in const [
      'NSPhotoLibraryUsageDescription',
      'NSPhotoLibraryAddUsageDescription',
    ]) {
      expect(
        plistStringFor(key, source)?.trim(),
        isNotEmpty,
        reason: '$key must remain set (save-to-Photos depends on it).',
      );
    }
  });

  test('camera capture is still represented in the application', () {
    // The permission is only justified while the app actually reaches the
    // camera. If every ImageSource.camera call site is removed, this fails on
    // purpose so the usage string is revisited alongside the feature.
    final usesCamera = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .any((f) => f.readAsStringSync().contains('ImageSource.camera'));
    expect(
      usesCamera,
      isTrue,
      reason:
          'no ImageSource.camera call site found under lib/ — either camera '
          'capture was removed (revisit NSCameraUsageDescription) or this '
          'guard is stale.',
    );
  });
}
