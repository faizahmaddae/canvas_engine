// One harness for the AGENTS.md `invert()` contract, driven over a
// table covering every public command (roadmap 5.4).
//
// The contract (AGENTS.md hard rule 3):
//
//     invert() takes the document BEFORE apply. Never the document
//     after. Never null. If the inverse is genuinely a no-op (the
//     target was already gone), return _NoopCommand().
//
// which operationally means, for every (document, command) pair:
//
//     let after    = command.apply(before)
//     let inverse  = command.invert(before)      // captured on BEFORE
//     then inverse.apply(after) == before
//
// Until now that was asserted ad hoc, one bespoke test per command,
// so a newly added command silently shipped with no inverse coverage
// at all. This file replaces the ad-hoc pattern with:
//
//   * [expectInvertRoundTrip] — the single structural prover. Checks
//     purity (apply must not mutate `before`), the round-trip itself
//     (via encoded key-path equality, so it reaches every subclass
//     field without per-type comparators), and the real HistoryStack
//     execute → undo → redo cycle.
//   * a table of cases, one or more per public command.
//   * a roster gate that reads the command sources off disk and fails
//     when a public command has no table entry — so this harness
//     cannot silently rot the way the ad-hoc tests did.
//
// Failures report a key-path diff (`layers[1].fillColor: … vs …`),
// never "documents differ".
//
// Pure engine test: no Material, no providers. `canvas_commands.dart`
// lives under `canvas/application/` but is pure command code
// (engine + `flutter/painting.dart`), and the roadmap names it as
// part of this sweep.
import 'dart:io';

import 'package:canvas_engine/features/editor/canvas/application/canvas_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/editor_command.dart';
import 'package:canvas_engine/features/editor/engine/commands/history_stack.dart';
import 'package:canvas_engine/features/editor/engine/commands/image_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/layer_state_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/paint_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/shape_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/text_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_mask.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/document_diff.dart';

// ---------------------------------------------------------------------------
// The harness
// ---------------------------------------------------------------------------

/// Everything one contract run produces, kept together so assertions
/// and failure messages read off the same values.
class InvertProof {
  InvertProof({
    required this.before,
    required this.after,
    required this.inverse,
    required this.restored,
  });

  final EditorDocument before;
  final EditorDocument after;
  final EditorCommand inverse;
  final EditorDocument restored;

  /// True when `apply` changed nothing — a legitimate outcome for
  /// idempotent setters and for commands whose target is missing.
  bool get applyWasNoOp => identical(after, before);

  /// `path: left vs right` lines describing how the restored document
  /// differs from `before`. Empty means the round-trip is exact.
  List<String> get divergence => documentDiffPaths(before, restored);

  /// Just the key paths from [divergence], for allow-list matching.
  List<String> get divergentPaths => <String>[
    for (final line in divergence) line.split(': ').first,
  ];
}

/// Run the contract for one pair. Does not assert — [expectInvertRoundTrip]
/// does. Split out so a caller can inspect the outcome (the known-gap
/// case below does exactly that).
InvertProof runInvert(EditorDocument before, EditorCommand command) {
  final inverse = command.invert(before);
  final after = command.apply(before);
  return InvertProof(
    before: before,
    after: after,
    inverse: inverse,
    restored: inverse.apply(after),
  );
}

/// Prove `invert(before).apply(after) == before` structurally.
///
/// [allowedDivergence] is an escape hatch for a *documented* gap: the
/// listed key paths — and only those — may differ after the round
/// trip. It is deliberately an exact-set match, not a subset check, so
/// a gap that widens (or silently closes) fails the test rather than
/// passing quietly.
void expectInvertRoundTrip(
  EditorDocument before,
  EditorCommand command, {
  required String label,
  List<String> allowedDivergence = const <String>[],
}) {
  // Purity (AGENTS.md hard rules 1 + 2): apply must not reach into
  // `before`. Snapshot its encoding around the call.
  final beforeBytes = DocumentCodec.encode(before);
  final proof = runInvert(before, command);
  expect(
    DocumentCodec.encode(before),
    beforeBytes,
    reason: '$label: apply() mutated the document it was handed',
  );

  if (allowedDivergence.isEmpty) {
    expect(
      DocumentCodec.encode(proof.restored),
      beforeBytes,
      reason:
          '$label: invert(before).apply(after) != before\n'
          '${describeDocumentDiff(before, proof.restored)}',
    );
    // Belt and braces: the encoding cannot see fields the codec omits
    // for the current layer state (e.g. PaintLayer.sides on a
    // freestyle stroke), so also assert Dart equality.
    expect(
      proof.restored,
      before,
      reason:
          '$label: documents encode identically but are not equal — '
          'a non-serialised field diverged',
    );
  } else {
    expect(
      proof.divergentPaths,
      allowedDivergence,
      reason:
          '$label: the set of known-diverging key paths changed.\n'
          '${describeDocumentDiff(before, proof.restored)}',
    );
  }

  // The same trip through the real stack. `execute` returns the
  // document untouched (and pushes nothing) when apply is a no-op, so
  // there is nothing to undo in that case.
  if (proof.applyWasNoOp) return;
  final stack = HistoryStack();
  final executed = stack.execute(before, command);
  expect(
    DocumentCodec.encode(executed),
    DocumentCodec.encode(proof.after),
    reason: '$label: HistoryStack.execute diverged from apply()',
  );
  final undone = stack.undo(executed);
  if (allowedDivergence.isEmpty) {
    expect(
      DocumentCodec.encode(undone),
      beforeBytes,
      reason:
          '$label: undo did not restore the pre-command document\n'
          '${describeDocumentDiff(before, undone)}',
    );
  }
  final redone = stack.redo(undone);
  expect(
    DocumentCodec.encode(redone),
    DocumentCodec.encode(proof.after),
    reason:
        '$label: redo did not reproduce the post-command document\n'
        '${describeDocumentDiff(proof.after, redone)}',
  );
}

