import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/core/viewport_state.dart';
import '../../engine/modules/shape/shape_layer.dart';
import '../../presentation/widgets/floating_action_bar.dart';
import '../../presentation/widgets/floating_toolbar_positioner.dart';
import '../../presentation/widgets/layer_actions_sheet.dart';
import '../application/shape_tool_controller.dart';

/// Compact glass pill that hovers near the selected shape layer.
///
/// Holds exactly two contextual actions:
///   ⇆  resize behaviour toggle (Scale ↔ Free)
///   ⋯  more actions (layer-ops sheet — duplicate / lock / delete …)
///
/// Fill / stroke / shadow / replace flows live in the bottom shape
/// dock; this floating bar exists purely to surface the *resize*
/// affordance (so users can override the per-kind aspect-lock
/// default) — symmetric with [PaintFloatingToolbar].
///
/// Visibility is owned by the canvas: mounted only when a single
/// shape layer is selected, unmounted while a transform gesture is
/// in flight or while the shape sub-tool sheet is open. See
/// `_buildShapeFloatingToolbar` in `editor_canvas.dart`.
class ShapeFloatingToolbar extends ConsumerWidget {
  const ShapeFloatingToolbar({
    super.key,
    required this.layer,
    required this.viewport,
  });

  final ShapeLayer layer;
  final ViewportState viewport;

  // Estimated bar width — used only to clamp horizontally. The bar
  // sizes itself via IntrinsicWidth, but the positioner needs a
  // reasonable bound. 180 covers the resize pill + more pill + padding.
  static const double _estWidth = 180;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final anchor = FloatingToolbarPositioner.resolve(
      layerPosition: layer.transform.position,
      layerSize: layer.transform.size,
      layerCenter: layer.transform.center,
      layerRotation: layer.transform.rotation,
      viewport: viewport,
      screenSize: size,
      safePadding: media.padding,
      barWidth: _estWidth,
      barHeight: kFloatingBarHeight,
      gap: kFloatingBarGap,
      horizontalMargin: kFloatingBarHorizontalMargin,
      bottomReserved: FloatingToolbarPositioner.dockHeight(
        screen: size,
        orientation: media.orientation,
      ),
    );
    if (anchor.isHidden) return const SizedBox.shrink();

    final ctrl = ref.read(shapeToolControllerProvider.notifier);
    // Use the *resolved* mode so the toggle reflects what the engine
    // is actually doing — including the kind-based default for shapes
    // that have never had an explicit pick.
    final isScale = layer.effectiveResizeMode == ShapeResizeMode.scale;
    final fg = isDark ? Colors.white : const Color(0xFF1A1A1A);

    final bar = FloatingGlassBar(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingPillButton(
            active: isScale,
            semanticLabel: isScale
                ? 'Resize behavior: Scale shape (tap for Free)'
                : 'Resize behavior: Resize freely (tap for Scale)',
            onTap: () {
              final next =
                  isScale ? ShapeResizeMode.free : ShapeResizeMode.scale;
              ctrl.setResizeMode(next);
            },
            child: ResizeModePillContent(
              isScale: isScale,
              foreground: fg,
              activeColor: scheme.primary,
            ),
          ),
          const SizedBox(width: 4),
          FloatingPillButton(
            semanticLabel: 'More actions',
            onTap: () => showLayerActionsSheet(context, ref, layer),
            child: Icon(Icons.more_horiz_rounded, size: 20, color: fg),
          ),
        ],
      ),
    );

    return AnimatedPositioned(
      left: anchor.left,
      top: anchor.top,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: SizedBox(height: kFloatingBarHeight, child: bar),
    );
  }
}
