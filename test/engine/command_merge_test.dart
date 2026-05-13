import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/commands/editor_command.dart';
import 'package:canvas_engine/features/editor/engine/commands/history_stack.dart';
import 'package:canvas_engine/features/editor/engine/commands/image_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
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
//   * `UpdateTextCommand` and `UpdatePaintStyleCommand` merge
//     unconditionally (no `live` flag, no time window). The existing
//     tests encode the intended behaviour. Add a `live` flag only if
//     a real "stale merge" bug surfaces.
// ---------------------------------------------------------------------

ImageLayer _img(String id) => ImageLayer(
      id: id,
      transform: const LayerTransform(
        position: Offset(0, 0),
        size: Size(100, 100),
      ),
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
          SetImageBorderCommand(
            layerId: 'a',
            width: i.toDouble(),
            live: true,
          ),
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
      expect((doc.layerById('a') as ImageLayer).borderWidth,
          original.borderWidth);
      expect(stack.undoDepth, 0);
      expect(stack.canRedo, true);
    });

    test('60 non-live width edits stay as 60 separate history entries',
        () {
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
          SetImageBorderCommand(
            layerId: 'a',
            width: i.toDouble(),
            live: true,
          ),
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
        const SetImageBorderCommand(
          layerId: 'a',
          color: Color(0xFFFF0000),
        ),
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
    test('60 live blur ticks collapse to one entry; undo restores original',
        () {
      final stack = HistoryStack();
      final original = _img('a');
      var doc = _docWith([original]);

      for (var i = 1; i <= 60; i++) {
        doc = stack.execute(
          doc,
          SetImageShadowCommand(
            layerId: 'a',
            blur: i.toDouble(),
            live: true,
          ),
        );
      }

      expect(stack.undoDepth, 1);
      expect((doc.layerById('a') as ImageLayer).shadowBlur, 60.0);

      doc = stack.undo(doc);
      expect((doc.layerById('a') as ImageLayer).shadowBlur,
          original.shadowBlur);
    });

    test('60 non-live shadow edits stay as 60 separate history entries',
        () {
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

    test('blur and opacity drags stay as 2 entries (different field-sets)',
        () {
      final stack = HistoryStack();
      var doc = _docWith([_img('a')]);

      // Blur drag.
      doc = _runAll(stack, doc, [
        for (var i = 1; i <= 5; i++)
          SetImageShadowCommand(
            layerId: 'a',
            blur: i.toDouble(),
            live: true,
          ),
      ]);
      // Opacity drag — different nullable shape.
      doc = _runAll(stack, doc, [
        for (var i = 1; i <= 5; i++)
          SetImageShadowCommand(
            layerId: 'a',
            opacity: i / 10.0,
            live: true,
          ),
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
          SetImageBorderCommand(
            layerId: 'a',
            width: i.toDouble(),
            live: true,
          ),
        );
      }

      final json = DocumentCodec.encode(doc);
      final decoded = DocumentCodec.decode(json);
      expect(DocumentCodec.encode(decoded), json);
      expect((decoded.layers.single as ImageLayer).borderWidth, 60.0);
    });

    test('encode after a 60-tick shadow-blur drag round-trips losslessly',
        () {
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
          SetImageShadowCommand(
            layerId: 'a',
            blur: i.toDouble(),
            live: true,
          ),
        );
      }

      final json = DocumentCodec.encode(doc);
      final decoded = DocumentCodec.decode(json);
      expect(DocumentCodec.encode(decoded), json);
      expect((decoded.layers.single as ImageLayer).shadowBlur, 60.0);
    });
  });
}
