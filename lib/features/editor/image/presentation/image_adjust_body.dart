import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../../color_picker/presentation/color_picker_sheet.dart';
import '../../application/document_controller.dart';
import '../../engine/commands/image_commands.dart';
import '../../engine/effects/editor_effect.dart';
import '../../engine/modules/image/image_layer.dart';
import '../../presentation/widgets/inline_color_body.dart';
import '../../presentation/widgets/panel_option_tile.dart';
import '../../application/recent_colors_controller.dart';
import 'image_panel_shell.dart';

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
/// Slider drags pass `live: true` so the command stream collapses
/// into a single undo entry per drag (see
/// [SetImageAdjustmentsCommand.mergeWith]). Preset taps leave
/// `live: false` so each tap is its own undoable action.
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
  bool _adjustOpen = false;
  bool _vignetteOpen = false;

  void _commit({
    double? brightness,
    double? contrast,
    double? saturation,
    double? exposure,
    double? warmth,
    bool live = false,
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
            live: live,
          ),
        );
  }

  void _commitVignette({
    double? intensity,
    double? feather,
    Color? color,
    bool live = false,
  }) {
    ref
        .read(documentControllerProvider.notifier)
        .execute(
          SetImageVignetteCommand(
            layerId: widget.layer.id,
            intensity: intensity,
            feather: feather,
            color: color,
            live: live,
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
          _AdjustHeader(
            open: _adjustOpen,
            onToggle: () {
              EditorHaptics.tap();
              setState(() => _adjustOpen = !_adjustOpen);
            },
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _adjustOpen
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _LabeledSlider(
                          label: context.l10n.brightnessLabel,
                          value: adj.brightness,
                          min: -100,
                          max: 100,
                          format: (v) => v.round().toString(),
                          onChange: (v) => _commit(brightness: v, live: true),
                        ),
                        _LabeledSlider(
                          label: context.l10n.contrastLabel,
                          value: adj.contrast,
                          min: 0,
                          max: 2,
                          format: (v) => '${(v * 100).round()}%',
                          onChange: (v) => _commit(contrast: v, live: true),
                        ),
                        _LabeledSlider(
                          label: context.l10n.saturationLabel,
                          value: adj.saturation,
                          min: 0,
                          max: 2,
                          format: (v) => '${(v * 100).round()}%',
                          onChange: (v) => _commit(saturation: v, live: true),
                        ),
                        _LabeledSlider(
                          label: context.l10n.exposureLabel,
                          value: adj.exposure,
                          min: -100,
                          max: 100,
                          format: (v) => v.round().toString(),
                          onChange: (v) => _commit(exposure: v, live: true),
                        ),
                        _LabeledSlider(
                          label: context.l10n.warmthLabel,
                          value: adj.warmth,
                          min: -100,
                          max: 100,
                          format: (v) => v.round().toString(),
                          onChange: (v) => _commit(warmth: v, live: true),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          // Vignette is the first non-colour-matrix effect on the
          // layer's effect stack \u2014 it lives in the same panel as
          // the colour adjustments because users think of it as
          // "one of the knobs", not as a separate tool.
          _VignetteHeader(
            open: _vignetteOpen,
            onToggle: () {
              EditorHaptics.tap();
              setState(() => _vignetteOpen = !_vignetteOpen);
            },
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _vignetteOpen
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _LabeledSlider(
                          label: context.l10n.intensityLabel,
                          value: vignette.intensity,
                          min: VignetteEffect.minIntensity,
                          max: VignetteEffect.maxIntensity,
                          format: (v) => '${(v * 100).round()}%',
                          onChange: (v) =>
                              _commitVignette(intensity: v, live: true),
                        ),
                        _LabeledSlider(
                          label: context.l10n.featherLabel,
                          value: vignette.feather,
                          min: VignetteEffect.minFeather,
                          max: VignetteEffect.maxFeather,
                          format: (v) => '${(v * 100).round()}%',
                          onChange: (v) =>
                              _commitVignette(feather: v, live: true),
                        ),
                        const SizedBox(height: 8),
                        InlineColorBody(
                          current: vignette.color,
                          recents: ref.watch(recentColorsControllerProvider),
                          palette: InlineColorBody.defaultPalette,
                          compactRecents: true,
                          onPick: (picked) {
                            EditorHaptics.toggle();
                            _commitVignette(color: picked);
                          },
                          onCustom: () async {
                            final original = vignette.color;
                            final picked = await showColorPickerSheet(
                              context,
                              initial: original,
                              recents: ref.read(recentColorsControllerProvider),
                              onLiveChange: (c) =>
                                  _commitVignette(color: c, live: true),
                              title: context.l10n.vignetteColorTitle,
                            );
                            if (picked == null) {
                              _commitVignette(color: original);
                              return;
                            }
                            ref
                                .read(recentColorsControllerProvider.notifier)
                                .remember(picked);
                          },
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
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
    return PanelOptionTile(
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
// Adjust precisely disclosure (matches Border / Shadow grammar)
// ---------------------------------------------------------------------------

class _AdjustHeader extends StatelessWidget {
  const _AdjustHeader({required this.open, required this.onToggle});

  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(Icons.tune_rounded, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.adjustPrecisely,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    context.l10n.adjustPreciselySubtitle,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedRotation(
              turns: open ? 0.25 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChange,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double) format;
  final ValueChanged<double> onChange;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChange,
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              format(value),
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
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

/// Disclosure header for the Vignette section. Mirrors the visual
/// grammar of [_AdjustHeader] so the panel reads as one consistent
/// list rather than two unrelated tools.
class _VignetteHeader extends StatelessWidget {
  const _VignetteHeader({required this.open, required this.onToggle});

  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(Icons.vignette_outlined, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.vignetteLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    context.l10n.vignetteSubtitle,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedRotation(
              turns: open ? 0.25 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
