import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../l10n/l10n.dart';
import '../../../color_picker/presentation/color_picker_sheet.dart';
import '../../engine/core/viewport_state.dart';
import '../../engine/modules/paint/paint_layer.dart';
import '../../presentation/widgets/floating_action_bar.dart';
import '../../presentation/widgets/floating_toolbar_positioner.dart';
import '../../presentation/widgets/layer_overflow_sheet.dart';
import '../application/paint_tool_controller.dart';
import 'paint_size_sheet.dart';

/// Compact glass pill that hovers near the selected paint layer.
///
/// Holds exactly four contextual actions, in order:
///   ●  stroke color swatch
///   ▭  stroke size readout
///   ⇆  resize behaviour toggle (Scale ↔ Free)
///   ⋯  more actions (layer-ops sheet)
///
/// Anything heavier (dash pattern, fill picker, blur sigma, polygon
/// sides) lives in the existing paint mode toolbar / size sheet. This
/// bar is the fast path only — symmetric with [TextFloatingToolbar]
/// and [ShapeFloatingToolbar].
///
/// Visibility is owned by the canvas: mounted only when a single
/// paint layer is selected and unmounted while a transform gesture
/// is in flight (see `_buildPaintFloatingToolbar` in
/// `editor_canvas.dart`).
class PaintFloatingToolbar extends ConsumerWidget {
  const PaintFloatingToolbar({
    super.key,
    required this.layer,
    required this.viewport,
  });

  final PaintLayer layer;
  final ViewportState viewport;

  // Estimated bar width — used only to clamp horizontally. The bar
  // sizes itself via IntrinsicWidth, but we need a reasonable bound
  // for the clamp; 280 covers the four pills + padding.
  static const double _estWidth = 280;

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

    final ctrl = ref.read(paintToolControllerProvider.notifier);
    final isScale = layer.resizeMode == PaintResizeMode.scale;
    final fg = tokens.textPrimary;

    final bar = FloatingGlassBar(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingPillButton(
            semanticLabel: context.l10n.strokeColorTitle,
            // The shared picker sheet — live, undimmed, recents
            // handled inside; nothing to restore or re-commit.
            onTap: () => showColorPickerSheet(
              context,
              initial: layer.strokeColor,
              onLiveChange: ctrl.setStrokeColor,
              title: context.l10n.strokeColorTitle,
            ),
            child: FloatingColorDot(color: layer.strokeColor),
          ),
          const SizedBox(width: 4),
          FloatingPillButton(
            semanticLabel: context.l10n.strokeSizeSemantics,
            onTap: () => showPaintSizeSheet(context, ref),
            child: _StrokeSizePillContent(
              strokeWidth: layer.strokeWidth,
              foreground: fg,
            ),
          ),
          const SizedBox(width: 4),
          FloatingPillButton(
            active: isScale,
            semanticLabel: isScale
                ? context.l10n.resizeBehaviorScaleObjectSemantics
                : context.l10n.resizeBehaviorFreeSemantics,
            onTap: () {
              final next = isScale
                  ? PaintResizeMode.free
                  : PaintResizeMode.scale;
              ctrl.setResizeMode(next);
            },
            // Reuse the shape toolbar's resize-mode label so the two
            // bars stay visually identical.
            child: ResizeModePillContent(
              isScale: isScale,
              foreground: fg,
              activeColor: tokens.accent,
            ),
          ),
          const SizedBox(width: 4),
          FloatingPillButton(
            semanticLabel: context.l10n.moreActionsSemantics,
            onTap: () {
              final scaffold = Scaffold.maybeOf(context);
              showLayerOverflowSheet(
                context,
                ref,
                layer: layer,
                onOpenLayers: scaffold == null
                    ? null
                    : () => scaffold.openEndDrawer(),
              );
            },
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

/// Mini stroke-width preview: a horizontal bar whose thickness
/// reflects the current `strokeWidth`, plus the rounded value as a
/// readable number. Lives next to the size pill so the user can see
/// the value without opening the size sheet.
class _StrokeSizePillContent extends StatelessWidget {
  const _StrokeSizePillContent({
    required this.strokeWidth,
    required this.foreground,
  });

  final double strokeWidth;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 18,
          height: math.max(2, math.min(strokeWidth, 10)),
          decoration: BoxDecoration(
            color: foreground,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          strokeWidth.round().toString(),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: foreground.withValues(alpha: 0.72),
            fontFeatures: const [FontFeature.tabularFigures()],
            height: 1,
          ),
        ),
      ],
    );
  }
}
