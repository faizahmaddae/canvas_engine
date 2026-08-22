import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/constants/engine_constants.dart';
import '../../../../core/utils/editor_value_format.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../application/document_controller.dart';
import '../../engine/modules/image/image_layer.dart';
import '../../engine/modules/image/image_source_provider.dart';
import '../../presentation/widgets/handle_drag_detector.dart';
import '../../presentation/widgets/selection_overlay.dart' show DragPhase;
import '../application/crop_controller.dart';
import '../../../../app/theme/app_icons.dart';

/// Crop Mode session surface. Mounted above the editor canvas
/// whenever [CropSession.active] is true. Owns the scrim, the source
/// preview, the crop frame + handles, and the bottom control card.
///
/// **Why this does not use `EditorToolPanelShell`:** Crop is a
/// draft session (interaction contract §1 class D), not a bottom-dock
/// sub-tool. It needs its own Done/Cancel that genuinely commit or
/// abort a draft, and — unlike mask-edit, which can leave the live
/// canvas underneath — it must show pixels *outside* the layer's box,
/// which the canvas clips. So it takes over the screen while keeping
/// the mask-edit chrome grammar: token surfaces, an accent-outlined
/// region over a scrim, and a floating control card carrying
/// Cancel / Done.
///
/// UX contract:
///   * The preview is the **whole source bitmap** with the layer's
///     current window drawn on it, at the layer's Look. Nothing a
///     previous crop hid is out of reach — see
///     [CropSession.draftBounds].
///   * Aspect chips and drags only mutate the draft. The document is
///     untouched until **Done**, and **Cancel** is a true no-op.
class CropModeOverlay extends ConsumerWidget {
  const CropModeOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(cropControllerProvider);
    if (!session.active || session.layerId == null) {
      return const SizedBox.shrink();
    }
    final layer = ref.watch(
      documentControllerProvider.select((d) => d.layerById(session.layerId!)),
    );
    if (layer is! ImageLayer) {
      // Layer was deleted while crop was open — close cleanly.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(cropControllerProvider.notifier).cancelCrop();
      });
      return const SizedBox.shrink();
    }
    final tokens = AppTokens.of(context);
    return Material(
      color: tokens.workspace,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _SourceAspectProbe(layer: layer),
            const _CropTopBar(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => _CropCanvas(
                  layer: layer,
                  available: Size(constraints.maxWidth, constraints.maxHeight),
                ),
              ),
            ),
            _CropBottomBar(layer: layer),
          ],
        ),
      ),
    );
  }
}

/// Zero-size widget that resolves the layer's image source once and
/// reports the bitmap's natural aspect into the crop session
/// ([CropController.setSourceAspect]). Both the non-destructive frame
/// bounds and the source-window commit need that ratio; until it
/// resolves the session stays in display space and commit falls back
/// to the legacy reshape.
class _SourceAspectProbe extends ConsumerStatefulWidget {
  const _SourceAspectProbe({required this.layer});
  final ImageLayer layer;

  @override
  ConsumerState<_SourceAspectProbe> createState() => _SourceAspectProbeState();
}

