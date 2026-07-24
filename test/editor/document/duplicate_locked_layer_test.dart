// Roadmap tb0 0.10: a clone of a LOCKED layer must start unlocked.
// A locked clone is immovable and invisible to hit-testing, so the
// duplicate action read as "did nothing" — most visibly when
// duplicating the protected base photo via Image → More.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/layer_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Probe extends ConsumerWidget {
  const _Probe();
  static WidgetRef? ref;
  @override
  Widget build(BuildContext context, WidgetRef r) {
    ref = r;
    return const SizedBox.shrink();
  }
}

void main() {
  testWidgets('duplicating a locked layer produces an unlocked clone', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: _Probe())),
    );
    final ref = _Probe.ref!;
    final docCtrl = ref.read(documentControllerProvider.notifier);
    docCtrl.newDocument(width: 500, height: 500);
    docCtrl.execute(
      AddLayerCommand(
        ShapeLayer(
          id: 'locked-src',
          transform: const LayerTransform(
            position: Offset(10, 10),
            size: Size(100, 100),
          ),
          kind: ShapeKind.rectangle,
          locked: true,
        ),
      ),
    );

    LayerActions.duplicate(
      ref,
      ref.read(documentControllerProvider).layerById('locked-src')!,
    );

    final doc = ref.read(documentControllerProvider);
    expect(doc.layers, hasLength(2));
    final clone = doc.layers.firstWhere((l) => l.id != 'locked-src');
    expect(clone.locked, isFalse, reason: 'clones must be editable');
    expect(
      clone.transform.position,
      const Offset(18, 18),
      reason: 'standard duplicate nudge still applies',
    );
    // Clone is selected (standard duplicate behaviour).
    expect(ref.read(selectionControllerProvider).selectedId, clone.id);
    // The source stays locked.
    expect(doc.layerById('locked-src')!.locked, isTrue);
  });
}
