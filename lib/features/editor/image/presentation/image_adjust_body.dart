import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../../color_picker/presentation/color_picker_sheet.dart';
import '../../application/document_controller.dart';
import '../../application/live_overlay_controller.dart';
import '../../engine/commands/editor_command.dart';
import '../../engine/commands/image_commands.dart';
import '../../engine/effects/editor_effect.dart';
import '../../engine/modules/image/image_layer.dart';
import '../../toolbar/presentation/widgets/preset_chip.dart';
import '../../ui/editor_slider_row.dart';
import '../../ui/precision_disclosure.dart';
import 'image_panel_shell.dart';
import '../../../../core/utils/editor_value_format.dart';

/// Expanded panel body for the Image sub-tool's "Adjust" tab.
///
/// Layout mirrors Border / Shadow so the three style panels read as
/// one system:
///   * **Preset chips** (Original / Pop / Soft / Warm / Cool) cover
///     the 95% case — one tap dials in tasteful brightness +
///     contrast + saturation values without the user touching a
///     slider.
///   * **Adjust precisely** disclosure exposes the underlying
///     brightness (-100..100), contrast (0..200%), saturation
///     (0..200%), exposure (-100..100), and warmth (-100..100)
///     sliders for power-users.
///
/// Slider drags follow the interaction contract's §2 preview
/// channel: every tick stages a preview on [liveOverlayProvider]
/// (zero committed writes mid-drag) and release/cancel commits ONE
/// non-live command — each drag is structurally one undo entry.
/// Preset taps stay discrete non-live commands so each tap is its
/// own undoable action (§3). The vignette colour picker rides the
/// same overlay channel as the sliders (tb2 5/16).
///
/// Every change goes through [SetImageAdjustmentsCommand] so undo
/// / redo always works, and Replace-image (and every other Image
/// command) preserves the layer's current adjustments.
class ImageAdjustBody extends ConsumerStatefulWidget {
  const ImageAdjustBody({super.key, required this.layer});

  final ImageLayer layer;

  @override
  ConsumerState<ImageAdjustBody> createState() => _ImageAdjustBodyState();
}

class _ImageAdjustBodyState extends ConsumerState<ImageAdjustBody> {
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

  void _commit({
    double? brightness,
    double? contrast,
    double? saturation,
    double? exposure,
    double? warmth,
  }) {
    ref
        .read(documentControllerProvider.notifier)
        .execute(
          SetImageAdjustmentsCommand(
            layerId: widget.layer.id,
            brightness: brightness,
            contrast: contrast,
            saturation: saturation,
            exposure: exposure,
            warmth: warmth,
          ),
        );
  }

  void _applyPreset(_AdjustPreset p) {
    EditorHaptics.toggle();
    _commit(
      brightness: p.brightness,
      contrast: p.contrast,
      saturation: p.saturation,
      exposure: p.exposure,
      warmth: p.warmth,
    );
  }

