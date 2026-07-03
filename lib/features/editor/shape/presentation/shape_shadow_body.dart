import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../../color_picker/presentation/color_picker_sheet.dart';
import '../../application/document_controller.dart';
import '../../engine/commands/shape_commands.dart';
import '../../engine/modules/shape/shape_layer.dart';
import '../../presentation/widgets/inline_color_body.dart';
import '../../presentation/widgets/panel_option_tile.dart';
import '../../application/recent_colors_controller.dart';
import '../../presentation/widgets/section_label.dart';
import '../../ui/editor_slider_row.dart';
import '../../ui/panel_direction_pad.dart';
import '../../ui/precision_disclosure.dart';
import 'shape_panel_shell.dart';

/// Expanded panel body for the Shape sub-tool's "Shadow" tab.
///
/// Mirrors [ImageShadowBody] one-to-one so users only learn the
/// shadow grammar once: five style presets (None / Soft / Hard /
/// Glow / Lift), a compact colour row, and an "Adjust precisely"
/// disclosure with a 3×3 direction pad + blur + opacity sliders.
///
/// Every interaction goes through [SetShapeShadowCommand] which
/// preserves the other shadow fields when only one knob is touched
/// — sliding blur won't reset the offset, picking a colour won't
/// reset opacity, etc. Slider drags use `live: true` so the entire
/// stream collapses into a single undo entry.
class ShapeShadowBody extends ConsumerStatefulWidget {
  const ShapeShadowBody({super.key, required this.layer});

  final ShapeLayer layer;

  @override
  ConsumerState<ShapeShadowBody> createState() => _ShapeShadowBodyState();
}

class _ShapeShadowBodyState extends ConsumerState<ShapeShadowBody> {
  // Direction-pad offsets are sized in proportion to the current
  // blur (or a sensible minimum). This keeps the spatial relation
  // between blur sigma and travel distance feeling cohesive.
  double get _directionMagnitude {
    final blur = widget.layer.shadowBlur;
    final mag = blur > 0 ? blur * 0.9 : 12;
    return mag.clamp(8, 40).toDouble();
  }

  void _commit({
    Color? c,
    double? blur,
    Offset? offset,
    double? opacity,
    bool live = false,
  }) {
    ref
        .read(documentControllerProvider.notifier)
        .execute(
          SetShapeShadowCommand(
            layerId: widget.layer.id,
            color: c,
            blur: blur,
            offset: offset,
            opacity: opacity,
            live: live,
          ),
        );
  }

  void _applyPreset(_ShadowPreset preset) {
    EditorHaptics.toggle();
    _commit(blur: preset.blur, offset: preset.offset, opacity: preset.opacity);
  }

