import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../application/document_controller.dart';
import '../../application/editor_lifecycle.dart';
import '../../application/selection_controller.dart';
import '../../engine/commands/transform_commands.dart';
import '../../engine/core/canvas_sizing.dart';
import '../../engine/core/editor_layer.dart';
import '../../engine/core/layer_transform.dart';
import '../../engine/modules/paint/paint_layer.dart';
import '../application/paint_draft.dart';
import '../application/paint_tool_controller.dart';
import '../domain/paint_tool_type.dart';

const _uuid = Uuid();

/// Full-bleed transparent surface that turns canvas drag gestures into
/// [PaintLayer]s.
///
/// Lives **inside** the viewport transform so drag offsets arrive in
/// canvas-local coordinates without manual mapping. Mounted only when
/// paint mode has an active tool, so in normal editing the surface
/// doesn't exist and the viewport's pan/pinch + selection chrome
/// behave exactly as before. When mounted it claims the gesture arena
/// via [GestureDetector.onPan*], so the background scale recogniser
/// never receives the drag and the canvas stays still.
///
/// Every committed drawing flows through [DocumentController.execute]
/// → [AddLayerCommand] / [RemoveLayerCommand], producing exactly one
/// undo step per finished gesture.
class PaintGestureSurface extends ConsumerStatefulWidget {
  const PaintGestureSurface({super.key, required this.docSize});

  final Size docSize;

  @override
  ConsumerState<PaintGestureSurface> createState() =>
      _PaintGestureSurfaceState();
}

class _PaintGestureSurfaceState extends ConsumerState<PaintGestureSurface> {
  PaintDraft? _draft;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(paintToolControllerProvider);
    final tool = session.activeTool;
    if (tool == null) return const SizedBox.shrink();
    final isEraser = tool == PaintToolType.eraser;

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Simple tap (no drag) = exit paint mode. For the eraser we
        // first try to delete a hit layer; if nothing was hit, we fall
        // through and dismiss too. Drawing is exclusively a drag
        // gesture, so this never interferes with an in-flight stroke.
        onTapUp: isEraser
            ? (d) => _handleEraserTap(d.localPosition)
            : (_) => _exitPaintMode(),
        onPanStart: (d) => _onPanStart(tool, session, d.localPosition),
        onPanUpdate: (d) => _onPanUpdate(d.localPosition, isEraser),
        onPanEnd: (_) => _onPanEnd(),
        onPanCancel: _onPanCancel,
        child: _draft == null
            ? const SizedBox.expand()
            : _DraftPreview(draft: _draft!),
      ),
    );
  }

  // ---------------------------------------------------------------- gestures

  void _onPanStart(PaintToolType tool, PaintSession session, Offset local) {
    if (tool == PaintToolType.eraser) {
      _eraseAt(local);
      return;
    }
    setState(() {
      // The blur slider stores its value as *reference px* (designed
      // against the 1080-square canvas) — same model as the text
      // controller's font-size slider. Scaling at draft-creation
      // time via `CanvasSizing.scaleDimension` means a "16" pick
      // reads at the same visual softness on a 100×100 sticker as
      // on a 12000×12000 poster, instead of vanishing on the big
      // canvas and erasing the layer on the small one. Stroke
      // width / fill / sides are user-picked geometry, so they
      // pass through unchanged.
      final doc = ref.read(documentControllerProvider);
      _draft = PaintDraft(
        kind: _kindFor(tool),
        strokeColor: session.strokeColor,
        strokeWidth: session.strokeWidth,
        fillColor: session.fillColor,
        sides: session.polygonSides,
        blurSigma: CanvasSizing.scaleDimension(session.blurRadius, doc),
        points: [local],
      );
    });
  }

  void _onPanUpdate(Offset local, bool isEraser) {
    if (isEraser) {
      _eraseAt(local);
      return;
    }
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      if (draft.kind == PaintKind.freestyle) {
        draft.points.add(local);
      } else {
        // Two-point geometry: replace the trailing endpoint each tick.
        if (draft.points.length == 1) {
          draft.points.add(local);
        } else {
          draft.points[draft.points.length - 1] = local;
        }
      }
    });
  }

  void _onPanEnd() {
    final draft = _draft;
    if (draft == null) return;
    final layer = draft.toLayer(id: _uuid.v4(), docSize: widget.docSize);
    setState(() => _draft = null);
    if (layer == null) return; // degenerate (zero-area) gesture
    ref
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(layer));
  }

  void _onPanCancel() {
    if (_draft == null) return;
    setState(() => _draft = null);
  }

  /// Tap-only handling for the eraser: erase a hit layer if any,
  /// otherwise treat the tap as "changed my mind" and exit paint mode.
  void _handleEraserTap(Offset local) {
    if (!_eraseAt(local)) {
      _exitPaintMode();
    }
  }

  /// Exit paint mode in response to a simple tap on empty canvas.
  /// Routes through the central [dismissActiveEditing] helper so
  /// the same teardown that text/selection use is applied here:
  /// closes the paint sub-tool panel + slot, clears any selection,
  /// drops focus, stops inline editing. Painted layers and any
  /// in-flight stroke (which lives on the pan route, not tap) are
  /// untouched.
  void _exitPaintMode() {
    dismissActiveEditing(ref);
  }

  // ---------------------------------------------------------------- eraser

  /// Phase-1 eraser: find the topmost paint layer whose oriented
  /// bounding box contains [local] and remove it via
  /// [RemoveLayerCommand]. Other layer kinds (text/shape/image) are
  /// deliberately skipped — the eraser is "paint only" by spec to keep
  /// behaviour predictable. Returns whether a layer was actually
  /// erased.
  bool _eraseAt(Offset local) {
    final doc = ref.read(documentControllerProvider);
    EditorLayer? hit;
    for (var i = doc.layers.length - 1; i >= 0; i--) {
      final layer = doc.layers[i];
      if (!layer.visible || layer.locked) continue;
      if (layer is! PaintLayer) continue;
      if (_containsLocal(layer.transform, local)) {
        hit = layer;
        break;
      }
    }
    if (hit == null) return false;
    ref
        .read(documentControllerProvider.notifier)
        .execute(RemoveLayerCommand(hit.id));
    // If the erased paint layer happened to be selected (e.g. user
    // tapped it to select it and then entered paint/eraser mode),
    // clear selection so no dangling id remains in SelectionState.
    if (ref.read(selectionControllerProvider).contains(hit.id)) {
      ref.read(selectionControllerProvider.notifier).clear();
    }
    return true;
  }

  /// Oriented bounding-box hit test — transforms [local] into the
  /// layer's local space using the inverse rotation about its centre.
  bool _containsLocal(LayerTransform t, Offset local) {
    final cx = t.position.dx + t.size.width / 2;
    final cy = t.position.dy + t.size.height / 2;
    final dx = local.dx - cx;
    final dy = local.dy - cy;
    final c = math.cos(-t.rotation);
    final s = math.sin(-t.rotation);
    final lx = dx * c - dy * s + t.size.width / 2;
    final ly = dx * s + dy * c + t.size.height / 2;
    return lx >= 0 && ly >= 0 && lx <= t.size.width && ly <= t.size.height;
  }

  PaintKind _kindFor(PaintToolType tool) {
    switch (tool) {
      case PaintToolType.freestyle:
        return PaintKind.freestyle;
      case PaintToolType.line:
        return PaintKind.line;
      case PaintToolType.arrow:
        return PaintKind.arrow;
      case PaintToolType.rectangle:
        return PaintKind.rectangle;
      case PaintToolType.circle:
        return PaintKind.circle;
      case PaintToolType.dashLine:
        return PaintKind.dashLine;
      case PaintToolType.dashDotLine:
        return PaintKind.dashDotLine;
      case PaintToolType.hexagon:
        return PaintKind.hexagon;
      case PaintToolType.polygon:
        return PaintKind.polygon;
      case PaintToolType.blur:
        return PaintKind.blur;
      case PaintToolType.eraser:
        // Eraser handled separately; never reaches the draft pipeline.
        return PaintKind.freestyle;
    }
  }
}

