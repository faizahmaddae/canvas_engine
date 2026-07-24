import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/commands/editor_command.dart';
import 'package:canvas_engine/features/editor/engine/commands/history_stack.dart';
import 'package:canvas_engine/features/editor/engine/commands/image_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/paint_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/text_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------
// Phase 1 / Step 2 — coalescing of `live` slider streams.
//
// What this file proves
//   For every command that opts into per-frame merge via a `live` flag:
//     1. A live drag of N ticks collapses to ONE history entry.
//     2. Discrete edits (live: false) NEVER merge — each is its own
//        undo entry.
//     3. Different field-sets (e.g. width vs colour) NEVER merge
//        even when both are live, so the user can step them back
//        independently.
//     4. Different target layers NEVER merge.
//     5. Undo after a merged drag restores the state from BEFORE the
//        first tick of the drag — NOT before the most recent tick.
//        This is the contract `HistoryStack.execute` enforces by
//        keeping the original inverse and replacing only the forward.
//     6. Encoding a document after a merged drag and decoding it
//        round-trips losslessly — merge is a history-stack concern,
//        never a document-payload concern.
//
// Items the audit deliberately did NOT touch and the next engineer
// should not "fix" without first reading the rationale in the Step 2
// audit:
//   * `SetLayerOpacityCommand` is commit-only via `onChangeEnd` in
//     `layers_panel.dart`. It does not need merge today. Flagged for
//     the Phase 5 live-decoupling sweep.
//   * `UpdateTextCommand` and `UpdatePaintStyleCommand` gained the
//     same `live` gate in tb2 6/16 (the merge-gate flip): non-live
//     commands never merge, so sub-second discrete taps stay
//     separate undo entries. Their truth tables are pinned below.
// ---------------------------------------------------------------------

ImageLayer _img(String id) => ImageLayer(
  id: id,
  transform: const LayerTransform(position: Offset(0, 0), size: Size(100, 100)),
  source: const ImageSource.asset('stub.png'),
);

EditorDocument _docWith(List<ImageLayer> layers) {
  var doc = EditorDocument.empty;
  for (final l in layers) {
    doc = doc.addLayer(l);
  }
  return doc;
}

EditorDocument _runAll(
  HistoryStack stack,
  EditorDocument doc,
  List<EditorCommand> cmds,
) {
  var d = doc;
  for (final c in cmds) {
    d = stack.execute(d, c);
  }
  return d;
}

