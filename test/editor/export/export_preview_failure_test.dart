// Export failure recovery (roadmap tb0 0.9): a failed or
// permission-denied save/share must keep the preview screen — and
// its already-rendered bytes — alive for an in-place retry, instead
// of tearing down the whole export flow. Distinct copy for the
// permission path vs a write failure.

import 'dart:typed_data';

import 'package:canvas_engine/features/editor/application/export_format.dart';
import 'package:canvas_engine/features/editor/application/image_export_service.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/export_preview_screen.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Programmable fake: fails N times, then succeeds.
class _FakeExportService extends ImageExportService {
  _FakeExportService(this.results);
  final List<ImageExportOutcome> results;
  int calls = 0;

  ImageExportResult _next() {
    final outcome = results[calls.clamp(0, results.length - 1)];
    calls++;
    return ImageExportResult(outcome);
  }

  @override
  Future<ImageExportResult> saveToGallery(
    Uint8List bytes, {
    String? filename,
    ExportFormat format = ExportFormat.png,
  }) async => _next();

  @override
  Future<ImageExportResult> share(
    Uint8List bytes, {
    String? filename,
    String? subject,
    String? text,
    Rect? shareOrigin,
    ExportFormat format = ExportFormat.png,
  }) async => _next();
}

// A 1x1 transparent PNG so the preview's decoder has real bytes.
final Uint8List _tinyPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, // IDAT
  0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, // IEND
  0x42, 0x60, 0x82,
]);

Future<void> _pumpPreview(WidgetTester tester, ImageExportService svc) async {
  // The preview must sit on a pushed route so its success-pop is
  // observable (popping a `home:` route is a silent no-op).
  final navKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [imageExportServiceProvider.overrideWithValue(svc)],
      child: MaterialApp(
        navigatorKey: navKey,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    ),
  );
  navKey.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => ExportPreviewScreen(
        bytes: _tinyPng,
        format: ExportFormat.png,
        pixelWidth: 1,
        pixelHeight: 1,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('failed save keeps the preview alive; retry succeeds and pops', (
    tester,
  ) async {
    final svc = _FakeExportService([
      ImageExportOutcome.failed,
      ImageExportOutcome.success,
    ]);
    await _pumpPreview(tester, svc);
    expect(find.byType(ExportPreviewScreen), findsOneWidget);

    final saveBtn = find.widgetWithText(FilledButton, 'Save');
    expect(saveBtn, findsOneWidget);
    await tester.tap(saveBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Still here — flow NOT torn down; error surfaced inline.
    expect(find.byType(ExportPreviewScreen), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(svc.calls, 1);

    // In-place retry with the SAME bytes now succeeds and pops.
    await tester.tap(saveBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(svc.calls, 2);
    expect(find.byType(ExportPreviewScreen), findsNothing);
  });

  testWidgets('permission denial shows the settings guidance and stays', (
    tester,
  ) async {
    final svc = _FakeExportService([ImageExportOutcome.permissionDenied]);
    await _pumpPreview(tester, svc);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ExportPreviewScreen), findsOneWidget);
    expect(
      find.textContaining('photo access', findRichText: true),
      findsWidgets,
      reason: 'permission failures need actionable, distinct copy',
    );
  });
}
