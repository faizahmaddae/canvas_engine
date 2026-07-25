import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../application/document_controller.dart';
import '../../engine/commands/transform_commands.dart';
import '../../engine/modules/text/text_layer.dart';
import '../../ui/canvas_preset_scale.dart';
import 'sticker_panel_shell.dart';
import '../../../../app/theme/app_icons.dart';

/// Body for the Sticker "Size" tab. Four square presets that resize
/// the layer around its visual centre so the sticker appears to
/// grow / shrink in place rather than jumping toward the top-left.
/// Chips are compact (54 px) and centered — they don't stretch to
/// fill the column.
class StickerSizeBody extends ConsumerWidget {
  const StickerSizeBody({super.key, required this.layer});

  final TextLayer layer;

  // Square presets — emoji glyphs occupy a square box, so width ==
  // height keeps the sticker visually balanced and matches the
  // 240 px insertion default sitting between M and L.
  //
  // Sides are authored against the reference canvas and scaled to
  // the open document (tb4 6/14): "XL" has to mean XL on a print
  // canvas too, not a tenth of one.
  static const _presets = <_SizePreset>[
    _SizePreset(label: 'S', side: 120),
    _SizePreset(label: 'M', side: 200),
    _SizePreset(label: 'L', side: 320),
    _SizePreset(label: 'XL', side: 480),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final doc = ref.watch(documentControllerProvider);
    final currentSide = layer.transform.size.shortestSide;
    return StickerPanelShell(
      title: context.l10n.sizeTool,
      icon: AppIcons.sizeTool,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header already says "Size" — no duplicate SectionLabel.
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              for (final p in _presets)
                _SizeChip(
                  label: p.label,
                  selected:
                      (currentSide - canvasScaledPreset(p.side, doc)).abs() < 1,
                  onTap: () => _apply(ref, canvasScaledPreset(p.side, doc)),
                  tokens: tokens,
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _apply(WidgetRef ref, double side) {
    EditorHaptics.tap();
    final t = layer.transform;
    final centre = t.position + Offset(t.size.width / 2, t.size.height / 2);
    final newSize = Size(side, side);
    final newPos = centre - Offset(newSize.width / 2, newSize.height / 2);
    final next = t.copyWith(position: newPos, size: newSize);
    if (next == t) return;
    ref
        .read(documentControllerProvider.notifier)
        .execute(ResizeLayerCommand(layerId: layer.id, transform: next));
  }
}

class _SizePreset {
  const _SizePreset({required this.label, required this.side});
  final String label;
  final double side;
}

class _SizeChip extends StatelessWidget {
  const _SizeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.tokens,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? tokens.accent.withValues(alpha: 0.14)
        : tokens.surfaceMuted;
    final border = selected ? tokens.accent : tokens.border;
    final fg = selected ? tokens.accent : tokens.textPrimary;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          EditorHaptics.tap();
          onTap();
        },
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: selected ? 1.5 : 1),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: tokens.accent.withValues(alpha: 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : const [],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}
