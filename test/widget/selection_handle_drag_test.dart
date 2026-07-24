import 'package:canvas_engine/core/constants/engine_constants.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/core/selection_state.dart';
import 'package:canvas_engine/features/editor/engine/core/viewport_state.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/selection_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Touching *anywhere* inside the 48-dp visual square must start a drag.
/// This test directly pumps the overlay on its own (no editor chrome) so
/// it exercises the handle hit surface in isolation.
void main() {
  testWidgets('drag starts from every point inside each corner handle', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final starts = <(InteractionHandle, Offset)>[];

    const transform = LayerTransform(
      position: Offset(200, 200),
      size: Size(300, 300),
    );
    const viewport = ViewportState(scale: 1, translation: Offset.zero);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              LayerSelectionOverlay(
                transform: transform,
                viewport: viewport,
                onHandle: (h, p, phase) {
                  if (phase == DragPhase.start) starts.add((h, p));
                },
              ),
            ],
          ),
        ),
      ),
    );

    // Layer corners in screen space (scale=1, no translation),
    // pushed outward by [EngineConstants.selectionOutset] along
    // the rect's local axes — this is where [LayerSelectionOverlay]
    // actually places the handle hit boxes (see `outsetSelectionQuad`
    // in selection_overlay.dart). Without compensating for the
    // outset, edge probes at +/- (touch/2 - 1) miss the 48-dp box.
    // Top-right is the unified rotate handle (text-style rotation
    // pattern applied universally), the other three are resize.
    const o = EngineConstants.selectionOutset; // 6
    const corners = <InteractionHandle, Offset>{
      InteractionHandle.topLeft: Offset(200 - o, 200 - o),
      InteractionHandle.rotate: Offset(500 + o, 200 - o),
      InteractionHandle.bottomLeft: Offset(200 - o, 500 + o),
      InteractionHandle.bottomRight: Offset(500 + o, 500 + o),
    };

    final touch = EngineConstants.handleTouchSize; // 48
    // 9 probe points: centre, 4 mid-edges, 4 extreme corners of the
    // hit box. All must start a drag on the expected handle.
    final probes = <Offset>[
      Offset.zero,
      Offset(touch / 2 - 1, 0),
      Offset(-touch / 2 + 1, 0),
      Offset(0, touch / 2 - 1),
      Offset(0, -touch / 2 + 1),
      Offset(touch / 2 - 1, touch / 2 - 1),
      Offset(-touch / 2 + 1, touch / 2 - 1),
      Offset(touch / 2 - 1, -touch / 2 + 1),
      Offset(-touch / 2 + 1, -touch / 2 + 1),
    ];

    for (final entry in corners.entries) {
      for (final probe in probes) {
        starts.clear();
        final gesture = await tester.startGesture(entry.value + probe);
        await tester.pump();
        expect(
          starts,
          hasLength(1),
          reason:
              'Expected drag to start at probe $probe inside ${entry.key} '
              'hit box (centre ${entry.value}).',
        );
        expect(starts.single.$1, entry.key);
        await gesture.up();
        await tester.pump();
      }
    }
  });
}
