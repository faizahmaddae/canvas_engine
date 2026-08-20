import 'package:canvas_engine/features/editor/application/alignment_controller.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/interaction/alignment_engine.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    c
        .read(documentControllerProvider.notifier)
        .newDocument(width: 1000, height: 1000);
    return c;
  }

  void addRect(
    ProviderContainer c, {
    required String id,
    required Offset position,
    Size size = const Size(50, 50),
    bool locked = false,
  }) {
    c
        .read(documentControllerProvider.notifier)
        .execute(
          AddLayerCommand(
            ShapeLayer(
              id: id,
              transform: LayerTransform(position: position, size: size),
              kind: ShapeKind.rectangle,
              locked: locked,
            ),
          ),
        );
  }

  test('align left moves every selected layer to bounds.left', () {
    final c = makeContainer();
    addRect(c, id: 'a', position: const Offset(20, 0));
    addRect(c, id: 'b', position: const Offset(80, 100));
    addRect(c, id: 'cc', position: const Offset(150, 200));
    c.read(selectionControllerProvider.notifier).select('a');
    c.read(selectionControllerProvider.notifier).add('b');
    c.read(selectionControllerProvider.notifier).add('cc');

    c.read(alignmentControllerProvider).align(AlignAxis.left);
    final doc = c.read(documentControllerProvider);
    expect(doc.layerById('a')!.transform.position.dx, 20);
    expect(doc.layerById('b')!.transform.position.dx, 20);
    expect(doc.layerById('cc')!.transform.position.dx, 20);
  });

  test('align is undoable as a single composite step', () {
    final c = makeContainer();
    addRect(c, id: 'a', position: const Offset(20, 0));
    addRect(c, id: 'b', position: const Offset(80, 100));
    addRect(c, id: 'cc', position: const Offset(150, 200));
    c.read(selectionControllerProvider.notifier).select('a');
    c.read(selectionControllerProvider.notifier).add('b');
    c.read(selectionControllerProvider.notifier).add('cc');

    c.read(alignmentControllerProvider).align(AlignAxis.left);
    c.read(documentControllerProvider.notifier).undo();
    final doc = c.read(documentControllerProvider);
    expect(doc.layerById('a')!.transform.position.dx, 20);
    expect(doc.layerById('b')!.transform.position.dx, 80);
    expect(doc.layerById('cc')!.transform.position.dx, 150);
  });

  test('distribute horizontally evens out gaps; outers fixed', () {
    final c = makeContainer();
    addRect(c, id: 'a', position: const Offset(0, 0));
    addRect(
      c,
      id: 'b',
      position: const Offset(80, 0),
      size: const Size(30, 30),
    );
    addRect(c, id: 'cc', position: const Offset(200, 0));
    c.read(selectionControllerProvider.notifier).select('a');
    c.read(selectionControllerProvider.notifier).add('b');
    c.read(selectionControllerProvider.notifier).add('cc');

    c.read(alignmentControllerProvider).distribute(DistributeAxis.horizontal);

    final doc = c.read(documentControllerProvider);
    // Span 0..250, sum extents = 50+30+50 = 130, gap = 60, mid at 110.
    expect(doc.layerById('a')!.transform.position.dx, 0);
    expect(doc.layerById('cc')!.transform.position.dx, 200);
    expect(doc.layerById('b')!.transform.position.dx, closeTo(110, 0.001));
  });

  test('alignToCanvas moves a single selected layer to canvas edge', () {
    final c = makeContainer();
    addRect(c, id: 'a', position: const Offset(20, 30));
    c.read(selectionControllerProvider.notifier).select('a');

    c.read(alignmentControllerProvider).alignToCanvas(AlignAxis.right);

    final doc = c.read(documentControllerProvider);
    expect(doc.layerById('a')!.transform.position.dx, 950);
    expect(doc.layerById('a')!.transform.position.dy, 30);
  });

  test('distribute vertically evens out gaps; outers fixed', () {
    final c = makeContainer();
    addRect(c, id: 'a', position: const Offset(0, 0));
    addRect(
      c,
      id: 'b',
      position: const Offset(0, 80),
      size: const Size(30, 30),
    );
    addRect(c, id: 'cc', position: const Offset(0, 200));
    c.read(selectionControllerProvider.notifier).select('a');
    c.read(selectionControllerProvider.notifier).add('b');
    c.read(selectionControllerProvider.notifier).add('cc');

    c.read(alignmentControllerProvider).distribute(DistributeAxis.vertical);

    final doc = c.read(documentControllerProvider);
    expect(doc.layerById('a')!.transform.position.dy, 0);
    expect(doc.layerById('cc')!.transform.position.dy, 200);
    expect(doc.layerById('b')!.transform.position.dy, closeTo(110, 0.001));
  });

  test('no-op when fewer than two movable layers selected', () {
    final c = makeContainer();
    addRect(c, id: 'a', position: const Offset(20, 0));
    c.read(selectionControllerProvider.notifier).select('a');

    c.read(alignmentControllerProvider).align(AlignAxis.left);
    final doc = c.read(documentControllerProvider);
    expect(doc.layerById('a')!.transform.position.dx, 20);
  });

  // ── lock eligibility (audit P2-7): the controller's drops, pinned ──

  test('mixed group: align moves only eligible members, locked stays', () {
    final c = makeContainer();
    addRect(c, id: 'a', position: const Offset(20, 0));
    addRect(c, id: 'b', position: const Offset(80, 100));
    addRect(c, id: 'frozen', position: const Offset(150, 200), locked: true);
    c.read(selectionControllerProvider.notifier).selectMany([
      'a',
      'b',
      'frozen',
    ]);

    c.read(alignmentControllerProvider).align(AlignAxis.left);

    // Bounds come from the ELIGIBLE members only, so the locked layer
    // neither moves nor pulls the alignment edge toward itself.
    final doc = c.read(documentControllerProvider);
    expect(doc.layerById('a')!.transform.position.dx, 20);
    expect(doc.layerById('b')!.transform.position.dx, 20);
    expect(doc.layerById('frozen')!.transform.position.dx, 150);
  });

  test('mixed pair with a single movable member: align is a no-op', () {
    final c = makeContainer();
    addRect(c, id: 'a', position: const Offset(20, 0));
    addRect(c, id: 'frozen', position: const Offset(150, 200), locked: true);
    c.read(selectionControllerProvider.notifier).selectMany(['a', 'frozen']);

    c.read(alignmentControllerProvider).align(AlignAxis.left);

    final doc = c.read(documentControllerProvider);
    expect(doc.layerById('a')!.transform.position.dx, 20);
    expect(doc.layerById('frozen')!.transform.position.dx, 150);
  });

  test('distribute needs three ELIGIBLE members, not three selected', () {
    final c = makeContainer();
    addRect(c, id: 'a', position: const Offset(0, 0));
    addRect(c, id: 'b', position: const Offset(80, 0));
    addRect(c, id: 'frozen', position: const Offset(200, 0), locked: true);
    c.read(selectionControllerProvider.notifier).selectMany([
      'a',
      'b',
      'frozen',
    ]);

    c.read(alignmentControllerProvider).distribute(DistributeAxis.horizontal);

    final doc = c.read(documentControllerProvider);
    expect(doc.layerById('a')!.transform.position.dx, 0);
    expect(doc.layerById('b')!.transform.position.dx, 80);
    expect(doc.layerById('frozen')!.transform.position.dx, 200);
  });

  test('alignToCanvas is a no-op for a locked layer', () {
    final c = makeContainer();
    addRect(c, id: 'frozen', position: const Offset(20, 30), locked: true);
    c.read(selectionControllerProvider.notifier).select('frozen');

    c.read(alignmentControllerProvider).alignToCanvas(AlignAxis.right);

    final doc = c.read(documentControllerProvider);
    expect(doc.layerById('frozen')!.transform.position.dx, 20);
  });

  // ── AlignmentEligibility: THE rule the UI gates render from must
  //    agree with the drops above (audit P2-7's drift complaint) ────

  test('eligibility mirrors the controller thresholds', () {
    final c = makeContainer();
    addRect(c, id: 'a', position: const Offset(20, 0));
    addRect(c, id: 'b', position: const Offset(80, 0));
    addRect(c, id: 'frozen', position: const Offset(150, 0), locked: true);
    final doc = c.read(documentControllerProvider);

    // Locked single: nothing to align to canvas.
    final lockedSingle = AlignmentEligibility.of(doc, [
      doc.layerById('frozen')!,
    ]);
    expect(lockedSingle.canAlign, isFalse);

    // Movable single: canvas alignment available, distribute never.
    final single = AlignmentEligibility.of(doc, [doc.layerById('a')!]);
    expect(single.canAlign, isTrue);
    expect(single.canDistribute, isFalse);

    // Mixed pair (1 eligible): align() would bail on `< 2`.
    final mixedPair = AlignmentEligibility.of(doc, [
      doc.layerById('a')!,
      doc.layerById('frozen')!,
    ]);
    expect(mixedPair.canAlign, isFalse);

    // Mixed trio (2 eligible): align yes, distribute (`< 3`) no.
    final mixedTrio = AlignmentEligibility.of(doc, [
      doc.layerById('a')!,
      doc.layerById('b')!,
      doc.layerById('frozen')!,
    ]);
    expect(mixedTrio.canAlign, isTrue);
    expect(mixedTrio.canDistribute, isFalse);
  });

  test('eligibility refuses the protected base photo even unlocked', () {
    final c = ProviderContainer();
    final ctrl = c.read(documentControllerProvider.notifier);
    ctrl.newDocument(width: 400, height: 300, kind: ProjectKind.photo);
    // Deliberately NOT locked: the import flow locks the base photo,
    // but the eligibility rule must hold without leaning on that.
    ctrl.execute(
      AddLayerCommand(
        ImageLayer(
          id: 'photo',
          transform: const LayerTransform(
            position: Offset.zero,
            size: Size(400, 300),
          ),
          source: const ImageSource.asset('a.png'),
        ),
      ),
    );
    ctrl.execute(const SetBasePhotoCommand('photo'));

    final doc = c.read(documentControllerProvider);
    final eligibility = AlignmentEligibility.of(doc, [doc.layerById('photo')!]);
    expect(eligibility.canAlign, isFalse);
  });
}
