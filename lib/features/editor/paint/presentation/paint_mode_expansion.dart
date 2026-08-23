import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_icons.dart';
import '../../../../l10n/l10n.dart';
import '../../toolbar/domain/sub_tool.dart';
import '../../toolbar/domain/sub_tools/widget_sub_tool.dart';
import '../../toolbar/presentation/sub_tool_sheet.dart';
import '../application/paint_tool_controller.dart';
import 'bodies/paint_blur_body.dart';
import 'bodies/paint_color_body.dart';
import 'bodies/paint_dash_body.dart';
import 'bodies/paint_pen_body.dart';
import 'bodies/paint_shape_body.dart';

/// In-dock sheet panel for paint mode. Routes [PaintSession.openSlot]
/// → its body and renders it inside the dock's `expanded` slot with
/// the shared sheet chrome.
///
/// The bench redesign (docs/paint-redesign-2026-08.md) reduced the
/// sheet set to five focused surfaces — colour, pen (size+opacity),
/// line style, shape, blur — and retired the per-sheet scope chips:
/// which target a write reaches is disclosed by the bench's posture
/// (armed rack slot vs adjust), not by a caption. Sibling-swipe
/// paging retired with the property-strip: the sheets are no longer
/// a flat list of siblings but per-tool options.
class PaintModeInlineExpansion extends ConsumerWidget {
  const PaintModeInlineExpansion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(paintToolControllerProvider);
    final view = ref.watch(paintStyleViewProvider);
    final openId = session.openSlot;
    if (openId == null) return const SizedBox.shrink();
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    final l10n = context.l10n;

    final SubTool? subTool = switch (openId) {
      'color' => WidgetSubTool(
        headerTitle: l10n.strokeColorTitle,
        headerIcon: AppIcons.colorTool,
        builder: (ctx, _) => PaintColorBody(current: view.strokeColor),
      ),
      'pen' => WidgetSubTool(
        headerTitle: l10n.penTool,
        headerIcon: AppIcons.strokeWeight,
        builder: (ctx, _) => PaintPenBody(view: view),
      ),
      'line' => WidgetSubTool(
        headerTitle: l10n.styleLabel,
        headerIcon: AppIcons.dashStyle,
        builder: (ctx, _) => const PaintDashBody(),
      ),
      'shape' => WidgetSubTool(
        headerTitle: l10n.shapeTool,
        headerIcon: AppIcons.shapeTool,
        builder: (ctx, _) => PaintShapeBody(view: view),
      ),
      'blur' => WidgetSubTool(
        headerTitle: l10n.blurLabel,
        headerIcon: AppIcons.blur,
        builder: (ctx, _) => PaintBlurBody(view: view),
      ),
      _ => null,
    };
    if (subTool == null) return const SizedBox.shrink();

    return SubToolSheet(
      subTool: subTool,
      onClose: ctrl.closeSlot,
      // Undo lives on the persistent editor chrome — single source
      // of history navigation.
      onUndo: null,
      onPrev: null,
      onNext: null,
    );
  }
}
