import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:canvas_engine/features/editor/application/export_format.dart';
import 'package:canvas_engine/features/editor/canvas/presentation/widgets/canvas_checkerboard.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/export_preview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Render a solid-colour PNG of [w] x [h] pixels for use as preview
/// bytes in a widget test.
Future<Uint8List> makeSolidPng(
  int w,
  int h, {
  Color color = const Color(0xFFFF00FF),
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final bd = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bd!.buffer.asUint8List();
}

/// Render a fully-transparent PNG of [w] x [h] -- nothing drawn so
/// every pixel is alpha = 0. Exercises the checkerboard backdrop.
Future<Uint8List> makeTransparentPng(int w, int h) async {
  final recorder = ui.PictureRecorder();
  // Open the canvas but draw nothing -> output bitmap is all zeros.
  Canvas(recorder);
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final bd = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bd!.buffer.asUint8List();
}

Widget _wrap(Widget child) {
  return ProviderScope(child: MaterialApp(home: child));
}

/// Locate the [AspectRatio] that drives the preview rectangle. The
/// ScrollView/Stack/etc. we wrap around the image have no
/// AspectRatio of their own, so a single `byType` is unambiguous.
double _previewAspect(WidgetTester tester) {
  final ar = tester.widget<AspectRatio>(find.byType(AspectRatio));
  return ar.aspectRatio;
}

void main() {
  group('ExportPreviewScreen aspect ratio', () {
    testWidgets('landscape 6720x4480 renders as 3:2, not stretched', (
      tester,
    ) async {
      // Use a small bitmap to keep the test cheap; the AspectRatio
      // widget is driven by the props (pixelWidth / pixelHeight),
      // so the on-screen rectangle exactly mirrors the production
      // 6720 x 4480 ratio.
      late final Uint8List bytes;
      await tester.runAsync(() async {
        bytes = await makeSolidPng(60, 40);
      });
      await tester.pumpWidget(
        _wrap(
          ExportPreviewScreen(
            bytes: bytes,
            format: ExportFormat.png,
            pixelWidth: 6720,
            pixelHeight: 4480,
          ),
        ),
      );
      // Image.memory schedules an async decode; drain it.
      await tester.pump();

      expect(_previewAspect(tester), closeTo(6720 / 4480, 1e-9));
      // Sanity check: that ratio is exactly 3:2.
      expect(_previewAspect(tester), closeTo(1.5, 1e-9));
    });

    testWidgets('tall 1080x1920 renders as 9:16', (tester) async {
      late final Uint8List bytes;
      await tester.runAsync(() async {
        bytes = await makeSolidPng(40, 60);
      });
      await tester.pumpWidget(
        _wrap(
          ExportPreviewScreen(
            bytes: bytes,
            format: ExportFormat.png,
            pixelWidth: 1080,
            pixelHeight: 1920,
          ),
        ),
      );
      await tester.pump();
      expect(_previewAspect(tester), closeTo(1080 / 1920, 1e-9));
    });

    testWidgets('square 1024x1024 renders as 1:1', (tester) async {
      late final Uint8List bytes;
      await tester.runAsync(() async {
        bytes = await makeSolidPng(50, 50);
      });
      await tester.pumpWidget(
        _wrap(
          ExportPreviewScreen(
            bytes: bytes,
            format: ExportFormat.png,
            pixelWidth: 1024,
            pixelHeight: 1024,
          ),
        ),
      );
      await tester.pump();
      expect(_previewAspect(tester), closeTo(1.0, 1e-9));
    });

    testWidgets('transparent PNG keeps aspect ratio AND shows checkerboard', (
      tester,
    ) async {
      late final Uint8List bytes;
      await tester.runAsync(() async {
        bytes = await makeTransparentPng(80, 40);
      });
      await tester.pumpWidget(
        _wrap(
          ExportPreviewScreen(
            bytes: bytes,
            format: ExportFormat.png,
            pixelWidth: 1600,
            pixelHeight: 800,
          ),
        ),
      );
      await tester.pump();
      expect(_previewAspect(tester), closeTo(2.0, 1e-9));
      // Checkerboard sits behind the image in the same aspect-ratio
      // box -- not behind the whole pane.
      expect(find.byType(CanvasCheckerboard), findsOneWidget);
    });
  });

  group('ExportPreviewScreen size label', () {
    testWidgets('shows caller-supplied dimensions immediately', (tester) async {
      late final Uint8List bytes;
      await tester.runAsync(() async {
        bytes = await makeSolidPng(2, 2);
      });
      await tester.pumpWidget(
        _wrap(
          ExportPreviewScreen(
            bytes: bytes,
            format: ExportFormat.png,
            pixelWidth: 6720,
            pixelHeight: 4480,
          ),
        ),
      );
      await tester.pump();
      // Before the async decode resolves, the label uses the props.
      expect(find.text('6720 \u00d7 4480'), findsOneWidget);
    });

    testWidgets('matches the actual decoded bitmap dimensions after decode', (
      tester,
    ) async {
      late final Uint8List bytes;
      await tester.runAsync(() async {
        bytes = await makeSolidPng(320, 200);
      });
      // Caller-supplied dimensions intentionally diverge from the
      // bytes so we can prove the label updates to ground truth.
      await tester.pumpWidget(
        _wrap(
          ExportPreviewScreen(
            bytes: bytes,
            format: ExportFormat.png,
            pixelWidth: 999,
            pixelHeight: 999,
          ),
        ),
      );
      // Let the async decode + setState complete.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.text('320 \u00d7 200'), findsOneWidget);
      // And the AspectRatio re-binds to the decoded ratio.
      expect(_previewAspect(tester), closeTo(320 / 200, 1e-9));
    });
  });
}
