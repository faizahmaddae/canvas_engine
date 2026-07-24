// Unit spec for editorToolModeProvider (roadmap tb1 7/17) — THE
// single derivation of the dock mode. Pins the priority ladder
// (explicit sessions → multi → selected layer type → idle) and the
// three bug-kills the derivation buys: selection change wins over
// sticky tool flags, and dead selection ids can never hold a mode.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/editor_mode_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/paint/application/paint_tool_controller.dart';
import 'package:canvas_engine/features/editor/paint/domain/paint_tool_type.dart';
import 'package:canvas_engine/features/editor/text/application/add_text_composer_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _t = LayerTransform(position: Offset.zero, size: Size(100, 100));

void main() {
  ProviderContainer make() {
    final c = ProviderContainer();
    c
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    addTearDown(c.dispose);
    return c;
  }

  void add(ProviderContainer c, dynamic layer) => c
      .read(documentControllerProvider.notifier)
      .execute(AddLayerCommand(layer as dynamic));

  EditorToolMode mode(ProviderContainer c) => c.read(editorToolModeProvider);

  test('empty selection → idle', () {
    final c = make();
    expect(mode(c), EditorToolMode.idle);
  });

  test('selected layer type drives the mode', () {
    final c = make();
    add(
      c,
      const TextLayer(
        id: 't',
        transform: _t,
        content: 'x',
        style: TextStyleSpec(),
      ),
    );
    add(c, const ShapeLayer(id: 's', transform: _t, kind: ShapeKind.rectangle));
    add(
      c,
      ImageLayer(id: 'i', transform: _t, source: const ImageSource.asset('a')),
    );
    final sel = c.read(selectionControllerProvider.notifier);

    sel.select('t');
    expect(mode(c), EditorToolMode.text);
    sel.select('s');
    expect(mode(c), EditorToolMode.shape);
    sel.select('i');
    expect(mode(c), EditorToolMode.image);
  });

  test('emoji sticker text layer → sticker, not text', () {
    final c = make();
    add(
      c,
      const TextLayer(
        id: 'st',
        transform: _t,
        content: '⭐',
        style: TextStyleSpec(),
        kind: TextLayerKind.emojiSticker,
      ),
    );
    c.read(selectionControllerProvider.notifier).select('st');
    expect(mode(c), EditorToolMode.sticker);
  });

  test('selected paint layer owns the paint dock (tb4 3/14)', () {
    final c = make();
    add(
      c,
      PaintLayer(
        id: 'p',
        transform: _t,
        kind: PaintKind.freestyle,
        normalizedPoints: const [Offset.zero, Offset(1, 1)],
      ),
    );
    c.read(selectionControllerProvider.notifier).select('p');
    expect(
      mode(c),
      EditorToolMode.paint,
      reason:
          'committed strokes are restylable — the strip shows what '
          'this stroke can still become',
    );
  });

  test('paint session outranks any selection', () {
    final c = make();
    add(
      c,
      const TextLayer(
        id: 't',
        transform: _t,
        content: 'x',
        style: TextStyleSpec(),
      ),
    );
    c.read(selectionControllerProvider.notifier).select('t');
    c
        .read(paintToolControllerProvider.notifier)
        .selectTool(PaintToolType.freestyle);
    expect(mode(c), EditorToolMode.paint);
  });

  test('add-composer session forces text mode (staged layer lives '
      'only on the overlay)', () {
    final c = make();
    c.read(addTextComposerOpenProvider.notifier).setOpen(true);
    expect(mode(c), EditorToolMode.text);
    c.read(addTextComposerOpenProvider.notifier).setOpen(false);
    expect(mode(c), EditorToolMode.idle);
  });

  test('two actionable selected layers → multi; protected base photo '
      'does not count', () {
    final c = make();
    final docCtrl = c.read(documentControllerProvider.notifier);
    docCtrl.newDocument(width: 800, height: 800, kind: ProjectKind.photo);
    docCtrl.execute(
      CompositeCommand([
        AddLayerCommand(
          ImageLayer(
            id: 'base',
            transform: _t,
            source: const ImageSource.asset('p'),
            locked: true,
          ),
        ),
        const SetBasePhotoCommand('base'),
      ]),
    );
    add(
      c,
      const TextLayer(
        id: 't',
        transform: _t,
        content: 'x',
        style: TextStyleSpec(),
      ),
    );
    add(c, const ShapeLayer(id: 's', transform: _t, kind: ShapeKind.rectangle));
    final sel = c.read(selectionControllerProvider.notifier);

    sel.selectMany(['t', 's']);
    expect(mode(c), EditorToolMode.multi);

    // Base photo in the set does not raise the actionable count.
    sel.selectMany(['base', 't']);
    expect(
      mode(c),
      EditorToolMode.text,
      reason: 'one actionable layer + the protected base is NOT multi',
    );
  });

  test('bug-kill: dead selection id after undo cannot hold a mode', () {
    final c = make();
    add(
      c,
      const TextLayer(
        id: 't',
        transform: _t,
        content: 'x',
        style: TextStyleSpec(),
      ),
    );
    c.read(selectionControllerProvider.notifier).select('t');
    expect(mode(c), EditorToolMode.text);

    c.read(documentControllerProvider.notifier).undo();
    // Selection still holds the dead id (the prune listener lives in
    // the editor screen) — the derivation itself must already fall
    // back to idle instead of a disabled text strip.
    expect(mode(c), EditorToolMode.idle);
  });

  test('bug-kill: selection change wins over any sticky tool state', () {
    final c = make();
    add(
      c,
      const TextLayer(
        id: 't',
        transform: _t,
        content: 'x',
        style: TextStyleSpec(),
      ),
    );
    add(
      c,
      ImageLayer(id: 'i', transform: _t, source: const ImageSource.asset('a')),
    );
    final sel = c.read(selectionControllerProvider.notifier);
    sel.select('t');
    expect(mode(c), EditorToolMode.text);
    // Selecting the image immediately owns the dock — no sticky
    // text-panel flag can hold the old mode (the pre-1.7 ladder
    // showed a fully-disabled text strip here).
    sel.select('i');
    expect(mode(c), EditorToolMode.image);
  });
}
