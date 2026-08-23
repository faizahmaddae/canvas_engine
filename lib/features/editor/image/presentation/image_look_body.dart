import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/editor_value_format.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../../color_picker/presentation/color_picker_sheet.dart';
import '../../application/document_controller.dart';
import '../../application/live_overlay_controller.dart';
import '../../application/mask_edit_controller.dart';
import '../../engine/commands/editor_command.dart';
import '../../engine/commands/image_commands.dart';
import '../../engine/core/layer_mask.dart';
import '../../engine/effects/editor_effect.dart';
import '../../engine/modules/image/image_layer.dart';
import '../../engine/modules/image/image_source_provider.dart';
import '../../ui/editor_slider_row.dart';
import '../../ui/precision_disclosure.dart';
import 'image_panel_shell.dart';
import '../../../../app/theme/app_icons.dart';

/// The Image dock's «Look» panel — the one surface that owns how a
/// photo is graded (tb4 1/14).
///
/// It replaces three panels that all claimed the same job: Style
/// (preset tiles writing brightness/contrast/saturation), Adjust
/// (five sliders plus a second, differently-valued preset row) and
/// Filters (the colour-matrix preset row). Two of those three wrote
/// the SAME adjustment fields with different curated numbers, so a
/// Style tile silently wiped an Adjust preset and vice versa, and
/// neither told the user why.
///
/// What survives is the pair that genuinely composes in the
/// renderer: the FILTER preset (an independent matrix applied to the
/// raw pixels) as the preset row, and the adjustment sliders as the
/// fine-tune disclosure applied after it. See `ImageLayer.build` —
/// filter first, then the effect stack.
///
/// The rules that follow from that, and which the panel guarantees:
///   * «بدون» / None resets the FILTER only. It never touches the
///     user's slider values.
///   * Fine-tuning never resets the preset row.
///   * Both channels compose, in that order.
///
/// Engine semantics are unchanged — no document migration, no new
/// fields, no new render cost. Only the surface was merged.
class ImageLookBody extends ConsumerStatefulWidget {
  const ImageLookBody({super.key, required this.layer});

  final ImageLayer layer;

  @override
  ConsumerState<ImageLookBody> createState() => _ImageLookBodyState();
}

class _ImageLookBodyState extends ConsumerState<ImageLookBody> {
  // ─── Contract §2 slider preview channel ─────────────────────────
  //
  // The pending command is the exact command release will execute;
  // each tick APPLIES it to the committed doc and stages the result
  // on the overlay, so preview == commit by construction.
  // `EditorSliderRow.onDragEnd` also fires on pointer-cancel, so an
  // interrupted drag (system gesture, app pause cancelling touches)
  // still commits the last previewed value (§7 pause policy).
  EditorCommand? _pendingSliderCommand;

  void _previewSlider(EditorCommand cmd) {
    _pendingSliderCommand = cmd;
    final doc = ref.read(documentControllerProvider);
    final preview = cmd.apply(doc).layerById(widget.layer.id);
    if (preview != null) {
      ref.read(liveOverlayProvider.notifier).replaceLayer(preview);
    }
  }

  void _commitSlider() {
    final cmd = _pendingSliderCommand;
    _pendingSliderCommand = null;
    if (cmd == null) return;
    // Clear-then-execute in one synchronous run (same pattern as
    // text's commitLiveEdit): the next frame renders committed(new)
    // + empty overlay, so there is no flash-back frame and the
    // engine's overlay effect cache drops with the overlay.
    ref.read(liveOverlayProvider.notifier).clear();
    ref.read(documentControllerProvider.notifier).execute(cmd);
  }

  @override
  void dispose() {
    // Mid-drag teardown without a pointer event (panel unmounted
    // programmatically) discards the preview, mirroring the
    // canonical opacity template. Real interruptions arrive as
    // pointer-cancel and commit via onDragEnd before dispose.
    if (_pendingSliderCommand != null) {
      ref.read(liveOverlayProvider.notifier).clear();
    }
    super.dispose();
  }

  /// Preset taps stay discrete non-live commands so each tap is its
  /// own undoable action (contract §3).
  void _applyFilter(ImageFilterPreset p) {
    EditorHaptics.toggle();
    ref
        .read(documentControllerProvider.notifier)
        .execute(
          SetImageFilterCommand(layerId: widget.layer.id, filterPreset: p),
        );
  }

