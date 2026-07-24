import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../../color_picker/presentation/color_picker_sheet.dart';
import '../../application/document_controller.dart';
import '../../application/live_overlay_controller.dart';
import '../../engine/commands/editor_command.dart';
import '../../engine/core/editor_layer.dart';
import '../../ui/editor_slider_row.dart';
import '../../ui/panel_direction_pad.dart';
import '../../ui/precision_disclosure.dart';
import 'panel_option_tile.dart';
import 'section_label.dart';

/// Adapter closing the gap between [LayerShadowBody]'s shared UI and
/// each layer type's own command/shell wiring.
///
/// Phase 4 plan §4.1: recon verified `ShapeLayer` and `ImageLayer`
/// expose identical shadow fields and their `Set*ShadowCommand`s
/// share an identical signature, so only the command constructor,
/// field accessors, and per-tool shell need to vary per layer type.
class ShadowPanelAdapter<L extends EditorLayer> {
  const ShadowPanelAdapter({
    required this.command,
    required this.read,
    required this.shell,
  });

  final EditorCommand Function({
    required String layerId,
    Color? color,
    double? blur,
    Offset? offset,
    double? opacity,
    bool live,
  })
  command;

  final ({Color color, double blur, Offset offset, double opacity}) Function(
    L layer,
  )
  read;

  /// Wraps [child] in the per-tool `Shape`/`ImagePanelShell`. Kept as
  /// part of the adapter (not hoisted out) because the twin shells
  /// bind different tool controllers for close/prev/next navigation.
  final Widget Function({required Widget child}) shell;
}

/// Shared "Shadow" sub-tool panel body for any layer type with a
/// [ShadowPanelAdapter]. Unifies `ShapeShadowBody`/`ImageShadowBody`
/// (Phase 4 plan §4.1) — both were byte-identical apart from the
/// layer type, the shadow command, and the shell wrapper.
///
/// Five style presets cover the 95% case (None / Soft / Hard / Glow
/// / Lift). For the 5% who want exact control, a Color picker, a
/// 3×3 direction pad, and an "Adjust precisely" disclosure with
/// blur + opacity sliders are stacked underneath.
///
/// Every interaction goes through [ShadowPanelAdapter.command] which
/// preserves the other shadow fields when only one knob is touched
/// — sliding blur won't reset the offset, picking a colour won't
/// reset opacity, etc.
///
/// The blur/opacity sliders AND the colour picker follow the
/// interaction contract's §2 preview channel: ticks stage an
/// overlay preview, release/settle commits ONE non-live command
/// (structurally one undo entry per interaction). Presets and the
/// direction pad stay discrete non-live commands (§3).
class LayerShadowBody<L extends EditorLayer> extends ConsumerStatefulWidget {
  const LayerShadowBody({
    super.key,
    required this.layer,
    required this.adapter,
  });

  final L layer;
  final ShadowPanelAdapter<L> adapter;

  @override
  ConsumerState<LayerShadowBody<L>> createState() => _LayerShadowBodyState<L>();
}

