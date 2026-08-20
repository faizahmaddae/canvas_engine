// THE floating quick-capsule (tb2 9/16) — ONE registry-derived pill
// for every selected layer type, replacing the four per-type
// floating surfaces (TextQuickCapsule, PaintFloatingToolbar,
// ShapeFloatingToolbar, QuickActionsOverlay).
//
//   [accelerator · accelerator (· accelerator)] | [⋯ more]
//
// Divergence-impossible rule: every action routes through an
// EXISTING controller entry point — the same dock slot ids the
// bottom bar toggles, the same crop/edit flows, the same layer
// overflow sheet. The capsule adds zero new command paths; it is
// pure acceleration.
//
// Per-type content matrix (roadmap/contract):
//   text    edit · colour swatch · visual-px size readout · More
//   image   style slot · crop · More
//   shape   fill swatch · corner · More   (both open the Style slot
//           — fill and corner radius live in the same dock body)
//   paint   stroke swatch · width readout · More  (colour/size dock
//           slots; the resize toggle lives in the overflow, tb2 7/16)
//   sticker replace · More  (the overflow sheet IS sticker's More —
//           closes the sticker-structural-actions gap)
//
// Visibility is owned by the canvas mount (single selection, no
// composer/mask session, not the protected base photo) plus the
// in-builder guards (inline edit, transform session,
// canvasChromeSuppressedProvider).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/constants/engine_constants.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../crop/application/crop_controller.dart';
import '../../application/context_toolbar_controller.dart';
import '../../engine/core/editor_layer.dart';
import '../../engine/core/viewport_state.dart';
import '../../engine/modules/image/image_layer.dart';
import '../../engine/modules/paint/paint_layer.dart';
import '../../engine/modules/shape/shape_layer.dart';
import '../../engine/modules/text/text_layer.dart';
import '../../image/application/image_tool_controller.dart';
import '../../paint/application/paint_tool_controller.dart';
import '../../shape/application/shape_tool_controller.dart';
import '../../sticker/application/sticker_tool_controller.dart';
import '../../text/application/text_tool_controller.dart';
import '../../text/presentation/text_edit_flow.dart';
import 'floating_action_bar.dart';
import 'floating_toolbar_positioner.dart';
import 'layer_overflow_sheet.dart';
import '../../../../core/utils/editor_value_format.dart';
import '../../../../app/theme/app_icons.dart';

/// One capsule item: an accelerator pill.
class _CapsuleItem {
  const _CapsuleItem({
    required this.semanticLabel,
    required this.child,
    required this.onTap,
    this.estWidth = 40,
  });

  final String semanticLabel;
  final Widget child;
  final VoidCallback onTap;

  /// Contribution to the positioner's horizontal clamp estimate —
  /// the bar itself sizes via its Row.
  final double estWidth;
}

class QuickCapsule extends ConsumerWidget {
  const QuickCapsule({super.key, required this.layer, required this.viewport});

  final EditorLayer layer;
  final ViewportState viewport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = _itemsFor(context, ref);
    if (items == null) return const SizedBox.shrink();

    final media = MediaQuery.of(context);
    final tokens = AppTokens.of(context);
    // Width from content: item estimates + the divider before More
    // + shell padding. Clamp-only — the Row is the real measure.
    final estWidth =
        items.fold<double>(0, (sum, i) => sum + i.estWidth) + 5 + 16 + 40;

