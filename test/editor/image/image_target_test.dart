// Contract §10.1/§10.2: the P-scope role target.
//
// `resolveRoleTarget` replaced a five-rung ladder (selection ->
// only-image -> basePhotoLayerId -> chooser -> none). The rungs this
// file exists to keep deleted are the ones that guessed: a design
// document must never resolve a target, and a photo document must
// never fall back off its base photo onto another image.
//
// See docs/command-scope-diagnosis-2026-07.md for why the ladder went.

import 'package:canvas_engine/features/editor/engine/commands/layer_state_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_layer.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/image/application/image_target.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

ImageLayer _img(String id, {bool visible = true, bool locked = false}) =>
    ImageLayer(
      id: id,
      transform: LayerTransform(
        position: Offset.zero,
        size: const Size(400, 300),
      ),
      source: ImageSource.asset('$id.png'),
      visible: visible,
      locked: locked,
    );

ShapeLayer _shape(String id) => ShapeLayer(
  id: id,
  transform: const LayerTransform(position: Offset.zero, size: Size(50, 50)),
  kind: ShapeKind.rectangle,
);

EditorDocument _doc({
  required ProjectKind kind,
  required List<EditorLayer> layers,
  String? basePhotoLayerId,
}) => EditorDocument(
  width: 1080,
  height: 1080,
  layers: layers,
  projectKind: kind,
  basePhotoLayerId: basePhotoLayerId,
);

void main() {
  group('photo project — the role names the target', () {
    test('resolves the protected base photo', () {
      final doc = _doc(
        kind: ProjectKind.photo,
        layers: [_img('photo', locked: true)],
        basePhotoLayerId: 'photo',
      );
      expect(resolveRoleTarget(doc)?.id, 'photo');
    });

    test('locked does NOT disqualify — the base photo is locked by '
        'construction and is exactly the intended target', () {
      final doc = _doc(
        kind: ProjectKind.photo,
        layers: [_img('photo', locked: true)],
        basePhotoLayerId: 'photo',
      );
      expect(doc.layerById('photo')!.locked, isTrue);
      expect(resolveRoleTarget(doc)?.id, 'photo');
    });

    test('an overlay image is never a candidate, whatever its order', () {
      final doc = _doc(
        kind: ProjectKind.photo,
        layers: [_img('photo'), _img('overlay')],
        basePhotoLayerId: 'photo',
      );
      expect(resolveRoleTarget(doc)?.id, 'photo');
    });

    test('a hidden base photo does not qualify, and does NOT fall through '
        'to the visible overlay', () {
      final doc = _doc(
        kind: ProjectKind.photo,
        layers: [_img('photo', visible: false), _img('overlay')],
        basePhotoLayerId: 'photo',
      );
      expect(resolveRoleTarget(doc), isNull);
      expect(roleTargetBlock(doc), RoleTargetBlock.hidden);
    });

    test('a dangling pointer resolves to nothing, not to the only image', () {
      final doc = _doc(
        kind: ProjectKind.photo,
        layers: [_img('other')],
        basePhotoLayerId: 'gone',
      );
      expect(resolveRoleTarget(doc), isNull);
      expect(roleTargetBlock(doc), RoleTargetBlock.missing);
    });

    test('no pointer at all resolves to nothing even with one image — '
        'the sole-image rung is gone', () {
      final doc = _doc(kind: ProjectKind.photo, layers: [_img('only')]);
      expect(resolveRoleTarget(doc), isNull);
      expect(roleTargetBlock(doc), RoleTargetBlock.missing);
    });

    test('a selected image does not become the target: selection is B '
        'scope and never feeds a P command', () {
      final doc = _doc(
        kind: ProjectKind.photo,
        layers: [_img('photo'), _img('overlay'), _shape('s1')],
        basePhotoLayerId: 'photo',
      );
      // No selectedId parameter exists any more — that IS the pin.
      expect(resolveRoleTarget(doc)?.id, 'photo');
    });
  });

  group('design project — no role, therefore no target (§10.1)', () {
    test('resolves nothing even when a base pointer is somehow set', () {
      // A legacy document saved before the claim was kind-gated.
      final doc = _doc(
        kind: ProjectKind.design,
        layers: [_img('a'), _img('b')],
        basePhotoLayerId: 'a',
      );
      expect(doc.basePhotoLayerId, 'a');
      expect(
        resolveRoleTarget(doc),
        isNull,
        reason: 'isProtectedBasePhoto is kind-gated; targeting reads only it',
      );
    });

    test('resolves nothing with exactly one image', () {
      final doc = _doc(kind: ProjectKind.design, layers: [_img('only')]);
      expect(resolveRoleTarget(doc), isNull);
    });

    test('resolves nothing on an empty document', () {
      final doc = _doc(kind: ProjectKind.design, layers: const []);
      expect(resolveRoleTarget(doc), isNull);
    });
  });

  group('import never claims a pointer in a design project', () {
    /// Mirrors `EditorScreen._addImage`'s gate: the pointer is claimed
    /// only in a photo project, and only when still vacant.
    EditorDocument importImage(EditorDocument doc, String id) {
      final claim =
          doc.basePhotoLayerId == null && doc.projectKind == ProjectKind.photo;
      final next = AddLayerCommand(_img(id)).apply(doc);
      return claim ? SetBasePhotoCommand(id).apply(next) : next;
    }

    test('a design import claims nothing, so a reopened design document '
        'carries no marker to steer anything', () {
      var doc = _doc(kind: ProjectKind.design, layers: const []);
      doc = importImage(doc, 'first');
      doc = importImage(doc, 'second');

      expect(doc.basePhotoLayerId, isNull);
      expect(resolveRoleTarget(doc), isNull);
    });

    test('a photo import claims the FIRST image only, and that stays the '
        'target when a second arrives', () {
      var doc = _doc(kind: ProjectKind.photo, layers: const []);
      doc = importImage(doc, 'first');
      doc = importImage(doc, 'second');

      expect(doc.basePhotoLayerId, 'first');
      expect(resolveRoleTarget(doc)?.id, 'first');
    });
  });

  group('visibility round-trip', () {
    test('unhiding the base photo restores the target — the recovery the '
        'unavailable tap offers actually satisfies the precondition', () {
      var doc = _doc(
        kind: ProjectKind.photo,
        layers: [_img('photo', visible: false)],
        basePhotoLayerId: 'photo',
      );
      expect(resolveRoleTarget(doc), isNull);

      doc = const SetLayerVisibilityCommand(
        layerId: 'photo',
        visible: true,
      ).apply(doc);

      expect(resolveRoleTarget(doc)?.id, 'photo');
    });
  });
}
