import 'dart:convert';
import 'dart:ui' show Color;

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/canvas/application/canvas_commands.dart';
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

  group('EditorDocument.backgroundMode', () {
    test('default is color', () {
      final c = makeContainer();
      expect(
        c.read(documentControllerProvider).backgroundMode,
        CanvasBackgroundMode.color,
      );
      expect(kDefaultCanvasBackgroundMode, CanvasBackgroundMode.color);
    });

    test('copyWith updates only the mode and preserves colour', () {
      final c = makeContainer();
      final doc = c.read(documentControllerProvider);
      final next = doc.copyWith(
        backgroundMode: CanvasBackgroundMode.transparent,
      );
      expect(next.backgroundMode, CanvasBackgroundMode.transparent);
      expect(next.backgroundColor, doc.backgroundColor);
      expect(next.width, doc.width);
    });

    test('equality and hashCode include backgroundMode', () {
      final base = EditorDocument(layers: const []);
      final transparent = base.copyWith(
        backgroundMode: CanvasBackgroundMode.transparent,
      );
      expect(base == transparent, isFalse);
      expect(base.hashCode == transparent.hashCode, isFalse);
      expect(base, equals(EditorDocument(layers: const [])));
    });
  });

  group('SetCanvasBackgroundModeCommand', () {
    test('apply swaps the mode', () {
      final c = makeContainer();
      c
          .read(documentControllerProvider.notifier)
          .execute(
            const SetCanvasBackgroundModeCommand(
              CanvasBackgroundMode.transparent,
            ),
          );
      expect(
        c.read(documentControllerProvider).backgroundMode,
        CanvasBackgroundMode.transparent,
      );
    });

    test('undo restores the previous mode', () {
      final c = makeContainer();
      c
          .read(documentControllerProvider.notifier)
          .execute(
            const SetCanvasBackgroundModeCommand(
              CanvasBackgroundMode.transparent,
            ),
          );
      c.read(documentControllerProvider.notifier).undo();
      expect(
        c.read(documentControllerProvider).backgroundMode,
        CanvasBackgroundMode.color,
      );
    });

    test('redoing restores transparent', () {
      final c = makeContainer();
      c
          .read(documentControllerProvider.notifier)
          .execute(
            const SetCanvasBackgroundModeCommand(
              CanvasBackgroundMode.transparent,
            ),
          );
      c.read(documentControllerProvider.notifier).undo();
      c.read(documentControllerProvider.notifier).redo();
      expect(
        c.read(documentControllerProvider).backgroundMode,
        CanvasBackgroundMode.transparent,
      );
    });

    test('flipping mode preserves the colour pick', () {
      final c = makeContainer();
      // Pick a colour, then go transparent, then back. The colour
      // must survive the round-trip so toggling is non-destructive.
      c
          .read(documentControllerProvider.notifier)
          .execute(const SetCanvasBackgroundCommand(color: Color(0xFFFF00FF)));
      c
          .read(documentControllerProvider.notifier)
          .execute(
            const SetCanvasBackgroundModeCommand(
              CanvasBackgroundMode.transparent,
            ),
          );
      c
          .read(documentControllerProvider.notifier)
          .execute(
            const SetCanvasBackgroundModeCommand(CanvasBackgroundMode.color),
          );
      expect(
        c.read(documentControllerProvider).backgroundColor,
        const Color(0xFFFF00FF),
      );
    });

    test('apply with same mode is a no-op (returns same instance)', () {
      const cmd = SetCanvasBackgroundModeCommand(CanvasBackgroundMode.color);
      final doc = EditorDocument(layers: const []);
      expect(identical(cmd.apply(doc), doc), isTrue);
    });
  });

  group('DocumentCodec round-trip with backgroundMode', () {
    test('omits field when default', () {
      final doc = EditorDocument(layers: const []);
      final json = DocumentCodec.toJson(doc);
      expect(json.containsKey('backgroundMode'), isFalse);
    });

    test('writes field when transparent', () {
      final doc = EditorDocument(
        layers: const [],
        backgroundMode: CanvasBackgroundMode.transparent,
      );
      final json = DocumentCodec.toJson(doc);
      expect(json['backgroundMode'], 'transparent');
    });

    test('round-trips transparent through encode + decode', () {
      final doc = EditorDocument(
        layers: const [],
        backgroundMode: CanvasBackgroundMode.transparent,
      );
      final json = DocumentCodec.toJson(doc);
      final encoded = jsonEncode(json);
      final decoded = DocumentCodec.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
      expect(decoded.backgroundMode, CanvasBackgroundMode.transparent);
    });

    test('decode tolerates unknown / missing backgroundMode value', () {
      final doc = EditorDocument(layers: const []);
      final json = DocumentCodec.toJson(doc)
        ..['backgroundMode'] = 'not-a-real-mode';
      final decoded = DocumentCodec.fromJson(json);
      expect(decoded.backgroundMode, kDefaultCanvasBackgroundMode);
    });

    test('legacy snapshots without backgroundMode decode as color', () {
      // Simulate a pre-Phase-8 snapshot that has no backgroundMode key.
      final json = <String, dynamic>{
        'version': DocumentCodec.schemaVersion,
        'width': 800,
        'height': 800,
        'layers': const <dynamic>[],
      };
      final decoded = DocumentCodec.fromJson(json);
      expect(decoded.backgroundMode, CanvasBackgroundMode.color);
    });
  });
}
