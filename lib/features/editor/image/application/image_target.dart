// Target resolution for the main strip's P-scope image commands
// (Crop / Look). Contract §10.
//
// There is no ladder here, and deliberately so. §10's rule is that
// no command searches for a target: a P command's target is the one
// layer the project kind names as its subject — the protected base
// photo — or there is no target and the control says so (§10.3).
// The predecessor walked selection -> only-image -> base pointer ->
// chooser, which let a design document steer Crop with a marker it
// never showed the user. See docs/command-scope-diagnosis-2026-07.md.
//
// Pure so it can be unit-tested without pumping the editor.

import '../../engine/core/editor_document.dart';
import '../../engine/modules/image/image_layer.dart';

/// The [ImageLayer] a main-strip P-scope command targets, or `null`
/// when the role target does not qualify (§10.2).
///
/// Qualifying means all of:
///   * the document is a photo project AND the layer is its
///     protected base photo — [EditorDocument.isProtectedBasePhoto]
///     carries the `ProjectKind.photo` gate, and is the single
///     admissible reader of `basePhotoLayerId` for targeting (§10.1);
///   * the layer still resolves to an [ImageLayer];
///   * the layer is [visible] — a command whose result cannot be
///     seen has no honest preview (§10.2).
///
/// `locked` is NOT disqualifying: the protected base photo is locked
/// by construction and is precisely the intended target.
///
/// Returning `null` never means "try something else". There is no
/// fallback to another image and no chooser: in a photo project a
/// second image is an overlay, not a candidate.
ImageLayer? resolveRoleTarget(EditorDocument doc) {
  final id = doc.basePhotoLayerId;
  if (id == null || !doc.isProtectedBasePhoto(id)) return null;
  final layer = doc.layerById(id);
  if (layer is! ImageLayer || !layer.visible) return null;
  return layer;
}

/// Why a P control is unavailable, so the caller can offer the
/// matching recovery (§10.3: the recovery must satisfy the stated
/// precondition).
enum RoleTargetBlock {
  /// The role target exists but is hidden. Recovery: unhide it.
  hidden,

  /// There is no role target at all. Recovery: none that fits — the
  /// control should not have been admissible (§10.1).
  missing,
}

/// Classifies why [resolveRoleTarget] returned `null`. Only
/// meaningful when it did.
RoleTargetBlock roleTargetBlock(EditorDocument doc) {
  final id = doc.basePhotoLayerId;
  if (id == null || !doc.isProtectedBasePhoto(id)) {
    return RoleTargetBlock.missing;
  }
  final layer = doc.layerById(id);
  if (layer is! ImageLayer) return RoleTargetBlock.missing;
  return layer.visible ? RoleTargetBlock.missing : RoleTargetBlock.hidden;
}
