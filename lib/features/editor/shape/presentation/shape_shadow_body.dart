import 'dart:math' as math;

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
  bool _adjustOpen = false;

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
                          Center(
                            child: _DirectionPad(
                              offset: layer.shadowOffset,
                              magnitude: _directionMagnitude,
                              onPick: (off) {
                                EditorHaptics.toggle();
                                _commit(offset: off);
                              },
                            ),
                          ),
                          const SizedBox(height: 6),
                          _LabeledSlider(
                            label: context.l10n.blurLabel,
                            value: layer.shadowBlur,
                            max: 80,
                            format: (v) => v.round().toString(),
                            onChange: (v) => _commit(blur: v, live: true),
                          ),
                          _LabeledSlider(
                            label: context.l10n.opacityLabel,
                            value: layer.shadowOpacity,
                            max: 1,
                            format: (v) => '${(v * 100).round()}%',
                            onChange: (v) => _commit(opacity: v, live: true),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
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

/// 3×3 grid of direction buttons. Centre cell maps to
/// `Offset.zero` (centred glow); the 8 perimeter cells map to unit
/// vectors scaled by the current direction magnitude.
class _DirectionPad extends StatelessWidget {
  const _DirectionPad({
    required this.offset,
    required this.magnitude,
    required this.onPick,
  });

  final Offset offset;
  final double magnitude;
  final ValueChanged<Offset> onPick;

  @override
  Widget build(BuildContext context) {
    const cells = <(int, int)>[
      (-1, -1),
      (0, -1),
      (1, -1),
      (-1, 0),
      (0, 0),
      (1, 0),
      (-1, 1),
      (0, 1),
      (1, 1),
    ];
    final activeCell = _activeCell(offset);
    return SizedBox(
      width: 132,
      child: GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        children: [
          for (final c in cells)
            _DirectionCell(
              dx: c.$1,
              dy: c.$2,
              selected: activeCell == c,
              onTap: () => onPick(
                c.$1 == 0 && c.$2 == 0
                    ? Offset.zero
                    : Offset(
                        c.$1 * magnitude.toDouble(),
                        c.$2 * magnitude.toDouble(),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  (int, int)? _activeCell(Offset off) {
    if (off == Offset.zero) return (0, 0);
    final dx = off.dx.abs() < 0.5 ? 0 : (off.dx > 0 ? 1 : -1);
    final dy = off.dy.abs() < 0.5 ? 0 : (off.dy > 0 ? 1 : -1);
    return (dx, dy);
  }
}

class _DirectionCell extends StatelessWidget {
  const _DirectionCell({
    required this.dx,
    required this.dy,
    required this.selected,
    required this.onTap,
  });

  final int dx;
  final int dy;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCenter = dx == 0 && dy == 0;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.16)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Center(
          child: isCenter
              ? Icon(
                  Icons.center_focus_strong_outlined,
                  size: 16,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                )
              : Transform.rotate(
                  angle: _arrowAngle(dx, dy),
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    size: 16,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
        ),
      ),
    );
  }

  double _arrowAngle(int dx, int dy) {
    return math.atan2(dy.toDouble(), dx.toDouble()) + math.pi / 2;
  }
}

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
                    context.l10n.blurDirectionOpacitySubtitle,
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
    required this.max,
    required this.format,
    required this.onChange,
  });

  final String label;
  final double value;
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
            width: 56,
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
              value: value.clamp(0.0, max),
              min: 0,
              max: max,
              onChanged: onChange,
            ),
          ),
          SizedBox(
            width: 44,
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

// Removed: the Color section now uses the shared `InlineColorBody`
// (matches Text Color / Background / Border / Shape Style / Shape
// Border / Image Border / Image Shadow / Canvas Background).
// Keeping this comment as a breadcrumb for archaeology.