/// Preview wrapper. Selects between a [CustomPaint] (for vector kinds)
/// and a real [BackdropFilter] (for blur) so the in-flight preview
/// always matches what the committed layer will look like.
class _DraftPreview extends StatelessWidget {
  const _DraftPreview({required this.draft});

  final PaintDraft draft;

  @override
  Widget build(BuildContext context) {
    if (draft.kind == PaintKind.blur) {
      final bounds = draft.previewBounds();
      if (bounds == null) return const SizedBox.expand();
      return Stack(
        children: [
          Positioned(
            left: bounds.left,
            top: bounds.top,
            width: bounds.width,
            height: bounds.height,
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: draft.blurSigma,
                  sigmaY: draft.blurSigma,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      );
    }
    return CustomPaint(
      size: Size.infinite,
      painter: _DraftPainter(draft),
      isComplex: true,
      willChange: true,
    );
  }
}

/// Painter for the in-flight draft. Reuses [PaintLayerPainter]'s
/// rendering so the preview pixels match the committed layer 1:1.
class _DraftPainter extends CustomPainter {
  _DraftPainter(this.draft);

  final PaintDraft draft;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = draft.previewBounds();
    if (bounds == null) return;
    canvas.save();
    canvas.translate(bounds.left, bounds.top);
    final inner = PaintLayerPainter(
      kind: draft.kind,
      normalizedPoints: draft.normalizedFor(bounds),
      strokeColor: draft.strokeColor,
      strokeWidth: draft.strokeWidth,
      sides: draft.kind == PaintKind.hexagon ? 6 : draft.sides,
      fillColor: _previewSupportsFill(draft.kind) ? draft.fillColor : null,
    );
    inner.paint(canvas, bounds.size);
    canvas.restore();
  }

  static bool _previewSupportsFill(PaintKind kind) =>
      kind == PaintKind.rectangle ||
      kind == PaintKind.circle ||
      kind == PaintKind.hexagon ||
      kind == PaintKind.polygon;

  @override
  bool shouldRepaint(covariant _DraftPainter old) => true;
}
