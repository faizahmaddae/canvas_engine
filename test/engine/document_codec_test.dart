import 'dart:convert';

import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_layer.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round-trip + invalid-input coverage for [DocumentCodec].
///
/// The contract under test:
///   * encode → decode produces a [EditorDocument] equal to the input
///     (relies on the existing value-equality on every model class).
///   * Layer order is preserved (z-order is list order).
///   * Visibility/locked/name flags survive a round trip.
///   * Per-layer module fields (text content + style, shape kind +
///     colours, image source + fit) survive a round trip.
///   * Malformed input throws [DocumentDecodeException] — never silently
///     produces a corrupted/blank document.
void main() {
  group('LayerTransform JSON', () {
    test('round-trip preserves all fields exactly', () {
      const t = LayerTransform(
        position: Offset(12.5, -7.25),
        size: Size(300, 150),
        rotation: 1.2345,
      );
      final back = LayerTransform.fromJson(t.toJson());
      expect(back, t);
    });

    test('throws FormatException on missing field', () {
      expect(
        () => LayerTransform.fromJson(<String, dynamic>{
          'x': 0,
          'y': 0,
          'w': 10,
          // h missing
          'r': 0,
        }),
        throwsFormatException,
      );
    });
  });

  group('TextStyleSpec JSON', () {
    test('round-trip preserves family, weight, color, alignment', () {
      const spec = TextStyleSpec(
        fontFamily: 'Inter',
        fontSize: 32,
        color: Color(0xFFAABBCC),
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
        alignment: TextAlign.right,
      );
      final back = TextStyleSpec.fromJson(spec.toJson());
      expect(back, spec);
    });

    test('defaults are restored when optional fields missing', () {
      // An effectively-empty JSON should hydrate every field from the
      // unnamed constructor's defaults — the codec promises that
      // anything omitted on encode (including legacy / hand-crafted
      // payloads) decodes back to the canonical default style.
      final back = TextStyleSpec.fromJson(<String, dynamic>{});
      expect(back, const TextStyleSpec());
    });
  });

  group('TextLayer JSON', () {
    test('round-trip preserves content + style + flags', () {
      const layer = TextLayer(
        id: 't1',
        transform: LayerTransform(
          position: Offset(10, 20),
          size: Size(200, 80),
          rotation: 0.5,
        ),
        content: 'Hello world',
        style: TextStyleSpec(
          fontFamily: 'Roboto',
          fontSize: 24,
          color: Color(0xFF112233),
          fontWeight: FontWeight.w400,
          letterSpacing: 0.5,
          alignment: TextAlign.left,
        ),
        name: 'caption',
        visible: false,
        locked: true,
      );
      final back = TextLayer.fromJson(layer.toJson());
      expect(back, layer);
    });

    test('round-trip preserves resizeMode', () {
      const layer = TextLayer(
        id: 't2',
        transform: LayerTransform(
          position: Offset(0, 0),
          size: Size(120, 40),
        ),
        content: 'paragraph',
        style: TextStyleSpec(),
        resizeMode: TextResizeMode.resizeBox,
      );
      final back = TextLayer.fromJson(layer.toJson());
      expect(back.resizeMode, TextResizeMode.resizeBox);
      expect(back, layer);
    });

    test('missing resizeMode in JSON falls back to scaleText', () {
      final back = TextLayer.fromJson(<String, dynamic>{
        'id': 't3',
        'type': 'text',
        'transform': const LayerTransform(
          position: Offset(0, 0),
          size: Size(50, 20),
        ).toJson(),
        'content': 'legacy',
        'style': const TextStyleSpec().toJson(),
        // no 'resizeMode' key — older saves
      });
      expect(back.resizeMode, TextResizeMode.scaleText);
    });
  });

  group('ShapeLayer JSON', () {
    test('rectangle with stroke round-trips', () {
      const layer = ShapeLayer(
        id: 's1',
        transform: LayerTransform(
          position: Offset(0, 0),
          size: Size(100, 60),
        ),
        kind: ShapeKind.rectangle,
        fillColor: Color(0xFFFF0000),
        strokeColor: Color(0xFF00FF00),
        strokeWidth: 4,
      );
      final back = ShapeLayer.fromJson(layer.toJson());
      expect(back, layer);
    });

    test('circle without stroke round-trips and omits null fields', () {
      const layer = ShapeLayer(
        id: 's2',
        transform: LayerTransform(
          position: Offset(0, 0),
          size: Size(80, 80),
        ),
        kind: ShapeKind.circle,
        fillColor: Color(0xFF0000FF),
      );
      final json = layer.toJson();
      expect(json.containsKey('strokeColor'), isFalse);
      final back = ShapeLayer.fromJson(json);
      expect(back, layer);
    });
  });

  group('ImageLayer JSON', () {
    test('asset source round-trips', () {
      const layer = ImageLayer(
        id: 'i1',
        transform: LayerTransform(
          position: Offset(5, 5),
          size: Size(120, 90),
        ),
        source: ImageSource.asset('assets/foo.png'),
        fit: BoxFit.contain,
      );
      final back = ImageLayer.fromJson(layer.toJson());
      expect(back, layer);
    });

    test('network source round-trips', () {
      const layer = ImageLayer(
        id: 'i2',
        transform: LayerTransform(
          position: Offset(0, 0),
          size: Size(50, 50),
        ),
        source: ImageSource.network('https://example.com/x.png'),
      );
      final back = ImageLayer.fromJson(layer.toJson());
      expect(back, layer);
    });

    test('source missing both asset and url throws FormatException', () {
      expect(
        () => ImageSource.fromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });

  group('layer opacity JSON', () {
    test('default opacity is omitted from JSON', () {
      const layer = ShapeLayer(
        id: 's',
        transform: LayerTransform(
          position: Offset.zero,
          size: Size(10, 10),
        ),
        kind: ShapeKind.rectangle,
      );
      expect(layer.toJson().containsKey('opacity'), isFalse);
    });

    test('non-default opacity round-trips for every layer type', () {
      const text = TextLayer(
        id: 't',
        transform: LayerTransform(
          position: Offset.zero,
          size: Size(50, 20),
        ),
        content: 'hi',
        style: TextStyleSpec(),
        opacity: 0.25,
      );
      const shape = ShapeLayer(
        id: 's',
        transform: LayerTransform(
          position: Offset.zero,
          size: Size(10, 10),
        ),
        kind: ShapeKind.circle,
        opacity: 0.5,
      );
      const image = ImageLayer(
        id: 'i',
        transform: LayerTransform(
          position: Offset.zero,
          size: Size(40, 40),
        ),
        source: ImageSource.asset('a.png'),
        opacity: 0.75,
      );
      expect(TextLayer.fromJson(text.toJson()).opacity, 0.25);
      expect(ShapeLayer.fromJson(shape.toJson()).opacity, 0.5);
      expect(ImageLayer.fromJson(image.toJson()).opacity, 0.75);
    });

    test('legacy JSON without opacity decodes to 1.0 (backward-compat)', () {
      final back = TextLayer.fromJson(<String, dynamic>{
        'id': 'legacy',
        'type': 'text',
        'transform': const LayerTransform(
          position: Offset.zero,
          size: Size(10, 10),
        ).toJson(),
        'content': 'old',
        'style': const TextStyleSpec().toJson(),
        // no 'opacity' key
      });
      expect(back.opacity, 1.0);
    });
  });

  group('DocumentCodec', () {
    EditorDocument makeMixedDoc() {
      return EditorDocument(
        width: 1920,
        height: 1080,
        layers: const [
          ShapeLayer(
            id: 'bg',
            transform: LayerTransform(
              position: Offset(0, 0),
              size: Size(1920, 1080),
            ),
            kind: ShapeKind.rectangle,
            fillColor: Color(0xFF222222),
          ),
          ImageLayer(
            id: 'photo',
            transform: LayerTransform(
              position: Offset(100, 200),
              size: Size(400, 300),
              rotation: 0.1,
            ),
            source: ImageSource.network('https://img/test.jpg'),
          ),
          TextLayer(
            id: 'title',
            transform: LayerTransform(
              position: Offset(80, 80),
              size: Size(800, 120),
            ),
            content: 'Headline',
            style: TextStyleSpec(
              fontSize: 96,
              color: Color(0xFFFFFFFF),
              fontWeight: FontWeight.w900,
            ),
            visible: false,
            locked: true,
            name: 'main title',
          ),
        ],
      );
    }

    test('mixed-layer document round-trips through encode/decode', () {
      final doc = makeMixedDoc();
      final encoded = DocumentCodec.encode(doc);
      final decoded = DocumentCodec.decode(encoded);
      expect(decoded, doc);
    });

    test('z-order (list order) is preserved', () {
      final doc = makeMixedDoc();
      final decoded = DocumentCodec.decode(DocumentCodec.encode(doc));
      expect(
        decoded.layers.map((l) => l.id).toList(),
        ['bg', 'photo', 'title'],
      );
    });

    test('encoded JSON declares the current schema version', () {
      final json = DocumentCodec.toJson(makeMixedDoc());
      expect(json['version'], DocumentCodec.schemaVersion);
    });

    test('empty document round-trips', () {
      final doc = EditorDocument(layers: const [], width: 800, height: 600);
      final back = DocumentCodec.decode(DocumentCodec.encode(doc));
      expect(back, doc);
      expect(back.layers, isEmpty);
    });

    test('non-JSON input throws DocumentDecodeException', () {
      expect(
        () => DocumentCodec.decode('not json {{{'),
        throwsA(isA<DocumentDecodeException>()),
      );
    });

    test('top-level non-object throws DocumentDecodeException', () {
      expect(
        () => DocumentCodec.decode('[1,2,3]'),
        throwsA(isA<DocumentDecodeException>()),
      );
    });

    test('missing version throws DocumentDecodeException', () {
      final raw = jsonEncode(<String, dynamic>{
        'width': 100,
        'height': 100,
        'layers': <Object>[],
      });
      expect(
        () => DocumentCodec.decode(raw),
        throwsA(isA<DocumentDecodeException>()),
      );
    });

    test('mismatched version throws DocumentDecodeException', () {
      final raw = jsonEncode(<String, dynamic>{
        'version': 999,
        'width': 100,
        'height': 100,
        'layers': <Object>[],
      });
      expect(
        () => DocumentCodec.decode(raw),
        throwsA(isA<DocumentDecodeException>()),
      );
    });

    test('unknown layer type throws DocumentDecodeException', () {
      final raw = jsonEncode(<String, dynamic>{
        'version': DocumentCodec.schemaVersion,
        'width': 100,
        'height': 100,
        'layers': [
          {
            'type': 'video', // not registered
            'id': 'v1',
            'transform': {'x': 0, 'y': 0, 'w': 10, 'h': 10, 'r': 0},
          },
        ],
      });
      expect(
        () => DocumentCodec.decode(raw),
        throwsA(
          isA<DocumentDecodeException>().having(
            (e) => e.message,
            'message',
            contains('video'),
          ),
        ),
      );
    });

    test('layer missing required field throws DocumentDecodeException', () {
      final raw = jsonEncode(<String, dynamic>{
        'version': DocumentCodec.schemaVersion,
        'width': 100,
        'height': 100,
        'layers': [
          {
            'type': 'text',
            'id': 't1',
            'transform': {'x': 0, 'y': 0, 'w': 10, 'h': 10, 'r': 0},
            // content missing
          },
        ],
      });
      expect(
        () => DocumentCodec.decode(raw),
        throwsA(isA<DocumentDecodeException>()),
      );
    });

    test('layer is not an object throws DocumentDecodeException', () {
      final raw = jsonEncode(<String, dynamic>{
        'version': DocumentCodec.schemaVersion,
        'width': 100,
        'height': 100,
        'layers': ['not-a-map'],
      });
      expect(
        () => DocumentCodec.decode(raw),
        throwsA(isA<DocumentDecodeException>()),
      );
    });

    test('decode is engine-pure (no widget binding required)', () {
      // This test runs in plain Dart context without WidgetsFlutterBinding;
      // a successful decode here proves the codec doesn't pull in any
      // widget/viewport coupling.
      final doc = makeMixedDoc();
      final back = DocumentCodec.decode(DocumentCodec.encode(doc));
      expect(back.layers, hasLength(doc.layers.length));
      for (var i = 0; i < doc.layers.length; i++) {
        expect(back.layers[i], isA<EditorLayer>());
      }
    });
  });
}