  @override
  Widget build(BuildContext context) {
    final layer = widget.layer;
    final hasShadow = layer.shadowOpacity > 0;
    final activePreset = _matchPreset(layer);

    return ShapePanelShell(
      title: context.l10n.shadowTool,
      icon: Icons.layers_outlined,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(context.l10n.styleLabel),
          _PresetRow(active: activePreset, onPick: _applyPreset),
          // When the shadow is None there's nothing to colour or
          // fine-tune — collapse the rest of the panel so the dock
          // stays short on phones. Picking any preset reveals it.
          if (hasShadow) ...[
            const SizedBox(height: 12),
            SectionLabel(context.l10n.colorLabel),
            // Approved compact color UI — fed by the app-wide
            // [recentColorsControllerProvider] so customs picked
            // in any colour panel surface here too.
            InlineColorBody(
              current: layer.shadowColor,
              recents: ref.watch(recentColorsControllerProvider),
              palette: InlineColorBody.defaultPalette,
              compactRecents: true,
              onPick: (picked) {
                EditorHaptics.toggle();
                _commit(c: picked);
              },
              onCustom: () async {
                final original = layer.shadowColor;
                final picked = await showColorPickerSheet(
                  context,
                  initial: original,
                  recents: ref.read(recentColorsControllerProvider),
                  onLiveChange: (c) => _commit(c: c, live: true),
                  title: context.l10n.shadowColorTitle,
                );
                if (picked == null) {
                  _commit(c: original);
                  return;
                }
                ref
                    .read(recentColorsControllerProvider.notifier)
                    .remember(picked);
              },
            ),
            const SizedBox(height: 2),
            PrecisionDisclosure(
              icon: Icons.tune_rounded,
              titleClosed: context.l10n.adjustPrecisely,
              subtitle: context.l10n.blurDirectionOpacitySubtitle,
              // The icon-header family used a constant primary
              // chevron regardless of open state — preserve exactly.
              chevronColorClosed: Theme.of(context).colorScheme.primary,
              chevronColorOpen: Theme.of(context).colorScheme.primary,
              children: [
                const SizedBox(height: 4),
                Center(
                  child: PanelDirectionPad(
                    offset: layer.shadowOffset,
                    magnitude: _directionMagnitude,
                    onPick: (off) {
                      EditorHaptics.toggle();
                      _commit(offset: off);
                    },
                  ),
                ),
                const SizedBox(height: 6),
                EditorSliderRow(
                  label: context.l10n.blurLabel,
                  value: layer.shadowBlur,
                  max: 80,
                  format: (v) => v.round().toString(),
                  onChanged: (v) => _commit(blur: v, live: true),
                ),
                EditorSliderRow(
                  label: context.l10n.opacityLabel,
                  value: layer.shadowOpacity,
                  max: 1,
                  format: (v) => '${(v * 100).round()}%',
                  onChanged: (v) => _commit(opacity: v, live: true),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Snapshot of one preset so callers can compare/apply uniformly.
class _ShadowPreset {
  const _ShadowPreset({
    required this.id,
    required this.label,
    required this.icon,
    required this.blur,
    required this.offset,
    required this.opacity,
  });

  final String id;
  final String label;
  final IconData icon;
  final double blur;
  final Offset offset;
  final double opacity;

  static const none = _ShadowPreset(
    id: 'none',
    label: 'None',
    icon: Icons.block_outlined,
    blur: 0,
    offset: Offset.zero,
    opacity: 0,
  );
  static const soft = _ShadowPreset(
    id: 'soft',
    label: 'Soft',
    icon: Icons.blur_on_outlined,
    blur: 18,
    offset: Offset(0, 8),
    opacity: 0.35,
  );
  static const hard = _ShadowPreset(
    id: 'hard',
    label: 'Hard',
    icon: Icons.square_outlined,
    blur: 2,
    offset: Offset(4, 4),
    opacity: 0.6,
  );
  static const glow = _ShadowPreset(
    id: 'glow',
    label: 'Glow',
    icon: Icons.wb_sunny_outlined,
    blur: 24,
    offset: Offset.zero,
    opacity: 0.55,
  );
  static const lift = _ShadowPreset(
    id: 'lift',
    label: 'Lift',
    icon: Icons.unfold_more_rounded,
    blur: 30,
    offset: Offset(0, 16),
    opacity: 0.25,
  );

  static const all = <_ShadowPreset>[none, soft, hard, glow, lift];
}

_ShadowPreset? _matchPreset(ShapeLayer layer) {
  if (layer.shadowOpacity <= 0) return _ShadowPreset.none;
  for (final p in _ShadowPreset.all) {
    if (p.id == 'none') continue;
    if ((p.blur - layer.shadowBlur).abs() < 0.5 &&
        (p.offset - layer.shadowOffset).distance < 0.5 &&
        (p.opacity - layer.shadowOpacity).abs() < 0.02) {
      return p;
    }
  }
  return null; // custom — no chip highlighted
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({required this.active, required this.onPick});

  final _ShadowPreset? active;
  final ValueChanged<_ShadowPreset> onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final p in _ShadowPreset.all) ...[
          Expanded(
            child: _PresetChip(
              preset: p,
              selected: active?.id == p.id,
              onTap: () => onPick(p),
            ),
          ),
          if (p != _ShadowPreset.all.last) const SizedBox(width: 6),
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

  final _ShadowPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PanelOptionTile(
      icon: preset.icon,
      iconSize: 18,
      label: _shadowPresetLabel(context, preset),
      selected: selected,
      onTap: onTap,
    );
  }
}

String _shadowPresetLabel(BuildContext context, _ShadowPreset preset) {
  return switch (preset.id) {
    'none' => context.l10n.noneOption,
    'soft' => context.l10n.softOption,
    'hard' => context.l10n.hardOption,
    'glow' => context.l10n.glowOption,
    'lift' => context.l10n.liftOption,
    _ => preset.label,
  };
}

// Removed: the Color section now uses the shared `InlineColorBody`
// (matches Text Color / Background / Border / Shape Style / Shape
// Border / Image Border / Image Shadow / Canvas Background).
// Keeping this comment as a breadcrumb for archaeology.
