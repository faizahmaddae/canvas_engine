import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/live_overlay_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/canvas_sizing.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/paint/application/paint_tool_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer harness(PaintLayer layer) {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final documents = container.read(documentControllerProvider.notifier);
    documents.newDocument(width: 800, height: 800);
    documents.execute(AddLayerCommand(layer));
    container.read(selectionControllerProvider.notifier).select(layer.id);
    return container;
  }

  PaintLayer committed(ProviderContainer container, String id) =>
      container.read(documentControllerProvider).layerById(id) as PaintLayer;

  // Keep a live subscription on the display provider for the whole
  // test — the dock watches it, so the test must too. A bare `read`
  // recomputes on demand and would pass even if nothing ever notified;
  // listening proves staging PUSHES a new view. The returned list is
  // the notification log.
  List<PaintStyleView> watchStyleView(ProviderContainer container) {
    final seen = <PaintStyleView>[];
    container.listen(
      paintStyleViewProvider,
      (_, next) => seen.add(next),
      fireImmediately: true,
    );
    return seen;
  }

  test(
    'opacity stages on overlay and commits once without leaking defaults',
    () {
      final container = harness(
        PaintLayer(
          id: 'stroke',
          transform: const LayerTransform(
            position: Offset(20, 20),
            size: Size(200, 100),
          ),
          kind: PaintKind.line,
          normalizedPoints: const [Offset.zero, Offset(1, 1)],
          strokeColor: const Color(0xFF336699),
        ),
      );
      final controller = container.read(paintToolControllerProvider.notifier);
      final defaults = container.read(paintToolControllerProvider);
      final version = container.read(documentCommitVersionProvider);

      controller.previewStrokeOpacity(40);

      expect(container.read(documentCommitVersionProvider), version);
      expect(committed(container, 'stroke').strokeColor.a, 1);
      final staged =
          container.read(liveOverlayProvider).replacements['stroke']
              as PaintLayer;
      expect(staged.strokeColor.a, closeTo(0.4, 0.001));
      expect(
        container.read(paintToolControllerProvider).strokeColor,
        defaults.strokeColor,
      );

      controller.commitStrokeOpacity(40);

      expect(container.read(documentCommitVersionProvider), version + 1);
      expect(container.read(liveOverlayProvider).isEmpty, isTrue);
      expect(committed(container, 'stroke').strokeColor.a, closeTo(0.4, 0.001));
      container.read(documentControllerProvider.notifier).undo();
      expect(committed(container, 'stroke').strokeColor.a, 1);
    },
  );

  test('blur stages reference pixels as canvas pixels and commits once', () {
    final container = harness(
      PaintLayer(
        id: 'blur',
        transform: LayerTransform(
          position: Offset(20, 20),
          size: Size(200, 100),
        ),
        kind: PaintKind.blur,
        normalizedPoints: [],
        blurSigma: 12,
      ),
    );
    final controller = container.read(paintToolControllerProvider.notifier);
    final doc = container.read(documentControllerProvider);
    final expected = CanvasSizing.scaleDimension(30, doc);
    final version = container.read(documentCommitVersionProvider);

    controller.previewBlurRadius(30);

    expect(container.read(documentCommitVersionProvider), version);
    expect(committed(container, 'blur').blurSigma, 12);
    final staged =
        container.read(liveOverlayProvider).replacements['blur'] as PaintLayer;
    expect(staged.blurSigma, closeTo(expected, 0.0001));

    controller.commitBlurRadius(30);

    expect(container.read(documentCommitVersionProvider), version + 1);
    expect(container.read(liveOverlayProvider).isEmpty, isTrue);
    expect(committed(container, 'blur').blurSigma, closeTo(expected, 0.0001));
    expect(
      container.read(paintStyleViewProvider).blurRadius,
      closeTo(30, 0.0001),
    );
  });

  test('blur commit cannot reuse a preview command from another layer', () {
    final container = harness(
      PaintLayer(
        id: 'blur',
        transform: const LayerTransform(
          position: Offset(20, 20),
          size: Size(200, 100),
        ),
        kind: PaintKind.blur,
        normalizedPoints: const [],
        blurSigma: 12,
      ),
    );
    final documents = container.read(documentControllerProvider.notifier);
    documents.execute(
      AddLayerCommand(
        PaintLayer(
          id: 'line',
          transform: const LayerTransform(
            position: Offset(250, 20),
            size: Size(200, 100),
          ),
          kind: PaintKind.line,
          normalizedPoints: const [Offset.zero, Offset(1, 1)],
        ),
      ),
    );
    final controller = container.read(paintToolControllerProvider.notifier);
    controller.previewBlurRadius(30);
    final version = container.read(documentCommitVersionProvider);

    container.read(selectionControllerProvider.notifier).select('line');
    controller.commitBlurRadius(50);

    expect(container.read(documentCommitVersionProvider), version);
    expect(committed(container, 'blur').blurSigma, 12);
    expect(container.read(liveOverlayProvider).isEmpty, isTrue);
  });

  test(
    'without a selection previews update defaults and never the document',
    () {
      final container = harness(
        PaintLayer(
          id: 'stroke',
          transform: const LayerTransform(
            position: Offset(20, 20),
            size: Size(200, 100),
          ),
          kind: PaintKind.line,
          normalizedPoints: const [Offset.zero, Offset(1, 1)],
        ),
      );
      container.read(selectionControllerProvider.notifier).clear();
      final controller = container.read(paintToolControllerProvider.notifier);
      final version = container.read(documentCommitVersionProvider);

      controller.previewStrokeOpacity(35);
      controller.commitStrokeOpacity(35);
      controller.previewBlurRadius(28);
      controller.commitBlurRadius(28);

      final session = container.read(paintToolControllerProvider);
      expect(session.strokeColor.a, closeTo(0.35, 0.001));
      expect(session.blurRadius, 28);
      expect(container.read(documentCommitVersionProvider), version);
      expect(container.read(liveOverlayProvider).isEmpty, isTrue);
    },
  );

  // ─── the display provider IS a consumer of the preview ────────────
  //
  // [paintStyleViewProvider] feeds every paint surface that shows a
  // value: the strip's value labels and swatches, the Size hero and
  // its precision thumb, the Polygon/Fill previews. It reads the
  // RENDERED document, so a staged command must be visible to it
  // *before* the commit — otherwise the canvas moves under a dock
  // frozen at the pre-gesture value. These pin that, plus the other
  // half of the contract: the committed document does not move.

  // Opaque blue, width 6, no fill — every assertion below names one of
  // those three so a changed default shows up as a failure, not a pass.
  PaintLayer strokeLayer() => PaintLayer(
    id: 'stroke',
    transform: const LayerTransform(
      position: Offset(20, 20),
      size: Size(200, 100),
    ),
    kind: PaintKind.line,
    normalizedPoints: const [Offset.zero, Offset(1, 1)],
    strokeColor: const Color(0xFF336699),
    strokeWidth: 6,
  );

  test('the style view sees a staged stroke WIDTH before commit', () {
    final container = harness(strokeLayer());
    final seen = watchStyleView(container);
    final controller = container.read(paintToolControllerProvider.notifier);
    final version = container.read(documentCommitVersionProvider);
    expect(seen.first.strokeWidth, 6);

    controller.previewStrokeWidth(23);

    expect(container.read(paintStyleViewProvider).strokeWidth, 23);
    expect(seen.length, greaterThan(1), reason: 'staging must PUSH a new view');
    expect(seen.last.strokeWidth, 23);
    expect(committed(container, 'stroke').strokeWidth, 6);
    expect(container.read(documentCommitVersionProvider), version);

    controller.commitStrokeWidth(23);

    expect(container.read(paintStyleViewProvider).strokeWidth, 23);
    expect(committed(container, 'stroke').strokeWidth, 23);
    expect(container.read(documentCommitVersionProvider), version + 1);
  });

  test('the style view sees a staged stroke COLOUR and OPACITY before '
      'commit', () {
    final container = harness(strokeLayer());
    final seen = watchStyleView(container);
    final controller = container.read(paintToolControllerProvider.notifier);
    final version = container.read(documentCommitVersionProvider);

    controller.previewStrokeColor(const Color(0xFF00AA55));

    expect(
      container.read(paintStyleViewProvider).strokeColor,
      const Color(0xFF00AA55),
    );
    expect(seen.last.strokeColor, const Color(0xFF00AA55));
    expect(committed(container, 'stroke').strokeColor, const Color(0xFF336699));
    expect(container.read(documentCommitVersionProvider), version);

    // The opacity slider rides the same channel; its staged alpha has
    // to reach the view too, or the strip's «٪» label and the mini
    // swatch sit still while the canvas fades.
    controller.previewStrokeOpacity(40);

    expect(
      container.read(paintStyleViewProvider).strokeColor.a,
      closeTo(0.4, 0.001),
    );
    expect(
      committed(container, 'stroke').strokeColor.a,
      1,
      reason: 'committed alpha untouched mid-drag',
    );
    expect(container.read(documentCommitVersionProvider), version);

    controller.commitStrokeColor();

    expect(
      container.read(paintStyleViewProvider).strokeColor.a,
      closeTo(0.4, 0.001),
    );
    expect(committed(container, 'stroke').strokeColor.a, closeTo(0.4, 0.001));
    expect(container.read(documentCommitVersionProvider), version + 1);
  });

  test('the style view sees a staged FILL colour before commit', () {
    final container = harness(strokeLayer());
    final seen = watchStyleView(container);
    final controller = container.read(paintToolControllerProvider.notifier);
    final version = container.read(documentCommitVersionProvider);
    expect(seen.first.fillColor, isNull);

    controller.previewFillColor(const Color(0xFF112233));

    expect(
      container.read(paintStyleViewProvider).fillColor,
      const Color(0xFF112233),
    );
    expect(seen.last.fillColor, const Color(0xFF112233));
    expect(committed(container, 'stroke').fillColor, isNull);
    expect(container.read(documentCommitVersionProvider), version);

    controller.commitFillColor();

    expect(committed(container, 'stroke').fillColor, const Color(0xFF112233));
    expect(container.read(documentCommitVersionProvider), version + 1);
  });

  test('the style view sees a staged BLUR radius before commit', () {
    final container = harness(
      PaintLayer(
        id: 'blur',
        transform: const LayerTransform(
          position: Offset(20, 20),
          size: Size(200, 100),
        ),
        kind: PaintKind.blur,
        normalizedPoints: const [],
        blurSigma: 12,
      ),
    );
    final seen = watchStyleView(container);
    final controller = container.read(paintToolControllerProvider.notifier);
    final doc = container.read(documentControllerProvider);
    final factor = CanvasSizing.scaleFactor(doc);
    final version = container.read(documentCommitVersionProvider);
    expect(seen.first.blurRadius, closeTo(12 / factor, 0.0001));

    controller.previewBlurRadius(30);

    // The view reads reference pixels back out of the staged canvas
    // pixels, so the number the slider shows is the number the user
    // dragged to — not the scaled storage value.
    expect(
      container.read(paintStyleViewProvider).blurRadius,
      closeTo(30, 0.0001),
    );
    expect(seen.last.blurRadius, closeTo(30, 0.0001));
    expect(committed(container, 'blur').blurSigma, 12);
    expect(container.read(documentCommitVersionProvider), version);

    controller.commitBlurRadius(30);

    expect(
      container.read(paintStyleViewProvider).blurRadius,
      closeTo(30, 0.0001),
    );
    expect(container.read(documentCommitVersionProvider), version + 1);
  });
}