/// Assert a command is a genuine no-op on [doc] AND that its inverse
/// is the sanctioned `_NoopCommand` fallback (AGENTS.md rule 3's
/// "the target was already gone" branch): applying the inverse to any
/// document must leave it untouched.
///
/// [returnsSameInstance] additionally pins the *identity* no-op —
/// `apply` returning the very object it was handed. That is not
/// cosmetic: `HistoryStack.execute` uses `identical(next, document)`
/// as its no-op guard, so a command that returns a fresh-but-equal
/// document pushes a phantom undo entry whose inverse does nothing.
/// One command legitimately fails it today (see the call site).
void expectNoopInverse(
  EditorDocument doc,
  EditorCommand command, {
  required String label,
  bool returnsSameInstance = true,
}) {
  final proof = runInvert(doc, command);
  if (returnsSameInstance) {
    expect(
      proof.applyWasNoOp,
      isTrue,
      reason: '$label: expected apply() to return the same document instance',
    );
  } else {
    expect(
      DocumentCodec.encode(proof.after),
      DocumentCodec.encode(doc),
      reason: '$label: expected apply() to leave the document unchanged',
    );
  }
  expect(
    identical(proof.inverse.apply(doc), doc),
    isTrue,
    reason:
        '$label: inverse is not a no-op — it returned a new document '
        'for a command whose target does not exist',
  );
  // A no-op inverse must also be its own inverse; otherwise undo→redo
  // through the stack could resurrect a command with a live effect.
  expect(
    identical(proof.inverse.invert(doc).apply(doc), doc),
    isTrue,
    reason: '$label: the no-op inverse is not itself a no-op under invert()',
  );
}

// ---------------------------------------------------------------------------
// Sample content
// ---------------------------------------------------------------------------

const _textTransform = LayerTransform(
  position: Offset(40, 60),
  size: Size(420, 160),
  rotation: 0.25,
);

const _shapeTransform = LayerTransform(
  position: Offset(120, 620),
  size: Size(840, 300),
  flipH: true,
);

const _imageTransform = LayerTransform(
  position: Offset(60, 60),
  size: Size(960, 720),
);

const _paintTransform = LayerTransform(
  position: Offset(50, 600),
  size: Size(500, 200),
  rotation: -0.4,
  flipV: true,
);

/// A text layer with every optional field off its default, so a
/// command that drops one is caught rather than hidden behind a
/// coincidence of defaults.
TextLayer textLayer({String id = 'txt-1'}) => TextLayer(
  id: id,
  transform: _textTransform,
  content: 'نوروزتان پیروز',
  style: const TextStyleSpec(
    fontFamily: 'Vazir_Regular',
    fontSize: 72,
    color: Color(0xFF1F1B16),
    fontWeight: FontWeight.w800,
    italic: true,
    underline: true,
    letterSpacing: 1.5,
    lineHeight: 1.45,
    alignment: TextAlign.start,
    shadowColor: Color(0x66000000),
    shadowBlur: 8,
    shadowOffset: Offset(2, 3),
    outlineColor: Color(0xFFFFFFFF),
    outlineWidth: 3,
    backgroundColor: Color(0x22FF0000),
    backgroundRadius: 12,
    backgroundPaddingX: 10,
    backgroundPaddingY: 6,
  ),
  resizeMode: TextResizeMode.resizeBox,
  textDirectionMode: TextDirectionMode.rtl,
  name: 'title',
  opacity: 0.9,
);

ShapeLayer shapeLayer({String id = 'shape-1'}) => ShapeLayer(
  id: id,
  transform: _shapeTransform,
  kind: ShapeKind.roundedRectangle,
  fillColor: const Color(0xFFC0872A),
  fill: const LinearGradientBackground(
    startColor: Color(0xFFF5B942),
    endColor: Color(0xFFE2703A),
    angleDegrees: 45,
  ),
  fillOpacity: 0.8,
  strokeColor: const Color(0xFF1F1B16),
  strokeWidth: 4,
  cornerRadius: 24,
  shadowColor: const Color(0xFF102030),
  shadowBlur: 18,
  shadowOffset: const Offset(0, 8),
  shadowOpacity: 0.45,
  resizeMode: ShapeResizeMode.free,
  name: 'band',
  locked: true,
);

