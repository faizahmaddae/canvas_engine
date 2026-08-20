import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/editor_value_format.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../application/document_controller.dart';
import '../../application/mask_edit_controller.dart';
import '../../engine/commands/image_commands.dart';
import '../../engine/core/layer_mask.dart';
import '../../engine/effects/editor_effect.dart';
import '../../engine/modules/image/image_layer.dart';
import '../application/image_tool_controller.dart';
import 'image_panel_shell.dart';
import '../../../../app/theme/app_icons.dart';

/// Expanded panel body for the Image sub-tool's "Effects" tab.
///
/// Surface for the layer's [EffectStack]: drag-to-reorder, tap to
/// toggle enabled, swipe / trailing button to delete, tap-to-edit
/// jumps to the originating panel (Adjust today; future per-effect
/// edit sheets land here without changing the data path).
///
/// All three structural mutations route through the engine commands
/// added in Phase 3 Step 2:
///   * [ReorderEffectCommand]   — drag handle
///   * [ToggleEffectEnabledCommand] — eyeball
///   * [DeleteEffectCommand]    — trash button
///
/// Display order matches `EffectStack.effects` index — bottom of the
/// list is the first applied (`effects[0]`), top of the list is the
/// last applied (`effects[last]`). That matches the Photoshop /
/// Lightroom adjustment-stack convention so users with that mental
/// model don't have to invert anything.
class ImageEffectsBody extends ConsumerWidget {
  const ImageEffectsBody({super.key, required this.layer});

  final ImageLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effects = layer.effects.effects;
    return ImagePanelShell(
      title: context.l10n.effectsTool,
      icon: AppIcons.effects,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (effects.isEmpty)
            const _EmptyState()
          else
            _EffectList(layer: layer),
          // The mask is subordinate to the stack: over an empty stack
          // its preset chips and "Adjust region" would open a session
          // with nothing to mask — the same precondition the strip's
          // «انتخابی» tile guards (P3-10), enforced here too so the
          // two entries to one session cannot carry opposite rules.
          // Same grammar as the effect list itself: the gated section
          // hides and [_EmptyState] names the recovery ("Open Look…").
          // EXCEPT while a mask still exists: [DeleteEffectCommand]
          // deliberately keeps the stack mask when the last effect is
          // deleted (it is user state), so the section stays visible
          // then — hiding it would leave the mask set but sightless,
          // with no control anywhere to see or clear it.
          if (effects.isNotEmpty || layer.effects.stackMask != null)
            _StackMaskSection(layer: layer),
        ],
      ),
    );
  }
}

/// Region presets for the stack mask. Placeholder UX for A3: preset
/// rects exercise the full command → render path today; on-canvas
/// mask-shape editing (drag the rect, live-merged commands) is the
/// roadmap Phase 3.2 replacement and needs no data change.
enum _MaskPreset { off, top, bottom, center }

class _StackMaskSection extends ConsumerWidget {
  const _StackMaskSection({required this.layer});

  final ImageLayer layer;