void main() {
  // ===================================================================
  // SetImageBorderCommand
  // ===================================================================
  group('SetImageBorderCommand merge', () {
    test('60 live width ticks collapse to one history entry; '
        'undo restores original (pre-first-tick) state', () {
      final stack = HistoryStack();
      final original = _img('a');
      var doc = _docWith([original]);

      // Simulate a 60-tick width drag: 1 → 60 px.
      for (var i = 1; i <= 60; i++) {
        doc = stack.execute(
          doc,
          SetImageBorderCommand(layerId: 'a', width: i.toDouble(), live: true),
        );
      }

      // One undo entry, not 60.
      expect(stack.undoDepth, 1);
      // Final width is the last tick.
      expect((doc.layerById('a') as ImageLayer).borderWidth, 60.0);

      // The critical invariant: undo restores the state from BEFORE
      // the very first tick — i.e. the layer's original border width
      // (default 0), not the second-to-last tick (59).
      doc = stack.undo(doc);
      expect(
        (doc.layerById('a') as ImageLayer).borderWidth,
        original.borderWidth,
      );
      expect(stack.undoDepth, 0);
      expect(stack.canRedo, true);
    });

    test('60 non-live width edits stay as 60 separate history entries', () {
      final stack = HistoryStack();
      var doc = _docWith([_img('a')]);

      for (var i = 1; i <= 60; i++) {
        doc = stack.execute(
          doc,
          SetImageBorderCommand(
            layerId: 'a',
            width: i.toDouble(),
            // live defaults to false — palette / chip taps.
          ),
        );
      }

      expect(stack.undoDepth, 60);
    });

    test('different field-sets do not merge: '
        'live colour drag + live width drag = 2 entries', () {
      final stack = HistoryStack();
      var doc = _docWith([_img('a')]);

      // Drag colour for 5 ticks.
      for (var i = 0; i < 5; i++) {
        doc = stack.execute(
          doc,
          SetImageBorderCommand(
            layerId: 'a',
            color: Color(0xFF000000 | i),
            live: true,
          ),
        );
      }
      expect(stack.undoDepth, 1);

      // Then drag width for 5 ticks.
      for (var i = 1; i <= 5; i++) {
        doc = stack.execute(
          doc,
          SetImageBorderCommand(layerId: 'a', width: i.toDouble(), live: true),
        );
      }

      // Field-shape changed (color-only -> width-only), so the
      // width drag must NOT swallow the colour drag.
      expect(stack.undoDepth, 2);
    });

    test('different target layers do not merge', () {
      final stack = HistoryStack();
      var doc = _docWith([_img('a'), _img('b')]);

      doc = stack.execute(
        doc,
        const SetImageBorderCommand(layerId: 'a', width: 4, live: true),
      );
      doc = stack.execute(
        doc,
        const SetImageBorderCommand(layerId: 'b', width: 4, live: true),
      );

      expect(stack.undoDepth, 2);
    });

    test('a non-live edit between two live drags terminates the merge '
        'stream (palette tap mid-drag = 3 entries)', () {
      final stack = HistoryStack();
      var doc = _docWith([_img('a')]);

      // Live width tick.
      doc = stack.execute(
        doc,
        const SetImageBorderCommand(layerId: 'a', width: 2, live: true),
      );
      // Discrete palette tap.
      doc = stack.execute(
        doc,
        const SetImageBorderCommand(layerId: 'a', color: Color(0xFFFF0000)),
      );
      // Another live width tick — must NOT swallow the palette tap.
      doc = stack.execute(
        doc,
        const SetImageBorderCommand(layerId: 'a', width: 6, live: true),
      );

      expect(stack.undoDepth, 3);
    });
  });

  // ===================================================================
  // SetImageShadowCommand — same matrix across its 4 fields
  // ===================================================================
  group('SetImageShadowCommand merge', () {
    test(
      '60 live blur ticks collapse to one entry; undo restores original',
      () {
        final stack = HistoryStack();
        final original = _img('a');
        var doc = _docWith([original]);

        for (var i = 1; i <= 60; i++) {
          doc = stack.execute(
            doc,
            SetImageShadowCommand(layerId: 'a', blur: i.toDouble(), live: true),
          );
        }

        expect(stack.undoDepth, 1);
        expect((doc.layerById('a') as ImageLayer).shadowBlur, 60.0);

        doc = stack.undo(doc);
        expect(
          (doc.layerById('a') as ImageLayer).shadowBlur,
          original.shadowBlur,
        );
      },
    );

    test('60 non-live shadow edits stay as 60 separate history entries', () {
      final stack = HistoryStack();
      var doc = _docWith([_img('a')]);

      for (var i = 1; i <= 60; i++) {
        doc = stack.execute(
          doc,
          SetImageShadowCommand(layerId: 'a', blur: i.toDouble()),
        );
      }
      expect(stack.undoDepth, 60);
    });

    test('blur and opacity drags stay as 2 entries (different field-sets)', () {
      final stack = HistoryStack();
      var doc = _docWith([_img('a')]);

      // Blur drag.
      doc = _runAll(stack, doc, [
        for (var i = 1; i <= 5; i++)
          SetImageShadowCommand(layerId: 'a', blur: i.toDouble(), live: true),
      ]);
      // Opacity drag — different nullable shape.
      doc = _runAll(stack, doc, [
        for (var i = 1; i <= 5; i++)
          SetImageShadowCommand(layerId: 'a', opacity: i / 10.0, live: true),
      ]);
      expect(stack.undoDepth, 2);
    });

    test('colour and offset drags stay as 2 entries', () {
      final stack = HistoryStack();
      var doc = _docWith([_img('a')]);

      doc = _runAll(stack, doc, [
        for (var i = 0; i < 3; i++)
          SetImageShadowCommand(
            layerId: 'a',
            color: Color(0xFF000000 | i),
            live: true,
          ),
      ]);
      doc = _runAll(stack, doc, [
        for (var i = 1; i <= 3; i++)
          SetImageShadowCommand(
            layerId: 'a',
            offset: Offset(i.toDouble(), 0),
            live: true,
          ),
      ]);
      expect(stack.undoDepth, 2);
    });

    test('different target layers do not merge', () {
      final stack = HistoryStack();
      var doc = _docWith([_img('a'), _img('b')]);

      doc = stack.execute(
        doc,
        const SetImageShadowCommand(layerId: 'a', blur: 5, live: true),
      );
      doc = stack.execute(
        doc,
        const SetImageShadowCommand(layerId: 'b', blur: 5, live: true),
      );
      expect(stack.undoDepth, 2);
    });

    test('preset tap mid-drag terminates the merge stream', () {
      final stack = HistoryStack();
      var doc = _docWith([_img('a')]);

      doc = stack.execute(
        doc,
        const SetImageShadowCommand(layerId: 'a', blur: 5, live: true),
      );
      // Discrete preset apply (sets all three: blur + offset + opacity).
      doc = stack.execute(
        doc,
        const SetImageShadowCommand(
          layerId: 'a',
          blur: 12,
          offset: Offset(0, 4),
          opacity: 0.4,
        ),
      );
      doc = stack.execute(
        doc,
        const SetImageShadowCommand(layerId: 'a', blur: 30, live: true),
      );

      expect(stack.undoDepth, 3);
    });
  });

  // ===================================================================
  // Cross-cutting: codec round-trip is unaffected by merge
  // ===================================================================
  group('codec round-trip after merged drag', () {
    test('encode after a 60-tick border-width drag round-trips losslessly '
        'and the redecoded document still matches the live state', () {
      final stack = HistoryStack();
      var doc = _docWith([_img('a')]);

      for (var i = 1; i <= 60; i++) {
        doc = stack.execute(
          doc,
          SetImageBorderCommand(layerId: 'a', width: i.toDouble(), live: true),
        );
      }

      final json = DocumentCodec.encode(doc);
      final decoded = DocumentCodec.decode(json);
      expect(DocumentCodec.encode(decoded), json);
      expect((decoded.layers.single as ImageLayer).borderWidth, 60.0);
    });

    test('encode after a 60-tick shadow-blur drag round-trips losslessly', () {
      final stack = HistoryStack();
      var doc = _docWith([_img('a')]);

      // Prime opacity so the codec actually persists shadow fields:
      // [ImageLayer] omits the entire shadow block when
      // `shadowOpacity == 0` (no shadow renders) — encoding a
      // blur-only change without any opacity would correctly drop
      // it. The drag-coalescing contract is independent of that
      // codec optimisation.
      doc = stack.execute(
        doc,
        const SetImageShadowCommand(layerId: 'a', opacity: 0.5),
      );

      for (var i = 1; i <= 60; i++) {
        doc = stack.execute(
          doc,
          SetImageShadowCommand(layerId: 'a', blur: i.toDouble(), live: true),
        );
      }

      final json = DocumentCodec.encode(doc);
      final decoded = DocumentCodec.decode(json);
      expect(DocumentCodec.encode(decoded), json);
      expect((decoded.layers.single as ImageLayer).shadowBlur, 60.0);
    });
  });

  // ===================================================================
  // Merge window (Phase 3.3) — streams terminate on idle
  // ===================================================================
  group('kLiveMergeWindow gate', () {
    test('same-knob drags separated by more than the window are '
        'separate undo entries', () {
      var now = DateTime.utc(2026, 1, 1);
      final stack = HistoryStack(clock: () => now);
      var doc = _docWith([_img('a')]);

      // First drag: two ticks 100 ms apart -> one entry.
      doc = stack.execute(
        doc,
        const SetImageAdjustmentsCommand(
          layerId: 'a',
          brightness: 10,
          live: true,
        ),
      );
      now = now.add(const Duration(milliseconds: 100));
      doc = stack.execute(
        doc,
        const SetImageAdjustmentsCommand(
          layerId: 'a',
          brightness: 20,
          live: true,
        ),
      );
      expect(stack.undoDepth, 1);

      // Second drag of the SAME knob, 5 s later -> fresh entry. This
      // was the bug: with no drag-end settle the two drags collapsed
      // into one undo step no matter how far apart they were.
      now = now.add(const Duration(seconds: 5));
      doc = stack.execute(
        doc,
        const SetImageAdjustmentsCommand(
          layerId: 'a',
          brightness: 40,
          live: true,
        ),
      );
      expect(
        stack.undoDepth,
        2,
        reason:
            'an idle gap beyond kLiveMergeWindow must terminate '
            'the merge stream',
      );

      // Undo granularity matches the two gestures.
      doc = stack.undo(doc);
      expect((doc.layerById('a')! as ImageLayer).adjustments.brightness, 20);
      doc = stack.undo(doc);
      expect((doc.layerById('a')! as ImageLayer).adjustments.brightness, 0);
    });

    test('ticks within the window keep merging (running total, not '
        'first-tick anchored)', () {
      var now = DateTime.utc(2026, 1, 1);
      final stack = HistoryStack(clock: () => now);
      var doc = _docWith([_img('a')]);
      // 30 ticks, 900 ms apart: every consecutive pair is inside the
      // window even though the whole stream spans ~26 s — the window
      // measures idle gaps, not total stream length.
      for (var i = 1; i <= 30; i++) {
        doc = stack.execute(
          doc,
          SetImageAdjustmentsCommand(
            layerId: 'a',
            brightness: i.toDouble(),
            live: true,
          ),
        );
        now = now.add(const Duration(milliseconds: 900));
      }
      expect(stack.undoDepth, 1);
      doc = stack.undo(doc);
      expect((doc.layerById('a')! as ImageLayer).adjustments.brightness, 0);
    });

    test('a redone entry does not absorb the next live drag', () {
      var now = DateTime.utc(2026, 1, 1);
      final stack = HistoryStack(clock: () => now);
      var doc = _docWith([_img('a')]);
      doc = stack.execute(
        doc,
        const SetImageAdjustmentsCommand(
          layerId: 'a',
          brightness: 10,
          live: true,
        ),
      );
      doc = stack.undo(doc);
      doc = stack.redo(doc);
      // Immediately drag again: the redone entry is completed work,
      // not an in-flight stream — must not be extended.
      doc = stack.execute(
        doc,
        const SetImageAdjustmentsCommand(
          layerId: 'a',
          brightness: 30,
          live: true,
        ),
      );
      expect(stack.undoDepth, 2);
      doc = stack.undo(doc);
      expect(
        (doc.layerById('a')! as ImageLayer).adjustments.brightness,
        10,
        reason: 'undo after redo+drag must stop at the redone state',
      );
    });
  });

  // ===================================================================
  // UpdateTextCommand — merge-gate truth table (tb2 6/16)
  // ===================================================================
  group('UpdateTextCommand merge gate', () {
    TextLayer text(String id) => TextLayer(
      id: id,
      transform: const LayerTransform(
        position: Offset(0, 0),
        size: Size(200, 80),
      ),
      content: 'hi',
      style: const TextStyleSpec(),
    );

    TextStyleSpec size(double v) => TextStyleSpec(fontSize: v);

    test('live × live, same shape + layer → ONE entry (stepper burst)', () {
      final stack = HistoryStack();
      var doc = EditorDocument.empty.addLayer(text('t'));
      doc = _runAll(stack, doc, [
        for (var i = 1; i <= 6; i++)
          UpdateTextCommand(layerId: 't', style: size(20.0 + i), live: true),
      ]);
      expect(stack.undoDepth, 1);
      doc = stack.undo(doc);
      expect(
        (doc.layerById('t')! as TextLayer).style.fontSize,
        const TextStyleSpec().fontSize,
        reason: 'one undo unwinds the whole burst',
      );
    });

    test('non-live × non-live → TWO entries (discrete taps never merge, '
        'regardless of the 1s window)', () {
      final stack = HistoryStack();
      var doc = EditorDocument.empty.addLayer(text('t'));
      doc = _runAll(stack, doc, [
        UpdateTextCommand(layerId: 't', style: size(24)),
        UpdateTextCommand(layerId: 't', style: size(30)),
      ]);
      expect(stack.undoDepth, 2);
    });

    test('live × non-live and non-live × live → no merge either way', () {
      final stack = HistoryStack();
      var doc = EditorDocument.empty.addLayer(text('t'));
      doc = _runAll(stack, doc, [
        UpdateTextCommand(layerId: 't', style: size(24), live: true),
        UpdateTextCommand(layerId: 't', style: size(30)),
        UpdateTextCommand(layerId: 't', style: size(36), live: true),
      ]);
      expect(
        stack.undoDepth,
        3,
        reason:
            'a discrete seal terminates the burst; the next burst '
            'must not reach back over it',
      );
    });

    test('live × live but different field shapes → no merge', () {
      final stack = HistoryStack();
      var doc = EditorDocument.empty.addLayer(text('t'));
      doc = _runAll(stack, doc, [
        UpdateTextCommand(layerId: 't', style: size(24), live: true),
        const UpdateTextCommand(layerId: 't', content: 'hello', live: true),
      ]);
      expect(stack.undoDepth, 2);
    });

    test('live × live but different layers → no merge', () {
      final stack = HistoryStack();
      var doc = EditorDocument.empty.addLayer(text('a')).addLayer(text('b'));
      doc = _runAll(stack, doc, [
        UpdateTextCommand(layerId: 'a', style: size(24), live: true),
        UpdateTextCommand(layerId: 'b', style: size(24), live: true),
      ]);
      expect(stack.undoDepth, 2);
    });
  });

  // ===================================================================
  // UpdatePaintStyleCommand — merge-gate truth table (tb2 6/16)
  // ===================================================================
  group('UpdatePaintStyleCommand merge gate', () {
    PaintLayer stroke(String id) => PaintLayer(
      id: id,
      transform: const LayerTransform(
        position: Offset(0, 0),
        size: Size(100, 100),
      ),
      kind: PaintKind.line,
      normalizedPoints: const [Offset(0, 0.5), Offset(1, 0.5)],
    );

    test('live × live, same field + layer → ONE entry', () {
      final stack = HistoryStack();
      var doc = EditorDocument.empty.addLayer(stroke('p'));
      doc = _runAll(stack, doc, [
        for (var i = 1; i <= 6; i++)
          UpdatePaintStyleCommand(
            layerId: 'p',
            strokeWidth: 6.0 + i,
            live: true,
          ),
      ]);
      expect(stack.undoDepth, 1);
      doc = stack.undo(doc);
      expect(
        (doc.layerById('p')! as PaintLayer).strokeWidth,
        6.0,
        reason: 'one undo unwinds the whole burst',
      );
    });

    test('non-live × non-live → TWO entries (two slider-drag seals '
        'released within the window stay separate)', () {
      final stack = HistoryStack();
      var doc = EditorDocument.empty.addLayer(stroke('p'));
      doc = _runAll(stack, doc, [
        const UpdatePaintStyleCommand(layerId: 'p', strokeWidth: 12),
        const UpdatePaintStyleCommand(layerId: 'p', strokeWidth: 20),
      ]);
      expect(stack.undoDepth, 2);
    });

    test('live × non-live and non-live × live → no merge either way', () {
      final stack = HistoryStack();
      var doc = EditorDocument.empty.addLayer(stroke('p'));
      doc = _runAll(stack, doc, [
        const UpdatePaintStyleCommand(
          layerId: 'p',
          strokeWidth: 12,
          live: true,
        ),
        const UpdatePaintStyleCommand(layerId: 'p', strokeWidth: 20),
        const UpdatePaintStyleCommand(
          layerId: 'p',
          strokeWidth: 28,
          live: true,
        ),
      ]);
      expect(stack.undoDepth, 3);
    });

    test('live × live but different field sets → no merge', () {
      final stack = HistoryStack();
      var doc = EditorDocument.empty.addLayer(stroke('p'));
      doc = _runAll(stack, doc, [
        const UpdatePaintStyleCommand(
          layerId: 'p',
          strokeWidth: 12,
          live: true,
        ),
        const UpdatePaintStyleCommand(
          layerId: 'p',
          strokeColor: Color(0xFF112233),
          live: true,
        ),
      ]);
      expect(stack.undoDepth, 2);
    });

    test('live × live but different layers → no merge', () {
      final stack = HistoryStack();
      var doc = EditorDocument.empty
          .addLayer(stroke('a'))
          .addLayer(stroke('b'));
      doc = _runAll(stack, doc, [
        const UpdatePaintStyleCommand(
          layerId: 'a',
          strokeWidth: 12,
          live: true,
        ),
        const UpdatePaintStyleCommand(
          layerId: 'b',
          strokeWidth: 12,
          live: true,
        ),
      ]);
      expect(stack.undoDepth, 2);
    });
  });
}
