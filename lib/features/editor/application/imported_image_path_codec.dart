import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../engine/core/editor_document.dart';
import '../engine/core/editor_layer.dart';
import '../engine/modules/image/image_layer.dart';
import '../engine/serialization/document_codec.dart';

/// Canonical directory segment under application-documents that holds
/// app-owned imported images. One constant so encode and decode agree.
const String importedImagesDirName = 'imported_images';

/// Resolves the app-owned imported-images directory
/// (`<applicationDocuments>/imported_images`). Mirrors
/// `projectsDirectoryProvider` so tests override it — or use the fake
/// documents dir — without platform channels.
final importedImagesDirectoryProvider = FutureProvider<Directory>((ref) async {
  final docs = await getApplicationDocumentsDirectory();
  return Directory('${docs.path}/$importedImagesDirName');
});

/// Portable persistence of app-owned imported-image paths.
///
/// ## Why
///
/// [ImageSource.file] holds an ABSOLUTE path under
/// `<applicationDocuments>/imported_images/`. Persisting that absolute
/// path bakes in the current container prefix; if the app's data is
/// restored into a different iOS container the file and the project both
/// survive, but the persisted prefix is stale, so the image reads as
/// missing.
///
/// ## Contract
///
/// * **Persist** app-owned imported images canonically as
///   `imported_images/<filename>` — a single safe leaf, forward slashes,
///   never the container prefix.
/// * **Resolve** those references back to an absolute path against the
///   CURRENT documents directory at load time, so the runtime document
///   always carries a usable absolute path (the renderer and exporter are
///   unchanged).
/// * **Legacy** absolute paths keep working; a missing one is rebased by
///   filename only when its direct parent is `imported_images` and the
///   file exists in the current directory — never on a bare basename
///   match of an arbitrary external path.
///
/// Application layer: the value transform is `dart:io`-free (existence
/// checks are injected via `fileExists`), so the engine stays
/// `dart:io`-free. Asset / network / external / malformed sources pass
/// through untouched and no physical file is moved.
class ImportedImagePathCodec {
  const ImportedImagePathCodec._();

  /// Encode [doc] for on-disk storage: app-owned absolute image paths
  /// become canonical `imported_images/<filename>` references. Delegates
  /// to [DocumentCodec.encode] after the transform, so the byte format is
  /// exactly the codec's (keeping the recovery byte-compare stable).
  static String encodeForStorage(
    EditorDocument doc, {
    required String importedImagesDir,
  }) => DocumentCodec.encode(
    canonicalizeDocument(doc, importedImagesDir: importedImagesDir),
  );

  /// Decode persisted [json] into a runtime [EditorDocument] whose image
  /// sources carry usable absolute paths. Throws [DocumentDecodeException]
  /// on malformed JSON (same contract as [DocumentCodec.decode]) so a
  /// caller surfaces it before publishing corrupted metadata.
  static EditorDocument decodeToRuntime(
    String json, {
    required String importedImagesDir,
    required bool Function(String path) fileExists,
  }) => runtimeDocument(
    DocumentCodec.decode(json),
    importedImagesDir: importedImagesDir,
    fileExists: fileExists,
  );

  /// [doc] with every app-owned image source rewritten to its canonical
  /// relative form. Non-image layers and non-file sources are untouched.
  static EditorDocument canonicalizeDocument(
    EditorDocument doc, {
    required String importedImagesDir,
  }) => _mapImageSources(
    doc,
    (s) => canonicalizeSource(s, importedImagesDir: importedImagesDir),
  );

  /// [doc] with every canonical/legacy image source resolved to a usable
  /// absolute path for the current install.
  static EditorDocument runtimeDocument(
    EditorDocument doc, {
    required String importedImagesDir,
    required bool Function(String path) fileExists,
  }) => _mapImageSources(
    doc,
    (s) => runtimeSource(
      s,
      importedImagesDir: importedImagesDir,
      fileExists: fileExists,
    ),
  );

