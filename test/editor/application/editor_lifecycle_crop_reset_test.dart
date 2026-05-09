// Regression: opening the editor must NOT inherit a crop session
// left active by a previous editor instance. The crop controller
// is a global non-autoDispose Notifier; without an explicit reset
// at the project boundary the new editor would mount with crop
// mode already on, often pointing at a layer id that doesn't
// exist in the new document.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/editor_lifecycle.dart';
import 'package:canvas_engine/features/editor/crop/application/crop_controller.dart';
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
  testWidgets(
      'resetEditorEphemeralState cancels any active crop session',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: _Probe()),
    ));
    final ref = _Probe._ref!;
    // Seed a document and open a crop session, simulating leftover
    // state from a previous editor.
    final doc = ref.read(documentControllerProvider.notifier);
    doc.newDocument(width: 500, height: 500);
    doc.execute(AddLayerCommand(ImageLayer(
      id: 'i',
      transform: LayerTransform(
        position: Offset.zero,
        size: const Size(400, 400),
      ),
      source: const ImageSource.asset('a.png'),
    )));
    ref.read(cropControllerProvider.notifier).openCrop('i');
    expect(ref.read(cropControllerProvider).active, isTrue);

    resetEditorEphemeralState(ref);

    expect(ref.read(cropControllerProvider).active, isFalse,
        reason: 'crop must be cancelled when entering a fresh editor');
  });
}
