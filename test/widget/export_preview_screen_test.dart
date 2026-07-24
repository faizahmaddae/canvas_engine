import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_engine/features/editor/application/export_format.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/export_preview_screen.dart';

/// 1×1 transparent PNG — small valid byte buffer for `Image.memory`.
final Uint8List _tinyPng = Uint8List.fromList(const <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

Widget _wrap(Widget child) => ProviderScope(child: MaterialApp(home: child));

void main() {
  group('ExportPreviewScreen', () {
    testWidgets('renders info chips for PNG (no quality chip)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ExportPreviewScreen(
            bytes: _tinyPng,
            format: ExportFormat.png,
            pixelWidth: 1080,
            pixelHeight: 720,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('1080 × 720'), findsOneWidget);
      expect(find.text('PNG'), findsOneWidget);
      // PNG has no quality knob -> no quality chip.
      expect(find.textContaining('Quality'), findsNothing);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('renders quality chip for JPG', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ExportPreviewScreen(
            bytes: _tinyPng,
            format: ExportFormat.jpg,
            pixelWidth: 2160,
            pixelHeight: 2160,
            jpgQuality: 0.85,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('2160 × 2160'), findsOneWidget);
      expect(find.text('JPG'), findsOneWidget);
      expect(find.text('Quality 85%'), findsOneWidget);
    });

    testWidgets('Cancel pops with cancel outcome and no result', (
      tester,
    ) async {
      ExportPreviewOutcome? popped;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await ExportPreviewScreen.push(
                      ctx,
                      bytes: _tinyPng,
                      format: ExportFormat.png,
                      pixelWidth: 100,
                      pixelHeight: 100,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(popped, isNotNull);
      expect(popped!.action, ExportPreviewAction.cancel);
      expect(popped!.result, isNull);
    });

    testWidgets('JPG asserts when jpgQuality is null', (tester) async {
      expect(
        () => ExportPreviewScreen(
          bytes: _tinyPng,
          format: ExportFormat.jpg,
          pixelWidth: 100,
          pixelHeight: 100,
        ),
        throwsAssertionError,
      );
    });
  });
}
