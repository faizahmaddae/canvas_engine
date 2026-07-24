// Compact effect sections for the Styles & Effects panel — the
// single home for text decoration (سایه / زمینه / خط دور) after the
// bar consolidation removed their standalone dock tiles. Each
// section is a preset-chip row plus at most one compact control row,
// so the styles sheet stays under the dock cap with a section open.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../l10n/l10n.dart';
import '../../../../color_picker/presentation/color_picker_sheet.dart';
import '../../../engine/modules/text/text_layer.dart';
import '../../../text/application/text_tool_controller.dart';
import '../../../ui/editor_slider_row.dart';
import '../../../ui/panel_offset_pad.dart';
import '../../../toolbar/presentation/widgets/preset_chip.dart';
import '../../widgets/controls/slider_row.dart';
import 'precision/background_precision.dart';
import 'precision/border_precision.dart';
import 'precision/shadow_precision.dart';
import '../../../../../core/utils/editor_value_format.dart';

/// One horizontally-scrolling row of preset chips — the compact
/// replacement for the 72dp icon-tile rail the old decoration
/// sheets used. Chips carry the same labels; the canvas above is
/// the preview, so the icons earned no extra 36dp.
class _PresetChipsRow extends StatelessWidget {
  const _PresetChipsRow({required this.chips});

  final List<({String label, bool selected, VoidCallback onTap})> chips;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // 44 (was 36): unified PresetChip pill height (tb2 15/16).
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) => PresetChip(
          label: chips[i].label,
          selected: chips[i].selected,
          onTap: chips[i].onTap,
        ),
      ),
    );
  }
}

/// Opens the shared two-level picker as its compact no-dim sheet.
/// The styles panel is too dense to embed the picker body without
/// blowing the dock height cap, so effect sections show a slim
/// [ColorEntryButton] and hand off here.
///
/// Contract §2 (tb2 4/16): every change previews through the
/// text controller's style-drag session — [setColor] is invoked
/// with the session lazily opened, so wheel ticks stage overlay
/// frames instead of executing per tick — and the picker's
/// onCommitted fires [onSettled] (endStyleDrag) to seal EXACTLY
/// one undoable command per interaction. Alpha and recents stay
/// the picker's concern.
Future<void> _pickColor(
  BuildContext context, {
  required Color current,
  required ValueChanged<Color> setColor,
  required VoidCallback onSettled,
  required String title,
}) {
  return showColorPickerSheet(
    context,
    initial: current,
    onLiveChange: setColor,
    onCommitted: (_) => onSettled(),
    title: title,
  );
}

// ─── Shadow ─────────────────────────────────────────────────────────
//
// Compact contract (compactness pass 2026-07): preset chips +, when
// on, ONE control row — the 2D offset pad (direction AND distance in
// a single drag) beside a blur slider and the mini swatch row.
// Replaces the old distance slider + 3×3 direction pad + full colour
// body + precision disclosure (~570dp natural → ~190dp). Writes the
// same `setShadowOffset` the old pair did; shadow opacity lives on
// the custom colour picker's alpha channel.

class ShadowEffectSection extends ConsumerWidget {
  const ShadowEffectSection({super.key, required this.layer});

  final TextLayer layer;

