// Regression: tapping off-canvas (or programmatically picking a
// different layer) must NOT leave the previously-opened object-tool
// sub-panel "remembered" in its controller. The image/shape/sticker
// tool controllers are global non-autoDispose Notifiers, so without
// the central reset their `openSlot` survives the implicit dismiss
// and the panel silently re-mounts the next time the user picks an
// image/shape/sticker — even though they thought they had closed it.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/editing_controller.dart';
import 'package:canvas_engine/features/editor/application/editor_lifecycle.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/canvas/application/canvas_tool_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/image/application/image_tool_controller.dart';
import 'package:canvas_engine/features/editor/paint/application/paint_tool_controller.dart';
import 'package:canvas_engine/features/editor/paint/domain/paint_tool_type.dart';
import 'package:canvas_engine/features/editor/shape/application/shape_tool_controller.dart';
import 'package:canvas_engine/features/editor/sticker/application/sticker_tool_controller.dart';
import 'package:canvas_engine/features/editor/text/application/text_tool_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Probe extends ConsumerWidget {
  const _Probe();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    _ref = ref;
    return const SizedBox.shrink();
  }

  static WidgetRef? _ref;
}

void main() {
  Future<WidgetRef> mountProbe(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: _Probe())),
    );
    return _Probe._ref!;
  }

  testWidgets('dismissActiveEditing closes image/shape/sticker/canvas panels', (
    tester,
  ) async {
    final ref = await mountProbe(tester);

    // Open all four panels.
    ref
        .read(imageToolControllerProvider.notifier)
        .toggleSlot(ImageToolSlot.border);
    ref
        .read(shapeToolControllerProvider.notifier)
        .toggleSlot(ShapeToolSlot.shadow);
    ref
        .read(stickerToolControllerProvider.notifier)
        .toggleSlot(StickerToolSlot.size);
    ref.read(canvasToolControllerProvider.notifier).togglePanel();
    expect(ref.read(imageToolControllerProvider).openSlot, isNotNull);
    expect(ref.read(shapeToolControllerProvider).openSlot, isNotNull);
    expect(ref.read(stickerToolControllerProvider).openSlot, isNotNull);
    expect(ref.read(canvasToolControllerProvider).panelOpen, isTrue);

    dismissActiveEditing(ref);

    expect(
      ref.read(imageToolControllerProvider).openSlot,
      isNull,
      reason: 'image panel must collapse on tap-off-canvas',
    );
    expect(
      ref.read(shapeToolControllerProvider).openSlot,
      isNull,
      reason: 'shape panel must collapse on tap-off-canvas',
    );
    expect(
      ref.read(stickerToolControllerProvider).openSlot,
      isNull,
      reason: 'sticker panel must collapse on tap-off-canvas',
    );
    expect(
      ref.read(canvasToolControllerProvider).panelOpen,
      isFalse,
      reason: 'canvas panel must collapse on tap-off-canvas',
    );
  });

  testWidgets(
    'closeObjectSubPanels collapses image/shape/sticker/text + stops editing but leaves canvas',
    (tester) async {
      final ref = await mountProbe(tester);

      ref
          .read(imageToolControllerProvider.notifier)
          .toggleSlot(ImageToolSlot.border);
      ref
          .read(shapeToolControllerProvider.notifier)
          .toggleSlot(ShapeToolSlot.shadow);
      ref
          .read(stickerToolControllerProvider.notifier)
          .toggleSlot(StickerToolSlot.size);
      ref.read(canvasToolControllerProvider.notifier).togglePanel();
      ref.read(textToolControllerProvider.notifier).openSheet('font');
      ref.read(editingControllerProvider.notifier).start('layer-1');
      expect(ref.read(textToolControllerProvider).openSheet, 'font');
      expect(ref.read(editingControllerProvider), 'layer-1');

      closeObjectSubPanels(ref);

      expect(ref.read(imageToolControllerProvider).openSlot, isNull);
      expect(ref.read(shapeToolControllerProvider).openSlot, isNull);
      expect(ref.read(stickerToolControllerProvider).openSlot, isNull);
      expect(
        ref.read(textToolControllerProvider).openSheet,
        isNull,
        reason: 'text sheet must clear on selection change',
      );
      expect(
        ref.read(editingControllerProvider),
        isNull,
        reason: 'in-flight inline edit must stop on selection change',
      );
      // Canvas is intentionally NOT touched by the selection-change
      // seam — it has no selection, so picking a different layer
      // shouldn't collapse it. Only an explicit dismiss does.
      expect(ref.read(canvasToolControllerProvider).panelOpen, isTrue);
    },
  );

  // ── The paint arm of the selection-change seam (§10.5 N) ──
  //
  // A paint sheet FOLLOWS its target rather than closing: commits
  // select the stroke they add, so closing on every selection change
  // would slam a sheet the user is drawing with. Only a selection
  // landing on a NON-paint layer exits paint — mode derivation puts
  // paint's panelOpen above the selected layer's type, so an armed
  // session left open would keep the paint dock mounted over a text
  // or image selection made from the layers drawer.

  PaintLayer strokeLayer(String id) => PaintLayer(
    id: id,
    transform: const LayerTransform(
      position: Offset(100, 100),
      size: Size(100, 80),
    ),
    kind: PaintKind.line,
    normalizedPoints: const [Offset(0, 0.5), Offset(1, 0.5)],
  );

  testWidgets('selection moving between paint layers keeps the open paint '
      'sheet (retarget, not dismiss)', (tester) async {
    final ref = await mountProbe(tester);
    final documents = ref.read(documentControllerProvider.notifier);
    documents.newDocument(width: 800, height: 800);
    documents.execute(AddLayerCommand(strokeLayer('a')));
    documents.execute(AddLayerCommand(strokeLayer('b')));

    ref.read(selectionControllerProvider.notifier).select('a');
    final paint = ref.read(paintToolControllerProvider.notifier);
    paint.openPanel();
    paint.toggleSlot('color');

    ref.read(selectionControllerProvider.notifier).select('b');
    closeObjectSubPanels(ref);

    final session = ref.read(paintToolControllerProvider);
    expect(session.openSlot, 'color', reason: 'the sheet retargets to b');
    expect(session.panelOpen, isTrue);
  });

  testWidgets('selection landing on a non-paint layer exits paint wholesale', (
    tester,
  ) async {
    final ref = await mountProbe(tester);
    final documents = ref.read(documentControllerProvider.notifier);
    documents.newDocument(width: 800, height: 800);
    documents.execute(AddLayerCommand(strokeLayer('a')));
    documents.execute(
      AddLayerCommand(
        const TextLayer(
          id: 't',
          transform: LayerTransform(
            position: Offset(300, 300),
            size: Size(200, 60),
          ),
          content: 'hi',
          style: TextStyleSpec(fontSize: 32),
        ),
      ),
    );

    ref.read(selectionControllerProvider.notifier).select('a');
    final paint = ref.read(paintToolControllerProvider.notifier);
    paint.openPanel();
    paint.toggleSlot('color');

    ref.read(selectionControllerProvider.notifier).select('t');
    closeObjectSubPanels(ref);

    final session = ref.read(paintToolControllerProvider);
    expect(session.panelOpen, isFalse, reason: 'paint exits for a text layer');
    expect(session.openSlot, isNull);
    expect(session.activeTool, isNull);
  });

  testWidgets('a no-selection sweep leaves an armed paint session alone', (
    tester,
  ) async {
    final ref = await mountProbe(tester);
    ref
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    final paint = ref.read(paintToolControllerProvider.notifier);
    paint.selectTool(PaintToolType.freestyle);
    paint.toggleSlot('color');

    closeObjectSubPanels(ref);

    final session = ref.read(paintToolControllerProvider);
    expect(session.panelOpen, isTrue);
    expect(session.openSlot, 'color');
    expect(session.activeTool, PaintToolType.freestyle);
  });
}
