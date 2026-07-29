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
import '../../engine/commands/editor_command.dart';
import '../../engine/commands/image_commands.dart';
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