ImageLayer imageLayer({String id = 'img-1', EffectStack? effects}) =>
    ImageLayer(
      id: id,
      transform: _imageTransform,
      source: const ImageSource.asset('assets/sample.jpg'),
      fit: BoxFit.cover,
      mask: ImageMask.squircle,
      borderColor: const Color(0xFFFFFFFF),
      borderWidth: 6,
      shadowColor: const Color(0xFF000000),
      shadowBlur: 16,
      shadowOffset: const Offset(0, 6),
      shadowOpacity: 0.4,
      cropRect: const Rect.fromLTRB(0.1, 0.15, 0.85, 0.95),
      filterPreset: ImageFilterPreset.vintage,
      opacity: 0.85,
      name: 'hero',
      effects: effects ?? richEffects(),
    );

/// A stack that is deliberately NOT in the canonical derived order and
/// carries a disabled entry, a per-effect mask, a custom-paint effect
/// and a stack mask — every shape
/// [SetImageAdjustmentsCommand]'s surgical edit has to preserve.
EffectStack richEffects() => EffectStack(
  List<EditorEffect>.unmodifiable(<EditorEffect>[
    const ContrastEffect(amount: 1.15),
    const ExposureEffect(amount: 0.3),
    BrightnessEffect(
      amount: 18,
      mask: const RectMask(
        rect: Rect.fromLTWH(0, 0, 960, 360),
        feather: 32,
        inverted: true,
      ),
    ),
    const SaturationEffect(amount: 0.75, enabled: false),
    const WarmthEffect(amount: -0.2),
    const VignetteEffect(
      intensity: 0.6,
      feather: 0.35,
      color: Color(0xFF102030),
    ),
  ]),
  stackMask: const EllipseMask(
    bounds: Rect.fromLTWH(20, 20, 900, 640),
    feather: 8,
  ),
);

PaintLayer paintLayer({
  String id = 'paint-1',
  PaintKind kind = PaintKind.polygon,
}) => PaintLayer(
  id: id,
  transform: _paintTransform,
  kind: kind,
  normalizedPoints: const [
    Offset(0, 0.5),
    Offset(0.25, 0),
    Offset(0.5, 0.75),
    Offset(1, 0.5),
  ],
  strokeColor: const Color(0xFFC0872A),
  strokeWidth: 14,
  fillColor: const Color(0x33FF3B30),
  sides: 5,
  blurSigma: 9,
  resizeMode: PaintResizeMode.scale,
  name: 'stroke',
);

/// The workhorse document: one layer of every type, a gradient
/// canvas background, a non-default background mode.
EditorDocument sampleDocument() => EditorDocument(
  layers: [textLayer(), shapeLayer(), imageLayer(), paintLayer()],
  width: 1080,
  height: 1350,
  background: const RadialGradientBackground(
    centerColor: Color(0xFFFFF3D6),
    edgeColor: Color(0xFF2A1B0B),
  ),
  backgroundMode: CanvasBackgroundMode.transparent,
);

/// A photo project whose base photo is the image layer. Separated out
/// because the base-photo pointer is its own invert surface.
EditorDocument photoDocument() => EditorDocument(
  layers: [imageLayer(), textLayer()],
  basePhotoLayerId: 'img-1',
  projectKind: ProjectKind.photo,
);

// ---------------------------------------------------------------------------
// The table
// ---------------------------------------------------------------------------

/// One table row: a document builder and a command builder. Both are
/// builders, not values, so each test gets a pristine document — a
/// shared instance would let one case's (hypothetical) mutation leak
/// into the next and mask exactly the purity bug the harness checks.
///
/// Deliberately no `allowedDivergence` field: a command whose inverse
/// does not round-trip is a *finding*, not a table configuration, and
/// belongs in the "known invert gap" group at the bottom of this file
/// where it can carry the explanation.
class _Case {
  const _Case(this.name, this.before, this.command);

  final String name;
  final EditorDocument Function() before;
  final EditorCommand Function() command;
}

