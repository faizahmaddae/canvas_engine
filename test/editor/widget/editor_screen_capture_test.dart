// Editor redesign (Phase 1) — visual capture of the full EditorScreen.
//
// Pumps the editor with the production theme in BOTH brightnesses and
// writes PNGs to build/test_exports/editor_{light,dark}.png for design
// review after each redesign commit. Persian locale on purpose: the
// editor is Persian-first, so captures must show the RTL chrome and
// the app's Persian face. Not a regression test — the only assertions
// are that the chrome actually rendered.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/editor_session.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/commands/shape_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/background_fill.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/shape/application/shape_tool_controller.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/image/application/image_tool_controller.dart';
import 'package:canvas_engine/features/editor/text/application/text_tool_controller.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadAppFonts() async {
  const families = <String, List<String>>{
    'Hanken_Grotesk': [
      'assets/fonts/english/Hanken_Grotesk/HankenGrotesk-Regular.ttf',
      'assets/fonts/english/Hanken_Grotesk/HankenGrotesk-Bold.ttf',
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

/// The Material icon font isn't an app asset — widget tests render
/// every [Icon] as a tofu box without it. Pull it from the local
/// Flutter SDK cache so the captures show real glyphs; silently skip
/// if unavailable (captures still render, just with boxes).
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

ProviderContainer _sampleEditor({
  bool withSelection = false,
  bool withLookPanel = false,
  bool withGradientFill = false,
  bool withPaintSelected = false,
  String? openSheet,
}) {
  final container = ProviderContainer();
  container.read(editorSessionProvider.notifier).state = const EditorSession(
    name: 'پوستر نوروز',
  );
  final ctrl = container.read(documentControllerProvider.notifier);
  ctrl.newDocument(width: 1080, height: 1080);
  ctrl.execute(
    AddLayerCommand(
      ShapeLayer(
        id: 'shape-1',
        transform: const LayerTransform(
          position: Offset(120, 620),
          size: Size(840, 300),
        ),
        kind: ShapeKind.rectangle,
        // Document content colour (sample data, not UI chrome).
        fillColor: const Color(0xFFC0872A),
      ),
    ),
  );
  ctrl.execute(
    AddLayerCommand(
      TextLayer(
        id: 'text-1',
        transform: const LayerTransform(
          position: Offset(140, 220),
          size: Size(800, 240),
        ),
        content: 'نوروزتان پیروز',
        // Ink on the white doc so the sample text is visible; Vazir
        // like a real freshly-created layer (the Persian-first
        // default) so captures show the true content face.
        style: const TextStyleSpec(
          fontFamily: 'Vazir_Regular',
          fontSize: 96,
          color: Color(0xFF1F1B16),
        ),
      ),
    ),
  );
  if (withLookPanel) {
    // Image layer (missing file → placeholder render, fine for a
    // layout capture) + the Look slot open.
    ctrl.execute(
      AddLayerCommand(
        ImageLayer(
          id: 'img-1',
          transform: const LayerTransform(
            position: Offset(140, 140),
            size: Size(800, 500),
          ),
          source: const ImageSource.file('/nonexistent-capture-image.png'),
        ),
      ),
    );
    container.read(selectionControllerProvider.notifier).select('img-1');
    container
        .read(imageToolControllerProvider.notifier)
        .toggleSlot(ImageToolSlot.look);
  }
  if (withPaintSelected) {
    // A committed stroke, selected — the paint dock in restyle mode
    // (tb4 3/14): tiles keyed off the layer's kind, values read off
    // the layer.
    ctrl.execute(
      AddLayerCommand(
        PaintLayer(
          id: 'paint-1',
          transform: const LayerTransform(
            position: Offset(160, 240),
            size: Size(760, 420),
          ),
          kind: PaintKind.polygon,
          normalizedPoints: const [Offset.zero, Offset(1, 1)],
          strokeColor: const Color(0xFFC0872A),
          strokeWidth: 14,
          sides: 5,
        ),
      ),
    );
    container.read(selectionControllerProvider.notifier).select('paint-1');
  }
  if (withGradientFill) {
    // The sample shape, re-filled with a gradient + its Style panel
    // open — the Solid | Gradient control in its gradient branch.
    ctrl.execute(
      const SetShapeFillCommand(
        layerId: 'shape-1',
        fill: LinearGradientBackground(
          startColor: Color(0xFFF5B942),
          endColor: Color(0xFFE2703A),
        ),
      ),
    );
    container.read(selectionControllerProvider.notifier).select('shape-1');
    container
        .read(shapeToolControllerProvider.notifier)
        .toggleSlot(ShapeToolSlot.style);
  }
  if (withSelection || openSheet != null) {
    container.read(selectionControllerProvider.notifier).select('text-1');
  }
  if (openSheet != null) {
    container.read(textToolControllerProvider.notifier).openSheet(openSheet);
  }
  return container;
}

void main() {
  final outputDir = Directory('build/test_exports');

  setUpAll(() async {
    if (!outputDir.existsSync()) outputDir.createSync(recursive: true);
    await _loadAppFonts();
    await _loadMaterialIcons();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> capture(
    WidgetTester tester, {
    required Brightness brightness,
    required String fileName,
    bool withSelection = false,
    bool withLookPanel = false,
    bool withGradientFill = false,
    bool withPaintSelected = false,
    String? openSheet,
    Future<void> Function(WidgetTester tester)? interact,
  }) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = _sampleEditor(
      withSelection: withSelection,
      withLookPanel: withLookPanel,
      withGradientFill: withGradientFill,
      withPaintSelected: withPaintSelected,
      openSheet: openSheet,
    );
    addTearDown(container.dispose);

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('fa'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(locale: const Locale('fa')),
            darkTheme: AppTheme.dark(locale: const Locale('fa')),
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            home: const EditorScreen(),
          ),
        ),
      ),
    );
    // Two extra pumps: the canvas hides itself until the first
    // auto-fit lands (see EditorCanvas `_fittedOnce`).
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    if (interact != null) {
      await interact(tester);
      await tester.pumpAndSettle();
    }

    expect(find.byType(AppBar), findsOneWidget);

    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await tester.runAsync(
      () => boundary.toImage(pixelRatio: 2.0),
    );
    final byteData = await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.png),
    );
    final bytes = byteData!.buffer.asUint8List();
    final file = File('${outputDir.path}/$fileName');
    file.writeAsBytesSync(bytes);
    // ignore: avoid_print
    print('  → wrote ${file.path} (${bytes.length} bytes)');
    image!.dispose();
  }

  testWidgets('EditorScreen visual capture — light', (tester) async {
    await capture(
      tester,
      brightness: Brightness.light,
      fileName: 'editor_light.png',
    );
  });

  testWidgets('EditorScreen visual capture — dark', (tester) async {
    await capture(
      tester,
      brightness: Brightness.dark,
      fileName: 'editor_dark.png',
    );
  });

  testWidgets('EditorScreen visual capture — selection, light', (tester) async {
    await capture(
      tester,
      brightness: Brightness.light,
      fileName: 'editor_selection_light.png',
      withSelection: true,
    );
  });

  testWidgets('EditorScreen visual capture — selection, dark', (tester) async {
    await capture(
      tester,
      brightness: Brightness.dark,
      fileName: 'editor_selection_dark.png',
      withSelection: true,
    );
  });

  testWidgets('EditorScreen visual capture — size panel, light', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.light,
      fileName: 'editor_panel_light.png',
      openSheet: 'size',
    );
  });

  testWidgets('EditorScreen visual capture — size panel, dark', (tester) async {
    await capture(
      tester,
      brightness: Brightness.dark,
      fileName: 'editor_panel_dark.png',
      openSheet: 'size',
    );
  });

  testWidgets('EditorScreen visual capture — paint restyle, light', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.light,
      fileName: 'editor_paint_restyle_light.png',
      withPaintSelected: true,
    );
  });

  testWidgets('EditorScreen visual capture — paint restyle, dark', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.dark,
      fileName: 'editor_paint_restyle_dark.png',
      withPaintSelected: true,
    );
  });

  testWidgets('EditorScreen visual capture — gradient fill, light', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.light,
      fileName: 'editor_gradient_light.png',
      withGradientFill: true,
    );
  });

  testWidgets('EditorScreen visual capture — gradient fill, dark', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.dark,
      fileName: 'editor_gradient_dark.png',
      withGradientFill: true,
    );
  });

  testWidgets('EditorScreen visual capture — look panel, light', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.light,
      fileName: 'editor_look_light.png',
      withLookPanel: true,
    );
  });

  testWidgets('EditorScreen visual capture — look panel, dark', (tester) async {
    await capture(
      tester,
      brightness: Brightness.dark,
      fileName: 'editor_look_dark.png',
      withLookPanel: true,
    );
  });

  testWidgets('EditorScreen visual capture — font panel, light', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.light,
      fileName: 'editor_font_panel_light.png',
      openSheet: 'font',
    );
  });

  testWidgets('EditorScreen visual capture — font panel, dark', (tester) async {
    await capture(
      tester,
      brightness: Brightness.dark,
      fileName: 'editor_font_panel_dark.png',
      openSheet: 'font',
    );
  });

  for (final (sheet, name) in [
    ('color', 'color'),
    ('styles', 'styles'),
    ('layout', 'align'),
  ]) {
    testWidgets('EditorScreen visual capture — $name panel, light', (
      tester,
    ) async {
      await capture(
        tester,
        brightness: Brightness.light,
        fileName: 'editor_${name}_panel_light.png',
        openSheet: sheet,
      );
    });

    testWidgets('EditorScreen visual capture — $name panel, dark', (
      tester,
    ) async {
      await capture(
        tester,
        brightness: Brightness.dark,
        fileName: 'editor_${name}_panel_dark.png',
        openSheet: sheet,
      );
    });
  }

  /// Effect chips render at 15px (unified PresetChip pill, tb2 15/16); the dock tile
  /// labels use 11px, so font size disambiguates duplicate strings.
  Finder effectChip(String label) => find.byWidgetPredicate(
    (w) => w is Text && w.data == label && w.style?.fontSize == 15,
  );

  for (final (b, name) in [
    (Brightness.light, 'light'),
    (Brightness.dark, 'dark'),
  ]) {
    testWidgets('EditorScreen visual capture — shadow effect, $name', (
      tester,
    ) async {
      await capture(
        tester,
        brightness: b,
        fileName: 'editor_effects_shadow_$name.png',
        openSheet: 'styles',
        interact: (t) async {
          // Open the سایه effect section, enable via the نرم (Soft)
          // preset chip — the compact section then shows the 2D
          // offset pad + blur slider + swatch row.
          await t.tap(effectChip('سایه'));
          await t.pumpAndSettle();
          await t.tap(effectChip('نرم'));
          await t.pumpAndSettle();
        },
      );
    });

    testWidgets('EditorScreen visual capture — background effect, $name', (
      tester,
    ) async {
      await capture(
        tester,
        brightness: b,
        fileName: 'editor_effects_background_$name.png',
        openSheet: 'styles',
        interact: (t) async {
          // Open the زمینه effect section, enable via the کپسولی
          // (Pill) preset chip — swatch row + precision disclosure.
          await t.tap(effectChip('زمینه'));
          await t.pumpAndSettle();
          await t.tap(effectChip('کپسولی'));
          await t.pumpAndSettle();
        },
      );
    });

    testWidgets('EditorScreen visual capture — border effect, $name', (
      tester,
    ) async {
      await capture(
        tester,
        brightness: b,
        fileName: 'editor_effects_border_$name.png',
        openSheet: 'styles',
        interact: (t) async {
          // Open the خط دور (frame/outline) section, enable via the
          // یکدست (Solid) preset chip.
          await t.tap(effectChip('خط دور'));
          await t.pumpAndSettle();
          await t.tap(effectChip('یکدست'));
          await t.pumpAndSettle();
        },
      );
    });

    testWidgets('EditorScreen visual capture — colour custom level, $name', (
      tester,
    ) async {
      await capture(
        tester,
        brightness: b,
        fileName: 'editor_color_custom_$name.png',
        openSheet: 'color',
        interact: (t) async {
          // Expand the shared picker's custom level in place —
          // HSV square + hue/opacity + hex/eyedropper/copy row.
          await t.tap(find.byKey(const ValueKey('color-picker-custom')));
          await t.pumpAndSettle();
        },
      );
    });

    testWidgets('EditorScreen visual capture — shadow colour picker, $name', (
      tester,
    ) async {
      await capture(
        tester,
        brightness: b,
        fileName: 'editor_shadow_color_picker_$name.png',
        openSheet: 'styles',
        interact: (t) async {
          // Second call site: the سایه section's entry row opens the
          // SAME shared picker as its compact no-dim sheet, titled
          // «رنگ سایه» — proof the surface is shared.
          await t.tap(effectChip('سایه'));
          await t.pumpAndSettle();
          await t.tap(effectChip('نرم'));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const ValueKey('effect-shadow-color')));
          await t.pumpAndSettle();
        },
      );
    });

    testWidgets('EditorScreen visual capture — more sheet, $name', (
      tester,
    ) async {
      await capture(
        tester,
        brightness: b,
        fileName: 'editor_more_sheet_$name.png',
        withSelection: true,
        interact: (t) async {
          // Open the «بیشتر» sheet from the consolidated bar — shows
          // the single B/I/U segmented row + compact action rows.
          await t.tap(find.text('بیشتر').first);
          await t.pumpAndSettle();
        },
      );
    });
  }
}
