import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../l10n/l10n.dart';
import '../../engine/core/viewport_state.dart';
import '../../engine/modules/shape/shape_layer.dart';
import '../../presentation/widgets/floating_action_bar.dart';
import '../../presentation/widgets/floating_toolbar_positioner.dart';
import '../application/shape_tool_controller.dart';

/// Compact glass pill that hovers near the selected shape layer.
///
/// Holds exactly one contextual action:
///   ⇆  resize behaviour toggle (Scale ↔ Free)
///
/// Fill / stroke / shadow / replace / opacity / more flows live in
/// the bottom shape dock; this floating bar exists purely to surface
/// the *resize* affordance so users can override the per-kind
/// aspect-lock default.
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
  // reasonable bound for the resize pill + padding.
  static const double _estWidth = 116;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final tokens = AppTokens.of(context);

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
    final fg = tokens.textPrimary;

    final bar = FloatingGlassBar(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingPillButton(
            active: isScale,
            semanticLabel: isScale
                ? context.l10n.resizeBehaviorScaleSemantics
                : context.l10n.resizeBehaviorFreeSemantics,
            onTap: () {
              final next = isScale
                  ? ShapeResizeMode.free
                  : ShapeResizeMode.scale;
              ctrl.setResizeMode(next);
            },
            child: ResizeModePillContent(
              isScale: isScale,
              foreground: fg,
              activeColor: tokens.accent,
            ),
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
