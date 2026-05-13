import 'package:canvas_engine/core/utils/user_error.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('permission denial gets actionable user copy', () {
    final message = userMessageFor(
      PlatformException(
        code: 'photo_access_denied',
        message: 'raw platform text',
      ),
      fallback: 'Something went wrong. Try again.',
      permissionDeniedMessage: 'Allow photo access in Settings to continue.',
    );

    expect(message, 'Allow photo access in Settings to continue.');
  });

  test('unknown errors keep the friendly fallback', () {
    final message = userMessageFor(
      Exception('raw exception text'),
      fallback: "Couldn't open this photo. Try again or pick a different one.",
    );

    expect(
      message,
      "Couldn't open this photo. Try again or pick a different one.",
    );
    expect(message, isNot(contains('raw exception text')));
  });
}