  @override
  Widget build(BuildContext context) {
    final layer = widget.layer;
    final adj = layer.adjustments;
    final vignette = _activeVignette(layer);
    final fmt = EditorValueFormat.of(context);

    // Resolve the live image once at the body level so each chip
    // reuses the same ImageProvider — Flutter dedupes the decode
    // and the 7 chips share one cached bitmap (cap 128px wide,
    // independent of canvas resolution).
    final provider = imageProviderFor(layer.source);

    return ImagePanelShell(
      title: context.l10n.lookTool,
      icon: AppIcons.lookTool,
      // The active preset IS the panel's value — the prototype's
      // header chip read the current state of whatever the panel owns.
      headerValue: _filterLabel(context, layer.filterPreset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header already says "Look" — no duplicate SectionLabel.
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              // Trailing inset (16dp) lets the last chip's bg pill +
              // its hover tint scroll fully clear of the trailing
              // edge of the panel.
              padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 16, 0),
              itemCount: _allPresets.length,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (context, i) {
                final p = _allPresets[i];
                return _FilterChip(
                  preset: p,
                  imageProvider: provider,
                  selected: layer.filterPreset == p,
                  onTap: () => _applyFilter(p),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          PrecisionDisclosure(
            compact: true,
            icon: AppIcons.precisionAdjust,
            titleClosed: context.l10n.adjustPrecisely,
            subtitle: context.l10n.adjustPreciselySubtitle,
            children: [
              const SizedBox(height: 4),
              EditorSliderRow(
                label: context.l10n.brightnessLabel,
                labelWidth: 80,
                readoutWidth: 48,
                value: adj.brightness,
                min: -100,
                max: 100,
                origin: 0,
                format: fmt.signedPlain,
                onChanged: (v) => _previewSlider(
                  SetImageAdjustmentsCommand(layerId: layer.id, brightness: v),
                ),
                onDragEnd: _commitSlider,
              ),
              EditorSliderRow(
                label: context.l10n.contrastLabel,
                labelWidth: 80,
                readoutWidth: 48,
                value: adj.contrast,
                min: 0,
                max: 2,
                origin: 1,
                format: (v) => fmt.signedPercent(((v - 1) * 100).round()),
                onChanged: (v) => _previewSlider(
                  SetImageAdjustmentsCommand(layerId: layer.id, contrast: v),
                ),
                onDragEnd: _commitSlider,
              ),
              EditorSliderRow(
                label: context.l10n.saturationLabel,
                labelWidth: 80,
                readoutWidth: 48,
                value: adj.saturation,
                min: 0,
                max: 2,
                origin: 1,
                format: (v) => fmt.signedPercent(((v - 1) * 100).round()),
                onChanged: (v) => _previewSlider(
                  SetImageAdjustmentsCommand(layerId: layer.id, saturation: v),
                ),
                onDragEnd: _commitSlider,
              ),
              EditorSliderRow(
                label: context.l10n.exposureLabel,
                labelWidth: 80,
                readoutWidth: 48,
                value: adj.exposure,
                min: -100,
                max: 100,
                origin: 0,
                format: fmt.signedPlain,
                onChanged: (v) => _previewSlider(
                  SetImageAdjustmentsCommand(layerId: layer.id, exposure: v),
                ),
                onDragEnd: _commitSlider,
              ),
              EditorSliderRow(
                label: context.l10n.warmthLabel,
                labelWidth: 80,
                readoutWidth: 48,
                value: adj.warmth,
                min: -100,
                max: 100,
                origin: 0,
                format: fmt.signedPlain,
                onChanged: (v) => _previewSlider(
                  SetImageAdjustmentsCommand(layerId: layer.id, warmth: v),
                ),
                onDragEnd: _commitSlider,
              ),
            ],
          ),
          // Vignette is the first non-colour-matrix effect on the
          // layer's effect stack — it lives in the same panel as
          // the colour adjustments because users think of it as
          // "one of the knobs", not as a separate tool.
          PrecisionDisclosure(
            compact: true,
            icon: AppIcons.vignette,
            titleClosed: context.l10n.vignetteLabel,
            subtitle: context.l10n.vignetteSubtitle,
            children: [
              const SizedBox(height: 4),
              EditorSliderRow(
                label: context.l10n.intensityLabel,
                labelWidth: 80,
                readoutWidth: 48,
                value: vignette.intensity,
                min: VignetteEffect.minIntensity,
                max: VignetteEffect.maxIntensity,
                format: (v) => fmt.percent((v * 100).round()),
                onChanged: (v) => _previewSlider(
                  SetImageVignetteCommand(layerId: layer.id, intensity: v),
                ),
                onDragEnd: _commitSlider,
              ),
              EditorSliderRow(
                label: context.l10n.featherLabel,
                labelWidth: 80,
                readoutWidth: 48,
                value: vignette.feather,
                min: VignetteEffect.minFeather,
                max: VignetteEffect.maxFeather,
                format: (v) => fmt.percent((v * 100).round()),
                onChanged: (v) => _previewSlider(
                  SetImageVignetteCommand(layerId: layer.id, feather: v),
                ),
                onDragEnd: _commitSlider,
              ),
              const SizedBox(height: 8),
              // The shared two-level picker, embedded. Contract §2
              // (tb2 5/16): drags stage overlay previews via the
              // same channel as the sliders above; the settled
              // change commits ONE undoable command. Recents and
              // alpha policy live inside the picker.
              ColorPickerBody(
                initial: vignette.color,
                title: context.l10n.vignetteColorTitle,
                onChanged: (c) => _previewSlider(
                  SetImageVignetteCommand(layerId: layer.id, color: c),
                ),
                onCommitted: (_) => _commitSlider(),
              ),
            ],
          ),
          // ── The stack the knobs above create ──────────────────
          // These two sections lived in a separate «جلوه‌ها» panel
          // whose empty state redirected here — two tiles, one
          // concept. Inside Look the list needs no empty state (an
          // empty stack simply shows nothing below the knobs), and
          // the mask section sits physically under the effects it
          // masks, so its precondition is visible instead of
          // narrated by a strip snackbar.
          if (layer.effects.effects.isNotEmpty)
            _AppliedEffectsSection(layer: layer),
          // The mask stays subordinate to the stack: hidden while
          // there is nothing to mask — EXCEPT while a mask survives
          // deleting the last effect (DeleteEffectCommand keeps it
          // as user state), when this is the only control that can
          // see or clear it (P3-10).
          if (layer.effects.effects.isNotEmpty ||
              layer.effects.stackMask != null)
            _StackMaskSection(layer: layer),
        ],
      ),
    );
  }
}

