import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/image/application/image_tool_controller.dart';
import 'package:canvas_engine/features/editor/image/presentation/image_mode_toolbar.dart';
import 'package:canvas_engine/features/editor/shape/application/shape_tool_controller.dart';
import 'package:canvas_engine/features/editor/shape/presentation/shape_mode_toolbar.dart';
import 'package:canvas_engine/features/editor/sticker/application/sticker_tool_controller.dart';
import 'package:canvas_engine/features/editor/sticker/presentation/sticker_mode_toolbar.dart';
import 'package:canvas_engine/features/editor/toolbar/presentation/slot_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drift detector (tb1 1.11): the sibling-swipe walk must follow
/// the RENDERED strip order. Each test pumps the real mode toolbar,
/// reads the chip ids the strip actually constructed, and compares
/// the panel-bearing projection against the mode's swipe order —
/// so a divergence between what the user sees and where swipe
/// lands is a CI failure, not a code-review hope.
void main() {
  Future<List<String>> pumpAndReadStripIds(
    WidgetTester tester,
    Widget toolbar,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 800, height: 120, child: toolbar),
          ),
        ),
      ),
    );
    final strip = tester.widget<SlotStrip>(find.byType(SlotStrip));
    return strip.slots.map((s) => s.id).toList();
  }

  testWidgets('image swipe order derives from the rendered strip order', (
    tester,
  ) async {
    final layer = ImageLayer(
      id: 'img1',
      transform: const LayerTransform(
        position: Offset(40, 40),
        size: Size(200, 200),
      ),
      source: const ImageSource.asset('assets/test.png'),
    );
    final renderedIds = await pumpAndReadStripIds(
      tester,
      ImageModeToolbar(layer: layer),
    );

    // The strip renders the single-source list verbatim.
    expect(
      renderedIds,
      kImageStripOrder.map((e) => e.slot?.name ?? e.actionId).toList(),
    );

    // Swipe order == rendered order filtered to panel-bearing
    // slots. 'opacity'/'more' are strip-only action chips and
    // crop/replace are one-shot (isPanel: false) — none of them
    // may be reachable by swipe.
    final renderedPanelOrder = renderedIds
        .map(ImageToolSlot.tryByName)
        .whereType<ImageToolSlot>()
        .where((s) => s.isPanel)
        .toList();
    expect(kImageSwipeStrategy.order, renderedPanelOrder);
    expect(kImagePanelSlotOrder, renderedPanelOrder);
  });

  testWidgets('shape swipe order derives from the rendered strip order', (
    tester,
  ) async {
    final layer = ShapeLayer(
      id: 'shape1',
      transform: const LayerTransform(
        position: Offset(40, 40),
        size: Size(200, 200),
      ),
      kind: ShapeKind.rectangle,
    );
    final renderedIds = await pumpAndReadStripIds(
      tester,
      ShapeModeToolbar(layer: layer, onReplaceTap: () {}),
    );

    expect(
      renderedIds,
      kShapeStripOrder.map((e) => e.slot?.name ?? e.actionId).toList(),
    );

    final renderedPanelOrder = renderedIds
        .map(ShapeToolSlot.tryByName)
        .whereType<ShapeToolSlot>()
        .where((s) => s.isPanel)
        .toList();
    expect(kShapeSwipeStrategy.order, renderedPanelOrder);
    expect(kShapePanelSlotOrder, renderedPanelOrder);
  });

  testWidgets('sticker strip renders the single-source order (no swipe)', (
    tester,
  ) async {
    final layer = TextLayer(
      id: 'sticker1',
      transform: const LayerTransform(
        position: Offset(40, 40),
        size: Size(120, 120),
      ),
      content: '😀',
      style: const TextStyleSpec(),
    );
    final renderedIds = await pumpAndReadStripIds(
      tester,
      StickerModeToolbar(layer: layer),
    );

    // Sticker opts out of swipe entirely, so the only single-source
    // contract to hold is strip == list.
    expect(
      renderedIds,
      kStickerStripOrder.map((e) => e.slot?.name ?? e.actionId).toList(),
    );
    // The slot-only projection excludes action chips. Sticker gained
    // a 'more' action in tb6 3/5, so the projection is now a strict
    // subset of the rendered ids rather than equal to them — compare
    // it against the rendered ids with the actions filtered out.
    final renderedSlotIds = kStickerStripOrder
        .where((e) => e.slot != null)
        .map((e) => e.slot!.name)
        .toList();
    expect(kStickerStripSlotOrder.map((s) => s.name).toList(), renderedSlotIds);
    expect(renderedSlotIds.every(renderedIds.contains), isTrue);
  });
}