  /// Build the preset's mask in layer-local space (LayerMask's
  /// contract). Feather = 15% of the shorter side: wide enough that
  /// the region edge reads as a gradient, not a hard seam, on any
  /// layer size — a presentation tuning choice, not engine math.
  ///
  /// Clamped to [LayerMask.maxFeatherPx], which the engine asserts on.
  /// 15% of the short side passes 256px once the layer is ~1707px
  /// across — which the shipped A4-300dpi preset (2480×3508) reaches
  /// on its own, so a full-bleed photo there tripped the assert rather
  /// than applying the preset. `mask_edit_controller` already clamps
  /// at both of its call sites; this was the one that did not.
  LayerMask? _maskFor(_MaskPreset preset) {
    final s = layer.transform.size;
    final feather = (math.min(s.width, s.height) * 0.15).clamp(
      0.0,
      LayerMask.maxFeatherPx,
    );
    return switch (preset) {
      _MaskPreset.off => null,
      _MaskPreset.top => RectMask(
        rect: Rect.fromLTWH(0, 0, s.width, s.height / 2),
        feather: feather,
      ),
      _MaskPreset.bottom => RectMask(
        rect: Rect.fromLTWH(0, s.height / 2, s.width, s.height / 2),
        feather: feather,
      ),
      _MaskPreset.center => RectMask(
        rect: Rect.fromLTWH(
          s.width * 0.15,
          s.height * 0.15,
          s.width * 0.7,
          s.height * 0.7,
        ),
        feather: feather,
      ),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final current = layer.effects.stackMask;
    // An on-canvas edit usually produces a mask matching no preset —
    // without an explicit Custom state every chip would silently
    // deselect and the section would read as "off".
    final isCustom =
        current != null &&
        !_MaskPreset.values.any((p) => _maskFor(p) == current);

    String labelFor(_MaskPreset p) => switch (p) {
      _MaskPreset.off => context.l10n.maskPresetOff,
      _MaskPreset.top => context.l10n.maskPresetTop,
      _MaskPreset.bottom => context.l10n.maskPresetBottom,
      _MaskPreset.center => context.l10n.maskPresetCenter,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.selectiveMaskLabel,
            style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            context.l10n.selectiveMaskHint,
            style: tt.bodySmall?.copyWith(
              color: AppTokens.of(context).textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final preset in _MaskPreset.values)
                ChoiceChip(
                  label: Text(labelFor(preset)),
                  visualDensity: VisualDensity.compact,
                  selected: current == _maskFor(preset),
                  onSelected: (_) {
                    EditorHaptics.tap();
                    ref
                        .read(documentControllerProvider.notifier)
                        .execute(
                          SetStackMaskCommand(
                            layerId: layer.id,
                            mask: _maskFor(preset),
                          ),
                        );
                  },
                ),
              if (isCustom)
                ChoiceChip(
                  label: Text(context.l10n.maskPresetCustom),
                  visualDensity: VisualDensity.compact,
                  selected: true,
                  // Read-only marker: tapping re-opens the editor.
                  onSelected: (_) => _openMaskEditor(ref),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonalIcon(
              onPressed: () => _openMaskEditor(ref),
              icon: const Icon(AppIcons.freeRegion, size: 18),
              label: Text(context.l10n.adjustRegionAction),
            ),
          ),
        ],
      ),
    );
  }

  void _openMaskEditor(WidgetRef ref) {
    EditorHaptics.tap();
    // The mode's chrome replaces the panel — close it first so the
    // dock isn't left open underneath (the mode hides the dock, but
    // leaving openSlot set would re-mount the panel on exit, which
    // is actually what we want: Done/Cancel returns the user here).
    ref
        .read(maskEditControllerProvider.notifier)
        .open(layer.id, priorSelectionId: layer.id);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.lookTool, size: 28, color: tokens.textSecondary),
          const SizedBox(height: 8),
          Text(
            context.l10n.noEffectsApplied,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            context.l10n.openLookToAddEffectHint,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _EffectList extends ConsumerWidget {
  const _EffectList({required this.layer});

  final ImageLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // We render the list visually top-down (most-recently-applied
    // first) because that matches every photo-editor users have
    // touched. The underlying `effects` list is bottom-up
    // (effects[0] = first applied), so the visual ↔ data mapping
    // is `dataIndex = length - 1 - visualIndex`.
    final effects = layer.effects.effects;
    final length = effects.length;
    int toData(int visual) => length - 1 - visual;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: ReorderableListView.builder(
        shrinkWrap: true,
        buildDefaultDragHandles: false,
        physics: const ClampingScrollPhysics(),
        itemCount: length,
        itemBuilder: (context, visual) {
          final dataIndex = toData(visual);
          final effect = effects[dataIndex];
          return _EffectRow(
            key: ValueKey('effect-row-$dataIndex-${effect.type}'),
            visualIndex: visual,
            dataIndex: dataIndex,
            effect: effect,
            layer: layer,
          );
        },
        onReorder: (oldVisual, newVisual) {
          // ReorderableListView reports newVisual as the index AFTER
          // the item is removed for indices > oldVisual. Convert
          // back to a stable destination index in the data list.
          var fromVisual = oldVisual;
          var toVisual = newVisual;
          if (toVisual > fromVisual) toVisual -= 1;
          final fromData = toData(fromVisual);
          final toData2 = toData(toVisual);
          if (fromData == toData2) return;
          EditorHaptics.tap();
          ref
              .read(documentControllerProvider.notifier)
              .execute(
                ReorderEffectCommand(
                  layerId: layer.id,
                  oldIndex: fromData,
                  newIndex: toData2,
                ),
              );
        },
      ),
    );
  }
}

class _EffectRow extends ConsumerWidget {
  const _EffectRow({
    super.key,
    required this.visualIndex,
    required this.dataIndex,
    required this.effect,
    required this.layer,
  });