/// Resolve the vignette currently on the layer's effect stack, or
/// fall back to the identity defaults so the sliders always have
/// a value to render. The renderer treats an identity vignette as
/// "no effect" — see [SetImageVignetteCommand] for the round-trip
/// guarantee.
VignetteEffect _activeVignette(ImageLayer layer) {
  for (final eff in layer.effects.effects) {
    if (eff is VignetteEffect) return eff;
  }
  return const VignetteEffect(
    intensity: VignetteEffect.defaultIntensity,
    feather: VignetteEffect.defaultFeather,
  );
}

const _allPresets = <ImageFilterPreset>[
  ImageFilterPreset.none,
  ImageFilterPreset.warm,
  ImageFilterPreset.cool,
  ImageFilterPreset.vintage,
  ImageFilterPreset.mono,
  ImageFilterPreset.fade,
  ImageFilterPreset.dramatic,
];

String _filterLabel(BuildContext context, ImageFilterPreset preset) {
  return switch (preset) {
    ImageFilterPreset.none => context.l10n.noneOption,
    ImageFilterPreset.warm => context.l10n.warmOption,
    ImageFilterPreset.cool => context.l10n.coolOption,
    ImageFilterPreset.vintage => context.l10n.vintageOption,
    ImageFilterPreset.mono => context.l10n.monoOption,
    ImageFilterPreset.fade => context.l10n.fadeOption,
    ImageFilterPreset.dramatic => context.l10n.dramaOption,
  };
}

class _FilterChip extends StatefulWidget {
  const _FilterChip({
    required this.preset,
    required this.imageProvider,
    required this.selected,
    required this.onTap,
  });

  final ImageFilterPreset preset;
  final ImageProvider? imageProvider;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final selected = widget.selected;
    final matrix = imageFilterMatrix(widget.preset);

    // Unified grammar with DockToolTile / preset chips: a single bg
    // channel drives hover + pressed + selected so all three states
    // share identical bounds. No glow, no outer ring.
    Color bg;
    if (selected) {
      bg = tokens.accent.withValues(alpha: _down ? 0.18 : 0.12);
    } else if (_down) {
      bg = tokens.accent.withValues(alpha: 0.10);
    } else if (_hover) {
      bg = tokens.textPrimary.withValues(alpha: 0.06);
    } else {
      bg = Colors.transparent;
    }
    // Glyph stop. The fill saffron put the SELECTED preset's label —
    // the one word saying which filter is on — at 2.61:1.
    final fg = selected ? tokens.accentText : tokens.textSecondary;

