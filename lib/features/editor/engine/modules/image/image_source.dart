// Source descriptor and mask enum for [ImageLayer], split out of
// image_layer.dart. Part file: symbols resolve via the library
// root's imports — add imports there, never here.
part of 'image_layer.dart';

/// Visual mask applied to an [ImageLayer]'s pixels. The transform
/// (position / size / rotation) is unaffected — the mask only
/// changes which part of the image is visible inside the layer's
/// bounds, so undo/redo, selection handles, and gestures keep
/// working unchanged.
enum ImageMask {
  /// Full rectangular bounds (the default — no clipping applied).
  original,

  /// Soft rounded corners with a consistent radius.
  rounded,

  /// Perfect circle inscribed inside the layer's shortest side.
  circle,

  /// Continuous-corner squircle (Apple-style rounded square).
  squircle,

  /// Five-point star inscribed in the layer's bounds.
  star,

  /// Heart inscribed in the layer's bounds.
  heart,
}

/// Lightweight source descriptor for an [ImageLayer]. The engine stays
/// agnostic to how pixels reach the screen — it only knows about the
/// layer's [LayerTransform] and [LayerCapabilities].
@immutable
class ImageSource {
  const ImageSource.asset(String this.assetName)
    : networkUrl = null,
      filePath = null;
  const ImageSource.network(String this.networkUrl)
    : assetName = null,
      filePath = null;

  /// Local on-device file path (e.g. one returned by `image_picker`
  /// after copying into app-documents storage). Stored as a string so
  /// the engine has no `dart:io` dependency at the type level.
  const ImageSource.file(String this.filePath)
    : assetName = null,
      networkUrl = null;

  final String? assetName;
  final String? networkUrl;
  final String? filePath;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageSource &&
          other.assetName == assetName &&
          other.networkUrl == networkUrl &&
          other.filePath == filePath;

  @override
  int get hashCode => Object.hash(assetName, networkUrl, filePath);

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (assetName != null) 'asset': assetName,
    if (networkUrl != null) 'url': networkUrl,
    if (filePath != null) 'file': filePath,
  };

  /// At least one of `asset`, `url` or `file` must be present, mirroring
  /// the named constructors. Throws otherwise — silent fallback would
  /// render a blank box for what was originally a real image.
  factory ImageSource.fromJson(Map<String, dynamic> json) {
    final asset = json['asset'];
    final url = json['url'];
    final file = json['file'];
    if (asset is String) return ImageSource.asset(asset);
    if (url is String) return ImageSource.network(url);
    if (file is String) return ImageSource.file(file);
    throw const FormatException(
      'ImageSource requires either "asset", "url" or "file"',
    );
  }

  /// Approximate retained size in bytes — just the cost of the one
  /// short identifier string. Pixels live in the OS image cache, not
  /// here, so an [ImageSource] is cheap to keep in undo history.
  int get estimatedByteSize {
    final n =
        (assetName?.length ?? 0) +
        (networkUrl?.length ?? 0) +
        (filePath?.length ?? 0);
    return n * 2; // 2 bytes per UTF-16 code unit.
  }
}
