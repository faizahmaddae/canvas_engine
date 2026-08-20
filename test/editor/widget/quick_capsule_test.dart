// THE floating quick-capsule contracts (tb2 9/16): one
// registry-derived pill for every selected layer type, each
// accelerator routing to the SAME surface the bottom bar opens
// (divergence-impossible), hiding while that surface is open, and
// covering the emoji-sticker case that previously fell to the
// deleted QuickActionsOverlay.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/image/application/image_tool_controller.dart';
import 'package:canvas_engine/features/editor/paint/application/paint_tool_controller.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/quick_capsule.dart';
import 'package:canvas_engine/features/editor/shape/application/shape_tool_controller.dart';
import 'package:canvas_engine/features/editor/sticker/application/sticker_tool_controller.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const transform = LayerTransform(
    position: Offset(140, 420),
    size: Size(800, 240),
  );

  Future<ProviderContainer> pumpWithLayer(
    WidgetTester tester,
    EditorLayer layer,
  ) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(documentControllerProvider.notifier);
    ctrl.newDocument(width: 1080, height: 1080);
    ctrl.execute(AddLayerCommand(layer));
    container.read(selectionControllerProvider.notifier).select(layer.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const EditorScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  Finder pill(String semanticLabel) => find.descendant(
    of: find.byType(QuickCapsule),
    matching: find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == semanticLabel,
    ),
  );

  Future<void> tapPill(WidgetTester tester, String label) async {
    await tester.tap(pill(label));
    // The canvas root owns double-tap-to-edit, so every in-canvas
    // single tap resolves only after the double-tap window lapses.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  TextLayer text({TextLayerKind kind = TextLayerKind.normal}) => TextLayer(
    id: 'layer-1',
    transform: transform,
    content: 'Hello',
    style: const TextStyleSpec(fontSize: 96),
    kind: kind,
  );

  ImageLayer image() => ImageLayer(
    id: 'layer-1',
    transform: transform,
    source: const ImageSource.asset('stub.png'),
  );

  ShapeLayer shape() => ShapeLayer(
    id: 'layer-1',
    transform: transform,
    kind: ShapeKind.rectangle,
    fillColor: const Color(0xFFDD2244),
  );

  PaintLayer paintStroke() => PaintLayer(
    id: 'layer-1',
    transform: transform,
    kind: PaintKind.line,
    normalizedPoints: const [Offset(0, 0.5), Offset(1, 0.5)],
    strokeWidth: 12,
  );

  group('content matrix', () {
    testWidgets('text: edit · More only — colour and size moved to the '
        'bench identity row (Text Studio redesign)', (tester) async {
      await pumpWithLayer(tester, text());
      expect(find.byType(QuickCapsule), findsOneWidget);
      expect(pill('Edit text'), findsOneWidget);
      expect(pill('More actions'), findsOneWidget);
      // The colour dot and px readout duplicated the Studio Bench's
      // identity row one gesture away — gone from the capsule.
      expect(pill('Color'), findsNothing);
      expect(pill('Size'), findsNothing);
    });

    testWidgets('image: look · crop · More', (tester) async {
      await pumpWithLayer(tester, image());
      expect(find.byType(QuickCapsule), findsOneWidget);
      expect(pill('Look'), findsOneWidget);
      expect(pill('Crop image'), findsOneWidget);
      expect(pill('More actions'), findsOneWidget);
    });

    testWidgets('shape: fill · corner · More', (tester) async {
      await pumpWithLayer(tester, shape());
      expect(find.byType(QuickCapsule), findsOneWidget);
      expect(pill('Fill'), findsOneWidget);
      expect(pill('Corner radius'), findsOneWidget);
      expect(pill('More actions'), findsOneWidget);
    });

    testWidgets('paint: stroke colour · width readout · More', (tester) async {
      await pumpWithLayer(tester, paintStroke());
      expect(find.byType(QuickCapsule), findsOneWidget);
      expect(pill('Stroke color'), findsOneWidget);
      expect(pill('Stroke size'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(QuickCapsule),
          matching: find.text('12px'),
        ),
        findsOneWidget,
      );
      expect(pill('More actions'), findsOneWidget);
    });

    testWidgets('sticker: replace · More (the audit gap, closed)', (
      tester,
    ) async {
      await pumpWithLayer(tester, text(kind: TextLayerKind.emojiSticker));
      expect(
        find.byType(QuickCapsule),
        findsOneWidget,
        reason:
            'stickers previously fell to the deleted '
            'QuickActionsOverlay — they now get the unified capsule',
      );
      expect(pill('Replace'), findsOneWidget);
      expect(pill('More actions'), findsOneWidget);
      // No text accelerators on a sticker.
      expect(pill('Edit text'), findsNothing);
    });
  });

  group('routes to the same surface as the dock (divergence-impossible)', () {
    // (The text colour pill died with the capsule slim-down — colour
    // now routes through the bench identity row's ink dot, whose
    // contract lives in the bench tests.)

    testWidgets('image look pill opens the look dock slot', (tester) async {
      final c = await pumpWithLayer(tester, image());
      await tapPill(tester, 'Look');
      // The Look body decodes the layer's (stub) asset for its filter
      // previews — swallow the missing-asset load error, same as the
      // sibling chrome test.
      tester.takeException();
      expect(c.read(imageToolControllerProvider).openSlot, ImageToolSlot.look);
      expect(find.byType(QuickCapsule), findsNothing);
    });

    testWidgets('shape fill pill opens the style dock slot', (tester) async {
      final c = await pumpWithLayer(tester, shape());
      await tapPill(tester, 'Fill');
      expect(c.read(shapeToolControllerProvider).openSlot, ShapeToolSlot.style);
      expect(find.byType(QuickCapsule), findsNothing);
    });

    testWidgets('paint colour pill opens the paint color dock slot', (
      tester,
    ) async {
      final c = await pumpWithLayer(tester, paintStroke());
      await tapPill(tester, 'Stroke color');
      expect(c.read(paintToolControllerProvider).openSlot, 'color');
      expect(find.byType(QuickCapsule), findsNothing);
    });

    testWidgets('sticker replace pill opens the replace dock slot', (
      tester,
    ) async {
      final c = await pumpWithLayer(
        tester,
        text(kind: TextLayerKind.emojiSticker),
      );
      await tapPill(tester, 'Replace');
      expect(
        c.read(stickerToolControllerProvider).openSlot,
        StickerToolSlot.replace,
      );
      expect(find.byType(QuickCapsule), findsNothing);
    });

    testWidgets('More pill opens the layer overflow sheet', (tester) async {
      await pumpWithLayer(tester, shape());
      await tapPill(tester, 'More actions');
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });

  group('suppression', () {
    testWidgets('capsule hides while its surface is open and returns on '
        'close', (tester) async {
      final c = await pumpWithLayer(tester, paintStroke());
      await tapPill(tester, 'Stroke color');
      expect(find.byType(QuickCapsule), findsNothing);
      c.read(paintToolControllerProvider.notifier).closeSlot();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(QuickCapsule), findsOneWidget);
    });
  });
}
