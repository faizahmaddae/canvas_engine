import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/constants/engine_constants.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../application/document_controller.dart';
import '../../application/mask_edit_controller.dart';
import '../../engine/core/layer_mask.dart';
import '../../engine/core/viewport_state.dart';
import '../../engine/interaction/layer_space_mapper.dart';
import '../../engine/modules/image/image_layer.dart';
import '../../ui/editor_slider_row.dart';
import 'handle_drag_detector.dart';
import 'selection_overlay.dart' show DragPhase;

/// On-canvas chrome for mask-edit mode
/// (docs/mask-edit-mode-design-2026-07.md §1, §5).
///
/// Screen-space: mounted OUTSIDE the viewport transform in
/// [EditorCanvas]'s chrome stack, mapping geometry with
/// [LayerSpaceMapper] so the region outline, scrim, and handles
/// follow the layer's rotation and the viewport's zoom without
/// scaling the chrome itself.
///
/// Draft-first: every drag mutates only the controller's draft;
/// [DragPhase.end] triggers the single per-gesture preview staging.
///
/// The scrim + outline sit inside an [AbsorbPointer], so the session
/// owns every pointer that the handles and body surface above it do
/// not claim (contract §5 row 1). Leaving is therefore always an
/// explicit act — Cancel, Done, or system back — and a modified draft
/// is confirmed first via [confirmAbandonMaskEdit].
class MaskEditOverlay extends ConsumerStatefulWidget {
  const MaskEditOverlay({super.key, required this.viewport});

  final ViewportState viewport;

  @override
  ConsumerState<MaskEditOverlay> createState() => _MaskEditOverlayState();
}

class _MaskEditOverlayState extends ConsumerState<MaskEditOverlay> {
  LayerMask? _dragStartDraft;
  Offset? _dragStartGlobal;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(maskEditControllerProvider);
    if (!session.active) return const SizedBox.shrink();
    final layer = ref.watch(
      documentControllerProvider.select(
        (doc) => doc.layerById(session.layerId),
      ),
    );
    final draft = session.draft;
    if (layer is! ImageLayer || draft == null) {
      // Layer vanished mid-frame; the controller's document listener
      // cancels next microtask — render nothing meanwhile.
      return const SizedBox.shrink();
    }

    final mapper = LayerSpaceMapper(
      transform: layer.transform,
      viewport: widget.viewport,
    );
    final bounds = MaskEditController.boundsOf(draft);
    final rotation = layer.transform.rotation;
    final scale = widget.viewport.scale;
    // The region on screen: an axis-aligned box of the scaled bounds
    // size, centred on the mapped bounds centre, rotated by the
    // layer's rotation (the viewport adds no rotation by design).
    final screenCenter = mapper.layerToScreen(bounds.center);
    final screenSize = bounds.size * scale;

    Offset handlePoint(MaskEditHandle h) => switch (h) {
      MaskEditHandle.topLeft => bounds.topLeft,
      MaskEditHandle.topRight => bounds.topRight,
      MaskEditHandle.bottomLeft => bounds.bottomLeft,
      MaskEditHandle.bottomRight => bounds.bottomRight,
      MaskEditHandle.left => bounds.centerLeft,
      MaskEditHandle.top => bounds.topCenter,
      MaskEditHandle.right => bounds.centerRight,
      MaskEditHandle.bottom => bounds.bottomCenter,
      MaskEditHandle.body => bounds.center,
    };

