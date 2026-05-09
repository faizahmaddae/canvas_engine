import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/haptics.dart';
import '../../application/document_controller.dart';
import '../../engine/commands/image_commands.dart';
import '../../engine/modules/image/image_layer.dart';
import 'image_panel_shell.dart';

/// Expanded panel body for the Image sub-tool's "Style" tab.
///
/// One-tap visual presets that map to the same three-knob
/// [ImageAdjustments] system already used by the Adjust tab. We
/// deliberately reuse the existing pipeline (no LUTs, no extra
/// uniforms in the render path) — every preset is just a curated
/// brightness + contrast + saturation triple committed via
/// [SetImageAdjustmentsCommand]. That keeps undo/redo, JSON,
/// preservation across mask/border/shadow/crop edits, and the
/// renderer's per-frame cost identical to what's already shipping.
///
/// Each tile renders a real thumbnail of the underlying image with
/// the preset's colour matrix applied so the user sees the
/// stylistic difference at a glance — no need to tap-and-undo to
/// preview.
class ImageStyleBody extends ConsumerWidget {
  const ImageStyleBody({super.key, required this.layer});

  final ImageLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adj = layer.adjustments;
    final active = _matchStyle(adj);

    void apply(_StylePreset p) {
      EditorHaptics.toggle();
      ref.read(documentControllerProvider.notifier).execute(
            SetImageAdjustmentsCommand(
              layerId: layer.id,
              brightness: p.brightness,
              contrast: p.contrast,
              saturation: p.saturation,
            ),
          );
    }

    return ImagePanelShell(
      title: 'Style',
      icon: Icons.auto_awesome_outlined,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header already says "Style" — no duplicate SectionLabel.
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              itemCount: _StylePreset.all.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final p = _StylePreset.all[i];
                return _StyleTile(
                  preset: p,
                  source: layer.source,
                  selected: active?.id == p.id,
                  onTap: () => apply(p),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Presets — distinct stylistic looks, separate from the Adjust presets so
// the two tabs read as different intents (curated colour grade vs. precise
// tweaks). Values intentionally stronger than Adjust's "Pop/Soft" set.
// ---------------------------------------------------------------------------

class _StylePreset {
  const _StylePreset({
    required this.id,
    required this.label,
    required this.brightness,
    required this.contrast,
    required this.saturation,
  });

  final String id;
  final String label;
  final double brightness;
  final double contrast;
  final double saturation;

  ImageAdjustments get adjustments => ImageAdjustments(
        brightness: brightness,
        contrast: contrast,
        saturation: saturation,
      );

  static const original = _StylePreset(
    id: 'original',
    label: 'Original',
    brightness: 0,
    contrast: 1,
    saturation: 1,
  );
  static const vivid = _StylePreset(
    id: 'vivid',
    label: 'Vivid',
    brightness: 4,
    contrast: 1.25,
    saturation: 1.5,
  );
  static const warm = _StylePreset(
    id: 'warm',
    label: 'Warm',
    brightness: 8,
    contrast: 1.1,
    saturation: 1.2,
  );
  static const cool = _StylePreset(
    id: 'cool',
    label: 'Cool',
    brightness: -6,
    contrast: 1.1,
    saturation: 0.85,
  );
  static const mono = _StylePreset(
    id: 'mono',
    label: 'Mono',
    brightness: 0,
    contrast: 1.1,
    saturation: 0,
  );
  static const fade = _StylePreset(
    id: 'fade',
    label: 'Fade',
    brightness: 12,
    contrast: 0.78,
    saturation: 0.85,
  );
  static const dramatic = _StylePreset(
    id: 'dramatic',
    label: 'Dramatic',
    brightness: -8,
    contrast: 1.5,
    saturation: 1.15,
  );

  static const all = <_StylePreset>[
    original,
    vivid,
    warm,
    cool,
    mono,
    fade,
    dramatic,
  ];
}

_StylePreset? _matchStyle(ImageAdjustments adj) {
  bool eq(double a, double b) => (a - b).abs() < 0.001;
  for (final p in _StylePreset.all) {
    if (eq(p.brightness, adj.brightness) &&
        eq(p.contrast, adj.contrast) &&
        eq(p.saturation, adj.saturation)) {
      return p;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Tile
// ---------------------------------------------------------------------------

class _StyleTile extends StatelessWidget {
  const _StyleTile({
    required this.preset,
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final _StylePreset preset;
  final ImageSource source;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? scheme.primary
                      : scheme.outlineVariant.withValues(alpha: 0.4),
                  width: selected ? 2 : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.22),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColorFiltered(
                        colorFilter: ColorFilter.matrix(
                          preset.adjustments.toMatrix(),
                        ),
                        child: _thumb(source, scheme),
                      ),
                      if (selected)
                        Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Container(
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.check_rounded,
                                size: 12,
                                color: scheme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            preset.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumb(ImageSource src, ColorScheme scheme) {
    if (src.assetName != null) {
      return Image.asset(
        src.assetName!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    if (src.filePath != null) {
      return Image.file(
        File(src.filePath!),
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    if (src.networkUrl != null) {
      return Image.network(
        src.networkUrl!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    return Container(color: scheme.surfaceContainerHighest);
  }
}