    final anchor = FloatingToolbarPositioner.resolve(
      layerPosition: layer.transform.position,
      layerSize: layer.transform.size,
      layerCenter: layer.transform.center,
      layerRotation: layer.transform.rotation,
      viewport: viewport,
      screenSize: media.size,
      safePadding: media.padding,
      barWidth: estWidth,
      barHeight: kFloatingBarHeight,
      // Above-placement clearance includes the rotation knob's stem
      // construction (tb3 6/7): outset + stem + half the knob glyph.
      // Without it the capsule floats exactly where the knob now
      // lives and eats its taps. Below-placement keeps the plain gap
      // — there is no knob under the selection.
      gap:
          kFloatingBarGap +
          EngineConstants.selectionOutset +
          EngineConstants.rotateHandleOffset +
          EngineConstants.handleVisualSize / 2,
      gapBelow: kFloatingBarGap,
      horizontalMargin: kFloatingBarHorizontalMargin,
      bottomReserved: FloatingToolbarPositioner.dockHeight(
        screen: media.size,
        orientation: media.orientation,
      ),
    );
    if (anchor.isHidden) return const SizedBox.shrink();

    final bar = Semantics(
      container: true,
      label: context.l10n.quickActionsSemantics,
      child: FloatingGlassBar(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              FloatingPillButton(
                semanticLabel: item.semanticLabel,
                onTap: item.onTap,
                child: item.child,
              ),
            _CapsuleDivider(color: tokens.border.withValues(alpha: 0.8)),
            FloatingPillButton(
              semanticLabel: context.l10n.moreActionsSemantics,
              onTap: () => _openOverflow(context, ref),
              child: Icon(
                AppIcons.moreActions,
                size: 18,
                color: tokens.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );

    return AnimatedPositioned(
      left: anchor.left,
      top: anchor.top,
      duration: AppMotion.of(context, AppMotion.state),
      curve: AppMotion.curve,
      child: SizedBox(height: kFloatingBarHeight, child: bar),
    );
  }

  /// More: close the type's own panel first (same as the dock's More
  /// tiles) so the overflow sheet never stacks on an open panel,
  /// then open the ONE capability-driven overflow sheet.
  void _openOverflow(BuildContext context, WidgetRef ref) {
    EditorHaptics.tap();
    final l = layer;
    if (l is TextLayer && !l.isSticker) {
      ref.read(textToolControllerProvider.notifier).closeSheet();
    } else if (l is TextLayer && l.isSticker) {
      ref.read(stickerToolControllerProvider.notifier).closePanel();
    } else if (l is ImageLayer) {
      ref.read(imageToolControllerProvider.notifier).closePanel();
      ref.read(contextToolbarControllerProvider.notifier).closePanel();
    } else if (l is ShapeLayer) {
      ref.read(shapeToolControllerProvider.notifier).closePanel();
      ref.read(contextToolbarControllerProvider.notifier).closePanel();
    } else if (l is PaintLayer) {
      ref.read(paintToolControllerProvider.notifier).closeSlot();
    }
    final scaffold = Scaffold.maybeOf(context);
    showLayerOverflowSheet(
      context,
      ref,
      layer: layer,
      onOpenLayers: scaffold == null ? null : () => scaffold.openEndDrawer(),
    );
  }

  /// The per-type accelerator registry. Returns null for layer types
  /// with no capsule (unknown/future types fall back to none —
  /// their structural actions stay reachable via the layers drawer).
  List<_CapsuleItem>? _itemsFor(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final l10n = context.l10n;
    final l = layer;

    if (l is TextLayer && !l.isSticker) {
      final ctrl = ref.read(textToolControllerProvider.notifier);
      return [
        _CapsuleItem(
          semanticLabel: l10n.editTextAction,
          child: Icon(AppIcons.editText, size: 18, color: tokens.textPrimary),
          onTap: () {
            EditorHaptics.tap();
            showEditTextLayerFlow(context, ref, l);
          },
        ),
        _CapsuleItem(
          semanticLabel: l10n.colorLabel,
          child: FloatingColorDot(color: l.style.color),
          onTap: () {
            EditorHaptics.tap();
            ctrl.toggleSheet('color');
          },
        ),
        _CapsuleItem(
          semanticLabel: l10n.sizeTool,
          estWidth: 48,
          child: Text(
            // VISUAL px (tb2 12/16) — raw fontSize lies after
            // corner drags on scaleText layers.
            EditorValueFormat.of(context).px(ctrl.visualFontSizeOf(l).round()),
            style: _readoutStyle(tokens),
          ),
          onTap: () {
            EditorHaptics.tap();
            ctrl.toggleSheet('size');
          },
        ),
      ];
    }

    if (l is TextLayer && l.isSticker) {
      return [
        _CapsuleItem(
          semanticLabel: l10n.replaceTool,
          child: Icon(AppIcons.replace, size: 18, color: tokens.textPrimary),
          onTap: () {
            EditorHaptics.tap();
            ref
                .read(stickerToolControllerProvider.notifier)
                .toggleSlot(StickerToolSlot.replace);
          },
        ),
      ];
    }

    if (l is ImageLayer) {
      final imageCtrl = ref.read(imageToolControllerProvider.notifier);
      final contextCtrl = ref.read(contextToolbarControllerProvider.notifier);
      return [
        _CapsuleItem(
          semanticLabel: l10n.lookTool,
          child: Icon(AppIcons.lookTool, size: 18, color: tokens.textPrimary),
          onTap: () {
            EditorHaptics.tap();
            contextCtrl.closePanel();
            imageCtrl.toggleSlot(ImageToolSlot.look);
          },
        ),
        _CapsuleItem(
          semanticLabel: l10n.cropImageAction,
          child: Icon(AppIcons.cropTool, size: 18, color: tokens.textPrimary),
          onTap: () {
            // Same one-shot entry as the image dock's Crop tile:
            // close panels first so leaving crop never reveals a
            // stale one, preserve the selection across the session.
            EditorHaptics.tap();
            contextCtrl.closePanel();
            imageCtrl.closePanel();
            ref
                .read(cropControllerProvider.notifier)
                .openCrop(l.id, priorSelectionId: l.id);
          },
        ),
      ];
    }

    if (l is ShapeLayer) {
      final ctrl = ref.read(shapeToolControllerProvider.notifier);
      final contextCtrl = ref.read(contextToolbarControllerProvider.notifier);
      // Fill and corner both open the Style slot — that dock body
      // owns both values; the two pills are different affordances
      // into the same surface (divergence-impossible).
      void openStyle() {
        EditorHaptics.tap();
        contextCtrl.closePanel();
        ctrl.toggleSlot(ShapeToolSlot.style);
      }

      return [
        _CapsuleItem(
          semanticLabel: l10n.fillLabel,
          child: FloatingColorDot(color: l.fillColor),
          onTap: openStyle,
        ),
        _CapsuleItem(
          semanticLabel: l10n.cornerRadiusLabel,
          child: Icon(
            AppIcons.cornerRadius,
            size: 18,
            color: tokens.textPrimary,
          ),
          onTap: openStyle,
        ),
      ];
    }

    if (l is PaintLayer) {
      final ctrl = ref.read(paintToolControllerProvider.notifier);
      return [
        _CapsuleItem(
          semanticLabel: l10n.strokeColorTitle,
          child: FloatingColorDot(color: l.strokeColor),
          onTap: () {
            EditorHaptics.tap();
            ctrl.toggleSlot('color');
          },
        ),
        _CapsuleItem(
          semanticLabel: l10n.strokeSizeSemantics,
          estWidth: 48,
          child: Text(
            EditorValueFormat.of(context).px(l.strokeWidth.round()),
            style: _readoutStyle(tokens),
          ),
          onTap: () {
            EditorHaptics.tap();
            // The bench's pen sheet owns size (+ opacity) since the
            // 2026-08 redesign; the old standalone 'size' slot died.
            ctrl.toggleSlot('pen');
          },
        ),
      ];
    }

    return null;
  }

  TextStyle _readoutStyle(AppTokens tokens) => TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w700,
    height: 1,
    color: tokens.textPrimary,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

class _CapsuleDivider extends StatelessWidget {
  const _CapsuleDivider({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: color,
    );
  }
}
