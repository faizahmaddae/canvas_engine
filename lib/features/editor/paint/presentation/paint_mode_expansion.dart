// Extracted verbatim from paint_mode_toolbar.dart (tb1 5/17); behaviour-preserving.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import '../../toolbar/domain/sibling_swipe_strategy.dart';
import '../../toolbar/domain/sub_tool.dart';
import '../../toolbar/domain/sub_tools/slider_sub_tool.dart';
import '../../toolbar/domain/sub_tools/widget_sub_tool.dart';
import '../../toolbar/presentation/sub_tool_sheet.dart';
import '../application/paint_tool_controller.dart';
import 'bodies/paint_color_body.dart';
import 'bodies/paint_dash_body.dart';
import 'bodies/paint_fill_body.dart';
import 'bodies/paint_polygon_body.dart';
import 'bodies/paint_size_entry.dart';
import 'bodies/paint_tool_body.dart';
import 'paint_mode_toolbar.dart';
import 'paint_tool_specs.dart';

/// In-dock sheet panel for paint mode. Routes [PaintSession.openSlot]
/// → its body and renders it inside the dock's `expanded` slot with
/// [DockSheetChrome]. Mirrors `TextModeSheetPanel`.
class PaintModeInlineExpansion extends ConsumerWidget {
  const PaintModeInlineExpansion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(paintToolControllerProvider);
    final openId = session.openSlot;
    if (openId == null) return const SizedBox.shrink();
    final spec = PaintModeToolbar.specById(openId);
    if (spec == null) return const SizedBox.shrink();

    final ctrl = ref.read(paintToolControllerProvider.notifier);

    // Resolve the [SubTool] for this slot. Slider tools come from
    // the data registry; everything else is wrapped by
    // [WidgetSubTool] so it inherits the lifted SubToolSheet
    // chrome (Done pill, surface elevation, padding) without
    // rewriting the body widget.
    //
    // The 'tool' slot gets a friendlier header so it reads as a
    // temporary chooser, not a persistent settings panel.
    final bool isPicker = openId == 'tool';
    final SubTool subTool =
        _paintSliderSubTools(context)[openId] ??
        WidgetSubTool(
          headerTitle: isPicker
              ? context.l10n.chooseToolTitle
              : paintSpecLabel(context.l10n, spec),
          headerIcon: isPicker ? Icons.brush_rounded : spec.icon,
          builder: (ctx, _) => _buildPaintBody(ctx, openId, session),
        );

    final ids = PaintModeToolbar.toolIdsFor(session.activeTool);
    // Single-list, no exclusions — [SiblingSwipeStrategy] handles
    // wrap-around and the single-slot "swipe is a no-op" case so
    // we don't have to special-case it here.
    final swipe = SiblingSwipeStrategy<String>(order: ids);
    final prevId = swipe.prev(openId);
    final nextId = swipe.next(openId);

    return SubToolSheet(
      subTool: subTool,
      onClose: ctrl.closeSlot,
      // Undo lives on the persistent floating action in the editor
      // chrome — single source of history navigation.
      onUndo: null,
      onPrev: prevId == null ? null : () => ctrl.toggleSlot(prevId),
      onNext: nextId == null ? null : () => ctrl.toggleSlot(nextId),
      // Header chip is the canonical neutral ✕ close — same
      // destination as the drag-handle dismiss. Mode-exit lives
      // on the top-right floating pill.
    );
  }

  /// Bespoke body resolver. Kept as a static helper so the routing
  /// in [build] stays a single expression. Each case is a one-liner
  /// constructing the existing body widget unchanged \u2014 only the
  /// surrounding chrome is unified.
  Widget _buildPaintBody(
    BuildContext context,
    String openId,
    PaintSession session,
  ) {
    switch (openId) {
      case 'tool':
        return const PaintToolBody();
      case 'color':
        return PaintColorBody(current: session.strokeColor);
      case 'fill':
        return PaintFillBody(
          enabled: session.fillColor != null,
          current: session.fillColor ?? session.strokeColor,
        );
      case 'polygon':
        return PaintPolygonBody(value: session.polygonSides);
      case 'dash':
        return const PaintDashBody();
      case 'size':
        return PaintSizeEntryBody(session: session);
      default:
        return const SizedBox.shrink();
    }
  }
}

String paintSpecLabel(AppLocalizations l10n, PaintSpec spec) {
  return switch (spec.id) {
    'tool' => l10n.toolLabel,
    'color' => l10n.colorLabel,
    'size' => l10n.sizeTool,
    'fill' => l10n.fillLabel,
    'opacity' => l10n.opacityLabel,
    'blur' => l10n.blurLabel,
    'polygon' => l10n.sidesTool,
    'dash' => l10n.styleLabel,
    _ => spec.label,
  };
}

/// Stroke-width body. Preset chips above a "Fine tune" slider with
/// a dot preview that grows/shrinks live.
/// Phase 2 registry: paint slots whose body is a generic
/// preset+slider. New numeric tools should be added here, not as
/// new private body widgets.
Map<String, SubTool> _paintSliderSubTools(BuildContext context) =>
    <String, SubTool>{
      'blur': SliderSubTool(
        headerTitle: context.l10n.blurLabel,
        headerIcon: Icons.blur_on_rounded,
        min: 0,
        max: 64,
        // Preset-first: 3 human choices users actually pick. Slider
        // covers everything in between for power users.
        presets: const [0, 10, 32],
        presetLabels: [
          context.l10n.noneOption,
          context.l10n.softOption,
          context.l10n.strongOption,
        ],
        readValue: (ref) => ref.watch(paintToolControllerProvider).blurRadius,
        writeValue: (ref, v) =>
            ref.read(paintToolControllerProvider.notifier).setBlurRadius(v),
        format: (v) => '${v.round()}',
      ),
      // Opacity drives the alpha channel of the active stroke colour.
      // Re-uses the colour-picker pathway ([setStrokeColor]) so undo,
      // recents, and layer-mirroring all keep working unchanged — the
      // slider is a faster surface for the same setter the picker calls.
      'opacity': SliderSubTool(
        headerTitle: context.l10n.opacityLabel,
        headerIcon: Icons.opacity_rounded,
        min: 0,
        max: 100,
        // Three plain-language steps cover ≥95% of intents.
        presets: const [25, 60, 100],
        presetLabels: [
          context.l10n.lightOption,
          context.l10n.normalOption,
          context.l10n.strongOption,
        ],
        readValue: (ref) {
          final c = ref.watch(paintToolControllerProvider).strokeColor;
          return (c.a * 100).clamp(0.0, 100.0);
        },
        writeValue: (ref, v) {
          final session = ref.read(paintToolControllerProvider);
          final next = session.strokeColor.withValues(
            alpha: (v / 100).clamp(0.0, 1.0),
          );
          ref.read(paintToolControllerProvider.notifier).setStrokeColor(next);
        },
        format: (v) => '${v.round()}%',
        leadingBuilder: (context, value) {
          // Mini swatch preview at the live opacity — instant proof
          // of what the stroke will look like before release.
          final session = ProviderScope.containerOf(
            context,
          ).read(paintToolControllerProvider);
          final c = session.strokeColor.withValues(
            alpha: (value / 100).clamp(0.0, 1.0),
          );
          return Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTokens.of(context).border.withValues(alpha: 0.6),
                width: 1,
              ),
            ),
          );
        },
      ),
    };