final List<_Case> _cases = <_Case>[
  // -- transform_commands.dart ---------------------------------------
  _Case(
    'AddLayerCommand appends',
    sampleDocument,
    () => AddLayerCommand(shapeLayer(id: 'shape-new')),
  ),
  _Case(
    'AddLayerCommand at an explicit index',
    sampleDocument,
    () => AddLayerCommand(textLayer(id: 'txt-new'), index: 1),
  ),
  _Case(
    'RemoveLayerCommand from the middle of the z-order',
    sampleDocument,
    () => const RemoveLayerCommand('shape-1'),
  ),
  _Case(
    'SetLayerTransformCommand',
    sampleDocument,
    () => const SetLayerTransformCommand(
      layerId: 'txt-1',
      transform: LayerTransform(
        position: Offset(11, 22),
        size: Size(333, 44),
        rotation: 1.1,
        flipH: true,
        flipV: true,
      ),
    ),
  ),
  _Case(
    'MoveLayerCommand',
    sampleDocument,
    () => const MoveLayerCommand(
      layerId: 'shape-1',
      transform: LayerTransform(
        position: Offset(200, 700),
        size: Size(840, 300),
        flipH: true,
      ),
    ),
  ),
  _Case(
    'ResizeLayerCommand',
    sampleDocument,
    () => const ResizeLayerCommand(
      layerId: 'img-1',
      transform: LayerTransform(position: Offset(60, 60), size: Size(400, 300)),
    ),
  ),
  _Case(
    'RotateLayerCommand',
    sampleDocument,
    () => const RotateLayerCommand(
      layerId: 'paint-1',
      transform: LayerTransform(
        position: Offset(50, 600),
        size: Size(500, 200),
        rotation: 2.4,
        flipV: true,
      ),
    ),
  ),
  _Case(
    'FlipLayerCommand horizontal (self-inverse)',
    sampleDocument,
    () => const FlipLayerCommand(layerId: 'shape-1', horizontal: true),
  ),
  _Case(
    'FlipLayerCommand vertical (self-inverse)',
    sampleDocument,
    () => const FlipLayerCommand(layerId: 'paint-1', horizontal: false),
  ),
  _Case(
    'SetBasePhotoCommand sets a pointer',
    sampleDocument,
    () => const SetBasePhotoCommand('img-1'),
  ),
  _Case(
    'SetBasePhotoCommand clears a pointer',
    photoDocument,
    () => const SetBasePhotoCommand(null),
  ),
  _Case(
    'SetProjectKindCommand design → photo',
    sampleDocument,
    () => const SetProjectKindCommand(ProjectKind.photo),
  ),
  _Case(
    'CompositeCommand bundles a move + a restyle + a delete',
    sampleDocument,
    () => CompositeCommand(<EditorCommand>[
      const MoveLayerCommand(
        layerId: 'txt-1',
        transform: LayerTransform(
          position: Offset(1, 2),
          size: Size(420, 160),
          rotation: 0.25,
        ),
      ),
      const SetShapeRadiusCommand(layerId: 'shape-1', radius: 64),
      const RemoveLayerCommand('paint-1'),
    ]),
  ),

  // -- layer_state_commands.dart -------------------------------------
  _Case(
    'ReorderLayerCommand moves up',
    sampleDocument,
    () => const ReorderLayerCommand(from: 0, to: 3),
  ),
  _Case(
    'ReorderLayerCommand moves down',
    sampleDocument,
    () => const ReorderLayerCommand(from: 2, to: 1),
  ),
  _Case(
    'SetLayerVisibilityCommand hides',
    sampleDocument,
    () => const SetLayerVisibilityCommand(layerId: 'img-1', visible: false),
  ),
  _Case(
    'SetLayerLockCommand unlocks an already-locked layer',
    sampleDocument,
    () => const SetLayerLockCommand(layerId: 'shape-1', locked: false),
  ),
  _Case(
    'SetLayerOpacityCommand',
    sampleDocument,
    () => const SetLayerOpacityCommand(layerId: 'txt-1', opacity: 0.25),
  ),
  _Case(
    'SetLayerNameCommand renames',
    sampleDocument,
    () => const SetLayerNameCommand(layerId: 'img-1', name: 'قاب اصلی'),
  ),
  _Case(
    'SetLayerNameCommand clears a name (whitespace normalises to null)',
    sampleDocument,
    () => const SetLayerNameCommand(layerId: 'shape-1', name: '   '),
  ),

  // -- image_commands.dart -------------------------------------------
  _Case(
    'ReplaceImageSourceCommand also restores the wiped crop',
    sampleDocument,
    () => const ReplaceImageSourceCommand(
      layerId: 'img-1',
      source: ImageSource.file('/tmp/other.png'),
    ),
  ),
  _Case(
    'SetImageMaskCommand',
    sampleDocument,
    () => const SetImageMaskCommand(layerId: 'img-1', mask: ImageMask.heart),
  ),
  _Case(
    'SetImageBorderCommand colour only',
    sampleDocument,
    () =>
        const SetImageBorderCommand(layerId: 'img-1', color: Color(0xFF00FF88)),
  ),
  _Case(
    'SetImageBorderCommand width to zero (drops the border keys)',
    sampleDocument,
    () => const SetImageBorderCommand(layerId: 'img-1', width: 0),
  ),
  _Case(
    'SetImageShadowCommand one knob at a time',
    sampleDocument,
    () => const SetImageShadowCommand(layerId: 'img-1', blur: 42),
  ),
  _Case(
    'SetImageShadowCommand opacity to zero (drops every shadow key)',
    sampleDocument,
    () => const SetImageShadowCommand(layerId: 'img-1', opacity: 0),
  ),
  _Case(
    'SetImageAdjustmentsCommand edits a live derived effect',
    sampleDocument,
    () => const SetImageAdjustmentsCommand(layerId: 'img-1', contrast: 1.4),
  ),
  _Case(
    'SetImageAdjustmentsCommand drags a knob back to identity',
    sampleDocument,
    () => const SetImageAdjustmentsCommand(layerId: 'img-1', exposure: 0),
  ),
  _Case(
    'SetImageAdjustmentsCommand inserts a knob that had no live instance',
    sampleDocument,
    () => const SetImageAdjustmentsCommand(layerId: 'img-1', saturation: 1.3),
  ),
  _Case(
    'SetImageVignetteCommand raises intensity',
    sampleDocument,
    () => const SetImageVignetteCommand(layerId: 'img-1', intensity: 0.9),
  ),
  _Case(
    'SetImageVignetteCommand drags intensity to zero (removes the effect)',
    sampleDocument,
    () => const SetImageVignetteCommand(layerId: 'img-1', intensity: 0),
  ),
  _Case(
    'SetImageVignetteCommand creates a vignette on a bare stack',
    () => EditorDocument(layers: [imageLayer(effects: EffectStack.empty)]),
    () => const SetImageVignetteCommand(layerId: 'img-1', intensity: 0.5),
  ),
  _Case(
    'SetImageCropCommand',
    sampleDocument,
    () => const SetImageCropCommand(
      layerId: 'img-1',
      cropRect: Rect.fromLTRB(0.2, 0.2, 0.6, 0.6),
    ),
  ),
  _Case(
    'SetImageCropCommand back to the full window',
    sampleDocument,
    () => const SetImageCropCommand(
      layerId: 'img-1',
      cropRect: ImageLayer.fullCrop,
    ),
  ),
  _Case(
    'SetImageFitCommand',
    sampleDocument,
    () => const SetImageFitCommand(layerId: 'img-1', fit: BoxFit.contain),
  ),
  _Case(
    'SetImageFilterCommand clears the preset',
    sampleDocument,
    () => const SetImageFilterCommand(
      layerId: 'img-1',
      filterPreset: ImageFilterPreset.none,
    ),
  ),
  _Case(
    'ReorderEffectCommand moves an effect up the stack',
    sampleDocument,
    () =>
        const ReorderEffectCommand(layerId: 'img-1', oldIndex: 0, newIndex: 4),
  ),
  _Case(
    'ReorderEffectCommand moves an effect down the stack',
    sampleDocument,
    () =>
        const ReorderEffectCommand(layerId: 'img-1', oldIndex: 5, newIndex: 1),
  ),
  _Case(
    'ToggleEffectEnabledCommand disables (self-inverse)',
    sampleDocument,
    () => const ToggleEffectEnabledCommand(layerId: 'img-1', index: 0),
  ),
  _Case(
    'ToggleEffectEnabledCommand re-enables a disabled entry',
    sampleDocument,
    () => const ToggleEffectEnabledCommand(layerId: 'img-1', index: 3),
  ),
  _Case(
    'DeleteEffectCommand restores value AND position',
    sampleDocument,
    () => const DeleteEffectCommand(layerId: 'img-1', index: 2),
  ),
  _Case(
    'DeleteEffectCommand on the last effect keeps the stack mask',
    sampleDocument,
    () => const DeleteEffectCommand(layerId: 'img-1', index: 5),
  ),
  _Case(
    'SetStackMaskCommand replaces the mask',
    sampleDocument,
    () => const SetStackMaskCommand(
      layerId: 'img-1',
      mask: PathMask(
        contours: [
          PathContour(
            start: Offset(0, 0),
            segments: [
              LineSegment(end: Offset(100, 0)),
              QuadSegment(control: Offset(150, 50), end: Offset(100, 100)),
              CubicSegment(
                control1: Offset(60, 120),
                control2: Offset(20, 120),
                end: Offset(0, 0),
              ),
            ],
          ),
        ],
        fillType: PathFillType.evenOdd,
        feather: 4,
      ),
    ),
  ),
  _Case(
    'SetStackMaskCommand clears the mask',
    sampleDocument,
    () => const SetStackMaskCommand(layerId: 'img-1', mask: null),
  ),

  // -- shape_commands.dart -------------------------------------------
  _Case(
    'SetShapeFillCommand solid pick over a gradient',
    sampleDocument,
    () =>
        const SetShapeFillCommand(layerId: 'shape-1', color: Color(0xFF3355FF)),
  ),
  _Case(
    'SetShapeFillCommand opacity only',
    sampleDocument,
    () => const SetShapeFillCommand(layerId: 'shape-1', opacity: 0.3),
  ),
  _Case(
    'SetShapeFillCommand installs a gradient over a solid',
    () => EditorDocument(
      layers: [
        const ShapeLayer(
          id: 'shape-1',
          transform: _shapeTransform,
          kind: ShapeKind.rectangle,
          fillColor: Color(0xFF445566),
        ),
      ],
    ),
    () => const SetShapeFillCommand(
      layerId: 'shape-1',
      fill: LinearGradientBackground(
        startColor: Color(0xFFF5B942),
        endColor: Color(0xFFE2703A),
      ),
    ),
  ),
  _Case(
    'SetShapeStrokeCommand clears the outline',
    sampleDocument,
    () => const SetShapeStrokeCommand(layerId: 'shape-1', clearColor: true),
  ),
  _Case(
    'SetShapeStrokeCommand width only',
    sampleDocument,
    () => const SetShapeStrokeCommand(layerId: 'shape-1', width: 11),
  ),
  _Case(
    'SetShapeRadiusCommand',
    sampleDocument,
    () => const SetShapeRadiusCommand(layerId: 'shape-1', radius: 64),
  ),
  _Case(
    'SetShapeRadiusCommand clamps a negative radius to zero',
    sampleDocument,
    () => const SetShapeRadiusCommand(layerId: 'shape-1', radius: -20),
  ),
  _Case(
    'ReplaceShapeKindCommand morphs to an aspect-locked kind',
    sampleDocument,
    () =>
        const ReplaceShapeKindCommand(layerId: 'shape-1', kind: ShapeKind.star),
  ),
  _Case(
    'SetShapeShadowCommand offset only',
    sampleDocument,
    () =>
        const SetShapeShadowCommand(layerId: 'shape-1', offset: Offset(-4, 9)),
  ),
  _Case(
    'SetShapeShadowCommand opacity to zero (drops every shadow key)',
    sampleDocument,
    () => const SetShapeShadowCommand(layerId: 'shape-1', opacity: 0),
  ),
  _Case(
    'SetShapeResizeModeCommand clears the override back to null',
    sampleDocument,
    () => const SetShapeResizeModeCommand(layerId: 'shape-1', mode: null),
  ),
  _Case(
    'SetShapeResizeModeCommand sets an explicit override',
    sampleDocument,
    () => const SetShapeResizeModeCommand(
      layerId: 'shape-1',
      mode: ShapeResizeMode.scale,
    ),
  ),

  // -- paint_commands.dart -------------------------------------------
  _Case(
    'UpdatePaintStyleCommand stroke colour + width',
    sampleDocument,
    () => const UpdatePaintStyleCommand(
      layerId: 'paint-1',
      strokeColor: Color(0xFF00A3FF),
      strokeWidth: 3,
    ),
  ),
  _Case(
    'UpdatePaintStyleCommand clears the fill via the sentinel',
    sampleDocument,
    () => const UpdatePaintStyleCommand(
      layerId: 'paint-1',
      setFillColor: true,
      fillColor: null,
    ),
  ),
  _Case(
    'UpdatePaintStyleCommand restyles to a peer kind',
    sampleDocument,
    () => const UpdatePaintStyleCommand(
      layerId: 'paint-1',
      kind: PaintKind.hexagon,
    ),
  ),
  _Case(
    'UpdatePaintStyleCommand sides + blur sigma',
    sampleDocument,
    () => const UpdatePaintStyleCommand(
      layerId: 'paint-1',
      sides: 8,
      blurSigma: 24,
    ),
  ),
  _Case(
    'SetPaintResizeModeCommand',
    sampleDocument,
    () => const SetPaintResizeModeCommand(
      layerId: 'paint-1',
      mode: PaintResizeMode.free,
    ),
  ),

  // -- text_commands.dart --------------------------------------------
  _Case(
    'UpdateTextCommand content only',
    sampleDocument,
    () => const UpdateTextCommand(layerId: 'txt-1', content: 'سال نو مبارک'),
  ),
  _Case(
    'UpdateTextCommand style only',
    sampleDocument,
    () => const UpdateTextCommand(
      layerId: 'txt-1',
      style: TextStyleSpec(fontSize: 44, color: Color(0xFF00FF00)),
    ),
  ),
  _Case(
    'UpdateTextCommand content + style + transform in one entry',
    sampleDocument,
    () => const UpdateTextCommand(
      layerId: 'txt-1',
      content: 'دو خطی\nمتن',
      style: TextStyleSpec(fontSize: 30),
      transform: LayerTransform(
        position: Offset(40, 60),
        size: Size(420, 260),
        rotation: 0.25,
      ),
    ),
  ),
  _Case(
    'SetTextResizeModeCommand with a bundled re-measure',
    sampleDocument,
    () => const SetTextResizeModeCommand(
      layerId: 'txt-1',
      mode: TextResizeMode.scaleText,
      transform: LayerTransform(position: Offset(40, 60), size: Size(420, 96)),
    ),
  ),
  _Case(
    'SetTextDirectionModeCommand',
    sampleDocument,
    () => const SetTextDirectionModeCommand(
      layerId: 'txt-1',
      mode: TextDirectionMode.ltr,
    ),
  ),

  // -- canvas_commands.dart ------------------------------------------
  _Case(
    'SetCanvasBackgroundCommand solid over a gradient',
    sampleDocument,
    () => const SetCanvasBackgroundCommand(color: Color(0xFF112233)),
  ),
  _Case(
    'SetCanvasBackgroundCommand gradient over a gradient',
    sampleDocument,
    () => const SetCanvasBackgroundCommand(
      fill: LinearGradientBackground(
        startColor: Color(0xFFFF0080),
        endColor: Color(0xFF7928CA),
        angleDegrees: 90,
      ),
    ),
  ),
  _Case(
    'SetCanvasBackgroundModeCommand',
    sampleDocument,
    () => const SetCanvasBackgroundModeCommand(CanvasBackgroundMode.color),
  ),
  _Case(
    'SetCanvasSizeCommand',
    sampleDocument,
    () => const SetCanvasSizeCommand(width: 2048, height: 1152),
  ),
];

