import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../core/layer_mask.dart';
import 'stack_mask_raster_cache.dart';

/// Composites a layer's effected pixels over its un-effected base
/// through the stack mask's alpha — the effects.md §5 line
///
///     I_prev := composite(I_prev over I0 through stack.stackMask)
///
/// implemented per the A3 spike verdict
/// (docs/effects-a3-scoped-plan-2026-07.md §7.1):
///
///     Stack(fit: expand, [
///       base,                                  // I0
///       ShaderMask(dstIn, ImageShader(mask), child: painted),
///     ])
///
/// `ShaderMask` (not canvas `saveLayer` + `dstIn`) because it is
/// itself a compositing layer: the shader + blend apply to the
/// child's *composited output*, so it survives children that push
/// their own layers — and `painted` always does (`ColorFiltered`).
/// The rejected canvas-level approach leaks the effect unmasked and
/// invalidates the cached canvas mid-paint (spike, pinned there).
///
/// Callers must NOT construct this widget when the stack mask is
/// null — the null path must stay render-tree identical to a
/// pre-stackMask document (byte-identity + widget-structure gates).
///
/// Until the mask raster resolves (typically one frame, async decode
/// in [StackMaskRasterCache]) this renders [base] only: a one-frame
/// delay of the adjustment is invisible; a one-frame flash of the
/// *unmasked* effect is not.
class StackMaskComposite extends StatefulWidget {
  const StackMaskComposite({
    super.key,
    required this.mask,
    required this.size,
    required this.base,
    required this.painted,
  });

  /// The stack mask, in layer-local space (LayerMask's contract).
  final LayerMask mask;

  /// Layer-local logical size — the raster is keyed on it, so a
  /// resize re-rasterizes at the new dimensions.
  final Size size;

  /// The layer's pixel subtree with every EffectStack contribution
  /// removed and nothing else removed (§7.2: source, fit, decode cap,
  /// filter preset, crop — no stack matrix, no custom-paint overlay).
  final Widget base;

  /// Today's fully-effected subtree, exactly as built without a mask.
  final Widget painted;

  @override
  State<StackMaskComposite> createState() => _StackMaskCompositeState();
}

class _StackMaskCompositeState extends State<StackMaskComposite> {
  int get _rasterW => widget.size.width.round();
  int get _rasterH => widget.size.height.round();

  @override
  void initState() {
    super.initState();
    _ensureRaster();
  }

  @override
  void didUpdateWidget(StackMaskComposite old) {
    super.didUpdateWidget(old);
    if (old.mask != widget.mask || old.size != widget.size) {
      _ensureRaster();
    }
  }

  void _ensureRaster() {
    final cache = StackMaskRasterCache.instance;
    if (cache.lookup(widget.mask, _rasterW, _rasterH) != null) return;
    final mask = widget.mask;
    final w = _rasterW, h = _rasterH;
    cache.request(mask, w, h, () {
      // The widget may have moved on (different mask/size) or been
      // disposed while the decode was in flight; a stale completion
      // only needs to trigger a rebuild when it still matches.
      if (!mounted) return;
      if (widget.mask != mask || _rasterW != w || _rasterH != h) return;
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    // Re-looked-up every build: the cache owns the image and may
    // evict it (disposing the handle), so retaining it across frames
    // would risk painting a disposed image.
    final raster =
        StackMaskRasterCache.instance.lookup(widget.mask, _rasterW, _rasterH);
    if (raster == null) {
      _ensureRaster();
      return widget.base;
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.base,
        ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (Rect bounds) => ui.ImageShader(
            raster,
            TileMode.clamp,
            TileMode.clamp,
            Matrix4.identity().storage,
          ),
          child: widget.painted,
        ),
      ],
    );
  }
}