  @override
  Widget build(BuildContext context) {
    final adj = widget.layer.adjustments;
    final activePreset = _matchPreset(adj);
    final vignette = _activeVignette(widget.layer);
    final tokens = AppTokens.of(context);

    return ImagePanelShell(
      title: context.l10n.adjustTool,
      icon: Icons.tune_rounded,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header already says "Adjust" — no duplicate SectionLabel.
          _PresetRow(active: activePreset, onPick: _applyPreset),
          const SizedBox(height: 6),
          PrecisionDisclosure(
            icon: Icons.tune_rounded,
            titleClosed: context.l10n.adjustPrecisely,
            subtitle: context.l10n.adjustPreciselySubtitle,
            chevronColorClosed: tokens.accent,
            chevronColorOpen: tokens.accent,
            children: [
              const SizedBox(height: 4),
              EditorSliderRow(
                label: context.l10n.brightnessLabel,
                labelWidth: 80,
                readoutWidth: 48,
                value: adj.brightness,
                min: -100,
                max: 100,
                format: (v) => EditorValueFormat.of(context).digits(v.round()),
                onChanged: (v) => _previewSlider(
                  SetImageAdjustmentsCommand(
                    layerId: widget.layer.id,
                    brightness: v,
                  ),
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
                format: (v) =>
                    EditorValueFormat.of(context).percent((v * 100).round()),
                onChanged: (v) => _previewSlider(
                  SetImageAdjustmentsCommand(
                    layerId: widget.layer.id,
                    contrast: v,
                  ),
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
                format: (v) =>
                    EditorValueFormat.of(context).percent((v * 100).round()),
                onChanged: (v) => _previewSlider(
                  SetImageAdjustmentsCommand(
                    layerId: widget.layer.id,
                    saturation: v,
                  ),
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
                format: (v) => EditorValueFormat.of(context).digits(v.round()),
                onChanged: (v) => _previewSlider(
                  SetImageAdjustmentsCommand(
                    layerId: widget.layer.id,
                    exposure: v,
                  ),
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
                format: (v) => EditorValueFormat.of(context).digits(v.round()),
                onChanged: (v) => _previewSlider(
                  SetImageAdjustmentsCommand(
                    layerId: widget.layer.id,
                    warmth: v,
                  ),
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
            icon: Icons.vignette_outlined,
            titleClosed: context.l10n.vignetteLabel,
            subtitle: context.l10n.vignetteSubtitle,
            chevronColorClosed: tokens.accent,
            chevronColorOpen: tokens.accent,
            children: [
              const SizedBox(height: 4),
              EditorSliderRow(
                label: context.l10n.intensityLabel,
                labelWidth: 80,
                readoutWidth: 48,
                value: vignette.intensity,
                min: VignetteEffect.minIntensity,
                max: VignetteEffect.maxIntensity,
                format: (v) =>
                    EditorValueFormat.of(context).percent((v * 100).round()),
                onChanged: (v) => _previewSlider(
                  SetImageVignetteCommand(
                    layerId: widget.layer.id,
                    intensity: v,
                  ),
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
                format: (v) =>
                    EditorValueFormat.of(context).percent((v * 100).round()),
                onChanged: (v) => _previewSlider(
                  SetImageVignetteCommand(layerId: widget.layer.id, feather: v),
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
                  SetImageVignetteCommand(layerId: widget.layer.id, color: c),
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

// ---------------------------------------------------------------------------
// Presets
// ---------------------------------------------------------------------------

/// Curated colour-grade presets. Each maps a single tap to a
/// brightness + contrast + saturation triple. Intentionally
/// conservative so the result reads as a stylistic tweak rather
/// than an obviously processed filter.
class _AdjustPreset {
  const _AdjustPreset({
    required this.id,
    required this.label,
    required this.icon,
    required this.brightness,
    required this.contrast,
    required this.saturation,
    this.exposure = 0,
    this.warmth = 0,
  });

  final String id;
  final String label;
  final IconData icon;
  final double brightness;
  final double contrast;
  final double saturation;
  final double exposure;
  final double warmth;

  static const original = _AdjustPreset(
    id: 'original',
    label: 'Original',
    icon: Icons.refresh_rounded,
    brightness: 0,
    contrast: 1,
    saturation: 1,
  );
  static const pop = _AdjustPreset(
    id: 'pop',
    label: 'Pop',
    icon: Icons.auto_awesome_rounded,
    brightness: 5,
    contrast: 1.2,
    saturation: 1.25,
    exposure: 6,
  );
  static const soft = _AdjustPreset(
    id: 'soft',
    label: 'Soft',
    icon: Icons.blur_on_rounded,
    brightness: 8,
    contrast: 0.9,
    saturation: 0.9,
  );
  static const warm = _AdjustPreset(
    id: 'warm',
    label: 'Warm',
    icon: Icons.wb_sunny_outlined,
    brightness: 6,
    contrast: 1.05,
    saturation: 1.15,
    warmth: 28,
  );
  static const cool = _AdjustPreset(
    id: 'cool',
    label: 'Cool',
    icon: Icons.ac_unit_rounded,
    brightness: -4,
    contrast: 1.05,
    saturation: 0.95,
    warmth: -28,
  );

  static const all = <_AdjustPreset>[original, pop, soft, warm, cool];
}

_AdjustPreset? _matchPreset(ImageAdjustments adj) {
  bool eq(double a, double b) => (a - b).abs() < 0.001;
  for (final p in _AdjustPreset.all) {
    if (eq(p.brightness, adj.brightness) &&
        eq(p.contrast, adj.contrast) &&
        eq(p.saturation, adj.saturation) &&
        eq(p.exposure, adj.exposure) &&
        eq(p.warmth, adj.warmth)) {
      return p;
    }
  }
  return null; // custom values — no chip highlighted
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({required this.active, required this.onPick});

  final _AdjustPreset? active;
  final ValueChanged<_AdjustPreset> onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final p in _AdjustPreset.all) ...[
          Expanded(
            child: _PresetChip(
              preset: p,
              selected: active?.id == p.id,
              onTap: () => onPick(p),
            ),
          ),
          if (p != _AdjustPreset.all.last) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final _AdjustPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PresetChip.option(
      icon: preset.icon,
      label: _adjustPresetLabel(context, preset),
      selected: selected,
      onTap: onTap,
    );
  }
}

String _adjustPresetLabel(BuildContext context, _AdjustPreset preset) {
  return switch (preset.id) {
    'original' => context.l10n.originalOption,
    'pop' => context.l10n.popOption,
    'soft' => context.l10n.softOption,
    'warm' => context.l10n.warmOption,
    'cool' => context.l10n.coolOption,
    _ => preset.label,
  };
}

// ---------------------------------------------------------------------------
// Vignette section
// ---------------------------------------------------------------------------

/// Resolve the vignette currently on the layer's effect stack, or
/// fall back to the identity defaults so the sliders always have
/// a value to render. The renderer treats an identity vignette as
/// "no effect" \u2014 see [SetImageVignetteCommand] for the round-trip
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
