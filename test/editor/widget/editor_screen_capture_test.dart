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
import 'package:canvas_engine/features/editor/crop/application/crop_controller.dart';
import 'package:canvas_engine/features/editor/crop/presentation/crop_mode_overlay.dart';
import 'package:canvas_engine/features/editor/canvas/application/canvas_tool_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/commands/shape_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/background_fill.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/paint/application/paint_tool_controller.dart';
import 'package:canvas_engine/features/editor/paint/domain/paint_tool_type.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/shape/application/shape_tool_controller.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/image/application/image_tool_controller.dart';
import 'package:canvas_engine/features/editor/text/application/text_tool_controller.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/editor_breakpoints.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/quick_capsule.dart';
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
  bool withPaintArmed = false,
  PaintToolType paintTool = PaintToolType.freestyle,
  String? paintOpenSlot,
  bool withCanvasPanel = false,
  bool withCropSession = false,
  bool withMultiSelect = false,
  bool withQuickCapsule = false,
  bool portraitDoc = false,
  String? openSheet,
}) {
  final container = ProviderContainer();
  container.read(editorSessionProvider.notifier).state = const EditorSession(
    name: 'پوستر نوروز',
  );
  final ctrl = container.read(documentControllerProvider.notifier);
  // Square by default — but a square document hides an entire class
  // of bug. The RTL dimension swap (tb7 7/7) shipped because W and H
  // were equal in every capture, so `1080 × 1080` reads the same in
  // both directions. `portraitDoc` gives that class somewhere to
  // fail (tb8 2/2).
  ctrl.newDocument(
    width: portraitDoc ? 1080 : 1080,
    height: portraitDoc ? 1350 : 1080,
  );
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
  if (withPaintArmed) {
    // The Draw tile's entry path: arms freestyle immediately — the
    // armed-drawing baseline every workflow starts from. A committed,
    // UNselected stroke keeps the canvas honest about what drawing
    // over existing work looks like.
    ctrl.execute(
      AddLayerCommand(
        PaintLayer(
          id: 'paint-stroke-bg',
          transform: const LayerTransform(
            position: Offset(200, 280),
            size: Size(680, 320),
          ),
          kind: PaintKind.freestyle,
          normalizedPoints: const [
            Offset(0, 0.8),
            Offset(0.2, 0.2),
            Offset(0.45, 0.9),
            Offset(0.7, 0.1),
            Offset(1, 0.6),
          ],
          strokeColor: const Color(0xFFB3541E),
          strokeWidth: 12,
        ),
      ),
    );
    container.read(paintToolControllerProvider.notifier).selectTool(paintTool);
    if (paintOpenSlot != null) {
      container
          .read(paintToolControllerProvider.notifier)
          .openSlot(paintOpenSlot);
    }
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
  if (withCropSession) {
    // Crop v2's on-canvas session (tb4 10/14): the frame is drawn over
    // the WHOLE source, so the missing-file placeholder stands in for
    // the bitmap and the chrome is what this variant proves.
    ctrl.execute(
      AddLayerCommand(
        ImageLayer(
          id: 'img-crop',
          transform: const LayerTransform(
            position: Offset(140, 200),
            size: Size(800, 600),
          ),
          source: const ImageSource.file('/nonexistent-capture-image.png'),
        ),
      ),
    );
    container.read(selectionControllerProvider.notifier).select('img-crop');
    container
        .read(cropControllerProvider.notifier)
        .openCrop('img-crop', priorSelectionId: 'img-crop');
  }
  if (withCanvasPanel) {
    // Canvas panel open with nothing selected — the tier-3 entry
    // clears selection first, so this mirrors the real path (tb4
    // 4/14: Size section above Background).
    container.read(canvasToolControllerProvider.notifier).togglePanel();
  }
  if (withMultiSelect) {
    // Two layers selected in explicit multi-select mode (the
    // long-press modal state). Proves the multi chrome: the count
    // chip, the per-layer selection rects, and the fact that the
    // single-selection floating capsule stands down.
    container.read(selectionModeProvider.notifier).enterMulti();
    container.read(selectionControllerProvider.notifier).selectMany(const [
      'shape-1',
      'text-1',
    ]);
  }
  if (withQuickCapsule) {
    // THE floating quick-capsule (tb2 9/16) over a shape: fill swatch
    // + corner pills + More. Selection only, no dock panel — an open
    // panel trips canvasChromeSuppressedProvider and the capsule
    // hides itself, which is why this cannot be folded into the
    // gradient-fill variant.
    container.read(selectionControllerProvider.notifier).select('shape-1');
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

  /// The phone viewport every variant used before tb1's breakpoints
  /// landed, and still the default here.
  const phoneView = Size(440, 956);

  /// Tablet-class viewport: shortestSide 1024 clears
  /// [EditorBreakpoints.wideMinShortestSide] (600), so the wide
  /// branch of the responsive chrome is what gets captured.
  const wideView = Size(1024, 1366);

  /// Renders one variant and returns the PNG bytes. Writing to disk is
  /// the caller's job so the determinism check can render twice
  /// without producing two files.
  Future<Uint8List> render(
    WidgetTester tester, {
    required Brightness brightness,
    bool withSelection = false,
    bool withLookPanel = false,
    bool withGradientFill = false,
    bool withPaintSelected = false,
    bool withPaintArmed = false,
    PaintToolType paintTool = PaintToolType.freestyle,
    String? paintOpenSlot,
    bool withCanvasPanel = false,
    bool withCropSession = false,
    bool withMultiSelect = false,
    bool withQuickCapsule = false,
    bool portraitDoc = false,
    Size viewSize = phoneView,
    String? openSheet,
    Future<void> Function(WidgetTester tester)? interact,
  }) async {
    tester.view.physicalSize = viewSize;
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
      withPaintArmed: withPaintArmed,
      paintTool: paintTool,
      paintOpenSlot: paintOpenSlot,
      withCanvasPanel: withCanvasPanel,
      withCropSession: withCropSession,
      withMultiSelect: withMultiSelect,
      withQuickCapsule: withQuickCapsule,
      portraitDoc: portraitDoc,
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

    // Crop owns the whole screen and replaces the app bar with its
    // own chrome, so that variant asserts the session instead.
    if (withCropSession) {
      expect(find.byType(CropModeOverlay), findsOneWidget);
    } else {
      expect(find.byType(AppBar), findsOneWidget);
    }
    // The capsule is the *point* of its variant, and it self-hides on
    // several signals — capturing a blank canvas because a guard
    // fired would be a silently-useless PNG.
    if (withQuickCapsule) {
      expect(find.byType(QuickCapsule), findsOneWidget);
    }
    // Multi-select stands the single-selection capsule down; if that
    // ever regresses the capture would look identical to the single
    // case and nobody would notice from the PNG alone.
    if (withMultiSelect) {
      expect(find.byType(QuickCapsule), findsNothing);
    }

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
    image!.dispose();
    return bytes;
  }

  /// Renders a variant and writes it to `build/test_exports/` for
  /// human review. Thin wrapper over [render] — every existing call
  /// site keeps its exact shape.
  Future<void> capture(
    WidgetTester tester, {
    required Brightness brightness,
    required String fileName,
    bool withSelection = false,
    bool withLookPanel = false,
    bool withGradientFill = false,
    bool withPaintSelected = false,
    bool withPaintArmed = false,
    PaintToolType paintTool = PaintToolType.freestyle,
    String? paintOpenSlot,
    bool withCanvasPanel = false,
    bool withCropSession = false,
    bool withMultiSelect = false,
    bool withQuickCapsule = false,
    bool portraitDoc = false,
    Size viewSize = phoneView,
    String? openSheet,
    Future<void> Function(WidgetTester tester)? interact,
  }) async {
    final bytes = await render(
      tester,
      brightness: brightness,
      withSelection: withSelection,
      withLookPanel: withLookPanel,
      withGradientFill: withGradientFill,
      withPaintSelected: withPaintSelected,
      withPaintArmed: withPaintArmed,
      paintTool: paintTool,
      paintOpenSlot: paintOpenSlot,
      withCanvasPanel: withCanvasPanel,
      withCropSession: withCropSession,
      withMultiSelect: withMultiSelect,
      withQuickCapsule: withQuickCapsule,
      portraitDoc: portraitDoc,
      viewSize: viewSize,
      openSheet: openSheet,
      interact: interact,
    );
    final file = File('${outputDir.path}/$fileName');
    file.writeAsBytesSync(bytes);
    // ignore: avoid_print
    print('  → wrote ${file.path} (${bytes.length} bytes)');
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

  // A NON-SQUARE document (tb8 2/2). Every other variant is 1080 ×
  // 1080, and that symmetry is exactly what let the RTL dimension
  // swap ship: `1080 × 1080` reads identically in both directions, so
  // no capture and no test could see W and H trading places. This
  // variant is where that class of bug has to show itself — the top
  // bar's «۱۰۸۰ × ۱۳۵۰» is legible in the PNG.
  testWidgets('EditorScreen visual capture — portrait doc, light', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.light,
      fileName: 'editor_portrait_doc_light.png',
      portraitDoc: true,
      withSelection: true,
    );
  });

  testWidgets('EditorScreen visual capture — portrait doc, dark', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.dark,
      fileName: 'editor_portrait_doc_dark.png',
      portraitDoc: true,
      withSelection: true,
    );
  });

  testWidgets('EditorScreen visual capture — crop session, light', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.light,
      fileName: 'editor_crop_light.png',
      withCropSession: true,
    );
  });

  testWidgets('EditorScreen visual capture — crop session, dark', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.dark,
      fileName: 'editor_crop_dark.png',
      withCropSession: true,
    );
  });

  testWidgets('EditorScreen visual capture — crop framing (drag held)', (
    tester,
  ) async {
    // The crop frame has two visual states and the resting one is the
    // boring half: the thirds guides, the deepened scrim and the pixel
    // readout only exist while a handle is under the finger. Capturing
    // that needs a gesture that is still DOWN when the boundary is
    // rasterised, so this variant starts a drag and never lifts it —
    // the tear-down disposes the whole tree anyway.
    await capture(
      tester,
      brightness: Brightness.light,
      fileName: 'editor_crop_framing_light.png',
      withCropSession: true,
      interact: (tester) async {
        // The frame body is the one target whose position needs no
        // geometry maths — it fills the frame, and a body drag arms
        // exactly the same focus state a handle drag does.
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(CropModeOverlay)),
        );
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.moveBy(const Offset(24, 32));
        await tester.pump(const Duration(milliseconds: 200));
      },
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

  testWidgets('EditorScreen visual capture — paint pen sheet, light', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.light,
      fileName: 'editor_paint_size_light.png',
      withPaintSelected: true,
      interact: (t) async {
        // The bench's size pill opens the pen sheet (size + opacity)
        // bound to the selected stroke.
        await t.tap(find.byKey(const ValueKey('paint-pill-size')));
        await t.pumpAndSettle();
      },
    );
  });

  testWidgets('EditorScreen visual capture — paint pen sheet, dark', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.dark,
      fileName: 'editor_paint_size_dark.png',
      withPaintSelected: true,
      interact: (t) async {
        await t.tap(find.byKey(const ValueKey('paint-pill-size')));
        await t.pumpAndSettle();
      },
    );
  });

  // Paint workflow states a drawing session actually passes through:
  // entry (pen armed, drawing-ready), the colour sheet, and the shape
  // slot's options sheet. The adjust posture is the existing
  // editor_paint_restyle variant.
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final suffix = brightness == Brightness.dark ? 'dark' : 'light';
    testWidgets('EditorScreen visual capture — paint entry, $suffix', (
      tester,
    ) async {
      await capture(
        tester,
        brightness: brightness,
        fileName: 'editor_paint_entry_$suffix.png',
        withPaintArmed: true,
      );
    });

    testWidgets('EditorScreen visual capture — paint shape sheet, $suffix', (
      tester,
    ) async {
      await capture(
        tester,
        brightness: brightness,
        fileName: 'editor_paint_shape_$suffix.png',
        withPaintArmed: true,
        paintTool: PaintToolType.polygon,
        paintOpenSlot: 'shape',
      );
    });

    testWidgets('EditorScreen visual capture — paint colour, $suffix', (
      tester,
    ) async {
      await capture(
        tester,
        brightness: brightness,
        fileName: 'editor_paint_color_$suffix.png',
        withPaintArmed: true,
        paintOpenSlot: 'color',
      );
    });
  }

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

  testWidgets('EditorScreen visual capture — canvas panel, light', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.light,
      fileName: 'editor_canvas_panel_light.png',
      withCanvasPanel: true,
    );
  });

  testWidgets('EditorScreen visual capture — canvas gradient, light', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.light,
      fileName: 'editor_canvas_gradient_light.png',
      withCanvasPanel: true,
      interact: (t) async {
        await t.ensureVisible(find.byKey(const ValueKey('canvas-bg-gradient')));
        await t.pump();
        await t.tap(find.byKey(const ValueKey('canvas-bg-gradient')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('canvas-gradient-preset-0')));
        await t.pumpAndSettle();
      },
    );
  });

  testWidgets('EditorScreen visual capture — canvas panel, dark', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.dark,
      fileName: 'editor_canvas_panel_dark.png',
      withCanvasPanel: true,
    );
  });

  // -- Stage 4 surfaces (roadmap 5.4) --------------------------------

  testWidgets('EditorScreen visual capture — multi-select, light', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.light,
      fileName: 'editor_multi_select_light.png',
      withMultiSelect: true,
    );
  });

  testWidgets('EditorScreen visual capture — multi-select, dark', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.dark,
      fileName: 'editor_multi_select_dark.png',
      withMultiSelect: true,
    );
  });

  testWidgets('EditorScreen visual capture — quick capsule, light', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.light,
      fileName: 'editor_quick_capsule_light.png',
      withQuickCapsule: true,
    );
  });

  testWidgets('EditorScreen visual capture — quick capsule, dark', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.dark,
      fileName: 'editor_quick_capsule_dark.png',
      withQuickCapsule: true,
    );
  });

  testWidgets('the wide variant really is on the far side of the breakpoint', (
    tester,
  ) async {
    // Guards the two captures below from silently becoming duplicate
    // phone shots if the breakpoint constant ever moves.
    expect(EditorBreakpoints.isWideFor(wideView), isTrue);
    expect(EditorBreakpoints.isWideFor(phoneView), isFalse);
  });

  testWidgets('EditorScreen visual capture — iPad wide, light', (tester) async {
    await capture(
      tester,
      brightness: Brightness.light,
      fileName: 'editor_wide_light.png',
      viewSize: wideView,
      withSelection: true,
    );
  });

  testWidgets('EditorScreen visual capture — iPad wide, dark', (tester) async {
    await capture(
      tester,
      brightness: Brightness.dark,
      fileName: 'editor_wide_dark.png',
      viewSize: wideView,
      withSelection: true,
    );
  });

  // -- Determinism (roadmap 5.4) -------------------------------------
  //
  // NOT goldens. This repo has no golden infrastructure and CI renders
  // on ubuntu while development happens on macOS, so a committed
  // reference PNG would fail in CI for font-rasterisation reasons that
  // have nothing to do with the code under review.
  //
  // What IS checkable without a reference image is *self-consistency*:
  // render the same variant twice inside one test run and require the
  // two byte streams to match. That catches the failure modes a human
  // reviewing PNGs cannot see —
  //
  //   * unseeded randomness in a painter,
  //   * an animation whose phase depends on the wall clock rather than
  //     the test's fake clock, so the capture lands mid-flight,
  //   * hash-ordered iteration leaking into paint order,
  //   * uninitialised state that differs between the first and second
  //     build of the same tree.
  //
  // — and it does so on both platforms, because it never compares
  // against anything but itself.

  for (final (name, build)
      in <(String, Future<Uint8List> Function(WidgetTester))>[
        ('base', (t) => render(t, brightness: Brightness.light)),
        (
          'selection',
          (t) => render(t, brightness: Brightness.light, withSelection: true),
        ),
        (
          'quick capsule',
          (t) =>
              render(t, brightness: Brightness.light, withQuickCapsule: true),
        ),
        (
          'multi-select',
          (t) => render(t, brightness: Brightness.light, withMultiSelect: true),
        ),
        (
          'iPad wide',
          (t) => render(
            t,
            brightness: Brightness.light,
            viewSize: wideView,
            withSelection: true,
          ),
        ),
      ]) {
    testWidgets('$name renders byte-identically twice in one run', (
      tester,
    ) async {
      final first = await build(tester);
      final second = await build(tester);
      expect(
        second.length,
        first.length,
        reason:
            '$name: the two renders produced different PNG sizes — the '
            'editor is drawing something non-deterministic',
      );
      // Compare the bytes, but report the first differing offset
      // rather than dumping two multi-megabyte lists into the failure.
      var firstDiff = -1;
      for (var i = 0; i < first.length; i++) {
        if (first[i] != second[i]) {
          firstDiff = i;
          break;
        }
      }
      expect(
        firstDiff,
        -1,
        reason:
            '$name: two renders of the same variant differ, first at byte '
            '$firstDiff of ${first.length}. Something in this surface is '
            'non-deterministic (unseeded random, wall-clock animation '
            'phase, hash-ordered paint). Captures of it are not '
            'reviewable until that is fixed.',
      );
    });
  }

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

  /// Effect chips render at 12.5px (unified PresetChip pill — tb2
  /// 15/16, resized to the prototype's pill grammar in tb7 3/7); the
  /// dock tile labels use 10-11px, so font size still disambiguates
  /// duplicate strings.
  Finder effectChip(String label) => find.byWidgetPredicate(
    (w) => w is Text && w.data == label && w.style?.fontSize == 12.5,
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
          await t.tap(effectChip('پس‌زمینه'));
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
