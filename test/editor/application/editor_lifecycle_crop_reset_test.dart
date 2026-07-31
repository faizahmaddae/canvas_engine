// Regression: opening the editor must NOT inherit a crop session
// left active by a previous editor instance. The crop controller
// is a global non-autoDispose Notifier; without an explicit reset
// at the project boundary the new editor would mount with crop
// mode already on, often pointing at a layer id that doesn't
// exist in the new document.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/editor_lifecycle.dart';
import 'package:canvas_engine/features/editor/canvas/application/canvas_tool_controller.dart';
import 'package:canvas_engine/features/editor/crop/application/crop_controller.dart';
import 'package:canvas_engine/features/editor/image/application/image_tool_controller.dart';
import 'package:canvas_engine/features/editor/shape/application/shape_tool_controller.dart';
import 'package:canvas_engine/features/editor/sticker/application/sticker_tool_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
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
  testWidgets('resetEditorEphemeralState cancels any active crop session', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: _Probe())),
    );
    final ref = _Probe._ref!;
    // Seed a document and open a crop session, simulating leftover
    // state from a previous editor.
    final doc = ref.read(documentControllerProvider.notifier);
    doc.newDocument(width: 500, height: 500);
    doc.execute(
      AddLayerCommand(
        ImageLayer(
          id: 'i',
          transform: LayerTransform(
            position: Offset.zero,
            size: const Size(400, 400),
          ),
          source: const ImageSource.asset('a.png'),
        ),
      ),
    );
    ref.read(cropControllerProvider.notifier).openCrop('i');
    expect(ref.read(cropControllerProvider).active, isTrue);

    resetEditorEphemeralState(ref);

    expect(
      ref.read(cropControllerProvider).active,
      isFalse,
      reason: 'crop must be cancelled when entering a fresh editor',
    );
  });

  // Same class of bug, four more controllers. Every dock tool is a
  // global non-autoDispose Notifier, so an open sub-tool panel
  // outlives the editor route: open Canvas, back out to Home, create
  // a new canvas, and the new editor mounts with the panel still
  // expanded — over a document that has nothing to do with it.
  // `resetEditorEphemeralState` covered text/paint/crop/mask but not
  // canvas/image/shape/sticker.
  testWidgets('resetEditorEphemeralState closes every dock tool panel', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: _Probe())),
    );
    final ref = _Probe._ref!;
    ref
        .read(documentControllerProvider.notifier)
        .newDocument(width: 500, height: 500);

    // Leave one panel open on each tool, as a previous session would.
    ref.read(canvasToolControllerProvider.notifier).togglePanel();
    ref
        .read(imageToolControllerProvider.notifier)
        .toggleSlot(ImageToolSlot.look);
    ref
        .read(shapeToolControllerProvider.notifier)
        .toggleSlot(ShapeToolSlot.style);
    ref
        .read(stickerToolControllerProvider.notifier)
        .toggleSlot(StickerToolSlot.size);

    expect(ref.read(canvasToolControllerProvider).panelOpen, isTrue);
    expect(ref.read(imageToolControllerProvider).openSlot, isNotNull);
    expect(ref.read(shapeToolControllerProvider).openSlot, isNotNull);
    expect(ref.read(stickerToolControllerProvider).openSlot, isNotNull);

    resetEditorEphemeralState(ref);

    expect(
      ref.read(canvasToolControllerProvider).panelOpen,
      isFalse,
      reason: 'the Canvas panel must not survive into a new project',
    );
    expect(
      ref.read(imageToolControllerProvider).openSlot,
      isNull,
      reason: 'an Image sub-tool must not survive into a new project',
    );
    expect(
      ref.read(shapeToolControllerProvider).openSlot,
      isNull,
      reason: 'a Shape sub-tool must not survive into a new project',
    );
    expect(
      ref.read(stickerToolControllerProvider).openSlot,
      isNull,
      reason: 'a Sticker sub-tool must not survive into a new project',
    );
  });
}