class _LayerShadowBodyState<L extends EditorLayer>
    extends ConsumerState<LayerShadowBody<L>> {
  // Direction-pad offsets are sized in proportion to the current
  // blur (or a sensible minimum). This keeps the spatial relation
  // between blur sigma and travel distance feeling cohesive.
  double _directionMagnitude(double blur) {
    final mag = blur > 0 ? blur * 0.9 : 12;
    return mag.clamp(8, 40).toDouble();
  }

  // ─── Contract §2 slider preview channel ─────────────────────────
  //
  // The pending command is the exact command release will execute;
  // each tick APPLIES it to the committed doc and stages the result
  // on the overlay, so preview == commit by construction.
  // `EditorSliderRow.onDragEnd` also fires on pointer-cancel, so an
  // interrupted drag still commits the last previewed value (§7).
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
    // Clear-then-execute in one synchronous run — no flash-back
    // frame (same pattern as text's commitLiveEdit).
    ref.read(liveOverlayProvider.notifier).clear();
    ref.read(documentControllerProvider.notifier).execute(cmd);
  }

  @override
  void dispose() {
    if (_pendingSliderCommand != null) {
      ref.read(liveOverlayProvider.notifier).clear();
    }
    super.dispose();
  }

  void _commit({Color? c, double? blur, Offset? offset, double? opacity}) {
    ref
        .read(documentControllerProvider.notifier)
        .execute(
          widget.adapter.command(
            layerId: widget.layer.id,
            color: c,
            blur: blur,
            offset: offset,
            opacity: opacity,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final adapter = widget.adapter;
    final fields = adapter.read(widget.layer);
    final hasShadow = fields.opacity > 0;
    final activePreset = _matchShadowPreset(fields);

    void applyPreset(_ShadowPreset preset) {
      EditorHaptics.toggle();
      _commit(
        blur: preset.blur,
        offset: preset.offset,
        opacity: preset.opacity,
      );
    }

    return adapter.shell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(context.l10n.styleLabel),
          _ShadowPresetRow(active: activePreset, onPick: applyPreset),
          // When the shadow is None there's nothing to colour or
          // fine-tune — collapse the rest of the panel so the dock
          // stays short on phones. Picking any preset reveals it.
          if (hasShadow) ...[
            const SizedBox(height: 12),
            SectionLabel(context.l10n.colorLabel),
            // The shared two-level picker, embedded. Contract §2
            // (tb2 5/16): drags stage overlay previews via the same
            // channel as the sliders below; the settled change
            // commits ONE undoable command. Recents and alpha
            // policy live inside the picker.
            ColorPickerBody(
              initial: fields.color,
              title: context.l10n.shadowColorTitle,
              onChanged: (c) => _previewSlider(
                adapter.command(layerId: widget.layer.id, color: c),
              ),
              onCommitted: (_) => _commitSlider(),
            ),
            const SizedBox(height: 2),
            PrecisionDisclosure(
              icon: Icons.tune_rounded,
              titleClosed: context.l10n.adjustPrecisely,
              subtitle: context.l10n.blurDirectionOpacitySubtitle,
              // The icon-header family used a constant accent
              // chevron regardless of open state — preserve exactly.
              chevronColorClosed: tokens.accent,
              chevronColorOpen: tokens.accent,
              children: [
                const SizedBox(height: 4),
                Center(
                  child: PanelDirectionPad(
                    offset: fields.offset,
                    magnitude: _directionMagnitude(fields.blur),
                    onPick: (off) {
                      EditorHaptics.toggle();
                      _commit(offset: off);
                    },
                  ),
                ),
                const SizedBox(height: 6),
                EditorSliderRow(
                  label: context.l10n.blurLabel,
                  value: fields.blur,
                  max: 80,
                  format: (v) => v.round().toString(),
                  onChanged: (v) => _previewSlider(
                    adapter.command(layerId: widget.layer.id, blur: v),
                  ),
                  onDragEnd: _commitSlider,
                ),
                EditorSliderRow(
                  label: context.l10n.opacityLabel,
                  value: fields.opacity,
                  max: 1,
                  format: (v) => '${(v * 100).round()}%',
                  onChanged: (v) => _previewSlider(
                    adapter.command(layerId: widget.layer.id, opacity: v),
                  ),
                  onDragEnd: _commitSlider,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Snapshot of one shadow preset so callers can compare/apply
/// uniformly.
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

_ShadowPreset? _matchShadowPreset(
  ({Color color, double blur, Offset offset, double opacity}) fields,
) {
  if (fields.opacity <= 0) return _ShadowPreset.none;
  for (final p in _ShadowPreset.all) {
    if (p.id == 'none') continue;
    if ((p.blur - fields.blur).abs() < 0.5 &&
        (p.offset - fields.offset).distance < 0.5 &&
        (p.opacity - fields.opacity).abs() < 0.02) {
      return p;
    }
  }
  return null; // custom — no chip highlighted
}

class _ShadowPresetRow extends StatelessWidget {
  const _ShadowPresetRow({required this.active, required this.onPick});

  final _ShadowPreset? active;
  final ValueChanged<_ShadowPreset> onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final p in _ShadowPreset.all) ...[
          Expanded(
            child: _ShadowPresetChip(
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

class _ShadowPresetChip extends StatelessWidget {
  const _ShadowPresetChip({
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
