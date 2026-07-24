// tb4 3/14: restyling an already-committed stroke. The command grew
// blurSigma / sides / kind; the kind switch is constrained to the
// layer's own geometry family so a restyle can never invalidate the
// points the stroke was drawn with.

import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/commands/paint_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PaintLayer makeLayer({
    PaintKind kind = PaintKind.rectangle,
    int sides = 6,
    double blurSigma = 12,
  }) => PaintLayer(
    id: 'p1',
    transform: const LayerTransform(
      position: Offset(10, 10),
      size: Size(200, 100),
    ),
    kind: kind,
    normalizedPoints: const [Offset.zero, Offset(1, 1)],
    sides: sides,
    blurSigma: blurSigma,
  );

  EditorDocument docWith(PaintLayer layer) =>
      EditorDocument(layers: [layer], width: 800, height: 600);

  PaintLayer paintOf(EditorDocument doc) => doc.layerById('p1') as PaintLayer;

  group('new fields', () {
    test('sides and blurSigma are settable and invertible', () {
      final doc = docWith(makeLayer(kind: PaintKind.polygon));
      const cmd = UpdatePaintStyleCommand(layerId: 'p1', sides: 8);
      final after = cmd.apply(doc);
      expect(paintOf(after).sides, 8);

      final undone = cmd.invert(doc).apply(after);
      expect(paintOf(undone).sides, 6);
    });

    test('blurSigma round-trips', () {
      final doc = docWith(makeLayer(kind: PaintKind.blur));
      const cmd = UpdatePaintStyleCommand(layerId: 'p1', blurSigma: 40);
      final after = cmd.apply(doc);
      expect(paintOf(after).blurSigma, 40);
      expect(paintOf(cmd.invert(doc).apply(after)).blurSigma, 12);
    });

    test('a no-net-change edit is dropped', () {
      final doc = docWith(makeLayer(kind: PaintKind.polygon));
      const cmd = UpdatePaintStyleCommand(layerId: 'p1', sides: 6);
      expect(identical(cmd.apply(doc), doc), isTrue);
    });
  });

  group('kind switch', () {
    test('box kinds are peers', () {
      final doc = docWith(makeLayer(kind: PaintKind.rectangle));
      const cmd = UpdatePaintStyleCommand(
        layerId: 'p1',
        kind: PaintKind.polygon,
      );
      expect(paintOf(cmd.apply(doc)).kind, PaintKind.polygon);
    });

    test('line kinds are peers', () {
      final doc = docWith(makeLayer(kind: PaintKind.line));
      const cmd = UpdatePaintStyleCommand(
        layerId: 'p1',
        kind: PaintKind.dashDotLine,
      );
      expect(paintOf(cmd.apply(doc)).kind, PaintKind.dashDotLine);
    });

    test('crossing families is rejected, not applied', () {
      final doc = docWith(makeLayer(kind: PaintKind.freestyle));
      const cmd = UpdatePaintStyleCommand(
        layerId: 'p1',
        kind: PaintKind.rectangle,
      );
      final after = cmd.apply(doc);
      expect(
        paintOf(after).kind,
        PaintKind.freestyle,
        reason: 'a freehand polyline has points a box kind would discard',
      );
      expect(identical(after, doc), isTrue, reason: 'and it is a no-op');
    });

    test('blur is nobody\'s peer', () {
      final doc = docWith(makeLayer(kind: PaintKind.rectangle));
      const cmd = UpdatePaintStyleCommand(layerId: 'p1', kind: PaintKind.blur);
      expect(paintOf(cmd.apply(doc)).kind, PaintKind.rectangle);
    });

    test('undo restores the previous kind and keeps the points', () {
      final layer = makeLayer(kind: PaintKind.circle);
      final doc = docWith(layer);
      const cmd = UpdatePaintStyleCommand(
        layerId: 'p1',
        kind: PaintKind.hexagon,
      );
      final after = cmd.apply(doc);
      final undone = cmd.invert(doc).apply(after);
      expect(paintOf(undone).kind, PaintKind.circle);
      expect(paintOf(undone).normalizedPoints, layer.normalizedPoints);
    });

    test('peer groups are symmetric', () {
      for (final kind in PaintKind.values) {
        for (final peer in paintKindPeers(kind)) {
          expect(
            paintKindPeers(peer).contains(kind),
            isTrue,
            reason: '$kind -> $peer must be reversible for invert to work',
          );
        }
      }
    });
  });

  group('merge parity', () {
    test('live bursts on the same new field coalesce', () {
      const a = UpdatePaintStyleCommand(
        layerId: 'p1',
        blurSigma: 10,
        live: true,
      );
      const b = UpdatePaintStyleCommand(
        layerId: 'p1',
        blurSigma: 20,
        live: true,
      );
      expect(b.mergeWith(a), same(b));
    });

    test('different new fields stay separate entries', () {
      const a = UpdatePaintStyleCommand(layerId: 'p1', sides: 5, live: true);
      const b = UpdatePaintStyleCommand(
        layerId: 'p1',
        blurSigma: 20,
        live: true,
      );
      expect(b.mergeWith(a), isNull);
    });

    test('a kind switch never merges into a value drag', () {
      const a = UpdatePaintStyleCommand(
        layerId: 'p1',
        blurSigma: 20,
        live: true,
      );
      const b = UpdatePaintStyleCommand(
        layerId: 'p1',
        kind: PaintKind.dashLine,
        live: true,
      );
      expect(b.mergeWith(a), isNull);
    });
  });
}
