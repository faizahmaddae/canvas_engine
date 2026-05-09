import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/haptics.dart';
import '../../application/document_controller.dart';
import '../../engine/commands/text_commands.dart';
import '../../engine/modules/text/text_layer.dart';
import 'sticker_panel_shell.dart';

/// Catalogue of sticker style presets. Each preset is just a
/// transformation on a [TextStyleSpec] — we never replace the
/// layer type, so undo/redo and JSON round-trip work for free
/// (the existing TextStyleSpec already serialises shadow + outline).
///
/// Limitations on color emoji:
///   * `outlineColor` (stroked TextStyle) doesn't render against
///     bitmap color-emoji glyphs reliably; we approximate an
///     outline using a tight zero-offset dark shadow which renders
///     as a true halo around the glyph silhouette.
///   * `color` is ignored by color emoji, so a "tint" preset would
///     only affect non-emoji fallback text — skipped for v1.
enum StickerStylePreset {
  original,
  softShadow,
  pop,
  glow,
  outline,
}

extension StickerStylePresetX on StickerStylePreset {
  String get label {
    switch (this) {
      case StickerStylePreset.original:
        return 'Original';
      case StickerStylePreset.softShadow:
        return 'Shadow';
      case StickerStylePreset.pop:
        return 'Pop';
      case StickerStylePreset.glow:
        return 'Glow';
      case StickerStylePreset.outline:
        return 'Outline';
    }
  }

  IconData get icon {
    switch (this) {
      case StickerStylePreset.original:
        return Icons.emoji_emotions_outlined;
      case StickerStylePreset.softShadow:
        return Icons.blur_on_rounded;
      case StickerStylePreset.pop:
        return Icons.flash_on_rounded;
      case StickerStylePreset.glow:
        return Icons.wb_sunny_outlined;
      case StickerStylePreset.outline:
        return Icons.format_shapes_rounded;
    }
  }

  /// Return [base] with the preset's shadow / outline parameters
  /// applied. Color, font, alignment, and background are left
  /// untouched so other tabs can still mutate them independently.
  TextStyleSpec apply(TextStyleSpec base) {
    switch (this) {
      case StickerStylePreset.original:
        return base.copyWith(clearShadow: true, clearOutline: true);
      case StickerStylePreset.softShadow:
        return base.copyWith(
          shadowColor: const Color(0x4D000000), // black 30 %
          shadowBlur: 12,
          shadowOffset: const Offset(0, 6),
          clearOutline: true,
        );
      case StickerStylePreset.pop:
        return base.copyWith(
          shadowColor: const Color(0x99000000), // black 60 %
          shadowBlur: 0,
          shadowOffset: const Offset(6, 6),
          clearOutline: true,
        );
      case StickerStylePreset.glow:
        return base.copyWith(
          shadowColor: const Color(0xCCFFFFFF), // white 80 %
          shadowBlur: 24,
          shadowOffset: Offset.zero,
          clearOutline: true,
        );
      case StickerStylePreset.outline:
        // Tight dark halo — approximates a true outline against
        // bitmap color-emoji glyphs where stroked TextStyle has no
        // effect.
        return base.copyWith(
          shadowColor: const Color(0xFF000000),
          shadowBlur: 2,
          shadowOffset: Offset.zero,
          clearOutline: true,
        );
    }
  }

  /// True when [style]'s shadow / outline parameters match this
  /// preset within a small tolerance. Used to highlight the active
  /// tile in [StickerStyleBody].
  bool matches(TextStyleSpec style) {
    final probe = apply(const TextStyleSpec());
    return probe.shadowColor == style.shadowColor &&
        (probe.shadowBlur - style.shadowBlur).abs() < 0.001 &&
        probe.shadowOffset == style.shadowOffset &&
        probe.outlineColor == style.outlineColor;
  }
}

/// Body for the Sticker "Style" tab. Centred grid of preset tiles;
/// tapping a tile applies the preset immediately via
/// [UpdateTextCommand] so it joins the standard undo stack.
class StickerStyleBody extends ConsumerWidget {
  const StickerStyleBody({super.key, required this.layer});

  final TextLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return StickerPanelShell(
      title: 'Style',
      icon: Icons.auto_awesome_outlined,
      // Full-bleed body: zero horizontal gutter so the preset
      // carousel runs from the panel's left edge to its right
      // edge. Vertical rhythm matches the default panel padding
      // (12 top / 24 bottom). [maxBodyWidth] is `null` so the row
      // does not get re-centered + width-capped on tablets.
      bodyPadding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
      maxBodyWidth: null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Single horizontal row — never wraps, always scrolls
          // when the tile count exceeds the visible viewport.
          // Cards keep their intrinsic width (see [_StyleTile]) so
          // a small phone shows ~3 cards and the rest scroll into
          // view; a tablet naturally reveals more without
          // resizing.
          //
          // The ListView itself owns the 16dp left/right inset so
          // the first and last tile read as nicely-spaced bookends
          // instead of glued to the panel edge — and so no parent
          // padding ever clips the row.
          SizedBox(
            height: 78,
            width: double.infinity,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: StickerStylePreset.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final preset = StickerStylePreset.values[i];
                return _StyleTile(
                  preset: preset,
                  selected: preset.matches(layer.style),
                  onTap: () => _apply(ref, preset),
                  scheme: scheme,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _apply(WidgetRef ref, StickerStylePreset preset) {
    EditorHaptics.tap();
    final next = preset.apply(layer.style);
    if (next == layer.style) return;
    ref.read(documentControllerProvider.notifier).execute(
          UpdateTextCommand(
            layerId: layer.id,
            content: layer.content,
            style: next,
          ),
        );
  }
}

class _StyleTile extends StatelessWidget {
  const _StyleTile({
    required this.preset,
    required this.selected,
    required this.onTap,
    required this.scheme,
  });

  final StickerStylePreset preset;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? scheme.primary.withValues(alpha: 0.14)
        : scheme.surfaceContainerHighest;
    final border = selected ? scheme.primary : scheme.outlineVariant;
    final fg = selected ? scheme.primary : scheme.onSurface;
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
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: selected ? 1.5 : 1),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : const [],
          ),
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(preset.icon, size: 22, color: fg),
              const SizedBox(height: 6),
              Text(
                preset.label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