    return Positioned.fill(
      child: Stack(
        children: [
          // Scrim + region outline. ABSORBS hits.
          //
          // Contract §5 row 1: while a crop/mask session is open the
          // session overlay owns the pointer, wherever it lands. This
          // used to be IgnorePointer, so a tap on the pasteboard fell
          // through to the always-mounted canvas detector, read as an
          // empty-canvas tap, and cancelled the session — discarding a
          // tuned mask with zero commands, i.e. with no undo. Crop is
          // immune only because its overlay happens to be an opaque
          // full-screen Material. Absorbing here makes the two
          // sessions of the same class behave the same way: the only
          // ways out are Cancel, Done, and system back.
          Positioned.fill(
            child: AbsorbPointer(
              child: CustomPaint(
                painter: _MaskScrimPainter(
                  draft: draft,
                  mapper: mapper,
                  scale: scale,
                  rotation: rotation,
                  scrimColor: Colors.black.withValues(alpha: 0.45),
                  outlineColor: AppTokens.of(context).accent,
                ),
              ),
            ),
          ),
          // Body-move surface: a rotated box matching the region.
          Positioned(
            left: screenCenter.dx - screenSize.width / 2,
            top: screenCenter.dy - screenSize.height / 2,
            width: screenSize.width,
            height: screenSize.height,
            child: Transform.rotate(
              angle: rotation,
              child: HandleDragDetector(
                onDrag: (global, phase) =>
                    _onDrag(MaskEditHandle.body, global, phase, layer),
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
          ),
          for (final h in const [
            MaskEditHandle.topLeft,
            MaskEditHandle.topRight,
            MaskEditHandle.bottomLeft,
            MaskEditHandle.bottomRight,
            MaskEditHandle.left,
            MaskEditHandle.top,
            MaskEditHandle.right,
            MaskEditHandle.bottom,
          ])
            _positionedHandle(h, mapper.layerToScreen(handlePoint(h)), layer),
          _BottomStrip(layer: layer, draft: draft),
        ],
      ),
    );
  }

  Widget _positionedHandle(
    MaskEditHandle handle,
    Offset screen,
    ImageLayer layer,
  ) {
    const touch = EngineConstants.handleTouchSize;
    const visual = EngineConstants.handleVisualSize;
    return Positioned(
      left: screen.dx - touch / 2,
      top: screen.dy - touch / 2,
      width: touch,
      height: touch,
      child: HandleDragDetector(
        onDrag: (global, phase) => _onDrag(handle, global, phase, layer),
        child: Center(
          child: Container(
            width: visual,
            height: visual,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppTokens.of(context).accent, width: 2),
            ),
          ),
        ),
      ),
    );
  }

  void _onDrag(
    MaskEditHandle handle,
    Offset global,
    DragPhase phase,
    ImageLayer layer,
  ) {
    final ctl = ref.read(maskEditControllerProvider.notifier);
    final session = ref.read(maskEditControllerProvider);
    final mapper = LayerSpaceMapper(
      transform: layer.transform,
      viewport: widget.viewport,
    );
    switch (phase) {
      case DragPhase.start:
        _dragStartDraft = session.draft;
        _dragStartGlobal = global;
      case DragPhase.update:
      case DragPhase.end:
        final startDraft = _dragStartDraft;
        final startGlobal = _dragStartGlobal;
        if (startDraft == null || startGlobal == null) return;
        // Recompute from the gesture origin each frame (no
        // incremental drift — the crop convention). The global
        // delta converts to layer-local through the mapper so the
        // drag tracks correctly under rotation + zoom.
        final delta =
            mapper.screenToLayer(global) - mapper.screenToLayer(startGlobal);
        final size = layer.transform.size;
        final next = handle == MaskEditHandle.body
            ? MaskEditController.translate(startDraft, delta, size)
            : MaskEditController.resize(startDraft, handle, delta, size);
        if (phase == DragPhase.end) {
          ctl.endGesture(next);
          _dragStartDraft = null;
          _dragStartGlobal = null;
        } else {
          ctl.updateDraft(next);
        }
    }
  }
}

/// Chrome-only approximation of the render path's linear feather
/// ramp ([RectMask.sampleAlpha]/[EllipseMask.sampleAlpha]) — softens
/// the scrim edge live during drag so feather is visibly applied
/// without re-rasterizing the exact per-pixel ramp every frame (the
/// cost [MaskEditController.updateDraft] already avoids for gesture
/// drags). [featherLayerPx] is layer-local like [LayerMask.feather];
/// the committed render path ([StackMaskComposite], via
/// [StackMaskRasterCache]) stays the source of truth for the actual
/// falloff shape and is unaffected by this approximation.
@visibleForTesting
double featherBlurSigma(double featherLayerPx, double scale) =>
    (featherLayerPx * scale) / 3;

/// Dim everything outside the region; stroke the region edge. The
/// region path is built in screen space through the mapper so it
/// rotates with the layer.
class _MaskScrimPainter extends CustomPainter {
  const _MaskScrimPainter({
    required this.draft,
    required this.mapper,
    required this.scale,
    required this.rotation,
    required this.scrimColor,
    required this.outlineColor,
  });

  final LayerMask draft;
  final LayerSpaceMapper mapper;
  final double scale;
  final double rotation;
  final Color scrimColor;
  final Color outlineColor;

