// Portable persistence of app-owned imported-image paths
// (ImportedImagePathCodec). Verifies the value transform in isolation and
// through the real DocumentController hydration seam.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/imported_image_path_codec.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:canvas_engine/features/editor/image/presentation/image_replace_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _dir = '/Documents/imported_images';

EditorDocument _docWith(ImageSource source) => EditorDocument(
  layers: [
    ImageLayer(
      id: 'img',
      transform: LayerTransform(
        position: Offset.zero,
        size: const Size(10, 10),
      ),
      source: source,
    ),
  ],
  width: 100,
  height: 100,
);

ImageSource _onlySource(EditorDocument doc) =>
    (doc.layers.single as ImageLayer).source;

// Never-called existence probe for cases where existence is irrelevant.
bool _neverExists(String _) => false;

void main() {
  group('canonicalizeSource (persist)', () {
    test('#2 current app-owned absolute -> imported_images/<leaf>', () {
      final out = ImportedImagePathCodec.canonicalizeSource(
        ImageSource.file('$_dir/a1b2.png'),
        importedImagesDir: _dir,
      );
      expect(out.filePath, 'imported_images/a1b2.png');
    });

    test('#7 external absolute (not under the dir) is unchanged', () {
      const external = '/Users/me/Desktop/photo.png';
      final out = ImportedImagePathCodec.canonicalizeSource(
        ImageSource.file(external),
        importedImagesDir: _dir,
      );
      expect(out.filePath, external);
    });

    test('nested child under the dir is NOT canonicalized', () {
      // A path two levels deep is not a *direct* child.
      const nested = '$_dir/sub/x.png';
      final out = ImportedImagePathCodec.canonicalizeSource(
        ImageSource.file(nested),
        importedImagesDir: _dir,
      );
      expect(out.filePath, nested);
    });

    test('#9 network/asset sources are untouched', () {
      final net = ImageSource.network('https://example.com/x.png');
      final asset = ImageSource.asset('assets/x.png');
      expect(
        ImportedImagePathCodec.canonicalizeSource(net, importedImagesDir: _dir),
        net,
      );
      expect(
        ImportedImagePathCodec.canonicalizeSource(
          asset,
          importedImagesDir: _dir,
        ),
        asset,
      );
    });

    test('sibling-prefix dir (imported_images_evil) is NOT app-owned', () {
      // Segment-aware, not a string-prefix check: a look-alike sibling
      // directory must never be classified as the app-owned dir.
      const evilAbs = '/Documents/imported_images_evil/x.png';
      expect(
        ImportedImagePathCodec.canonicalizeSource(
          ImageSource.file(evilAbs),
          importedImagesDir: _dir,
        ).filePath,
        evilAbs,
      );
      const evilRel = 'imported_images_evil/x.png';
      expect(
        ImportedImagePathCodec.runtimeSource(
          ImageSource.file(evilRel),
          importedImagesDir: _dir,
          fileExists: (_) => true,
        ).filePath,
        evilRel,
      );
    });
  });

  group('runtimeSource (hydrate)', () {
    test('#1 canonical relative resolves beneath the current dir', () {
      final out = ImportedImagePathCodec.runtimeSource(
        ImageSource.file('imported_images/a1b2.png'),
        importedImagesDir: _dir,
        fileExists: _neverExists,
      );
      expect(out.filePath, '$_dir/a1b2.png');
    });

    test('#4 legacy absolute that still exists is kept as-is', () {
      const legacy = '/old/container/imported_images/a1b2.png';
      final out = ImportedImagePathCodec.runtimeSource(
        ImageSource.file(legacy),
        importedImagesDir: _dir,
        fileExists: (p) => p == legacy,
      );
      expect(out.filePath, legacy);
    });

    test('#5 missing legacy rebases when the restored file exists', () {
      const legacy = '/old/container/imported_images/a1b2.png';
      final out = ImportedImagePathCodec.runtimeSource(
        ImageSource.file(legacy),
        importedImagesDir: _dir,
        // old path gone; leaf present under the current dir.
        fileExists: (p) => p == '$_dir/a1b2.png',
      );
      expect(out.filePath, '$_dir/a1b2.png');
    });

    test('#6 missing legacy stays unresolved when no candidate exists', () {
      const legacy = '/old/container/imported_images/a1b2.png';
      final out = ImportedImagePathCodec.runtimeSource(
        ImageSource.file(legacy),
        importedImagesDir: _dir,
        fileExists: _neverExists,
      );
      expect(out.filePath, legacy);
    });

    test('#7 arbitrary external absolute is never rebased on basename', () {
      // Same leaf as an imported image but a foreign parent dir, and a
      // candidate DOES exist under the current dir — must NOT rebase.
      const external = '/Users/me/Desktop/a1b2.png';
      final out = ImportedImagePathCodec.runtimeSource(
        ImageSource.file(external),
        importedImagesDir: _dir,
        fileExists: (p) => p == '$_dir/a1b2.png',
      );
      expect(out.filePath, external);
    });

    test('#8 traversal / nested / foreign relatives are not accepted', () {
      for (final bad in const [
        'imported_images/../secret.png',
        'imported_images/sub/x.png',
        'other/x.png',
        'imported_images/',
      ]) {
        final out = ImportedImagePathCodec.runtimeSource(
          ImageSource.file(bad),
          importedImagesDir: _dir,
          fileExists: (_) => true,
        );
        expect(out.filePath, bad, reason: '"$bad" must be left unchanged');
      }
    });

    test('#9 network/asset sources are untouched', () {
      final net = ImageSource.network('https://example.com/x.png');
      expect(
        ImportedImagePathCodec.runtimeSource(
          net,
          importedImagesDir: _dir,
          fileExists: (_) => true,
        ),
        net,
      );
    });

    test('#14 an unresolved legacy path stays "known unavailable"', () {
      const legacy = '/old/container/imported_images/gone.png';
      final out = ImportedImagePathCodec.runtimeSource(
        ImageSource.file(legacy),
        importedImagesDir: _dir,
        fileExists: _neverExists,
      );
      // Unchanged -> the existing relink flow still recognises it.
      expect(out.filePath, legacy);
      expect(imageSourceIsKnownUnavailable(out), isTrue);
    });
  });

  group('document encode/decode', () {
    test('#2/#3 app-owned absolute persists relative and round-trips', () {
      final doc = _docWith(ImageSource.file('$_dir/a1b2.png'));
      final stored = ImportedImagePathCodec.encodeForStorage(
        doc,
        importedImagesDir: _dir,
      );
      expect(stored, contains('"file": "imported_images/a1b2.png"'));
      expect(stored, isNot(contains(_dir)), reason: 'no container prefix');

      // Re-encoding the runtime document is byte-stable.
      final runtime = ImportedImagePathCodec.decodeToRuntime(
        stored,
        importedImagesDir: _dir,
        fileExists: (_) => true,
      );
      expect(_onlySource(runtime).filePath, '$_dir/a1b2.png');
      expect(
        ImportedImagePathCodec.encodeForStorage(
          runtime,
          importedImagesDir: _dir,
        ),
        stored,
        reason: 'encode(decode(x)) == x — recovery byte-compare stays exact',
      );
    });

    test('transform is immutable and preserves all non-source fields', () {
      final img = ImageLayer(
        id: 'img',
        transform: LayerTransform(
          position: const Offset(5, 6),
          size: const Size(10, 10),
        ),
        source: ImageSource.file('$_dir/a1b2.png'),
        borderWidth: 3,
        opacity: 0.5,
      );
      final doc = EditorDocument(layers: [img], width: 123, height: 456);
      final out = ImportedImagePathCodec.canonicalizeDocument(
        doc,
        importedImagesDir: _dir,
      );
      final outImg = out.layers.single as ImageLayer;
      expect(outImg.source.filePath, 'imported_images/a1b2.png');
      expect(outImg.borderWidth, 3);
      expect(outImg.opacity, 0.5);
      expect(outImg.transform.position, const Offset(5, 6));
      expect(out.width, 123);
      expect(out.height, 456);
      // Original document is untouched.
      expect(_onlySource(doc).filePath, '$_dir/a1b2.png');
    });

    test('#9 a network-image document is byte-identical to a plain encode', () {
      final doc = _docWith(ImageSource.network('https://example.com/x.png'));
      expect(
        ImportedImagePathCodec.encodeForStorage(doc, importedImagesDir: _dir),
        DocumentCodec.encode(doc),
      );
    });

    test(
      '#10 hydration through DocumentController yields an absolute path',
      () {
        final stored = ImportedImagePathCodec.encodeForStorage(
          _docWith(ImageSource.file('$_dir/a1b2.png')),
          importedImagesDir: _dir,
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final ctrl = container.read(documentControllerProvider.notifier);

        // Mirrors HomeActions._hydrate + loadDocument.
        ctrl.loadDocument(
          ImportedImagePathCodec.decodeToRuntime(
            stored,
            importedImagesDir: _dir,
            fileExists: (_) => true,
          ),
        );

        final loaded = container.read(documentControllerProvider);
        expect(_onlySource(loaded).filePath, '$_dir/a1b2.png');
        expect(
          ctrl.canUndo,
          isFalse,
          reason: 'loaded document is a fresh origin',
        );
      },
    );
  });
}
