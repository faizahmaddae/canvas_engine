import 'dart:convert';
import 'dart:ui' show Color;

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/canvas/application/canvas_commands.dart';
import 'package:canvas_engine/features/editor/canvas/application/canvas_tool_controller.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    c
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    addTearDown(c.dispose);
    return c;
  }

  group('EditorDocument.backgroundColor', () {
    test('default is white', () {
      final c = makeContainer();
      expect(
        c.read(documentControllerProvider).backgroundColor,
        kDefaultCanvasBackground,
      );
      expect(kDefaultCanvasBackground, const Color(0xFFFFFFFF));
    });

    test('copyWith updates only the colour', () {
      final c = makeContainer();
      final doc = c.read(documentControllerProvider);
      final next = doc.copyWith(backgroundColor: const Color(0xFF112233));
      expect(next.backgroundColor, const Color(0xFF112233));
      expect(next.width, doc.width);
      expect(next.height, doc.height);
      expect(next.layers, same(doc.layers));
    });
  });

  group('SetCanvasBackgroundCommand', () {
    test('execute swaps the document background colour', () {
      final c = makeContainer();
      c
          .read(documentControllerProvider.notifier)
          .execute(const SetCanvasBackgroundCommand(color: Color(0xFF202020)));
      expect(
        c.read(documentControllerProvider).backgroundColor,
        const Color(0xFF202020),
      );
    });

    test('undo restores the previous colour', () {
      final c = makeContainer();
      c
          .read(documentControllerProvider.notifier)
          .execute(const SetCanvasBackgroundCommand(color: Color(0xFFFF8800)));
      c
          .read(documentControllerProvider.notifier)
          .execute(const SetCanvasBackgroundCommand(color: Color(0xFF003366)));
      c.read(documentControllerProvider.notifier).undo();
      expect(
        c.read(documentControllerProvider).backgroundColor,
        const Color(0xFFFF8800),
      );
      c.read(documentControllerProvider.notifier).undo();
      expect(
        c.read(documentControllerProvider).backgroundColor,
        kDefaultCanvasBackground,
      );
    });

    test('no-op when colour matches current (preserves stack)', () {
      final c = makeContainer();
      c
          .read(documentControllerProvider.notifier)
          .execute(const SetCanvasBackgroundCommand(color: Color(0xFFAABBCC)));
      // Re-applying same colour should not push a fresh entry.
      c
          .read(documentControllerProvider.notifier)
          .execute(const SetCanvasBackgroundCommand(color: Color(0xFFAABBCC)));
      // Single undo restores white.
      c.read(documentControllerProvider.notifier).undo();
      expect(
        c.read(documentControllerProvider).backgroundColor,
        kDefaultCanvasBackground,
      );
    });

    test('live commands collapse into one undo entry', () {
      final c = makeContainer();
      for (final hex in <int>[0xFF111111, 0xFF222222, 0xFF333333, 0xFF444444]) {
        c
            .read(documentControllerProvider.notifier)
            .execute(SetCanvasBackgroundCommand(color: Color(hex), live: true));
      }
      expect(
        c.read(documentControllerProvider).backgroundColor,
        const Color(0xFF444444),
      );
      // One undo should land back at the original white, NOT step
      // backward through the live frames.
      c.read(documentControllerProvider.notifier).undo();
      expect(
        c.read(documentControllerProvider).backgroundColor,
        kDefaultCanvasBackground,
      );
    });

    test('undo of a solid pick over a GRADIENT restores the gradient', () {
      // Regression (roadmap tb0 0.5): invert used to capture only the
      // derived backgroundColor (the gradient's start colour), so
      // undo restored a SOLID of that colour — the template's
      // authored gradient was unrecoverable in-session.
      final c = makeContainer();
      const gradient = LinearGradientBackground(
        startColor: Color(0xFFBE8A2E),
        endColor: Color(0xFF7A4E1E),
        angleDegrees: 160,
      );
      final docCtrl = c.read(documentControllerProvider.notifier);
      docCtrl.execute(const SetCanvasBackgroundCommand(fill: gradient));
      expect(c.read(documentControllerProvider).background, gradient);

      docCtrl.execute(
        const SetCanvasBackgroundCommand(color: Color(0xFF112233)),
      );
      expect(
        c.read(documentControllerProvider).background,
        const SolidBackground(color: Color(0xFF112233)),
      );

      docCtrl.undo();
      expect(
        c.read(documentControllerProvider).background,
        gradient,
        reason: 'undo must restore the full gradient, not a solid',
      );
    });

    test('picking a solid equal to the gradient START colour is a real '
        'change, not a no-op', () {
      final c = makeContainer();
      const gradient = LinearGradientBackground(
        startColor: Color(0xFFBE8A2E),
        endColor: Color(0xFF7A4E1E),
      );
      final docCtrl = c.read(documentControllerProvider.notifier);
      docCtrl.execute(const SetCanvasBackgroundCommand(fill: gradient));

      // Old guard compared against the DERIVED colour (gradient
      // start) and swallowed this as a no-op.
      docCtrl.execute(
        const SetCanvasBackgroundCommand(color: Color(0xFFBE8A2E)),
      );
      expect(
        c.read(documentControllerProvider).background,
        const SolidBackground(color: Color(0xFFBE8A2E)),
      );
      docCtrl.undo();
      expect(c.read(documentControllerProvider).background, gradient);
    });

    test('non-live commands do NOT merge', () {
      final c = makeContainer();
      c
          .read(documentControllerProvider.notifier)
          .execute(const SetCanvasBackgroundCommand(color: Color(0xFFAA0000)));
      c
          .read(documentControllerProvider.notifier)
          .execute(const SetCanvasBackgroundCommand(color: Color(0xFF00AA00)));
      // Undo once -> previous entry still visible.
      c.read(documentControllerProvider.notifier).undo();
      expect(
        c.read(documentControllerProvider).backgroundColor,
        const Color(0xFFAA0000),
      );
    });
  });

  group('DocumentCodec backgroundColor', () {
    test('omits background when default white (back-compat)', () {
      final c = makeContainer();
      final json = DocumentCodec.toJson(c.read(documentControllerProvider));
      expect(json.containsKey('background'), isFalse);
    });

    test('serialises non-default background as ARGB int', () {
      final c = makeContainer();
      c
          .read(documentControllerProvider.notifier)
          .execute(const SetCanvasBackgroundCommand(color: Color(0xFF334455)));
      final json = DocumentCodec.toJson(c.read(documentControllerProvider));
      expect(json['background'], 0xFF334455);
    });

    test('round-trip preserves the background colour', () {
      final c = makeContainer();
      c
          .read(documentControllerProvider.notifier)
          .execute(const SetCanvasBackgroundCommand(color: Color(0xFF445566)));
      final encoded = DocumentCodec.encode(c.read(documentControllerProvider));
      final restored = DocumentCodec.fromJson(
        Map<String, dynamic>.from(jsonDecode(encoded) as Map),
      );
      expect(restored.backgroundColor, const Color(0xFF445566));
    });

    test('absent background field decodes as white (back-compat)', () {
      final restored = DocumentCodec.fromJson(<String, dynamic>{
        'version': DocumentCodec.schemaVersion,
        'width': 500.0,
        'height': 500.0,
        'layers': const <Map<String, dynamic>>[],
      });
      expect(restored.backgroundColor, kDefaultCanvasBackground);
    });
  });

  group('CanvasToolController', () {
    test('toggle flips panelOpen', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(canvasToolControllerProvider).panelOpen, isFalse);
      c.read(canvasToolControllerProvider.notifier).togglePanel();
      expect(c.read(canvasToolControllerProvider).panelOpen, isTrue);
      c.read(canvasToolControllerProvider.notifier).togglePanel();
      expect(c.read(canvasToolControllerProvider).panelOpen, isFalse);
    });

    test('closePanel is a no-op when already closed', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(canvasToolControllerProvider.notifier).closePanel();
      expect(c.read(canvasToolControllerProvider).panelOpen, isFalse);
    });
  });
}
