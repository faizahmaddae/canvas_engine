import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
import '../../../../core/utils/haptics.dart';
import '../../application/document_controller.dart';
import '../../engine/modules/image/image_layer.dart';
import '../../presentation/widgets/handle_drag_detector.dart';
import '../../presentation/widgets/selection_overlay.dart' show DragPhase;
import '../application/crop_controller.dart';

/// Full-screen Crop Mode overlay. Mounted above the editor canvas
/// whenever [CropSession.active] is true. Owns the dim, the image
/// preview, the crop frame + handles, and the bottom action bar.
///
/// **Why this does not use `EditorToolPanelShell`:** Crop is a
/// full-screen mode, not a bottom-dock panel. It needs to own the
/// status-bar region, the canvas, the dim, and its own bottom
/// action bar with **Cancel** and **Done** semantics that genuinely
/// commit/abort a draft. The shell is for in-dock sub-tools that
/// share the editor's chrome \u2014 forking it for a full-screen mode
/// would muddy the contract for both. This overlay is the canonical
/// example of when to skip the shell.
///
/// UX contract:
///   * The image preview is rendered **uncropped** so the user can
///     always see the full image while choosing the crop.
///   * Aspect chips and corner drags only mutate the draft. The
///     document is untouched until **Done**, and **Cancel** is a
///     true no-op.
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
    return Material(
      color: Colors.black,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _CropTopBar(),
            const Divider(height: 1, thickness: 1, color: Color(0xFF1A1A1A)),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => _CropCanvas(
                  layer: layer,
                  available: Size(constraints.maxWidth, constraints.maxHeight),
                ),
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFF1A1A1A)),
            _CropBottomBar(layer: layer),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// Top bar — Cancel / title / Done
// =============================================================

class _CropTopBar extends ConsumerWidget {
  const _CropTopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(cropControllerProvider.notifier);
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            TextButton(
              onPressed: () {
                EditorHaptics.tap();
                ctrl.cancelCrop();
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                minimumSize: const Size(64, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              child: Text(context.l10n.cancelAction),
            ),
            const Spacer(),
            Text(
              context.l10n.cropTool,
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () {
                EditorHaptics.confirm();
                ctrl.commitCrop();
              },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                minimumSize: const Size(76, 38),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(19),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(context.l10n.doneAction),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// Canvas — image preview + draggable crop frame
// =============================================================

class _CropCanvas extends ConsumerWidget {
  const _CropCanvas({required this.layer, required this.available});
  final ImageLayer layer;
  final Size available;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Asymmetric padding: extra bottom clearance so the crop frame
    // never visually crowds the control panel below it.
    const paddingSide = 28.0;
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
    final layerAspect = layerW / layerH;
    double imgW = paneW;
    double imgH = imgW / layerAspect;
    if (imgH > paneH) {
      imgH = paneH;
      imgW = imgH * layerAspect;
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
          child: IgnorePointer(child: _UncroppedImage(layer: layer)),
        ),
        Positioned.fill(
          child: _CropFrameLayer(layer: layer, imageRect: imageRect),
        ),
      ],
    );
  }
}

/// Renders the layer's image source at its natural fit, ignoring
/// `cropRect`, mask, border, and shadow — crop mode is about
/// choosing pixels, not styling the silhouette.
class _UncroppedImage extends StatelessWidget {
  const _UncroppedImage({required this.layer});
  final ImageLayer layer;

  @override
  Widget build(BuildContext context) {
    final src = layer.source;
    if (src.assetName != null) {
      return Image.asset(src.assetName!, fit: layer.fit);
    }
    if (src.networkUrl != null) {
      return Image.network(src.networkUrl!, fit: layer.fit);
    }
    if (src.filePath != null) {
      return Image.file(io.File(src.filePath!), fit: layer.fit);
    }
    return const ColoredBox(color: Color(0x22FFFFFF));
  }
}

// =============================================================
// Crop frame — mask, handles, gestures
// =============================================================

class _CropFrameLayer extends ConsumerStatefulWidget {
  const _CropFrameLayer({required this.layer, required this.imageRect});
  final ImageLayer layer;
  final Rect imageRect;