  /// Storage form of a single [source]. Converts ONLY an absolute file
  /// that is a direct child of [importedImagesDir] into
  /// `imported_images/<leaf>`. Asset, network, already-relative,
  /// external, and malformed sources are returned unchanged; the physical
  /// file is never touched.
  static ImageSource canonicalizeSource(
    ImageSource source, {
    required String importedImagesDir,
  }) {
    final path = source.filePath;
    if (path == null) return source; // asset / network
    if (!_isAbsolute(path)) return source; // already relative / unknown
    final leaf = _basename(path);
    if (_dirname(path) != _stripTrailingSlash(importedImagesDir)) return source;
    if (!_isSafeLeaf(leaf)) return source;
    return ImageSource.file('$importedImagesDirName/$leaf');
  }

  /// Runtime form of a single [source].
  ///
  ///  * Canonical `imported_images/<leaf>` -> `<importedImagesDir>/<leaf>`.
  ///  * Legacy absolute path that still exists -> unchanged.
  ///  * Legacy absolute path that is missing but whose direct parent is
  ///    `imported_images`, whose leaf is safe, and whose leaf exists under
  ///    the current [importedImagesDir] -> rebased to the current dir.
  ///  * Everything else (asset, network, external absolute, traversal,
  ///    nested, malformed) -> unchanged, so the existing missing-image
  ///    placeholder / relink flow still applies.
  static ImageSource runtimeSource(
    ImageSource source, {
    required String importedImagesDir,
    required bool Function(String path) fileExists,
  }) {
    final path = source.filePath;
    if (path == null) return source; // asset / network
    final base = _stripTrailingSlash(importedImagesDir);

    if (!_isAbsolute(path)) {
      // Canonical relative reference (only our exact shape resolves;
      // nested / traversal / foreign relatives are left untouched).
      final leaf = _canonicalLeaf(path);
      if (leaf == null) return source;
      return ImageSource.file('$base/$leaf');
    }

    // Legacy absolute path.
    if (fileExists(path)) return source; // still valid on this install
    final leaf = _basename(path);
    final parentIsImported = _basename(_dirname(path)) == importedImagesDirName;
    if (parentIsImported && _isSafeLeaf(leaf) && fileExists('$base/$leaf')) {
      return ImageSource.file('$base/$leaf');
    }
    return source; // unresolved legacy -> placeholder / relink
  }

  static EditorDocument _mapImageSources(
    EditorDocument doc,
    ImageSource Function(ImageSource) transform,
  ) {
    var changed = false;
    final next = <EditorLayer>[];
    for (final layer in doc.layers) {
      if (layer is ImageLayer) {
        final updated = transform(layer.source);
        if (updated != layer.source) {
          changed = true;
          next.add(layer.copyAll(source: updated));
          continue;
        }
      }
      next.add(layer);
    }
    return changed ? doc.copyWith(layers: next) : doc;
  }

  // --- path helpers (forward-slash; POSIX is the only ship target) ---

  static bool _isAbsolute(String path) => path.startsWith('/');

  static String _stripTrailingSlash(String path) =>
      path.endsWith('/') ? path.substring(0, path.length - 1) : path;

  static String _basename(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }

  static String _dirname(String path) {
    final i = path.lastIndexOf('/');
    return i <= 0 ? '' : path.substring(0, i);
  }

  /// The single safe leaf of a canonical `imported_images/<leaf>` value,
  /// or null when [path] is not exactly that shape (wrong prefix, nested,
  /// traversal, or unsafe leaf).
  static String? _canonicalLeaf(String path) {
    const prefix = '$importedImagesDirName/';
    if (!path.startsWith(prefix)) return null;
    final leaf = path.substring(prefix.length);
    return _isSafeLeaf(leaf) ? leaf : null;
  }

  static bool _isSafeLeaf(String leaf) =>
      leaf.isNotEmpty &&
      leaf != '.' &&
      leaf != '..' &&
      !leaf.contains('/') &&
      !leaf.contains(r'\');
}
