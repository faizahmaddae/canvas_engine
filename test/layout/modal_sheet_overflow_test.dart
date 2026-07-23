// Regression coverage for the modal-sheet overflow class found in the
// 2026-07 layout audit: several bottom sheets / dialogs put a
// Column(mainAxisSize.min) of fixed-height content inside a
// height-bounded modal with no scroll guard, so they overflow at short
// viewport heights (landscape phones, small devices) or when the soft
// keyboard shrinks the available space. Each test opens the real sheet
// via its production entry point at a short viewport and asserts no
// layout exception is thrown.
//
// These tests FAIL (RenderFlex overflow captured by takeException)
// before the scroll-guard fixes and pass after.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_layer.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/paint/presentation/paint_size_sheet.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/export_action_sheet.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/layer_actions_sheet.dart';
import 'package:canvas_engine/features/editor/text/presentation/text_input_flow_sheet.dart';
import 'package:canvas_engine/features/color_picker/presentation/color_picker_sheet.dart';
import 'package:canvas_engine/features/settings/presentation/settings_screen.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadAppFonts() async {
  const families = <String, List<String>>{
    'Hanken_Grotesk': [
      'assets/fonts/english/Hanken_Grotesk/HankenGrotesk-Regular.ttf',
    ],
    'Vazir_Regular': ['assets/fonts/farsi/Vazir_Regular.ttf'],
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(rootBundle.load(path));
    }
    await loader.load();
  }
}

Future<void> _loadMaterialIcons() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) return;
  final file = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _loadAppFonts();
    await _loadMaterialIcons();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Short landscape phone (~iPhone SE landscape) — the height that
  /// makes non-scrolling modal columns overflow.
  const landscape = Size(720, 360);

  /// iPhone SE landscape (320dp tall) — the tightest common height.
  const shortLandscape = Size(720, 320);
  const landscapeKeyboard = 200.0;

  /// Short portrait phone with the keyboard raised: available body
  /// height ≈ 568 − 290 = 278dp.
  const shortPortrait = Size(320, 568);
  const keyboardInset = 290.0;

  void applyView(WidgetTester tester, Size size, {double keyboard = 0}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    if (keyboard > 0) {
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    }
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });
  }

  /// Pumps a host that exposes a (context, ref) pair to drive the
  /// production `show*` entry points, then hands them to [open].
  Future<void> pumpAndOpen(
    WidgetTester tester,
    ProviderContainer container,
    FutureOr<void> Function(BuildContext context, WidgetRef ref) open,
  ) async {
    late BuildContext ctx;
    late WidgetRef widgetRef;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('fa'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              ctx = context;
              widgetRef = ref;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      ),
    );
    await tester.pump();
    unawaited(Future.sync(() => open(ctx, widgetRef)));
    // Bounded pumps rather than pumpAndSettle: the sheet's open
    // animation settles quickly and we avoid any looping-animation
    // hang risk.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  ProviderContainer docContainer({EditorLayer? extraLayer}) {
    final c = ProviderContainer();
    final ctrl = c.read(documentControllerProvider.notifier);
    ctrl.newDocument(width: 1080, height: 1080);
    if (extraLayer != null) ctrl.execute(AddLayerCommand(extraLayer));
    return c;
  }

  testWidgets('paint size sheet — no overflow @ short landscape', (
    tester,
  ) async {
    applyView(tester, shortLandscape);
    final c = docContainer();
    addTearDown(c.dispose);
    await pumpAndOpen(tester, c, (ctx, ref) => showPaintSizeSheet(ctx, ref));
    expect(tester.takeException(), isNull);
  });

  testWidgets('layer actions sheet — no overflow @ short landscape', (
    tester,
  ) async {
    applyView(tester, landscape);
    final layer = ShapeLayer(
      id: 'shape-1',
      transform: const LayerTransform(
        position: Offset(120, 120),
        size: Size(400, 300),
      ),
      kind: ShapeKind.rectangle,
      fillColor: const Color(0xFFC0872A),
    );
    final c = docContainer(extraLayer: layer);
    addTearDown(c.dispose);
    await pumpAndOpen(
      tester,
      c,
      (ctx, ref) => showLayerActionsSheet(ctx, ref, layer),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('export action sheet — no overflow @ short landscape', (
    tester,
  ) async {
    applyView(tester, landscape);
    final c = docContainer();
    addTearDown(c.dispose);
    await pumpAndOpen(tester, c, (ctx, ref) => ExportActionSheet.open(ctx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('text input composer — no overflow @ short + keyboard', (
    tester,
  ) async {
    applyView(tester, shortLandscape, keyboard: landscapeKeyboard);
    final c = docContainer();
    addTearDown(c.dispose);
    await pumpAndOpen(
      tester,
      c,
      (ctx, ref) => showTextInputFlowSheet(ctx, initial: 'نمونه'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('color picker custom sheet — no overflow @ short + keyboard', (
    tester,
  ) async {
    applyView(tester, shortPortrait, keyboard: keyboardInset);
    final c = docContainer();
    addTearDown(c.dispose);
    await pumpAndOpen(
      tester,
      c,
      (ctx, ref) => showColorPickerSheet(
        ctx,
        initial: const Color(0xFFC0872A),
        startAtCustom: true,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings category picker dialog — no overflow @ landscape', (
    tester,
  ) async {
    applyView(tester, shortLandscape);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('fa'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump();
    // The enabled-categories picker is the tallest dialog (4 checkbox
    // tiles); open it by its stable, locale-independent leading icon.
    // Scroll it into view first — in the short viewport the row sits
    // below the fold and the lazy ListView hasn't built it yet.
    final target = find.byIcon(Icons.dashboard_customize_outlined);
    await tester.scrollUntilVisible(
      target,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
