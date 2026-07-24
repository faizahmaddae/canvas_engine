// Extracted verbatim from paint_mode_toolbar.dart (tb1 4/17); behaviour-preserving.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../l10n/l10n.dart';
import '../../../presentation/widgets/section_label.dart';
import '../../../toolbar/presentation/widgets/preset_chip.dart';
import '../../application/paint_tool_controller.dart';

class PaintPolygonBody extends ConsumerWidget {
  const PaintPolygonBody({super.key, required this.value});

  final int value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 6),
        SectionLabel(
          context.l10n.polygonSidesLabel,
          uppercase: true,
          letterSpacing: 0.8,
        ),
        // Horizontal scroll mirrors the chip strip used by every
        // other preset surface in the editor (paint Size/Blur,
        // text sliders) — single layout grammar across modes.
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: 8,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              const sides = <int>[3, 4, 5, 6, 7, 8, 10, 12];
              final n = sides[i];
              return PresetChip(
                label: '$n',
                selected: n == value,
                onTap: () => ctrl.setPolygonSides(n),
              );
            },
          ),
        ),
      ],
    );
  }
}
