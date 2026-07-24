import 'package:flutter/widgets.dart';

import '../core/editor_document.dart';
import 'background_fill_box.dart';
import 'layer_renderer.dart';

/// Pure visual representation of an [EditorDocument].
///
/// Renders only the document itself — background fill + visible layers
/// in z-order — using the same [LayerRenderer] the editor canvas uses,
/// so the on-screen and exported pixels stay in lockstep. Deliberately
/// excludes:
///
///   * selection chrome (handles, outlines, group rectangles)
///   * snap guides
///   * mode indicators / HUDs
///   * gesture detectors
///   * the viewport transform
///
/// This widget is the single source of truth for "what the document
/// actually looks like" and is reused by [DocumentPngExporter]. Editor-
/// canvas chrome is painted on top of (not inside) this view.
///
/// **Color-space contract (see `docs/effects.md` §6).** Every layer
/// renders in **sRGB-encoded, premultiplied-alpha** Flutter colour
/// space. Effects in `engine/effects/` operate as `ColorFilter.matrix`
/// or sRGB custom paint — they do **not** linearise. The `DocumentView`
/// composite, the per-layer `RepaintBoundary`, and the exporter all
/// assume this contract. Adding a wide-gamut source, an HDR layer, or
/// a linear-light effect is a deliberate phase change that must update
/// the contract here, in `EditorEffect`, and in the exporter together.
class DocumentView extends StatelessWidget {
  const DocumentView({
    super.key,
    required this.document,
    this.backgroundFill,
    @Deprecated('Pass backgroundFill: SolidBackground(color: ...) instead')
    this.background = const Color(0xFFFFFFFF),
    this.honorTransparentMode = false,
  });

  final EditorDocument document;

  /// The fill painted under the layers when this view is asked to
  /// composite over an opaque backdrop. When non-null, takes precedence
  /// over [background] and supports gradients via [LinearGradientBackground]
  /// / [RadialGradientBackground].
  ///
  /// IGNORED when [honorTransparentMode] is true AND the document's own
  /// [EditorDocument.backgroundMode] is [CanvasBackgroundMode.transparent]
  /// — the view then paints no backdrop at all so the resulting image
  /// carries alpha.
  final BackgroundFill? backgroundFill;

  /// Legacy solid backdrop. Used only when [backgroundFill] is null.
  /// Defaults to opaque white. Set to a transparent colour when
  /// exporting against a checker-pattern preview, etc.
  ///
  /// Subject to the same [honorTransparentMode] rule as [backgroundFill].
  @Deprecated('Pass backgroundFill: SolidBackground(color: ...) instead')
  final Color background;

  /// When true, [EditorDocument.backgroundMode] decides whether to
  /// paint a backdrop at all. PNG export sets this so transparent
  /// projects export with real alpha. JPEG export keeps it false
  /// because the format has no alpha channel and would otherwise
  /// flatten transparent pixels to black.
  final bool honorTransparentMode;

  @override
  Widget build(BuildContext context) {
    final paintBackdrop =
        !(honorTransparentMode &&
            document.backgroundMode == CanvasBackgroundMode.transparent);
    final BackgroundFill effectiveFill =
        // ignore: deprecated_member_use_from_same_package
        backgroundFill ?? SolidBackground(color: background);
    return SizedBox(
      width: document.width,
      height: document.height,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          if (paintBackdrop)
            Positioned.fill(child: BackgroundFillBox(fill: effectiveFill)),
          for (final layer in document.layers)
            if (layer.visible)
              LayerRenderer(
                key: ValueKey(layer.id),
                layer: layer,
                transform: layer.transform,
              ),
        ],
      ),
    );
  }
}
