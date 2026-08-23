// The export flow's ONE decision point. The sheet used to offer two
// exits («Preview & Share» / «Preview & Save») that both just opened
// the preview, which then re-asked with Cancel · Share · Save — the
// same question, twice. The preview now always renders Save as the
// filled primary and Share as the outlined secondary, and Cancel is
// the header × alone. This suite pins that contract and the
// keep-the-preview-alive failure paths.

import 'dart:typed_data';

import 'package:canvas_engine/features/editor/application/export_format.dart';
import 'package:canvas_engine/features/editor/application/image_export_service.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/export_preview_screen.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:canvas_engine/app/theme/app_icons.dart';

/// Records which exit the preview actually fired.
class _RecordingExportService extends ImageExportService {
  _RecordingExportService();

  final List<String> calls = <String>[];

  @override
  Future<ImageExportResult> saveToGallery(
    Uint8List bytes, {
    String? filename,
    ExportFormat format = ExportFormat.png,
  }) async {
    calls.add('save');
    return const ImageExportResult(ImageExportOutcome.success);
  }

  @override
  Future<ImageExportResult> share(
    Uint8List bytes, {
    String? filename,
    String? subject,
    String? text,
    Rect? shareOrigin,
    ExportFormat format = ExportFormat.png,
  }) async {
    calls.add('share');
    return const ImageExportResult(ImageExportOutcome.success);
  }
}

/// Returns a fixed outcome from both exits — the per-outcome contract
/// harness.
class _OutcomeExportService extends ImageExportService {
  const _OutcomeExportService(this.result);

  final ImageExportResult result;

  @override
  Future<ImageExportResult> saveToGallery(
    Uint8List bytes, {
    String? filename,
    ExportFormat format = ExportFormat.png,
  }) async => result;

  @override
  Future<ImageExportResult> share(
    Uint8List bytes, {
    String? filename,
    String? subject,
    String? text,
    Rect? shareOrigin,
    ExportFormat format = ExportFormat.png,
  }) async => result;
}

// 1×1 transparent PNG so the preview's decoder has real bytes.
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

const _primary = ValueKey('export-preview-primary');
const _secondary = ValueKey('export-preview-secondary');

Future<GlobalKey<NavigatorState>> _pumpPreview(
  WidgetTester tester, {
  ImageExportService? service,
}) async {
  // Pushed route, not `home:`, so the success-pop is observable.
  final navKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (service != null)
          imageExportServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        navigatorKey: navKey,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    ),
  );
  // Drive the production entry point so the test covers `push`.
  ExportPreviewScreen.push(
    navKey.currentContext!,
    bytes: _tinyPng,
    format: ExportFormat.png,
    pixelWidth: 1,
    pixelHeight: 1,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return navKey;
}

void main() {
  group('export preview action bar', () {
    testWidgets('Save is the filled primary, Share the outlined secondary — '
        'and there is no Cancel button', (tester) async {
      await _pumpPreview(tester);

      expect(
        find.descendant(of: find.byKey(_primary), matching: find.text('Save')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(_primary),
          matching: find.byIcon(AppIcons.exportSave),
        ),
        findsOneWidget,
      );
      expect(tester.widget(find.byKey(_primary)), isA<FilledButton>());
      expect(
        find.descendant(
          of: find.byKey(_secondary),
          matching: find.text('Share'),
        ),
        findsOneWidget,
      );
      expect(tester.widget(find.byKey(_secondary)), isA<OutlinedButton>());
      // Cancel is the header × alone — a third button restating it
      // made the action bar read as a second questionnaire after the
      // sheet.
      expect(find.byKey(const ValueKey('export-preview-cancel')), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsNothing);
      expect(find.byTooltip('Cancel'), findsOneWidget);
    });

    testWidgets('the header × pops a cancel outcome', (tester) async {
      ExportPreviewOutcome? popped;
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: navKey,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const Scaffold(body: SizedBox.shrink()),
          ),
        ),
      );
      ExportPreviewScreen.push(
        navKey.currentContext!,
        bytes: _tinyPng,
        format: ExportFormat.png,
        pixelWidth: 1,
        pixelHeight: 1,
      ).then((v) => popped = v);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byTooltip('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(popped, isNotNull);
      expect(popped!.action, ExportPreviewAction.cancel);
      expect(popped!.result, isNull);
    });

    testWidgets('tapping the primary saves', (tester) async {
      final svc = _RecordingExportService();
      await _pumpPreview(tester, service: svc);

      await tester.tap(find.byKey(_primary));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(svc.calls, ['save']);
    });

    testWidgets('tapping the secondary shares', (tester) async {
      final svc = _RecordingExportService();
      await _pumpPreview(tester, service: svc);

      await tester.tap(find.byKey(_secondary));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(svc.calls, ['share']);
    });

    testWidgets('the outcome the preview pops matches the action tapped', (
      tester,
    ) async {
      final svc = _RecordingExportService();
      ExportPreviewOutcome? popped;
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
      ExportPreviewScreen.push(
        navKey.currentContext!,
        bytes: _tinyPng,
        format: ExportFormat.png,
        pixelWidth: 1,
        pixelHeight: 1,
      ).then((v) => popped = v);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byKey(_secondary));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(popped, isNotNull);
      expect(popped!.action, ExportPreviewAction.share);
      expect(popped!.result?.isSuccess, isTrue);
    });
  });

  group('share outcome → preview behavior', () {
    testWidgets('a dismissed system sheet keeps the preview alive with no '
        'toast — cancelling is not "Shared"', (tester) async {
      final svc = _OutcomeExportService(
        const ImageExportResult(ImageExportOutcome.cancelled),
      );
      await _pumpPreview(tester, service: svc);

      await tester.tap(find.byKey(_secondary));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.byType(ExportPreviewScreen),
        findsOneWidget,
        reason: 'cancelling the share must not tear the export flow down',
      );
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: 'nothing was shared and nothing failed — stay quiet',
      );
      // The buttons must be live again for an in-place retry.
      final secondary = tester.widget<OutlinedButton>(find.byKey(_secondary));
      expect(secondary.onPressed, isNotNull);
    });

    testWidgets('share-unavailable keeps the preview and explains itself', (
      tester,
    ) async {
      final svc = _OutcomeExportService(
        const ImageExportResult(ImageExportOutcome.unavailable),
      );
      await _pumpPreview(tester, service: svc);

      await tester.tap(find.byKey(_secondary));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ExportPreviewScreen), findsOneWidget);
      expect(
        find.text("Sharing isn't available on this device"),
        findsOneWidget,
        reason: 'the one actionable share failure finally has visible copy',
      );
    });
  });
}
