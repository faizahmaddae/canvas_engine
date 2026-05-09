// Photo-vs-design project kind: round-trip + behaviour coverage.
//
// Verifies the four contracts that make ProjectKind safe to add:
//   1. Default is `design` (every existing on-disk doc loads
//      identically).
//   2. JSON omits the field when default → byte-for-byte backward
//      compatible.
//   3. JSON round-trips when set to `photo`.
//   4. `isProtectedBasePhoto` matches its specification.

import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ImageLayer makeImage(String id) => ImageLayer(
        id: id,
        transform: LayerTransform(
          position: Offset.zero,
          size: const Size(400, 300),
        ),
        source: ImageSource.asset('assets/$id.png'),
      );

  group('ProjectKind defaults & equality', () {
    test('EditorDocument defaults to ProjectKind.design', () {
      final doc = EditorDocument(layers: const []);
      expect(doc.projectKind, ProjectKind.design);
    });

    test('two docs differing only by kind are not equal', () {
      final a = EditorDocument(layers: const []);
      final b = EditorDocument(
        layers: const [],
        projectKind: ProjectKind.photo,
      );
      expect(a, isNot(equals(b)));
    });

    test('copyWith(projectKind:) updates without touching other fields', () {
      final a = EditorDocument(
        layers: [makeImage('p1')],
        width: 1000,
        height: 800,
      );
      final b = a.copyWith(projectKind: ProjectKind.photo);
      expect(b.projectKind, ProjectKind.photo);
      expect(b.layers, a.layers);
      expect(b.width, a.width);
      expect(b.basePhotoLayerId, a.basePhotoLayerId);
    });
  });

  group('JSON round-trip backward compatibility', () {
    test('design-mode doc omits projectKind from JSON', () {
      final doc = EditorDocument(layers: [makeImage('p1')]);
      final json = DocumentCodec.toJson(doc);
      expect(json.containsKey('projectKind'), isFalse);
    });

    test('photo-mode doc serializes projectKind as "photo"', () {
      final doc = EditorDocument(
        layers: [makeImage('p1')],
        basePhotoLayerId: 'p1',
        projectKind: ProjectKind.photo,
      );
      final json = DocumentCodec.toJson(doc);
      expect(json['projectKind'], 'photo');
    });

    test('round-trip preserves projectKind=photo + basePhotoLayerId', () {
      final src = EditorDocument(
        layers: [makeImage('p1')],
        basePhotoLayerId: 'p1',
        projectKind: ProjectKind.photo,
      );
      final json = DocumentCodec.encode(src);
      final restored = DocumentCodec.decode(json);
      expect(restored.projectKind, ProjectKind.photo);
      expect(restored.basePhotoLayerId, 'p1');
    });

    test('decoding a legacy doc (no projectKind field) -> design', () {
      // Hand-crafted v1 payload exactly as historic projects stored.
      const legacy = '''
      {
        "version": 1,
        "width": 1080,
        "height": 1080,
        "layers": []
      }
      ''';
      final doc = DocumentCodec.decode(legacy);
      expect(doc.projectKind, ProjectKind.design);
    });

    test('decoding an unknown projectKind value -> falls back to design', () {
      const payload = '''
      {
        "version": 1,
        "width": 1080,
        "height": 1080,
        "projectKind": "scrapbook",
        "layers": []
      }
      ''';
      final doc = DocumentCodec.decode(payload);
      expect(doc.projectKind, ProjectKind.design);
    });
  });

  group('isProtectedBasePhoto', () {
    test('false in design mode even when basePhotoLayerId matches', () {
      final doc = EditorDocument(
        layers: [makeImage('p1')],
        basePhotoLayerId: 'p1',
      );
      expect(doc.isProtectedBasePhoto('p1'), isFalse);
    });

    test('true in photo mode when id matches basePhotoLayerId', () {
      final doc = EditorDocument(
        layers: [makeImage('p1'), makeImage('p2')],
        basePhotoLayerId: 'p1',
        projectKind: ProjectKind.photo,
      );
      expect(doc.isProtectedBasePhoto('p1'), isTrue);
      expect(doc.isProtectedBasePhoto('p2'), isFalse);
    });

    test('false in photo mode when basePhotoLayerId is null', () {
      final doc = EditorDocument(
        layers: [makeImage('p1')],
        projectKind: ProjectKind.photo,
      );
      expect(doc.isProtectedBasePhoto('p1'), isFalse);
    });
  });

  group('SetProjectKindCommand', () {
    test('apply changes kind; invert restores prior kind', () {
      var doc = EditorDocument(layers: const []);
      const cmd = SetProjectKindCommand(ProjectKind.photo);
      final applied = cmd.apply(doc);
      expect(applied.projectKind, ProjectKind.photo);

      final inverse = cmd.invert(doc);
      final reverted = inverse.apply(applied);
      expect(reverted.projectKind, ProjectKind.design);
    });

    test('apply is a no-op when kind is unchanged', () {
      final doc =
          EditorDocument(layers: const [], projectKind: ProjectKind.photo);
      const cmd = SetProjectKindCommand(ProjectKind.photo);
      expect(identical(cmd.apply(doc), doc), isTrue);
    });
  });
}