  Path _regionPath() {
    final bounds = MaskEditController.boundsOf(draft);
    final center = mapper.layerToScreen(bounds.center);
    final half = (bounds.size * scale) / 2;
    final local = Rect.fromCenter(
      center: Offset.zero,
      width: half.width * 2,
      height: half.height * 2,
    );
    final shape = Path();
    if (draft is EllipseMask) {
      shape.addOval(local);
    } else {
      shape.addRect(local);
    }
    final m = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..rotateZ(rotation);
    return shape.transform(m.storage);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final region = _regionPath();
    // Inverted masks flip which side the effect lands on — flip the
    // scrim with it so "dimmed = untouched by the adjustment" stays
    // true.
    final inverted = draft.inverted;
    final full = Path()..addRect(Offset.zero & size);
    final scrim = inverted
        ? region
        : (Path.combine(PathOperation.difference, full, region));
    final scrimPaint = Paint()..color = scrimColor;
    final sigma = featherBlurSigma(draft.feather, scale);
    if (sigma > 0) {
      scrimPaint.maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
    }
    canvas.drawPath(scrim, scrimPaint);
    canvas.drawPath(
      region,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = outlineColor,
    );
  }

  @override
  bool shouldRepaint(_MaskScrimPainter old) =>
      old.draft != draft ||
      old.scale != scale ||
      old.rotation != rotation ||
      old.mapper.transform != mapper.transform ||
      old.mapper.viewport != mapper.viewport;
}

/// Shape toggle, feather slider, invert switch, Cancel / Done.
class _BottomStrip extends ConsumerWidget {
  const _BottomStrip({required this.layer, required this.draft});

  final ImageLayer layer;
  final LayerMask draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(maskEditControllerProvider.notifier);
    final tokens = AppTokens.of(context);
    final featherMax = math.min(
      layer.transform.size.shortestSide / 2,
      LayerMask.maxFeatherPx,
    );
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: SafeArea(
        top: false,
        child: Material(
          color: tokens.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Wrap, not Row: on narrow phones (and long Persian
                // labels) the chips + invert control exceed one line.
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ChoiceChip(
                      label: Text(context.l10n.maskShapeRect),
                      visualDensity: VisualDensity.compact,
                      selected: draft is RectMask,
                      onSelected: (_) {
                        EditorHaptics.tap();
                        ctl.setShape(ellipse: false);
                      },
                    ),
                    ChoiceChip(
                      label: Text(context.l10n.maskShapeEllipse),
                      visualDensity: VisualDensity.compact,
                      selected: draft is EllipseMask,
                      onSelected: (_) {
                        EditorHaptics.tap();
                        ctl.setShape(ellipse: true);
                      },
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.l10n.maskInvertLabel,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Switch(
                          value: draft.inverted,
                          onChanged: (_) {
                            EditorHaptics.toggle();
                            ctl.toggleInvert();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                EditorSliderRow(
                  label: context.l10n.maskFeatherLabel,
                  labelWidth: 80,
                  showReadout: false,
                  value: draft.feather,
                  max: featherMax,
                  format: (v) => v.round().toString(),
                  onChanged: ctl.setFeather,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () async {
                        EditorHaptics.tap();
                        if (!await confirmAbandonMaskEdit(context, ref)) {
                          return;
                        }
                        ctl.cancel(restoreSelection: true);
                      },
                      // Glyph stop. `accent` is the FILL stop and
                      // measures 2.92:1 on this surface — same
                      // construct, same fix as the crop overlay's
                      // Cancel one directory over.
                      style: TextButton.styleFrom(
                        foregroundColor: tokens.accentText,
                      ),
                      child: Text(context.l10n.cancelAction),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        EditorHaptics.tap();
                        ctl.commit();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: tokens.brand,
                        foregroundColor: tokens.onBrand,
                      ),
                      child: Text(context.l10n.doneAction),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Gate every path that would abandon a mask session.
///
/// Returns true when the caller may proceed to `cancel()`. A clean
/// session (draft still equals what the layer had at open) leaves
/// silently — there is nothing to lose and a dialog would be noise.
/// A modified one asks first, because `cancel()` restores the entry
/// mask with ZERO commands: once it runs, undo cannot bring the work
/// back. Shared by the overlay's Cancel button and the editor's
/// system-back handler so the two exits cannot diverge.
Future<bool> confirmAbandonMaskEdit(BuildContext context, WidgetRef ref) async {
  if (!ref.read(maskEditControllerProvider).isDirty) return true;
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.discardMaskChangesTitle),
      content: Text(l10n.discardMaskChangesBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.keepEditingAction),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            foregroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.discardAction),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
