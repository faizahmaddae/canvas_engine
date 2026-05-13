import 'dart:io' show FileSystemException, SocketException;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

/// Translates a raw exception into a short, user-facing sentence.
/// Callers keep the exception in [debugLogError]; this helper only
/// returns copy that is safe to show in UI.
///
/// Usage:
/// ```dart
/// try {
///   ...
/// } catch (e, st) {
///   ScaffoldMessenger.of(context).showSnackBar(
///     SnackBar(content: Text(userMessageFor(e, fallback: fallbackText))),
///   );
///   debugLogError('save failed', e, st);
/// }
/// ```
String userMessageFor(
  Object error, {
  required String fallback,
  String? permissionDeniedMessage,
  String? genericMessage,
}) {
  if (isPermissionDenied(error)) {
    return permissionDeniedMessage ?? fallback;
  }
  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    if (code.contains('cancelled') || code.contains('canceled')) {
      return fallback;
    }
    if (code.contains('not_available') || code.contains('unavailable')) {
      return genericMessage ?? fallback;
    }
    return fallback;
  }
  if (error is FileSystemException) return fallback;
  if (error is SocketException) return genericMessage ?? fallback;
  if (error is FormatException) return fallback;
  return fallback;
}

bool isPermissionDenied(Object error) {
  if (error is! PlatformException) return false;
  final code = error.code.toLowerCase();
  return code.contains('denied') ||
      code.contains('permission') ||
      code.contains('photo_access_denied') ||
      code.contains('camera_access_denied');
}

/// Logs a technical error in debug builds. Stripped from release.
void debugLogError(String label, Object error, [StackTrace? stackTrace]) {
  if (!kDebugMode) return;
  debugPrint('[$label] $error');
  if (stackTrace != null) debugPrintStack(stackTrace: stackTrace, label: label);
}