  @override
  ConsumerState<_CropFrameLayer> createState() => _CropFrameLayerState();
}

enum _Handle { tl, tr, bl, br, t, r, b, l, body }

class _CropFrameLayerState extends ConsumerState<_CropFrameLayer> {
  Rect? _dragStartDraft;
  Offset? _dragStartGlobal;

  Rect _draftToScreen(Rect d) {
    final r = widget.imageRect;
    return Rect.fromLTRB(
      r.left + d.left * r.width,
      r.top + d.top * r.height,
      r.left + d.right * r.width,
      r.top + d.bottom * r.height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(cropControllerProvider);
    final frame = _draftToScreen(session.draftCrop);
    const handleHit = 36.0;
    const handleDot = 14.0;
    // Edge handles: shorter cross-axis length keeps them visually
    // distinct from corners while still offering a generous touch
    // target along the edge they live on.
    const edgeHitMain = 56.0;
    const edgeHitCross = 28.0;
    const edgeBarMain = 26.0;
    const edgeBarCross = 4.0;

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _CropMaskPainter(frame: frame)),
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
        // opposite edge \u2014 matching iOS Photos / Instagram.
        Positioned(
          left: frame.center.dx - edgeHitMain / 2,
          top: frame.top - edgeHitCross / 2,
          width: edgeHitMain,
          height: edgeHitCross,
          child: HandleDragDetector(
            onDrag: (gp, phase) => _onHandle(_Handle.t, gp, phase),
            child: const Center(
              child: _EdgeBar(width: edgeBarMain, height: edgeBarCross),
            ),
          ),
        ),
        Positioned(
          left: frame.center.dx - edgeHitMain / 2,
          top: frame.bottom - edgeHitCross / 2,
          width: edgeHitMain,
          height: edgeHitCross,
          child: HandleDragDetector(
            onDrag: (gp, phase) => _onHandle(_Handle.b, gp, phase),
            child: const Center(
              child: _EdgeBar(width: edgeBarMain, height: edgeBarCross),
            ),
          ),
        ),
        Positioned(
          left: frame.left - edgeHitCross / 2,
          top: frame.center.dy - edgeHitMain / 2,
          width: edgeHitCross,
          height: edgeHitMain,
          child: HandleDragDetector(
            onDrag: (gp, phase) => _onHandle(_Handle.l, gp, phase),
            child: const Center(
              child: _EdgeBar(width: edgeBarCross, height: edgeBarMain),
            ),
          ),
        ),
        Positioned(
          left: frame.right - edgeHitCross / 2,
          top: frame.center.dy - edgeHitMain / 2,
          width: edgeHitCross,
          height: edgeHitMain,
          child: HandleDragDetector(
            onDrag: (gp, phase) => _onHandle(_Handle.r, gp, phase),
            child: const Center(
              child: _EdgeBar(width: edgeBarCross, height: edgeBarMain),
            ),
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
              child: Center(
                child: Container(
                  width: handleDot,
                  height: handleDot,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black87, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _onHandle(_Handle h, Offset globalPos, DragPhase phase) {
    final ctrl = ref.read(cropControllerProvider.notifier);
    final session = ref.read(cropControllerProvider);
    switch (phase) {
      case DragPhase.start:
        _dragStartDraft = session.draftCrop;
        _dragStartGlobal = globalPos;
        EditorHaptics.tap();
        return;
      case DragPhase.update:
        final start = _dragStartDraft;
        final origin = _dragStartGlobal;
        if (start == null || origin == null) return;
        final r = widget.imageRect;
        if (r.width <= 0 || r.height <= 0) return;
        final dxNorm = (globalPos.dx - origin.dx) / r.width;
        final dyNorm = (globalPos.dy - origin.dy) / r.height;
        Rect next;
        if (h == _Handle.body) {
          next = CropController.translate(start, dxNorm, dyNorm);
        } else {
          // Aspect is stored in image-pixel space; convert to
          // normalised-space aspect so the handle drag stays
          // visually locked on a non-square layer.
          final aspectImage = session.aspectRatio;
          final layerAspect = session.originalAspect ?? 1.0;
          final aspectNorm = (aspectImage == null || layerAspect <= 0)
              ? null
              : aspectImage / layerAspect;
          next = CropController.resize(
            start,
            handle: _toPublicHandle(h),
            dx: dxNorm,
            dy: dyNorm,
            aspect: aspectNorm,
          );
        }
        ctrl.updateDraft(next);
        return;
      case DragPhase.end:
        _dragStartDraft = null;
        _dragStartGlobal = null;
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

/// Visual edge-handle bar. Small white pill anchored on the crop
/// frame edge, mirrored in styling to the corner dots.
class _EdgeBar extends StatelessWidget {
  const _EdgeBar({required this.width, required this.height});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: Colors.black87, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
    );
  }
}

class _CropMaskPainter extends CustomPainter {
  _CropMaskPainter({required this.frame});
  final Rect frame;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = const Color(0xB3000000);
    final outer = Path()..addRect(Offset.zero & size);
    final inner = Path()..addRect(frame);
    canvas.drawPath(Path.combine(PathOperation.difference, outer, inner), dim);
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(frame, stroke);
    final guide = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (var i = 1; i < 3; i++) {
      final dx = frame.left + frame.width * i / 3;
      final dy = frame.top + frame.height * i / 3;
      canvas.drawLine(Offset(dx, frame.top), Offset(dx, frame.bottom), guide);
      canvas.drawLine(Offset(frame.left, dy), Offset(frame.right, dy), guide);
    }
  }

  @override
  bool shouldRepaint(covariant _CropMaskPainter old) => old.frame != frame;
}

// =============================================================
// Bottom bar — aspect chips + Reset
// =============================================================

class _CropBottomBar extends ConsumerWidget {
  const _CropBottomBar({required this.layer});
  final ImageLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(cropControllerProvider);
    final ctrl = ref.read(cropControllerProvider.notifier);
    final layerH = layer.transform.size.height;
    final layerAspect = layerH == 0 ? 1.0 : layer.transform.size.width / layerH;
    final presets = <_AspectChip>[
      _AspectChip(label: context.l10n.freeOption, aspect: null),
      _AspectChip(label: context.l10n.originalOption, aspect: layerAspect),
      const _AspectChip(label: '1:1', aspect: 1),
      const _AspectChip(label: '4:5', aspect: 4 / 5),
      const _AspectChip(label: '5:4', aspect: 5 / 4),
      const _AspectChip(label: '16:9', aspect: 16 / 9),
      const _AspectChip(label: '9:16', aspect: 9 / 16),
    ];
    // SafeArea wraps the panel so content is always lifted above
    // the gesture-navigation pill / home indicator.  The Container
    // sits *outside* SafeArea so its dark background bleeds edge-
    // to-edge behind the system bar.
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D0D),
        border: Border(top: BorderSide(color: Color(0xFF2A2A2A), width: 1)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 14, 0, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Row 1: aspect chip scroll strip ──────────────
              SizedBox(
                height: 38,
                child: ListView.separated(
                  key: const ValueKey('crop-aspect-strip'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: presets.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final p = presets[i];
                    final selected = _aspectMatches(
                      session.aspectRatio,
                      p.aspect,
                    );
                    return _ChipButton(
                      label: p.label,
                      selected: selected,
                      onTap: () {
                        EditorHaptics.tap();
                        ctrl.setAspectRatio(p.aspect);
                      },
                    );
                  },
                ),
              ),
              // ── Row 2: Reset crop (centered, secondary) ──────
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () {
                  EditorHaptics.tap();
                  ctrl.resetCrop();
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(context.l10n.resetCropAction),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xD9FFFFFF), // ~white85
                  minimumSize: const Size(140, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                    side: const BorderSide(color: Color(0xFF3A3A3A), width: 1),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
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
  const _AspectChip({required this.label, required this.aspect});
  final String label;
  final double? aspect;
}

class _ChipButton extends StatelessWidget {
  const _ChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : const Color(0xFF252525),
      borderRadius: BorderRadius.circular(19),
      elevation: selected ? 3 : 0,
      shadowColor: Colors.white24,
      child: InkWell(
        borderRadius: BorderRadius.circular(19),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}