/// Public command class names, scraped off the sources the roadmap
/// names, so a newly-added command cannot ship without a table entry.
Set<String> _publicCommandNames() {
  const sources = <String>[
    'lib/features/editor/engine/commands/editor_command.dart',
    'lib/features/editor/engine/commands/history_stack.dart',
    'lib/features/editor/engine/commands/image_commands.dart',
    'lib/features/editor/engine/commands/layer_state_commands.dart',
    'lib/features/editor/engine/commands/paint_commands.dart',
    'lib/features/editor/engine/commands/shape_commands.dart',
    'lib/features/editor/engine/commands/text_commands.dart',
    'lib/features/editor/engine/commands/transform_commands.dart',
    'lib/features/editor/canvas/application/canvas_commands.dart',
  ];
  // Catches direct subclasses and the three SetLayerTransformCommand
  // aliases (Move / Resize / Rotate).
  final pattern = RegExp(
    r'^class\s+(\w+)\s+extends\s+(EditorCommand|SetLayerTransformCommand)\b',
    multiLine: true,
  );
  final names = <String>{};
  for (final path in sources) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: 'command source missing: $path');
    for (final match in pattern.allMatches(file.readAsStringSync())) {
      final name = match.group(1)!;
      // `_`-prefixed classes are the sanctioned private inverses
      // (_NoopCommand, _RestoreEffectsCommand, _InsertEffectCommand,
      // _RestoreImageSourceCommand). They are exercised transitively
      // by the public commands that produce them, and cannot be
      // constructed from a test.
      if (name.startsWith('_')) continue;
      names.add(name);
    }
  }
  return names;
}

