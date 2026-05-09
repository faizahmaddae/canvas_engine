import 'dart:convert';

import '../core/background_fill.dart';
import '../core/editor_document.dart';
import '../core/editor_layer.dart';
import '../modules/image/image_layer.dart';
import '../modules/paint/paint_layer.dart';
import '../modules/shape/shape_layer.dart';
import '../modules/text/text_layer.dart';

/// Thrown when a document JSON payload cannot be decoded. Carries a
/// human-readable [message] plus the original [cause] (e.g. a
/// [FormatException] from a layer factory) for diagnostics. The decoder
/// never silently swaps in defaults for missing required fields — it
/// always throws this exception so the caller can show an error rather
/// than corrupt the user's document.
class DocumentDecodeException implements Exception {
  const DocumentDecodeException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'DocumentDecodeException: $message'
      : 'DocumentDecodeException: $message ($cause)';
}

/// Signature of a layer subclass `fromJson` factory.
typedef LayerFromJson = EditorLayer Function(Map<String, dynamic> json);

/// Static encode/decode for [EditorDocument] and the registry of layer
/// factories keyed by their [EditorLayer.type] discriminator.
///
/// This is intentionally the only file that imports every layer module:
/// `core/` stays module-agnostic, and adding a new layer type means
/// touching one line here plus the new module's own `toJson`/`fromJson`.
class DocumentCodec {
  DocumentCodec._();

  /// Current document schema version. v1 stored `'background'` as a
  /// bare ARGB int (solid colour only); v2 also accepts a tagged map
  /// for [LinearGradientBackground] / [RadialGradientBackground].
  /// Solid backgrounds are still written as ints in v2 so v1 readers
  /// can open any document that doesn't use a gradient.
  static const int schemaVersion = 2;

  /// Lowest schema version we still know how to read. v1 docs may
  /// arrive from older app installs and from on-disk projects saved
  /// before the gradient engine landed.
  static const int minSupportedSchemaVersion = 1;

  /// Built-in layer factories. Keyed by the same string returned from
  /// each subclass's `type` getter.
  static final Map<String, LayerFromJson> _layerFactories =
      <String, LayerFromJson>{
    'text': TextLayer.fromJson,
    'shape': ShapeLayer.fromJson,
    'image': ImageLayer.fromJson,
    'paint': PaintLayer.fromJson,
  };

  /// Encode a document to a stable JSON map. Use [encode] to get a
  /// string; this lower-level form is exposed so tests and embedders
  /// can inspect the structure directly.
  static Map<String, dynamic> toJson(EditorDocument doc) {
    final fill = doc.background;
    // Solid + default-white → omit entirely (matches v1 behaviour).
    // Solid + non-default → bare int (forward + backward compatible).
    // Gradient            → tagged map (v2-only).
    final Object? backgroundJson = switch (fill) {
      SolidBackground(:final color) =>
        color == kDefaultCanvasBackground ? null : color.toARGB32(),
      LinearGradientBackground() || RadialGradientBackground() => fill.toJson(),
    };
    return <String, dynamic>{
      'version': schemaVersion,
      'width': doc.width,
      'height': doc.height,
      if (backgroundJson != null) 'background': backgroundJson,
      if (doc.backgroundMode != kDefaultCanvasBackgroundMode)
        'backgroundMode': doc.backgroundMode.name,
      if (doc.basePhotoLayerId != null)
        'basePhotoLayerId': doc.basePhotoLayerId,
      if (doc.projectKind != kDefaultProjectKind)
        'projectKind': doc.projectKind.name,
      'layers': doc.layers.map((l) => l.toJson()).toList(growable: false),
    };
  }

  /// Encode a document as a JSON string. Pretty-printed with two-space
  /// indent so saved files are readable + diff-friendly.
  static String encode(EditorDocument doc) =>
      const JsonEncoder.withIndent('  ').convert(toJson(doc));