    // Real-image preview. Decoded at 128px via cacheWidth so memory
    // stays tiny regardless of source resolution. Falls back to a
    // tasteful gradient if the source isn't decodable yet (e.g.
    // network not loaded) — chips remain meaningful.
    Widget preview;
    if (widget.imageProvider != null) {
      preview = Image(
        image: ResizeImage(widget.imageProvider!, width: 128),
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _gradientFallback(),
      );
    } else {
      preview = _gradientFallback();
    }
    if (matrix != null) {
      preview = ColorFiltered(
        colorFilter: ColorFilter.matrix(matrix),
        child: preview,
      );
    }

    // Role + selected state, and the visual subtree excluded so the
    // thumbnail and caption don't concatenate onto the node. Same
    // shape as `PresetChip`; without it the Filter tool's primary
    // control announced as a plain ImageView and a screen reader could
    // not tell which look was applied (WCAG 4.1.2, Level A).
    return Semantics(
      button: true,
      selected: widget.selected,
      label: _filterLabel(context, widget.preset),
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _down = true),
            onTapCancel: () => setState(() => _down = false),
            onTapUp: (_) => setState(() => _down = false),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(14),
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                focusColor: Colors.transparent,
                child: AnimatedContainer(
                  duration: AppMotion.standard,
                  curve: AppMotion.curve,
                  width: 62,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Thumbnail with optional ✓ badge inset in the
                      // corner. Inset (not -2 overhang) so the selected
                      // chip occupies the *exact* same bounds as every
                      // other chip — no apparent height lift.
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 52,
                              height: 52,
                              child: preview,
                            ),
                          ),
                          // Subtle hairline so the thumb edge still
                          // reads on very light/dark images.
                          Positioned.fill(
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: tokens.border.withValues(
                                      alpha: 0.45,
                                    ),
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (selected)
                            PositionedDirectional(
                              end: 4,
                              bottom: 4,
                              child: _SelectedBadge(tokens: tokens),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _filterLabel(context, widget.preset),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: fg,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _gradientFallback() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFFFB36B),
            Color(0xFFE05A8A),
            Color(0xFF4A6CF7),
          ],
        ),
      ),
    );
  }
}

/// Small ✓ badge anchored to the thumbnail corner so the active
/// filter is unmistakable even at a glance, on busy images.
class _SelectedBadge extends StatelessWidget {
  const _SelectedBadge({required this.tokens});
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: tokens.accent,
        shape: BoxShape.circle,
        border: Border.all(color: tokens.surface, width: 1.5),
      ),
      child: Icon(AppIcons.confirm, size: 10, color: tokens.onBrand),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Applied-effects list — moved here from the retired Effects panel
// ─────────────────────────────────────────────────────────────────

/// The layer's [EffectStack] as a managed list: drag-to-reorder,
/// eyeball to toggle, trash to delete. All three mutations route
/// through the Phase 3 Step 2 engine commands ([ReorderEffectCommand],
/// [ToggleEffectEnabledCommand], [DeleteEffectCommand]).
///
/// Display order matches `EffectStack.effects` index — bottom of the
/// list is the first applied, top the last — the Photoshop /
/// Lightroom stack convention.
class _AppliedEffectsSection extends StatelessWidget {
  const _AppliedEffectsSection({required this.layer});

  final ImageLayer layer;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.effectsTool,
            style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          _EffectList(layer: layer),
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
    // Rendered visually top-down (most-recently-applied first); the
    // underlying `effects` list is bottom-up (effects[0] = first
    // applied), so the visual ↔ data mapping is
    // `dataIndex = length - 1 - visualIndex`.
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

    // No row-level tap: the panel this row used to jump to is the
    // panel it now lives in. The row's verbs are its own controls.
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Material(
        color: tokens.surfaceMuted.withValues(alpha: dim ? 0.4 : 1),
        borderRadius: BorderRadius.circular(10),
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
                        color: dim ? tokens.textSecondary : tokens.textPrimary,
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

// ─────────────────────────────────────────────────────────────────
// Selective mask — moved here from the retired Effects panel
// ─────────────────────────────────────────────────────────────────

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
    // The mask-edit mode's chrome replaces the dock; openSlot stays
    // set on purpose so Done/Cancel returns the user to this panel.
    ref
        .read(maskEditControllerProvider.notifier)
        .open(layer.id, priorSelectionId: layer.id);
  }
}
