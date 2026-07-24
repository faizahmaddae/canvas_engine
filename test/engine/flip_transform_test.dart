// tb4 7/14: mirroring a layer. Design note:
// docs/flip-transform-design-2026-07.md.
//
// The persisted field is omit-default, so the load-bearing pin here
// is the legacy lift: a transform written before flip existed must
// decode as unflipped AND re-encode without the keys, or every
// fixture in the corpus breaks.

import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/core/viewport_state.dart';
import 'package:canvas_engine/features/editor/engine/interaction/layer_space_mapper.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const t = LayerTransform(position: Offset(100, 50), size: Size(200, 100));

  ShapeLayer shape([LayerTransform? transform]) => ShapeLayer(
    id: 's1',
    kind: ShapeKind.rectangle,
    transform: transform ?? t,
  );

  EditorDocument docWith(ShapeLayer l) =>
      EditorDocument(layers: [l], width: 800, height: 800);

  group('serialization', () {
    test('an unflipped transform writes no flip keys at all', () {
      final json = t.toJson();
      expect(json.containsKey('fx'), isFalse);
      expect(json.containsKey('fy'), isFalse);
    });

    test('a legacy transform decodes as unflipped', () {
      final legacy = LayerTransform.fromJson(<String, dynamic>{
        'x': 10.0,
        'y': 20.0,
        'w': 30.0,
        'h': 40.0,
        'r': 0.0,
      });
      expect(legacy.flipH, isFalse);
      expect(legacy.flipV, isFalse);
      expect(legacy.isMirrored, isFalse);
      expect(
        legacy.toJson().keys.toSet(),
        {'x', 'y', 'w', 'h', 'r'},
        reason: 'round-tripping a legacy doc must not add keys to it',
      );
    });

    test('flips round-trip', () {
      final flipped = t.copyWith(flipH: true, flipV: true);
      final decoded = LayerTransform.fromJson(
        Map<String, dynamic>.from(flipped.toJson()),
      );
      expect(decoded, flipped);
    });

    test('flip participates in equality', () {
      expect(t.copyWith(flipH: true) == t, isFalse);
      expect(t.copyWith(flipH: true).hashCode == t.hashCode, isFalse);
    });
  });

  group('FlipLayerCommand', () {
    test('toggles the axis it names and leaves the other alone', () {
      final doc = docWith(shape());
      const cmd = FlipLayerCommand(layerId: 's1', horizontal: true);
      final after = cmd.apply(doc).layerById('s1')!.transform;
      expect(after.flipH, isTrue);
      expect(after.flipV, isFalse);
    });

    test('leaves position, size and rotation untouched', () {
      final doc = docWith(shape(t.copyWith(rotation: 0.4)));
      const cmd = FlipLayerCommand(layerId: 's1', horizontal: false);
      final after = cmd.apply(doc).layerById('s1')!.transform;
      expect(after.position, t.position);
      expect(after.size, t.size);
      expect(after.rotation, 0.4);
      expect(after.flipV, isTrue);
    });

    test('is its own inverse', () {
      final doc = docWith(shape());
      const cmd = FlipLayerCommand(layerId: 's1', horizontal: true);
      final after = cmd.apply(doc);
      final undone = cmd.invert(doc).apply(after);
      expect(undone.layerById('s1')!.transform, t);
    });

    test('a missing layer is a no-op', () {
      final doc = docWith(shape());
      const cmd = FlipLayerCommand(layerId: 'nope', horizontal: true);
      expect(identical(cmd.apply(doc), doc), isTrue);
    });
  });

  group('hit testing follows the pixels', () {
    const viewport = ViewportState(scale: 1, translation: Offset.zero);

    test('a horizontal flip mirrors local x about the centre', () {
      const mapper = LayerSpaceMapper(
        transform: LayerTransform(
          position: Offset(100, 50),
          size: Size(200, 100),
          flipH: true,
        ),
        viewport: viewport,
      );
      // The layer's local left edge is drawn at its canvas RIGHT edge.
      expect(mapper.layerToCanvas(const Offset(0, 50)).dx, 300);
      expect(mapper.layerToCanvas(const Offset(200, 50)).dx, 100);
    });

    test('canvasToLayer is the inverse of layerToCanvas when mirrored', () {
      const mapper = LayerSpaceMapper(
        transform: LayerTransform(
          position: Offset(100, 50),
          size: Size(200, 100),
          rotation: 0.6,
          flipH: true,
          flipV: true,
        ),
        viewport: viewport,
      );
      const local = Offset(35, 80);
      final round = mapper.canvasToLayer(mapper.layerToCanvas(local));
      expect(round.dx, closeTo(local.dx, 1e-9));
      expect(round.dy, closeTo(local.dy, 1e-9));
    });

    test('an unflipped layer maps exactly as before', () {
      const mapper = LayerSpaceMapper(transform: t, viewport: viewport);
      expect(mapper.layerToCanvas(const Offset(0, 0)), const Offset(100, 50));
      expect(
        mapper.layerToCanvas(const Offset(200, 100)),
        const Offset(300, 150),
      );
    });
  });
}
