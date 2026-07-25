import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/image_source_sheet.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' as picker;

/// The source picker lived in the APPLICATION layer, where the
/// import-direction gate kept it away from the editor's own sheet
/// host — so it shipped as stock Material chrome (two bare
/// `ListTile`s, no title). tb2 8/16 named the relocation as the fix.
/// These tests pin what the relocation bought: the shared sheet, a
/// title, and two peer options that both return the right source.
void main() {
  /// Opens the sheet and returns a one-slot box the assertions read
  /// after the sheet pops. Returning the pending `Future` directly
  /// deadlocks: the future only completes once `Navigator.pop` runs,
  /// which needs pumps that the awaiting test is no longer driving.
  Future<List<picker.ImageSource?>> open(
    WidgetTester tester, {
    Locale locale = const Locale('fa'),
    Brightness brightness = Brightness.light,
  }) async {
    final popped = <picker.ImageSource?>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => pickImageSource(context).then(popped.add),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return popped;
  }

  testWidgets('renders a titled sheet with both sources', (tester) async {
    await open(tester, locale: const Locale('en'));
    expect(tester.takeException(), isNull);

    expect(find.text('Add image'), findsOneWidget);
    expect(find.byKey(const ValueKey('image-source-gallery')), findsOneWidget);
    expect(find.byKey(const ValueKey('image-source-camera')), findsOneWidget);
  });

  testWidgets('gallery returns ImageSource.gallery', (tester) async {
    final popped = await open(tester);
    await tester.tap(find.byKey(const ValueKey('image-source-gallery')));
    await tester.pumpAndSettle();
    expect(popped, [picker.ImageSource.gallery]);
  });

  testWidgets('camera returns ImageSource.camera', (tester) async {
    final popped = await open(tester);
    await tester.tap(find.byKey(const ValueKey('image-source-camera')));
    await tester.pumpAndSettle();
    expect(popped, [picker.ImageSource.camera]);
  });

  testWidgets('dismissing returns null so the caller can bail', (tester) async {
    final popped = await open(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(popped, [null]);
  });

  testWidgets('both options are equal-width peers, not a ranked list', (
    tester,
  ) async {
    await open(tester);
    final gallery = tester.getRect(
      find.byKey(const ValueKey('image-source-gallery')),
    );
    final camera = tester.getRect(
      find.byKey(const ValueKey('image-source-camera')),
    );
    expect(gallery.width, moreOrLessEquals(camera.width, epsilon: 0.5));
    expect(
      gallery.top,
      moreOrLessEquals(camera.top, epsilon: 0.5),
      reason: 'peers share a row',
    );
    expect(gallery.height, greaterThanOrEqualTo(44));
  });

  testWidgets('renders in dark mode without exception', (tester) async {
    await open(tester, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('image-source-gallery')), findsOneWidget);
  });
}