  /// Decode a [Map] produced by [toJson] back into an [EditorDocument].
  /// Throws [DocumentDecodeException] on malformed input or unknown
  /// layer types.
  static EditorDocument fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! int) {
      throw const DocumentDecodeException('missing or non-integer "version"');
    }
    if (version < minSupportedSchemaVersion || version > schemaVersion) {
      throw DocumentDecodeException(
        'unsupported schema version $version '
        '(supported: $minSupportedSchemaVersion..$schemaVersion)',
      );
    }
    final width = json['width'];
    final height = json['height'];
    if (width is! num || height is! num) {
      throw const DocumentDecodeException(
        'document "width"/"height" missing or not numeric',
      );
    }
    final rawLayers = json['layers'];
    if (rawLayers is! List) {
      throw const DocumentDecodeException(
        'document "layers" missing or not a list',
      );
    }
    final layers = <EditorLayer>[];
    for (var i = 0; i < rawLayers.length; i++) {
      final entry = rawLayers[i];
      if (entry is! Map) {
        throw DocumentDecodeException('layer[$i] is not a JSON object');
      }
      final layerJson = Map<String, dynamic>.from(entry);
      final type = layerJson['type'];
      if (type is! String) {
        throw DocumentDecodeException(
          'layer[$i] missing string "type" discriminator',
        );
      }
      final factory = _layerFactories[type];
      if (factory == null) {
        throw DocumentDecodeException(
          'layer[$i] has unknown type "$type"',
        );
      }
      try {
        layers.add(factory(layerJson));
      } on FormatException catch (e) {
        throw DocumentDecodeException(
          'layer[$i] of type "$type" failed to decode',
          e,
        );
      }
    }
    final rawBase = json['basePhotoLayerId'];
    final basePhotoLayerId =
        (rawBase is String && layers.any((l) => l.id == rawBase))
            ? rawBase
            : null;
    // Project kind: tolerate missing / unknown values by falling
    // back to the default. We never throw here — forward-compat
    // beats strictness for what's effectively a behaviour hint.
    final rawKind = json['projectKind'];
    final projectKind = ProjectKind.values.firstWhere(
      (k) => k.name == rawKind,
      orElse: () => kDefaultProjectKind,
    );
    // Background mode: tolerate missing / unknown values just like
    // projectKind -- a behaviour hint, never a fatal decode error.
    final rawBgMode = json['backgroundMode'];
    final backgroundMode = CanvasBackgroundMode.values.firstWhere(
      (m) => m.name == rawBgMode,
      orElse: () => kDefaultCanvasBackgroundMode,
    );
    // Background fill: int (legacy v1 / solid v2) or tagged map (v2
    // gradient). Missing field → default solid white. Malformed
    // payloads bubble up as DocumentDecodeException.
    final rawBg = json['background'];
    final BackgroundFill background;
    if (rawBg == null) {
      background = kDefaultCanvasBackgroundFill;
    } else {
      try {
        background = BackgroundFill.fromJson(rawBg);
      } on FormatException catch (e) {
        throw DocumentDecodeException('invalid "background" payload', e);
      }
    }
    return EditorDocument(
      layers: layers,
      width: width.toDouble(),
      height: height.toDouble(),
      background: background,
      backgroundMode: backgroundMode,
      basePhotoLayerId: basePhotoLayerId,
      projectKind: projectKind,
    );
  }

  /// Decode a single layer from its JSON map. Thin public facade over
  /// the private factory registry so UI code (e.g. quick-actions
  /// duplicate) can round-trip `toJson → decodeLayer` without having
  /// to know the concrete subclass or import every layer module.
  ///
  /// Throws [DocumentDecodeException] on missing / unknown type
  /// discriminator, or on a layer-factory [FormatException] (wrapped
  /// as the cause).
  static EditorLayer decodeLayer(Map<String, dynamic> json) {
    final type = json['type'];
    if (type is! String) {
      throw const DocumentDecodeException(
        'layer missing string "type" discriminator',
      );
    }
    final factory = _layerFactories[type];
    if (factory == null) {
      throw DocumentDecodeException('unknown layer type "$type"');
    }
    try {
      return factory(json);
    } on FormatException catch (e) {
      throw DocumentDecodeException(
        'layer of type "$type" failed to decode',
        e,
      );
    }
  }

  /// Decode a document from a JSON string. Wraps [JsonDecoder] errors
  /// in a [DocumentDecodeException] so callers only need one catch.
  static EditorDocument decode(String source) {
    final Object? raw;
    try {
      raw = jsonDecode(source);
    } on FormatException catch (e) {
      throw DocumentDecodeException('input is not valid JSON', e);
    }
    if (raw is! Map) {
      throw const DocumentDecodeException('top-level JSON is not an object');
    }
    return fromJson(Map<String, dynamic>.from(raw));
  }
}