void main() {
  group('invert harness', () {
    for (final testCase in _cases) {
      test(testCase.name, () {
        expectInvertRoundTrip(
          testCase.before(),
          testCase.command(),
          label: testCase.name,
        );
      });
    }
  });

  group('table covers every public command', () {
    test('no public command is missing an invert case', () {
      final covered = <String>{
        for (final c in _cases) c.command().runtimeType.toString(),
      };
      final declared = _publicCommandNames();
      expect(
        declared.difference(covered).toList()..sort(),
        isEmpty,
        reason:
            'these public commands have no entry in the invert table — '
            'add one rather than deleting this gate',
      );
      // The reverse direction guards against a stale entry naming a
      // command that no longer exists.
      expect(
        covered.difference(declared).toList()..sort(),
        isEmpty,
        reason: 'invert table references commands that are no longer declared',
      );
    });

    test('the table is not accidentally shrinking', () {
      // A floor, not an exact count: adding cases is always fine.
      expect(_cases.length, greaterThanOrEqualTo(70));
    });
  });

  // -------------------------------------------------------------------
  // Commands that legitimately cannot "round-trip" in the usual sense.
  // AGENTS.md rule 3 sanctions a _NoopCommand inverse when the target
  // is gone; these assert that branch explicitly instead of leaving it
  // as an untested silent fallback.
  // -------------------------------------------------------------------
  group('missing-target inverses are explicit no-ops', () {
    final doc = sampleDocument();

    final noopCases = <String, EditorCommand>{
      'SetLayerTransformCommand': const SetLayerTransformCommand(
        layerId: 'ghost',
        transform: LayerTransform(position: Offset.zero, size: Size(10, 10)),
      ),
      'FlipLayerCommand': const FlipLayerCommand(
        layerId: 'ghost',
        horizontal: true,
      ),
      'SetLayerVisibilityCommand': const SetLayerVisibilityCommand(
        layerId: 'ghost',
        visible: false,
      ),
      'SetLayerLockCommand': const SetLayerLockCommand(
        layerId: 'ghost',
        locked: true,
      ),
      'SetLayerOpacityCommand': const SetLayerOpacityCommand(
        layerId: 'ghost',
        opacity: 0.5,
      ),
      'SetLayerNameCommand': const SetLayerNameCommand(
        layerId: 'ghost',
        name: 'x',
      ),
      'SetImageMaskCommand': const SetImageMaskCommand(
        layerId: 'ghost',
        mask: ImageMask.circle,
      ),
      'SetImageCropCommand': const SetImageCropCommand(
        layerId: 'ghost',
        cropRect: Rect.fromLTRB(0, 0, 0.5, 0.5),
      ),
      'SetShapeFillCommand': const SetShapeFillCommand(
        layerId: 'ghost',
        color: Color(0xFF000000),
      ),
      'UpdateTextCommand': const UpdateTextCommand(
        layerId: 'ghost',
        content: 'x',
      ),
      'UpdatePaintStyleCommand': const UpdatePaintStyleCommand(
        layerId: 'ghost',
        strokeWidth: 2,
      ),
    };

    for (final entry in noopCases.entries) {
      test('${entry.key} on a missing layer', () {
        expectNoopInverse(doc, entry.value, label: entry.key);
      });
    }

    test(
      'RemoveLayerCommand on a missing layer (value no-op, new instance)',
      () {
        // `EditorDocument.removeLayer` runs `layers.where(...)` and then
        // `copyWith`, so removing an id that isn't there still allocates
        // a fresh (equal) document rather than returning `this`. The
        // inverse is correctly a `_NoopCommand`, so undo/redo stay
        // correct — but `HistoryStack.execute`'s `identical` guard does
        // not fire, so a ghost delete pushes an undo entry that undoes
        // nothing. Pinned here rather than fixed in lib/ (roadmap 5.4 is
        // a test-only stage); see the accompanying report.
        expectNoopInverse(
          doc,
          const RemoveLayerCommand('ghost'),
          label: 'RemoveLayerCommand on a missing layer',
          returnsSameInstance: false,
        );
        final stack = HistoryStack();
        stack.execute(doc, const RemoveLayerCommand('ghost'));
        expect(
          stack.undoDepth,
          1,
          reason:
              'documents the phantom entry: change this to 0 in the same '
              'commit that makes removeLayer return `this` for a missing id',
        );
      },
    );

    test('type-mismatched target is also a no-op (image command on text)', () {
      expectNoopInverse(
        doc,
        const SetImageFitCommand(layerId: 'txt-1', fit: BoxFit.fill),
        label: 'SetImageFitCommand on a TextLayer',
      );
    });

    test('out-of-range effect index is a no-op', () {
      expectNoopInverse(
        doc,
        const DeleteEffectCommand(layerId: 'img-1', index: 99),
        label: 'DeleteEffectCommand index 99',
      );
      expectNoopInverse(
        doc,
        const ReorderEffectCommand(layerId: 'img-1', oldIndex: 0, newIndex: 99),
        label: 'ReorderEffectCommand newIndex 99',
      );
      expectNoopInverse(
        doc,
        const ToggleEffectEnabledCommand(layerId: 'img-1', index: -1),
        label: 'ToggleEffectEnabledCommand index -1',
      );
    });

    test('idempotent setters return the same document instance', () {
      expectNoopInverse(
        doc,
        const SetImageFitCommand(layerId: 'img-1', fit: BoxFit.cover),
        label: 'SetImageFitCommand to the value already set',
      );
      expectNoopInverse(
        doc,
        const SetCanvasSizeCommand(width: 1080, height: 1350),
        label: 'SetCanvasSizeCommand to the size already set',
      );
      expectNoopInverse(
        doc,
        const SetShapeRadiusCommand(layerId: 'shape-1', radius: 24),
        label: 'SetShapeRadiusCommand to the radius already set',
      );
    });

    test('base-photo reorder guard refuses symmetrically', () {
      // reorderLayer refuses moves that would unpin the base photo.
      // The refusal has to be symmetric or the inverse of a refused
      // reorder would be a REAL move, and undo would scramble the
      // z-order. Both directions must no-op.
      final photo = photoDocument();
      expectNoopInverse(
        photo,
        const ReorderLayerCommand(from: 0, to: 1),
        label: 'ReorderLayerCommand lifting the base photo',
      );
      expectNoopInverse(
        photo,
        const ReorderLayerCommand(from: 1, to: 0),
        label: 'ReorderLayerCommand sliding under the base photo',
      );
    });
  });

  // -------------------------------------------------------------------
  // Known divergence — see the report accompanying roadmap 5.4.
  // -------------------------------------------------------------------
  group('known invert gap', () {
    test('RemoveLayerCommand does not restore basePhotoLayerId on undo', () {
      // `EditorDocument.removeLayer` clears `basePhotoLayerId` as a
      // side effect, and `RemoveLayerCommand.invert` deliberately
      // does not re-point it (see the comment in
      // transform_commands.dart). Production compensates by bundling
      // an explicit SetBasePhotoCommand into the delete composite,
      // so the gap is unreachable through the one real base-photo
      // delete flow — but the command's own inverse does NOT satisfy
      // `invert(before).apply(after) == before`.
      //
      // Asserted as an exact allow-list so the day someone folds the
      // pointer into the inverse (or the gap widens), this fails.
      expectInvertRoundTrip(
        photoDocument(),
        const RemoveLayerCommand('img-1'),
        label: 'RemoveLayerCommand on the base photo',
        allowedDivergence: const <String>['basePhotoLayerId'],
      );
    });

    test('the composite production actually uses does round-trip', () {
      // The compensating shape: clear the pointer first, then remove.
      // Proof that the gap is a command-level one, not a user-visible
      // undo bug on the shipped path.
      expectInvertRoundTrip(
        photoDocument(),
        CompositeCommand(const <EditorCommand>[
          SetBasePhotoCommand(null),
          RemoveLayerCommand('img-1'),
        ]),
        label: 'base-photo delete composite',
      );
    });
  });
}
