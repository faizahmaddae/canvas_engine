import 'package:flutter/foundation.dart';

/// Lightweight metadata + serialized payload for a saved design.
///
/// Architecture note: this lives in the **home** feature and only
/// references the editor through the opaque [documentJson] string.
/// Home never reaches into the engine.
@immutable
class Project {
  const Project({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.createdAt,
    required this.lastModified,
    required this.documentJson,
    this.thumbnailPath,
    this.thumbnailVersion = 0,
  });

  /// Bumped whenever the rule for *what a thumbnail PNG should
  /// contain* changes (e.g. canvas background colour newly being
  /// honoured). PNGs written by older versions are stale and the
  /// Recent grid live-renders from [documentJson] instead until the
  /// project is saved again with the current renderer.
  ///
  /// Bump history:
  ///   * 0 — legacy: thumbnails baked an opaque white backdrop
  ///         even for coloured/transparent canvases.
  ///   * 1 — thumbnails respect `EditorDocument.backgroundColor`
  ///         and `backgroundMode` (transparent stays transparent).
  static const int currentThumbnailVersion = 1;

  final String id;
  final String name;
  final double width;
  final double height;

  /// When the project was first persisted. Set once by
  /// `ProjectSaveService` on the first save and preserved across
  /// subsequent updates. Used by the home grid for "Created on …"
  /// metadata and to enable date-based sorting/grouping later.
  final DateTime createdAt;

  /// When the project was last persisted. Bumped on every save
  /// (manual or autosave). Drives the recent-projects sort order.
  final DateTime lastModified;

  /// Encoded [EditorDocument] (via `DocumentCodec.encode`). Stored as a
  /// string to keep this layer free of engine imports.
  final String documentJson;

  /// On-device path to a small PNG snapshot of the project for the
  /// home grid. May be null while the project hasn't been previewed.
  final String? thumbnailPath;

  /// Renderer version that produced [thumbnailPath]. Compared
  /// against [currentThumbnailVersion] to decide whether the cached
  /// PNG is trustworthy or the Recent grid should fall back to a
  /// live `DocumentThumbnail`.
  final int thumbnailVersion;

  Project copyWith({
    String? name,
    double? width,
    double? height,
    DateTime? createdAt,
    DateTime? lastModified,
    String? documentJson,
    String? thumbnailPath,
    int? thumbnailVersion,
  }) => Project(
    id: id,
    name: name ?? this.name,
    width: width ?? this.width,
    height: height ?? this.height,
    createdAt: createdAt ?? this.createdAt,
    lastModified: lastModified ?? this.lastModified,
    documentJson: documentJson ?? this.documentJson,
    thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    thumbnailVersion: thumbnailVersion ?? this.thumbnailVersion,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'width': width,
    'height': height,
    'createdAt': createdAt.toIso8601String(),
    'lastModified': lastModified.toIso8601String(),
    'documentJson': documentJson,
    if (thumbnailPath != null) 'thumbnailPath': thumbnailPath,
    'thumbnailVersion': thumbnailVersion,
  };

  factory Project.fromJson(Map<String, Object?> json) {
    final lastModified = DateTime.parse(json['lastModified']! as String);
    // Backward compat: projects persisted before `createdAt` was
    // introduced fall back to `lastModified`. Any new save will
    // immediately stamp the real createdAt going forward.
    final createdRaw = json['createdAt'] as String?;
    final createdAt = createdRaw == null
        ? lastModified
        : DateTime.parse(createdRaw);
    return Project(
      id: json['id']! as String,
      name: json['name']! as String,
      width: (json['width']! as num).toDouble(),
      height: (json['height']! as num).toDouble(),
      createdAt: createdAt,
      lastModified: lastModified,
      documentJson: json['documentJson']! as String,
      thumbnailPath: json['thumbnailPath'] as String?,
      // Missing field => legacy 0; current renderer will treat it
      // as stale and re-render live until the next save.
      thumbnailVersion: (json['thumbnailVersion'] as int?) ?? 0,
    );
  }
}
