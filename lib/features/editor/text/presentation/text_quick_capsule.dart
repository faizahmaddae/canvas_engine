// Floating quick-capsule for the selected text layer (re-added,
// redesigned — the old five-pill bar died with the one-bar
// consolidation; this is a NEW lean quick-access, not a second full
// bar). One elevated pill floating just above the selection:
//
//   [✏️ edit] | [Aa font] · [live px] · [● live colour] | [⋯ more]
//
// Every item routes to EXACTLY the surface the matching bottom-bar
// tile opens (font/size/color sheets via TextToolController, the
// «بیشتر» modal, the edit flow) — one source of truth, zero
// divergent state. The capsule hides while any of those surfaces is
// open (gated at the mount site in editor_canvas.dart), so it never
// stacks on the dock panel it just opened.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../engine/core/viewport_state.dart';
import '../../engine/modules/text/text_layer.dart';
import '../../presentation/widgets/layer_overflow_sheet.dart';
import '../../presentation/widgets/floating_action_bar.dart';
import '../../presentation/widgets/floating_toolbar_positioner.dart';
import '../application/text_tool_controller.dart';
import 'text_edit_flow.dart';

class TextQuickCapsule extends ConsumerWidget {
  const TextQuickCapsule({
    super.key,
    required this.layer,
    required this.viewport,
  });

  final TextLayer layer;
  final ViewportState viewport;

  /// Estimated width for the horizontal clamp only — the bar sizes
  /// itself via its Row. Five pills (the size pill is text-wide) +
  /// two dividers + shell padding.
  static const double _estWidth = 236;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    final anchor = FloatingToolbarPositioner.resolve(
      layerPosition: layer.transform.position,
      layerSize: layer.transform.size,
      layerCenter: layer.transform.center,
      layerRotation: layer.transform.rotation,
      viewport: viewport,
      screenSize: media.size,
      safePadding: media.padding,
      barWidth: _estWidth,
      barHeight: kFloatingBarHeight,
      gap: kFloatingBarGap,
      horizontalMargin: kFloatingBarHorizontalMargin,
      bottomReserved: FloatingToolbarPositioner.dockHeight(
        screen: media.size,
        orientation: media.orientation,
      ),
    );
    if (anchor.isHidden) return const SizedBox.shrink();

    final tokens = AppTokens.of(context);
    final l10n = context.l10n;
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final style = layer.style;

    void openSheet(String id) {
      EditorHaptics.tap();
      ctrl.toggleSheet(id);
    }

    final bar = Semantics(
      container: true,
      label: l10n.textQuickActionsSemantics,
      child: FloatingGlassBar(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Edit FIRST — the single most common follow-up to
            // selecting text.
            FloatingPillButton(
              semanticLabel: l10n.editTextAction,
              onTap: () {
                EditorHaptics.tap();
                showEditTextLayerFlow(context, ref, layer);
              },
              child: Icon(
                Icons.edit_rounded,
                size: 18,
                color: tokens.textPrimary,
              ),
            ),
            _CapsuleDivider(color: tokens.border.withValues(alpha: 0.8)),
            FloatingPillButton(
              semanticLabel: l10n.fontTool,
              onTap: () => openSheet('font'),
              child: Icon(
                Icons.text_fields_rounded,
                size: 18,
                color: tokens.textPrimary,
              ),
            ),
            FloatingPillButton(
              semanticLabel: l10n.sizeTool,
              onTap: () => openSheet('size'),
              child: Text(
                '${style.fontSize.round()}px',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: tokens.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            FloatingPillButton(
              semanticLabel: l10n.colorLabel,
              onTap: () => openSheet('color'),
              child: FloatingColorDot(color: style.color),
            ),
            _CapsuleDivider(color: tokens.border.withValues(alpha: 0.8)),
            FloatingPillButton(
              semanticLabel: l10n.moreActionsSemantics,
              onTap: () {
                EditorHaptics.tap();
                // Same routing as the bar's بیشتر tile: any open
                // sheet closes first so the modal never stacks.
                ctrl.closeSheet();
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
              child: Icon(
                Icons.more_horiz_rounded,
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
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: SizedBox(height: kFloatingBarHeight, child: bar),
    );
  }
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
