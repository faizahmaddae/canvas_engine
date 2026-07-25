// Roadmap tb4 4.8 — export intent flows into the preview's primary
// action. The sheet offers two exits (share / save to photo library);
// whichever the user picked must BE the preview's primary button —
// label, icon and the action it fires — with the other still one tap
// away as a secondary button. Before this, the preview always showed
// the same generic row, so choosing "Preview & Share" meant choosing
// Share twice.

import 'dart:typed_data';

import 'package:canvas_engine/features/editor/application/export_format.dart';
import 'package:canvas_engine/features/editor/application/export_intent.dart';
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

Future<void> _pumpPreview(
  WidgetTester tester, {
  required ExportIntent intent,
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
  // Drive the production entry point so the test covers `push`
  // forwarding the intent, not just the constructor.
  ExportPreviewScreen.push(
    navKey.currentContext!,
    bytes: _tinyPng,
    format: ExportFormat.png,
    pixelWidth: 1,
    pixelHeight: 1,
    intent: intent,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('export intent → preview primary action', () {
    testWidgets('share intent promotes Share to the filled primary', (
      tester,
    ) async {
      await _pumpPreview(tester, intent: ExportIntent.share);

      expect(
        find.descendant(of: find.byKey(_primary), matching: find.text('Share')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(_primary),
          matching: find.byIcon(AppIcons.share),
        ),
        findsOneWidget,
        reason: 'the primary carries the intent icon, not a generic one',
      );
      // The primary is the emphasised (filled) button; the other
      // intent is the quieter outlined one.
      expect(tester.widget(find.byKey(_primary)), isA<FilledButton>());
      expect(tester.widget(find.byKey(_secondary)), isA<OutlinedButton>());
      // The other intent stays reachable without going back.
      expect(
        find.descendant(
          of: find.byKey(_secondary),
          matching: find.text('Save'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('save intent keeps Save as the filled primary', (tester) async {
      await _pumpPreview(tester, intent: ExportIntent.save);

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
      expect(
        find.descendant(
          of: find.byKey(_secondary),
          matching: find.text('Share'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping the primary fires the chosen intent (share)', (
      tester,
    ) async {
      final svc = _RecordingExportService();
      await _pumpPreview(tester, intent: ExportIntent.share, service: svc);

      await tester.tap(find.byKey(_primary));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(svc.calls, ['share']);
    });

    testWidgets('tapping the secondary fires the other intent (save)', (
      tester,
    ) async {
      final svc = _RecordingExportService();
      await _pumpPreview(tester, intent: ExportIntent.share, service: svc);

      await tester.tap(find.byKey(_secondary));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(svc.calls, ['save']);
    });

    testWidgets('save intent primary fires save', (tester) async {
      final svc = _RecordingExportService();
      await _pumpPreview(tester, intent: ExportIntent.save, service: svc);

      await tester.tap(find.byKey(_primary));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(svc.calls, ['save']);
    });

    testWidgets('the outcome the preview pops matches the intent tapped', (
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
        intent: ExportIntent.share,
      ).then((v) => popped = v);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byKey(_primary));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(popped, isNotNull);
      expect(popped!.action, ExportPreviewAction.share);
      expect(popped!.result?.isSuccess, isTrue);
    });
  });
}
