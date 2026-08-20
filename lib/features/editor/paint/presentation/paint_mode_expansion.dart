// Extracted verbatim from paint_mode_toolbar.dart (tb1 5/17); behaviour-preserving.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
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
import '../../../../core/utils/editor_value_format.dart';
import '../../../../app/theme/app_icons.dart';

/// In-dock sheet panel for paint mode. Routes [PaintSession.openSlot]
/// → its body and renders it inside the dock's `expanded` slot with
/// [DockSheetChrome]. Mirrors `TextModeSheetPanel`.
class PaintModeInlineExpansion extends ConsumerWidget {
  const PaintModeInlineExpansion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(paintToolControllerProvider);
    final view = ref.watch(paintStyleViewProvider);
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
          headerIcon: isPicker ? AppIcons.drawTool : spec.icon,
          builder: (ctx, _) => _buildPaintBody(ctx, openId, view),
        );
    final scopedSubTool = _PaintScopedSubTool(
      delegate: subTool,
      scopeLabel: openId == 'tool' || !view.isRestyling
          ? context.l10n.nextStrokeScope
          : context.l10n.editingStrokeScope,
    );

    final ids = PaintModeToolbar.toolIdsFor(
      tool: view.isRestyling ? null : session.activeTool,
      layerKind: view.layerKind,
    );
    // Single-list, no exclusions — [SiblingSwipeStrategy] handles
    // wrap-around and the single-slot "swipe is a no-op" case so
    // we don't have to special-case it here.
    final swipe = SiblingSwipeStrategy<String>(order: ids);
    final prevId = swipe.prev(openId);
    final nextId = swipe.next(openId);

    return SubToolSheet(
      subTool: scopedSubTool,
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
    PaintStyleView view,
  ) {
    switch (openId) {
      case 'tool':
        return const PaintToolBody();
      case 'color':
        return PaintColorBody(current: view.strokeColor);
      case 'fill':
        return PaintFillBody(view: view);
      case 'polygon':
        return PaintPolygonBody(view: view);
      case 'dash':
        return const PaintDashBody();
      case 'size':
        return PaintSizeEntryBody(view: view);
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Paint controls have two honest destinations: defaults for the next
/// stroke, or the selected stroke itself. Keeping that scope visible in
/// every body prevents a colour/size edit from feeling global when it
/// is actually a restyle (and vice versa).
class _PaintScopedSubTool extends SubTool {
  const _PaintScopedSubTool({required this.delegate, required this.scopeLabel});

  final SubTool delegate;
  final String scopeLabel;

  @override
  String get headerTitle => delegate.headerTitle;

  @override
  IconData get headerIcon => delegate.headerIcon;

  @override
  String? get headerValue => delegate.headerValue;

  @override
  double get maxHeightFraction => delegate.maxHeightFraction;

  @override
  bool get supportsSiblingSwipe => delegate.supportsSiblingSwipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Semantics(
            container: true,
            label: scopeLabel,
            child: ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Text(
                    scopeLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: tokens.accentText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        delegate.build(context, ref),
      ],
    );
  }
}

/// Stroke-width body. Preset chips above a "Fine tune" slider with
/// a dot preview that grows/shrinks live.
/// Phase 2 registry: paint slots whose body is a generic
/// preset+slider. New numeric tools should be added here, not as
/// new private body widgets.
Map<String, SubTool> _paintSliderSubTools(
  BuildContext context,
) => <String, SubTool>{
  'blur': SliderSubTool(
    headerTitle: context.l10n.blurLabel,
    headerIcon: AppIcons.blur,
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
    readValue: (ref) => ref.watch(paintStyleViewProvider).blurRadius,
    previewValue: (ref, v) =>
        ref.read(paintToolControllerProvider.notifier).previewBlurRadius(v),
    writeValue: (ref, v) =>
        ref.read(paintToolControllerProvider.notifier).commitBlurRadius(v),
    format: (v) => EditorValueFormat.of(context).digits(v.round()),
  ),
  // Opacity drives the alpha channel of the active stroke colour.
  // Re-uses the colour-picker pathway ([setStrokeColor]) so undo,
  // recents, and layer-mirroring all keep working unchanged — the
  // slider is a faster surface for the same setter the picker calls.
  'opacity': SliderSubTool(
    headerTitle: context.l10n.strokeOpacityLabel,
    headerIcon: AppIcons.opacity,
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
      final c = ref.watch(paintStyleViewProvider).strokeColor;
      return (c.a * 100).clamp(0.0, 100.0);
    },
    previewValue: (ref, v) =>
        ref.read(paintToolControllerProvider.notifier).previewStrokeOpacity(v),
    writeValue: (ref, v) =>
        ref.read(paintToolControllerProvider.notifier).commitStrokeOpacity(v),
    format: (v) => EditorValueFormat.of(context).percent(v.round()),
    leadingBuilder: (context, value) {
      // Mini swatch preview at the live opacity — instant proof
      // of what the stroke will look like before release.
      final c = ProviderScope.containerOf(context)
          .read(paintStyleViewProvider)
          .strokeColor
          .withValues(alpha: (value / 100).clamp(0.0, 1.0));
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