  /// Offset magnitude at the pad's rim. Matches the old distance
  /// slider ceiling so existing layers land inside the pad.
  static const double _maxDistance = 24;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final style = layer.style;
    final hasShadow = style.shadowColor != null;
    final l10n = context.l10n;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PresetChipsRow(
          chips: [
            (
              label: l10n.noneOption,
              selected: !hasShadow,
              onTap: () => ctrl.setShadowEnabled(false),
            ),
            for (int i = 0; i < shadowPresets.length; i++)
              (
                label: shadowPresetLabel(l10n, shadowPresets[i]),
                selected: hasShadow && shadowMatches(style, shadowPresets[i]),
                onTap: () {
                  if (!hasShadow) ctrl.setShadowEnabled(true);
                  applyShadowPreset(
                    ref,
                    shadowPresets[i],
                    baseColor: style.shadowColor ?? const Color(0xFF000000),
                  );
                },
              ),
          ],
        ),
        if (hasShadow) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              PanelOffsetPad(
                offset: style.shadowOffset,
                maxDistance: _maxDistance,
                semanticLabel: l10n.shadowOffsetPadSemantics,
                onChanged: ctrl.setShadowOffset,
                onDragStart: ctrl.beginStyleDrag,
                onDragEnd: ctrl.endStyleDrag,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EditorSliderRow(
                      label: l10n.blurLabel,
                      labelWidth: 44,
                      value: style.shadowBlur,
                      max: 40,
                      format: (v) =>
                          EditorValueFormat.of(context).px(v.round()),
                      onChanged: ctrl.setShadowBlur,
                      onDragStart: ctrl.beginStyleDrag,
                      onDragEnd: ctrl.endStyleDrag,
                      haptics: EditorSliderHaptics.startTickEnd,
                      labelStyle: flatSliderLabelStyle(context),
                      readoutStyle: flatSliderReadoutStyle(context),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 4),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: ColorEntryButton(
                          key: const ValueKey('effect-shadow-color'),
                          color: style.shadowColor!,
                          semanticLabel: l10n.shadowColorTitle,
                          onTap: () => _pickColor(
                            context,
                            current: style.shadowColor!,
                            setColor: (c) {
                              ctrl.beginStyleDrag();
                              ctrl.setShadowColor(c);
                            },
                            onSettled: ctrl.endStyleDrag,
                            title: l10n.shadowColorTitle,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ─── Background (زمینه) ─────────────────────────────────────────────

class BackgroundEffectSection extends ConsumerWidget {
  const BackgroundEffectSection({super.key, required this.layer});

  final TextLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final style = layer.style;
    final hasBg = style.backgroundColor != null;
    final l10n = context.l10n;

    void applyPreset(BgPreset p) {
      if (!hasBg) ctrl.setBackgroundEnabled(true);
      applyBgPreset(ref, p);
    }

    String presetLabel(BgPreset p) => switch (p.id) {
      'pill' => l10n.pillOption,
      'card' => l10n.cardOption,
      'tag' => l10n.tagOption,
      _ => p.id,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PresetChipsRow(
          chips: [
            (
              label: l10n.noneOption,
              selected: !hasBg,
              onTap: () => ctrl.setBackgroundEnabled(false),
            ),
            for (final p in backgroundPresets)
              if (p.id != 'none')
                (
                  label: presetLabel(p),
                  selected: hasBg && bgMatches(style, p),
                  onTap: () => applyPreset(p),
                ),
          ],
        ),
        if (hasBg) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: ColorEntryButton(
                key: const ValueKey('effect-background-color'),
                color: style.backgroundColor!,
                semanticLabel: l10n.backgroundColorTitle,
                onTap: () => _pickColor(
                  context,
                  current: style.backgroundColor!,
                  setColor: (c) {
                    ctrl.beginStyleDrag();
                    ctrl.setBackgroundColor(c);
                  },
                  onSettled: ctrl.endStyleDrag,
                  title: l10n.backgroundColorTitle,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          BackgroundPrecisionAdvanced(style: style),
        ],
      ],
    );
  }
}

// ─── Border / کادر (glyph outline) ──────────────────────────────────

class BorderEffectSection extends ConsumerWidget {
  const BorderEffectSection({super.key, required this.layer});

  final TextLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final style = layer.style;
    final hasOutline = style.outlineColor != null;
    final l10n = context.l10n;

    bool widthMatches(double target) =>
        hasOutline && (style.outlineWidth - target).abs() < 0.25;

    void pickWidth(double w) {
      if (!hasOutline) ctrl.setOutlineEnabled(true);
      ctrl.setOutlineWidth(w);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PresetChipsRow(
          chips: [
            (
              label: l10n.noneOption,
              selected: !hasOutline,
              onTap: () => ctrl.setOutlineEnabled(false),
            ),
            (
              label: l10n.hairlineOption,
              selected: widthMatches(0.5),
              onTap: () => pickWidth(0.5),
            ),
            (
              label: l10n.solidOption,
              selected: widthMatches(2),
              onTap: () => pickWidth(2),
            ),
            (
              label: l10n.boldAction,
              selected: widthMatches(4),
              onTap: () => pickWidth(4),
            ),
          ],
        ),
        if (hasOutline) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: ColorEntryButton(
                key: const ValueKey('effect-border-color'),
                color: style.outlineColor!,
                semanticLabel: l10n.borderColorTitle,
                onTap: () => _pickColor(
                  context,
                  current: style.outlineColor!,
                  setColor: (c) {
                    ctrl.beginStyleDrag();
                    ctrl.setOutlineColor(c);
                  },
                  onSettled: ctrl.endStyleDrag,
                  title: l10n.borderColorTitle,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          BorderPrecisionAdvanced(style: style),
        ],
      ],
    );
  }
}