class _SourceAspectProbeState extends ConsumerState<_SourceAspectProbe> {
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_SourceAspectProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layer.source != widget.layer.source) _resolve();
  }

  void _resolve() {
    _detach();
    final provider = _sourceProvider(widget.layer.source);
    if (provider == null) return;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        final aspect = info.image.height > 0
            ? info.image.width / info.image.height
            : null;
        final pixels = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        info.dispose();
        if (aspect == null || !mounted) return;
        // DEFERRED, and that is the whole point.
        //
        // `addListener` delivers synchronously when the bitmap is
        // already in the image cache — i.e. on every crop open after
        // the first — and that lands this callback inside `build()`.
        // Writing a Riverpod provider there throws "Tried to modify a
        // provider while the widget tree was building"; the exception
        // surfaced through the image stream, `_SourcePreview`'s
        // errorBuilder caught it, and crop rendered
        // «تصویر در دسترس نیست». So the photo appeared the first time
        // and never again, and the user cropped blind from the second
        // attempt onward. Deferring makes the cached and uncached paths
        // behave identically.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref
              .read(cropControllerProvider.notifier)
              .setSourceAspect(aspect, pixelSize: pixels);
        });
      },
      // Unresolvable source (missing file, dead URL): stay silent —
      // commit simply keeps the legacy fallback path.
      onError: (Object _, StackTrace? _) {},
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _detach() {
    final s = _stream;
    final l = _listener;
    if (s != null && l != null) s.removeListener(l);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Resolve an [ImageSource] to a provider, or `null` when the bytes
/// are unreachable. Shared by the aspect probe and the preview so the
/// two never disagree about whether an image exists.
ImageProvider? _sourceProvider(ImageSource src) => imageProviderFor(src);

// =============================================================
// Top bar — Cancel / title / Done
// =============================================================

class _CropTopBar extends ConsumerWidget {
  const _CropTopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(cropControllerProvider.notifier);
    final tokens = AppTokens.of(context);
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            TextButton(
              key: const ValueKey('crop-top-cancel'),
              onPressed: () {
                EditorHaptics.tap();
                ctrl.cancelCrop();
              },
              style: TextButton.styleFrom(
                foregroundColor: tokens.accentText,
                minimumSize: const Size(64, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              // Weight and size ride on the CHILD, not on
              // ButtonStyle.textStyle: a bare TextStyle there REPLACES
              // the theme's button style, taking the locale-aware
              // family with it — Persian labels fell back to a face
              // with no Persian coverage. A Text style merges.
              child: Text(
                context.l10n.cancelAction,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Spacer(),
            Text(
              context.l10n.cropImageAction,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const Spacer(),
            FilledButton(
              key: const ValueKey('crop-top-done'),
              onPressed: () {
                EditorHaptics.confirm();
                ctrl.commitCrop();
              },
              style: FilledButton.styleFrom(
                backgroundColor: tokens.brand,
                foregroundColor: tokens.onBrand,
                // Painted pill stays 38dp; the tap target grows to
                // the 44dp floor via Material's padded density
                // (kMinHitTarget a11y pass — the 56dp bar has room,
                // so no layout shift).
                minimumSize: const Size(76, 38),
                tapTargetSize: MaterialTapTargetSize.padded,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(19),
                ),
              ),
              child: Text(
                context.l10n.doneAction,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// Canvas — source preview + draggable crop frame
// =============================================================

class _CropCanvas extends ConsumerWidget {
  const _CropCanvas({required this.layer, required this.available});
  final ImageLayer layer;
  final Size available;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(cropControllerProvider);
    // Asymmetric padding: extra bottom clearance so the crop frame
    // never visually crowds the control card below it.
    //
    // The SIDE inset also has to clear Android's back-gesture strip.
    // At a flat 28dp the left/right handles of a full-width photo —
    // the state crop opens in — landed inside that strip, so the first
    // drag a user tries was swallowed by the system as a back gesture:
    // crop closed, the crop was discarded, and nothing said why.
    // `systemGestureInsets` is the platform's own answer for how wide
    // that strip is, so honour it and keep 28 as the visual floor.
    // `systemGestureInsets` reports where the system MAY claim a
    // gesture; sitting a draggable handle exactly on that line still
    // loses races, so clear it by a finger's worth rather than
    // touching it.
    final gestureInsets = MediaQuery.systemGestureInsetsOf(context);
    final paddingSide = math.max(
      28.0,
      math.max(gestureInsets.left, gestureInsets.right) + 16.0,
    );
    const paddingBottom = 48.0;
    final paneW = (available.width - paddingSide * 2).clamp(
      0.0,
      double.infinity,
    );
    final paneH = (available.height - paddingSide - paddingBottom).clamp(
      0.0,
      double.infinity,
    );
    final layerW = layer.transform.size.width.abs();
    final layerH = layer.transform.size.height.abs();
    if (paneW <= 0 || paneH <= 0 || layerW <= 0 || layerH <= 0) {
      return const SizedBox.shrink();
    }
    // Preview aspect: the WHOLE source once its ratio is known, so a
    // re-opened crop shows every pixel the frame can still reach —
    // and shows it undistorted, which a fill-fitted (already cropped)
    // layer previewed at its own box aspect never was. Before the
    // ratio resolves we mirror the layer box + its fit, which is the
    // basis commit falls back to.
    final previewAspect = session.sourceAspect ?? (layerW / layerH);
    double imgW = paneW;
    double imgH = imgW / previewAspect;
    if (imgH > paneH) {
      imgH = paneH;
      imgW = imgH * previewAspect;
    }
    // Center image within the asymmetric pane (shifted slightly upward).
    final offsetY = paddingSide + (paneH - imgH) / 2;
    final imageRect = Rect.fromLTWH(
      (available.width - imgW) / 2,
      offsetY,
      imgW,
      imgH,
    );
    return Stack(
      children: [
        Positioned.fromRect(
          rect: imageRect,
          child: IgnorePointer(
            child: _SourcePreview(
              layer: layer,
              // `contain` inside an exactly source-shaped box is a
              // no-op scale; it only guards against rounding when the
              // aspect is still the layer's fallback.
              fit: session.sourceAspect == null ? layer.fit : BoxFit.contain,
            ),
          ),
        ),
        Positioned.fill(
          child: _CropFrameLayer(layer: layer, imageRect: imageRect),
        ),
      ],
    );
  }
}

/// Colour-matrix **Look** the layer renders with: its filter preset
/// composed with the effect stack's adjustments, in the same order
/// [ImageLayer.buildContent] applies them. Custom-paint effects
/// (vignette) are deliberately excluded — they anchor to the layer
/// box, so painting them over a preview of the whole source would put
/// the falloff somewhere the user never sees it.
List<double>? lookMatrixOf(ImageLayer layer) {
  final filter = imageFilterMatrix(layer.filterPreset);
  final adjustments = layer.effects.composedColorMatrix;
  if (filter == null) return adjustments;
  if (adjustments == null) return filter;
  return composeColorMatrices(adjustments, filter);
}

/// Renders the layer's image source at [fit], ignoring `cropRect`,
/// mask, border, and shadow — crop mode is about choosing pixels, not
/// styling the silhouette — but **keeping the Look**, so what the
/// user frames is what they get.
class _SourcePreview extends StatelessWidget {
  const _SourcePreview({required this.layer, required this.fit});
  final ImageLayer layer;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final provider = _sourceProvider(layer.source);
    if (provider == null) {
      return _CropUnavailableImage(label: context.l10n.imageUnavailableLabel);
    }
    final Widget pixels = Image(
      image: provider,
      fit: fit,
      errorBuilder: (_, _, _) =>
          _CropUnavailableImage(label: context.l10n.imageUnavailableLabel),
    );
    final matrix = lookMatrixOf(layer);
    if (matrix == null) return pixels;
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(matrix),
      child: pixels,
    );
  }
}

class _CropUnavailableImage extends StatelessWidget {
  const _CropUnavailableImage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfaceMuted,
          border: Border.all(color: tokens.border),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================
// Crop frame — scrim, handles, gestures
// =============================================================

class _CropFrameLayer extends ConsumerStatefulWidget {
  const _CropFrameLayer({required this.layer, required this.imageRect});
  final ImageLayer layer;
  final Rect imageRect;

  @override
  ConsumerState<_CropFrameLayer> createState() => _CropFrameLayerState();
}

enum _Handle { tl, tr, bl, br, t, r, b, l, body }

class _CropFrameLayerState extends ConsumerState<_CropFrameLayer>
    with SingleTickerProviderStateMixin {
  Rect? _dragStartDraft;
  Offset? _dragStartGlobal;

  /// 0 = resting, 1 = a handle is under the finger.
  ///
  /// Drives everything that should only exist *while framing*: the
  /// thirds guides, the deeper scrim, and the pixel readout. A crop
  /// frame that permanently draws its own grid competes with the
  /// photograph the user is trying to judge; one that never draws it
  /// gives no composition help at the moment it is wanted. Tying both
  /// to the drag is the resolution every pro crop tool converged on.
  late final AnimationController _focus = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 260),
  );

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Screen pixels one draft unit spans on each axis.
  ///
  /// The preview covers the whole source while the draft is
  /// normalised over the displayed window, so a draft unit is only
  /// part of the pane — [CropSession.displayBasis] is the conversion.
  /// When the two spaces coincide this is exactly the image rect.
  Size _draftUnit(Rect basis) => Size(
    widget.imageRect.width * basis.width,
    widget.imageRect.height * basis.height,
  );

  /// Top-left of the draft's origin in screen space.
  Offset _draftOrigin(Rect basis) => Offset(
    widget.imageRect.left + basis.left * widget.imageRect.width,
    widget.imageRect.top + basis.top * widget.imageRect.height,
  );

  Rect _draftToScreen(Rect d, Rect basis) {
    final o = _draftOrigin(basis);
    final u = _draftUnit(basis);
    return Rect.fromLTRB(
      o.dx + d.left * u.width,
      o.dy + d.top * u.height,
      o.dx + d.right * u.width,
      o.dy + d.bottom * u.height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(cropControllerProvider);
    final frame = _draftToScreen(session.draftCrop, session.displayBasis);
    // Corners keep the shared 48dp handle target; edges stay
    // elongated so the two are distinguishable by touch. What changed
    // is that the affordances are now PAINTED (see
    // [_CropFramePainter]) instead of being widget children of these
    // detectors — that is what lets a corner bracket sit flush on the
    // frame line, thick enough to read over any photo, while the
    // finger target around it stays 48dp and centred.
    const handleHit = EngineConstants.handleTouchSize;
    const edgeHitMain = 56.0;
    const edgeHitCross = 28.0;

    return AnimatedBuilder(
      animation: _focus,
      builder: (context, _) {
        final focus = Curves.easeOut.transform(_focus.value);
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _CropFramePainter(frame: frame, focus: focus),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: frame,
              child: HandleDragDetector(
                onDrag: (gp, phase) => _onHandle(_Handle.body, gp, phase),
              ),
            ),
            // ── Edge handles (T / B / L / R) ──────────────────────
            // Centered on the midpoint of each edge. Single-axis drag
            // keeps free crops natural and, when an aspect is locked,
            // resizes the perpendicular axis symmetrically around the
            // opposite edge — matching iOS Photos / Instagram.
            Positioned(
              left: frame.center.dx - edgeHitMain / 2,
              top: frame.top - edgeHitCross / 2,
              width: edgeHitMain,
              height: edgeHitCross,
              child: HandleDragDetector(
                onDrag: (gp, phase) => _onHandle(_Handle.t, gp, phase),
              ),
            ),
            Positioned(
              left: frame.center.dx - edgeHitMain / 2,
              top: frame.bottom - edgeHitCross / 2,
              width: edgeHitMain,
              height: edgeHitCross,
              child: HandleDragDetector(
                onDrag: (gp, phase) => _onHandle(_Handle.b, gp, phase),
              ),
            ),
            Positioned(
              left: frame.left - edgeHitCross / 2,
              top: frame.center.dy - edgeHitMain / 2,
              width: edgeHitCross,
              height: edgeHitMain,
              child: HandleDragDetector(
                onDrag: (gp, phase) => _onHandle(_Handle.l, gp, phase),
              ),
            ),
            Positioned(
              left: frame.right - edgeHitCross / 2,
              top: frame.center.dy - edgeHitMain / 2,
              width: edgeHitCross,
              height: edgeHitMain,
              child: HandleDragDetector(
                onDrag: (gp, phase) => _onHandle(_Handle.r, gp, phase),
              ),
            ),
            for (final entry in <MapEntry<_Handle, Offset>>[
              MapEntry(_Handle.tl, frame.topLeft),
              MapEntry(_Handle.tr, frame.topRight),
              MapEntry(_Handle.bl, frame.bottomLeft),
              MapEntry(_Handle.br, frame.bottomRight),
            ])
              Positioned(
                left: entry.value.dx - handleHit / 2,
                top: entry.value.dy - handleHit / 2,
                width: handleHit,
                height: handleHit,
                child: HandleDragDetector(
                  onDrag: (gp, phase) => _onHandle(entry.key, gp, phase),
                ),
              ),
            if (focus > 0.01) _readout(context, session, frame, focus),
          ],
        );
      },
    );
  }

  /// Pixel readout that rides the frame while it is being dragged.
  ///
  /// The one fact a crop screen can state without inventing anything:
  /// how many real source pixels the current frame keeps. It sits
  /// above the frame, flipping inside when the frame is near the top
  /// edge, so it never leaves the pane.
  Widget _readout(
    BuildContext context,
    CropSession session,
    Rect frame,
    double focus,
  ) {
    final px = session.draftPixelSize;
    if (px == null) return const SizedBox.shrink();
    final values = EditorValueFormat.of(context);
    final w = values.digits(px.width.round());
    final h = values.digits(px.height.round());
    const bandWidth = 200.0;
    const above = 42.0;
    final top = frame.top > above + 8 ? frame.top - above : frame.top + 12;
    return Positioned(
      left: frame.center.dx - bandWidth / 2,
      top: top,
      width: bandWidth,
      child: IgnorePointer(
        child: Opacity(
          opacity: focus,
          child: Center(
            child: Semantics(
              key: const ValueKey('crop-live-readout'),
              label: context.l10n.cropOutputSizeLabel(w, h),
              child: ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    // Deliberately NOT a token surface: this chip
                    // floats over the photograph, so it has to carry
                    // its own contrast in both themes rather than
                    // borrow the app's.
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '$w × $h',
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onHandle(_Handle h, Offset globalPos, DragPhase phase) {
    final ctrl = ref.read(cropControllerProvider.notifier);
    final session = ref.read(cropControllerProvider);
    switch (phase) {
      case DragPhase.start:
        _dragStartDraft = session.draftCrop;
        _dragStartGlobal = globalPos;
        _focus.forward();
        EditorHaptics.tap();
        return;
      case DragPhase.update:
        final start = _dragStartDraft;
        final origin = _dragStartGlobal;
        if (start == null || origin == null) return;
        final unit = _draftUnit(session.displayBasis);
        if (unit.width <= 0 || unit.height <= 0) return;
        final dxNorm = (globalPos.dx - origin.dx) / unit.width;
        final dyNorm = (globalPos.dy - origin.dy) / unit.height;
        // The frame roams the whole source, not just the window the
        // layer displays — that is what keeps crop non-destructive.
        final bounds = session.draftBounds;
        Rect next;
        if (h == _Handle.body) {
          next = CropController.translate(
            start,
            dxNorm,
            dyNorm,
            bounds: bounds,
          );
        } else {
          // Aspect is stored in image-pixel space; convert to
          // normalised-space aspect so the handle drag stays
          // visually locked on a non-square layer.
          final aspectImage = session.aspectRatio;
          // Same denominator the preset chips use — the draft unit
          // box, not the layer box. See CropSession.draftUnitAspect.
          final layerAspect = session.draftUnitAspect;
          final aspectNorm = (aspectImage == null || layerAspect <= 0)
              ? null
              : aspectImage / layerAspect;
          next = CropController.resize(
            start,
            handle: _toPublicHandle(h),
            dx: dxNorm,
            dy: dyNorm,
            aspect: aspectNorm,
            bounds: bounds,
          );
        }
        ctrl.updateDraft(next);
        return;
      case DragPhase.end:
        _dragStartDraft = null;
        _dragStartGlobal = null;
        _focus.reverse();
        return;
    }
  }

  static CropHandle _toPublicHandle(_Handle h) => switch (h) {
    _Handle.tl => CropHandle.tl,
    _Handle.tr => CropHandle.tr,
    _Handle.bl => CropHandle.bl,
    _Handle.br => CropHandle.br,
    _Handle.t => CropHandle.t,
    _Handle.b => CropHandle.b,
    _Handle.l => CropHandle.l,
    _Handle.r => CropHandle.r,
    // body has no public handle counterpart; callers must
    // route body drags to CropController.translate directly.
    _Handle.body => CropHandle.tl,
  };
}

/// Scrim + frame + affordances, in one pass.
///
/// **Why white and black instead of tokens.** Every other surface in
/// the app paints on a themed ground, so it reads tokens. This one
/// paints on *the user's photograph* — an unknown ground that changes
/// per pixel. The saffron accent that carries the app's identity on
/// cream and ink disappears over a saffron-ish sunset, and the 1.5dp
/// accent hairline this replaces was doing exactly that. A white mark
/// with a black under-shadow is the photographic convention because
/// it is the one pair that survives any image.
///
/// **Corner brackets, not dots.** The old 14dp dot said "generic
/// selection"; a bracket that traces the corner says "this is the
/// frame of the picture". The bracket is also self-documenting about
/// which way the corner moves.
class _CropFramePainter extends CustomPainter {
  _CropFramePainter({required this.frame, required this.focus});

  final Rect frame;

  /// 0 while resting, 1 while a handle is held. Deepens the scrim and
  /// fades the thirds guides in.
  final double focus;

  static const double _bracketArm = 24.0;
  static const double _bracketWeight = 3.0;
  static const double _edgeBarLength = 28.0;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()
      ..color = Colors.black.withValues(
        // Resting scrim stays readable — the pixels you are about to
        // discard are still part of the decision. It deepens while
        // framing so the keep-area separates at the moment of choice.
        alpha: 0.42 + 0.20 * focus,
      );
    final outer = Path()..addRect(Offset.zero & size);
    final inner = Path()..addRect(frame);
    canvas.drawPath(Path.combine(PathOperation.difference, outer, inner), dim);

    // Thirds guides: absent at rest, present while framing.
    if (focus > 0.01) {
      final guide = Paint()
        ..color = Colors.white.withValues(alpha: 0.55 * focus)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      for (var i = 1; i < 3; i++) {
        final dx = frame.left + frame.width * i / 3;
        final dy = frame.top + frame.height * i / 3;
        canvas.drawLine(Offset(dx, frame.top), Offset(dx, frame.bottom), guide);
        canvas.drawLine(Offset(frame.left, dy), Offset(frame.right, dy), guide);
      }
    }

    // Frame line: a soft dark under-stroke so the white one holds on
    // a blown-out sky as well as on a dark ground.
    canvas.drawRect(
      frame,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawRect(
      frame,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Affordances sit just inside the line so their outer edge is
    // flush with it; the arm shortens on a tiny frame so two brackets
    // never meet in the middle of an edge.
    final arm = math.min(_bracketArm, frame.shortestSide / 3);
    final inset = frame.deflate(_bracketWeight / 2);
    final marks = Path();
    // Corners: L-brackets.
    marks
      ..moveTo(inset.left, inset.top + arm)
      ..lineTo(inset.left, inset.top)
      ..lineTo(inset.left + arm, inset.top)
      ..moveTo(inset.right - arm, inset.top)
      ..lineTo(inset.right, inset.top)
      ..lineTo(inset.right, inset.top + arm)
      ..moveTo(inset.left, inset.bottom - arm)
      ..lineTo(inset.left, inset.bottom)
      ..lineTo(inset.left + arm, inset.bottom)
      ..moveTo(inset.right - arm, inset.bottom)
      ..lineTo(inset.right, inset.bottom)
      ..lineTo(inset.right, inset.bottom - arm);
    // Edge midpoints: short bars, only while they can't collide with
    // the corner brackets.
    final barX = math.min(_edgeBarLength, frame.width - arm * 2 - 8);
    final barY = math.min(_edgeBarLength, frame.height - arm * 2 - 8);
    if (barX > 8) {
      marks
        ..moveTo(frame.center.dx - barX / 2, inset.top)
        ..lineTo(frame.center.dx + barX / 2, inset.top)
        ..moveTo(frame.center.dx - barX / 2, inset.bottom)
        ..lineTo(frame.center.dx + barX / 2, inset.bottom);
    }
    if (barY > 8) {
      marks
        ..moveTo(inset.left, frame.center.dy - barY / 2)
        ..lineTo(inset.left, frame.center.dy + barY / 2)
        ..moveTo(inset.right, frame.center.dy - barY / 2)
        ..lineTo(inset.right, frame.center.dy + barY / 2);
    }
    canvas.drawPath(
      marks,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _bracketWeight + 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      marks,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = _bracketWeight
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CropFramePainter old) =>
      old.frame != frame || old.focus != focus;
}

// =============================================================
// Bottom card — aspect chips + Reset
// =============================================================

class _CropBottomBar extends ConsumerStatefulWidget {
  const _CropBottomBar({required this.layer});
  final ImageLayer layer;

  @override
  ConsumerState<_CropBottomBar> createState() => _CropBottomBarState();
}

class _CropBottomBarState extends ConsumerState<_CropBottomBar> {
  /// Which way the ratio presets are pointing. `null` until the first
  /// build picks the source's own orientation as the starting point —
  /// a portrait photo should open offering portrait ratios.
  ///
  /// Presentation-only on purpose: it changes which ratio the next tap
  /// applies and how the chips are labelled, never the document, so it
  /// has no business in [CropSession] (or in serialization).
  bool? _portrait;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(cropControllerProvider);
    final ctrl = ref.read(cropControllerProvider.notifier);
    final tokens = AppTokens.of(context);
    final layer = widget.layer;
    final layerH = layer.transform.size.height;
    final layerAspect = layerH == 0 ? 1.0 : layer.transform.size.width / layerH;
    final sourceAspect = session.sourceAspect ?? layerAspect;
    final portrait = _portrait ?? (sourceAspect < 1);
    // Ratio labels are numbers, so they follow the same digit rule as
    // every other value in the editor: Persian digits under fa. They
    // were the last ASCII numerals left in the Persian UI, sitting one
    // row away from «عمودی ۴:۵» in the size picker.
    final values = EditorValueFormat.of(context);
    // Ratios are declared once, landscape-major, and the orientation
    // switch transposes BOTH the applied ratio and the printed label.
    // The old strip listed 4:5 and 5:4, 16:9 and 9:16 as unrelated
    // chips — seven items that overflowed the row and still could not
    // express a portrait "Original". One axis of meaning (which
    // shape) and one switch (which way up) covers strictly more
    // ground in fewer targets, and the labels rewriting themselves on
    // the tap is what teaches the switch.
    final ratios = <({int a, int b})>[
      (a: 1, b: 1),
      (a: 5, b: 4),
      (a: 3, b: 2),
      (a: 16, b: 9),
    ];
    String ratioLabel(int a, int b) =>
        values.mapDigits(portrait ? '$b:$a' : '$a:$b');
    final presets = <_AspectChip>[
      _AspectChip(label: context.l10n.freeOption, aspect: null, free: true),
      _AspectChip(
        label: context.l10n.originalOption,
        // "Original" means the picture's own shape; standing it the
        // other way up is a legitimate crop, so it transposes too.
        aspect: portrait == (layerAspect < 1) ? layerAspect : 1 / layerAspect,
      ),
      for (final r in ratios)
        _AspectChip(
          label: ratioLabel(r.a, r.b),
          aspect: portrait ? r.b / r.a : r.a / r.b,
        ),
    ];
    // Floating control card, mask-edit grammar: a rounded [surface]
    // slab inset from the edges rather than a full-bleed bar, so the
    // session reads as chrome over the work instead of a new screen.
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          color: tokens.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Row 1: orientation switch + ratio strip ──────
                // Height scales with the text. At a flat 38dp the chip
                // stayed 38dp while the glyphs grew, so at 1.3x the
                // final ی of «اصلی» was sheared to a stub — Persian
                // descenders are the first thing a fixed row height
                // eats. Also lifts the chip off its 38dp floor toward
                // the 44dp target.
                SizedBox(
                  height: MediaQuery.textScalerOf(context).scale(50),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      _OrientationSwitch(
                        portrait: portrait,
                        onTap: () {
                          EditorHaptics.tap();
                          final next = !portrait;
                          setState(() => _portrait = next);
                          // A locked ratio follows the switch
                          // immediately — otherwise the labels would
                          // say one thing and the frame another.
                          final current = session.aspectRatio;
                          if (current != null && current > 0) {
                            ctrl.setAspectRatio(1 / current);
                          }
                        },
                      ),
                      const SizedBox(width: 10),
                      Container(width: 1, height: 22, color: tokens.border),
                      Expanded(
                        child: ShaderMask(
                          // The strip scrolls, and at rest the last
                          // chip was cut mid-glyph against a hard
                          // edge — which reads as a rendering fault,
                          // not as "there is more". A fade says
                          // "keep going" in the language every
                          // scrolling rail in the app already uses.
                          shaderCallback: (rect) => const LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Color(0x00000000),
                              Color(0xFF000000),
                              Color(0xFF000000),
                              Color(0x00000000),
                            ],
                            stops: [0.0, 0.05, 0.94, 1.0],
                          ).createShader(rect),
                          blendMode: BlendMode.dstIn,
                          child: ListView.separated(
                            key: const ValueKey('crop-aspect-strip'),
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: presets.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              final p = presets[i];
                              final selected = _aspectMatches(
                                session.aspectRatio,
                                p.aspect,
                              );
                              return _ChipButton(
                                label: p.label,
                                aspect: p.aspect,
                                free: p.free,
                                selected: selected,
                                onTap: () {
                                  EditorHaptics.tap();
                                  ctrl.setAspectRatio(p.aspect);
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // ── Row 2: restore + what the crop will produce ──
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8, end: 16),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          EditorHaptics.tap();
                          ctrl.resetCrop();
                        },
                        icon: const Icon(AppIcons.reset, size: 16),
                        label: Text(
                          context.l10n.restoreImageAction,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: tokens.textSecondary,
                          minimumSize: const Size(44, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const Spacer(),
                      // The resting home of the drag readout: the
                      // frame answers "which pixels", this answers
                      // "how many". Absent — never «۰ × ۰» — until
                      // the bitmap resolves (contract §10.3).
                      _SizeReadout(size: session.draftPixelSize),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static bool _aspectMatches(double? a, double? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return (a - b).abs() < 0.005;
  }
}

class _AspectChip {
  const _AspectChip({
    required this.label,
    required this.aspect,
    this.free = false,
  });
  final String label;
  final double? aspect;

  /// The unconstrained preset. Same `aspect: null` as "no ratio",
  /// but it draws a different specimen, so it is flagged rather than
  /// inferred.
  final bool free;
}

/// Orientation switch that stands the ratio presets on end.
///
/// Deliberately a *state* control, not a toggle-with-two-labels: the
/// glyph IS the current orientation, and the chip labels next to it
/// rewrite themselves when it changes, so the effect is legible
/// before and after the tap.
class _OrientationSwitch extends StatelessWidget {
  const _OrientationSwitch({required this.portrait, required this.onTap});
  final bool portrait;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      label: context.l10n.cropOrientationAction,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          key: const ValueKey('crop-orientation-toggle'),
          color: tokens.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tokens.borderStrong, width: 1),
              ),
              child: AnimatedRotation(
                // The glyph is drawn portrait; a quarter turn is the
                // sanctioned way to land the landscape reading (see
                // AppIcons.aspectPortrait), and animating the turn is
                // what makes the switch's meaning obvious.
                turns: portrait ? 0 : 0.25,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: Icon(
                  AppIcons.aspectPortrait,
                  size: 20,
                  color: tokens.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "How many pixels this crop keeps", in the card's status line.
class _SizeReadout extends StatelessWidget {
  const _SizeReadout({required this.size});
  final Size? size;

  @override
  Widget build(BuildContext context) {
    final px = size;
    if (px == null) return const SizedBox.shrink();
    final tokens = AppTokens.of(context);
    final values = EditorValueFormat.of(context);
    final w = values.digits(px.width.round());
    final h = values.digits(px.height.round());
    return Semantics(
      key: const ValueKey('crop-size-readout'),
      label: context.l10n.cropOutputSizeLabel(w, h),
      child: ExcludeSemantics(
        child: Text(
          '$w × $h',
          // The pair is a dimension, not prose: it reads
          // width-then-height in every locale, so it is pinned LTR
          // the same way the editor's other value readouts are.
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// The specimen a ratio chip carries: an outline drawn at the ratio
/// the chip applies, so the row can be read by shape before it is
/// read by number — and so "Original" and "Free", which have no
/// number, still say something.
class _RatioSpecimen extends StatelessWidget {
  const _RatioSpecimen({
    required this.aspect,
    required this.free,
    required this.color,
  });
  final double? aspect;
  final bool free;
  final Color color;

  static const double _extent = 17.0;

  @override
  Widget build(BuildContext context) {
    final r = (aspect == null || !aspect!.isFinite || aspect! <= 0)
        ? 1.0
        : aspect!;
    final w = r >= 1 ? _extent : _extent * r;
    final h = r >= 1 ? _extent / r : _extent;
    return SizedBox(
      width: _extent,
      height: _extent,
      child: Center(
        // The SIZE has to come from a box, not from `CustomPaint.size`
        // — that field is only consulted when the constraints are
        // unbounded, so inside this fixed 17dp cell every specimen
        // painted as a square and the row said nothing.
        child: SizedBox(
          width: w,
          height: h,
          child: CustomPaint(
            painter: _RatioSpecimenPainter(color: color, dashed: free),
          ),
        ),
      ),
    );
  }
}

class _RatioSpecimenPainter extends CustomPainter {
  _RatioSpecimenPainter({required this.color, required this.dashed});
  final Color color;

  /// Free crop: a dashed edge, the universal "not fixed".
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height).deflate(0.7);
    if (!dashed) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );
      return;
    }
    const dash = 3.0;
    const gap = 2.5;
    void run(Offset from, Offset to) {
      final total = (to - from).distance;
      if (total <= 0) return;
      final step = (to - from) / total;
      var t = 0.0;
      while (t < total) {
        final end = math.min(t + dash, total);
        canvas.drawLine(from + step * t, from + step * end, paint);
        t = end + gap;
      }
    }

    run(rect.topLeft, rect.topRight);
    run(rect.topRight, rect.bottomRight);
    run(rect.bottomRight, rect.bottomLeft);
    run(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(covariant _RatioSpecimenPainter old) =>
      old.color != color || old.dashed != dashed;
}

class _ChipButton extends StatelessWidget {
  const _ChipButton({
    required this.label,
    required this.aspect,
    required this.free,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final double? aspect;
  final bool free;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // The crop session's only control row announced itself as seven
    // plain Views with no role and no selected state, so a screen
    // reader could neither tell they were buttons nor which ratio was
    // active (WCAG 4.1.2, Level A).
    //
    // Mirrors `PresetChip` exactly, including the two parts that are
    // easy to drop: `ExcludeSemantics` around the visual subtree, or
    // the inner `Text` concatenates onto this node and every chip
    // announces its label twice («اصلی اصلی»); and `onTap` here,
    // because excluding the subtree also excludes the InkWell's tap
    // action, leaving a button a screen reader cannot activate.
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? tokens.brand : tokens.surfaceMuted,
          borderRadius: BorderRadius.circular(19),
          child: InkWell(
            borderRadius: BorderRadius.circular(19),
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(19),
                border: Border.all(
                  // `borderStrong`: the unselected edge measured 1.26:1
                  // against the crop card — the same invisible hairline
                  // that was fixed in PresetChip but never reached here.
                  color: selected ? tokens.brand : tokens.borderStrong,
                  width: 1,
                ),
              ),
              padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 14, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RatioSpecimen(
                    aspect: aspect,
                    free: free,
                    color: selected ? tokens.onBrand : tokens.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? tokens.onBrand : tokens.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