  final int visualIndex;
  final int dataIndex;
  final EditorEffect effect;
  final ImageLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final view = effectDisplay(context, effect);
    final dim = !effect.enabled;
    final tt = Theme.of(context).textTheme;

    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Material(
        color: tokens.surfaceMuted.withValues(alpha: dim ? 0.4 : 1),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            EditorHaptics.tap();
            // Tap-to-edit: jump to the panel that owns this effect
            // type. Today both colour-matrix and vignette live in
            // Look; per-effect edit sheets land here later with
            // no engine change required.
            ref
                .read(imageToolControllerProvider.notifier)
                .toggleSlot(ImageToolSlot.look);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: visualIndex,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      AppIcons.dragHandle,
                      size: 18,
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  view.icon,
                  size: 18,
                  color: dim ? tokens.textSecondary : tokens.accentText,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        view.name,
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: dim
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          color: dim
                              ? tokens.textSecondary
                              : tokens.textPrimary,
                        ),
                      ),
                      if (view.summary.isNotEmpty)
                        // Pinned LTR. Summaries are numeric runs with a
                        // leading sign and a trailing unit, both of
                        // which are bidi-neutral: unpinned in this RTL
                        // row «+۵۰٪» painted as «۵۰٪+», with the sign
                        // stranded on the far side of the digits. The
                        // widget-level pin is preferred over LRI/PDI
                        // because no bundled family, Vazir included,
                        // carries glyphs for those codepoints — see
                        // EditorValueFormat.dimensionsPlain.
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            view.summary,
                            style: tt.bodySmall?.copyWith(
                              color: tokens.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: effect.enabled
                      ? context.l10n.hideAction
                      : context.l10n.showAction,
                  icon: Icon(
                    effect.enabled ? AppIcons.visible : AppIcons.hidden,
                    size: 18,
                  ),
                  onPressed: () {
                    EditorHaptics.toggle();
                    ref
                        .read(documentControllerProvider.notifier)
                        .execute(
                          ToggleEffectEnabledCommand(
                            layerId: layer.id,
                            index: dataIndex,
                          ),
                        );
                  },
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: context.l10n.deleteAction,
                  icon: const Icon(AppIcons.delete, size: 18),
                  onPressed: () {
                    EditorHaptics.tap();
                    ref
                        .read(documentControllerProvider.notifier)
                        .execute(
                          DeleteEffectCommand(
                            layerId: layer.id,
                            index: dataIndex,
                          ),
                        );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Presentation-layer view-model for an [EditorEffect] row.
/// Lives here (not on the engine type) because icon + display strings
/// are presentation concerns; the engine stays Material-free.
class EffectDisplay {
  const EffectDisplay({
    required this.icon,
    required this.name,
    required this.summary,
  });
  final IconData icon;
  final String name;
  final String summary;
}

EffectDisplay effectDisplay(BuildContext context, EditorEffect e) =>
    switch (e) {
      BrightnessEffect(:final amount) => EffectDisplay(
        icon: AppIcons.brightness,
        name: context.l10n.brightnessLabel,
        summary: EditorValueFormat.of(context).signedPlain(amount),
      ),
      ContrastEffect(:final amount) => EffectDisplay(
        icon: AppIcons.contrast,
        name: context.l10n.contrastLabel,
        summary: EditorValueFormat.of(
          context,
        ).signedPercent(((amount - 1) * 100).round()),
      ),
      SaturationEffect(:final amount) => EffectDisplay(
        icon: AppIcons.saturation,
        name: context.l10n.saturationLabel,
        summary: EditorValueFormat.of(
          context,
        ).signedPercent(((amount - 1) * 100).round()),
      ),
      ExposureEffect(:final amount) => EffectDisplay(
        icon: AppIcons.exposure,
        name: context.l10n.exposureLabel,
        summary: EditorValueFormat.of(context).signedPlain(amount),
      ),
      WarmthEffect(:final amount) => EffectDisplay(
        icon: AppIcons.warmthEffect,
        name: context.l10n.warmthLabel,
        summary: EditorValueFormat.of(context).signedPlain(amount),
      ),
      VignetteEffect(:final intensity) => EffectDisplay(
        icon: AppIcons.vignette,
        name: context.l10n.vignetteLabel,
        summary: EditorValueFormat.of(
          context,
        ).percent((intensity * 100).round()),
      ),
      UnknownEffect() => EffectDisplay(
        // Forward-compat carrier for an effect type written by a
        // newer build than this binary understands. The codec
        // preserves its raw JSON so resaving doesn't drop data;
        // surface a generic row in the panel so the user can see
        // (and remove) the entry instead of a crash or silent gap.
        icon: AppIcons.unknownEffect,
        name: context.l10n.unknownEffectLabel(e.type),
        summary: context.l10n.inactiveLabel,
      ),
    };
