// tb1 16/17 rebuild-isolation evidence, measured against a 200-layer
// document (the layer-count stress line in the roadmap's edge-case
// matrix). Two contracts:
//
//  1. The screen-level payload selects (renderedDocumentProvider
//     narrowed to layerById(selectedId)) must NOT emit when a
//     DIFFERENT layer streams overlay previews. Pre-fix the screen
//     watched the whole merged document, so every preview frame of
//     any layer re-ran the entire EditorScreen build.
//  2. SnapEngine returns identity-stable (const) empty guide lists,
//     because interaction state stores them per move tick and the
//     canvas' Riverpod selects compare lists by identity — fresh
//     empties read as "changed" and re-ran the whole canvas build on
//     every no-snap drag frame.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/live_overlay_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_layer.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/interaction/snap_engine.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ShapeLayer _shape(String id, double x) => ShapeLayer(
  id: id,
  transform: LayerTransform(position: Offset(x, 100), size: const Size(40, 40)),
  kind: ShapeKind.rectangle,
  fillColor: const Color(0xFF808080),
);

void main() {
  test('narrowed payload select ignores foreign overlay ticks '
      '(200-layer doc, 60 preview frames)', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final docCtrl = c.read(documentControllerProvider.notifier);
    docCtrl.newDocument(width: 4000, height: 4000);
    final layers = [for (var i = 0; i < 200; i++) _shape('L$i', i * 15.0)];
    docCtrl.execute(
      CompositeCommand([for (final l in layers) AddLayerCommand(l)]),
    );

    // The narrowed select the screen helpers now use, pinned on L0.
    var narrowedEmissions = 0;
    final narrowSub = c.listen<EditorLayer?>(
      renderedDocumentProvider.select((d) => d.layerById('L0')),
      (_, _) => narrowedEmissions++,
    );
    addTearDown(narrowSub.close);
    // The old pattern: whole merged document.
    var fullEmissions = 0;
    final fullSub = c.listen(renderedDocumentProvider, (_, _) {
      fullEmissions++;
    });
    addTearDown(fullSub.close);

    // 60 preview frames on a DIFFERENT layer (a 1s style drag).
    // Riverpod delivers notifications per event-loop turn, so yield
    // between ticks — in the app each gesture frame is its own turn.
    final overlay = c.read(liveOverlayProvider.notifier);
    final base = layers.last;
    for (var i = 1; i <= 60; i++) {
      // Transform participates in EditorLayer equality (a drag
      // preview), so every tick is a distinct merged document.
      overlay.replaceLayer(
        base.withTransform(
          base.transform.copyWith(
            position: base.transform.position + Offset(i.toDouble(), 0),
          ),
        ),
      );
      await Future<void>(() {});
    }
    await Future<void>.delayed(Duration.zero);

    expect(
      fullEmissions,
      60,
      reason: 'baseline: the old whole-doc watch fired per frame',
    );
    expect(
      narrowedEmissions,
      0,
      reason:
          'the narrowed select must be silent for foreign previews — '
          'this is what stops per-frame EditorScreen rebuilds',
    );
  });

  test('no-snap results carry identity-stable empty guide lists', () {
    final engine = SnapEngine();
    SnapResult run() => engine.snapPosition(
      // Far from every peer and from canvas guides: nothing engages.
      proposed: const Offset(1111.7, 933.3),
      size: const Size(10, 10),
      peerRects: const [Rect.fromLTWH(0, 0, 5, 5)],
      canvasSize: const Size(4000, 4000),
    );
    final a = run();
    final b = run();
    expect(a.guides, isEmpty);
    expect(
      identical(a.guides, b.guides),
      isTrue,
      reason:
          'fresh empty allocations per tick defeat the canvas select '
          'granularity (lists compare by identity)',
    );
  });
}
