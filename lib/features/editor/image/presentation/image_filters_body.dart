import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../application/document_controller.dart';
import '../../engine/commands/image_commands.dart';
import '../../engine/modules/image/image_layer.dart';
import 'image_panel_shell.dart';

/// Expanded panel body for the Image sub-tool's "Filters" tab.
///
/// One row of preview chips, one tap = one undoable
/// [SetImageFilterCommand]. Each chip renders the **actual layer
/// image** through the same [ColorFilter.matrix] used at paint
/// time, so the user sees a true preview of the selected look —
/// not a generic gradient swatch.
///
/// Selected state matches the unified `DockToolTile` grammar
/// (2026-05): accent @ 12% pill behind the chip + accent label,
/// no glow shadow, no thick border ring. A small ✓ corner badge
/// makes the active filter unmistakable at a glance.
///
/// Filter is independent of the brightness/contrast/etc.
/// adjustment knobs (those live in the Adjust tab); selecting a
/// filter never overwrites the user's manual tuning.
class ImageFiltersBody extends ConsumerWidget {
  const ImageFiltersBody({super.key, required this.layer});

  final ImageLayer layer;

  void _commit(WidgetRef ref, ImageFilterPreset p) {
    ref
        .read(documentControllerProvider.notifier)
        .execute(SetImageFilterCommand(layerId: layer.id, filterPreset: p));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resolve the live image once at the body level so each chip
    // reuses the same ImageProvider — Flutter dedupes the decode
    // and the 7 chips share one cached bitmap (cap 128px wide,
    // independent of canvas resolution).
    final provider = _providerFor(layer.source);

    return ImagePanelShell(
      title: context.l10n.filtersTool,
      icon: Icons.auto_fix_high_outlined,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header already says "Filters" — no duplicate SectionLabel.
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              // Trailing inset (16dp) lets the last chip's bg pill +
              // its hover tint scroll fully clear of the right edge
              // of the panel — without it the last item visually
              // clipped at narrow widths.
              padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
              itemCount: _allPresets.length,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (context, i) {
                final p = _allPresets[i];
                return _FilterChip(
                  preset: p,
                  imageProvider: provider,
                  selected: layer.filterPreset == p,
                  onTap: () {
                    EditorHaptics.toggle();
                    _commit(ref, p);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Build an `ImageProvider` for the layer's source. Mirrors the
/// resolution logic in `_ImageThumb` (`layer_thumbnail.dart`).
ImageProvider? _providerFor(ImageSource src) {
  final asset = src.assetName;
  final url = src.networkUrl;
  final file = src.filePath;
  if (asset != null) return AssetImage(asset);
  if (url != null) return NetworkImage(url);
  if (file != null && !kIsWeb) return FileImage(File(file));
  return null;
}

const _allPresets = <ImageFilterPreset>[
  ImageFilterPreset.none,
  ImageFilterPreset.warm,
  ImageFilterPreset.cool,
  ImageFilterPreset.vintage,
  ImageFilterPreset.mono,
  ImageFilterPreset.fade,
  ImageFilterPreset.dramatic,
];

String _filterLabel(BuildContext context, ImageFilterPreset preset) {
  return switch (preset) {
    ImageFilterPreset.none => context.l10n.noneOption,
    ImageFilterPreset.warm => context.l10n.warmOption,
    ImageFilterPreset.cool => context.l10n.coolOption,
    ImageFilterPreset.vintage => context.l10n.vintageOption,
    ImageFilterPreset.mono => context.l10n.monoOption,
    ImageFilterPreset.fade => context.l10n.fadeOption,
    ImageFilterPreset.dramatic => context.l10n.dramaOption,
  };
}

class _FilterChip extends StatefulWidget {
  const _FilterChip({
    required this.preset,
    required this.imageProvider,
    required this.selected,
    required this.onTap,
  });

  final ImageFilterPreset preset;
  final ImageProvider? imageProvider;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final selected = widget.selected;
    final matrix = imageFilterMatrix(widget.preset);

    // Unified grammar with DockToolTile / Adjust preset chip:
    // a single bg channel drives hover + pressed + selected so all
    // three states share identical bounds. No glow, no outer ring.
    Color bg;
    if (selected) {
      bg = tokens.accent.withValues(alpha: _down ? 0.18 : 0.12);
    } else if (_down) {
      bg = tokens.accent.withValues(alpha: 0.10);
    } else if (_hover) {
      bg = tokens.textPrimary.withValues(alpha: 0.06);
    } else {
      bg = Colors.transparent;
    }
    final fg = selected ? tokens.accent : tokens.textSecondary;

    // Real-image preview. Decoded at 128px via cacheWidth so memory
    // stays tiny regardless of source resolution. Falls back to a
    // tasteful gradient if the source isn't decodable yet (e.g.
    // network not loaded) — chips remain meaningful.
    Widget preview;
    if (widget.imageProvider != null) {
      preview = Image(
        image: ResizeImage(widget.imageProvider!, width: 128),
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _gradientFallback(),
      );
    } else {
      preview = _gradientFallback();
    }
    if (matrix != null) {
      preview = ColorFiltered(
        colorFilter: ColorFilter.matrix(matrix),
        child: preview,
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(14),
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            focusColor: Colors.transparent,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              width: 72,
              // Vertical padding reduced 6→4 so selected and
              // unselected chips share visually identical heights
              // (badge is now inset, no longer extends bounds).
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Thumbnail with optional ✓ badge inset in the
                  // corner. Inset (not -2 overhang) so the selected
                  // chip occupies the *exact* same bounds as every
                  // other chip — no apparent height lift.
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(width: 60, height: 60, child: preview),
                      ),
                      // Subtle hairline so the thumb edge still
                      // reads on very light/dark images.
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: tokens.border.withValues(alpha: 0.45),
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (selected)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: _SelectedBadge(tokens: tokens),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _filterLabel(context, widget.preset),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: fg,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _gradientFallback() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFFFB36B),
            Color(0xFFE05A8A),
            Color(0xFF4A6CF7),
          ],
        ),
      ),
    );
  }
}

/// Small ✓ badge anchored to the thumbnail corner so the active
/// filter is unmistakable even at a glance, on busy images.
class _SelectedBadge extends StatelessWidget {
  const _SelectedBadge({required this.tokens});
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    // Smaller (16) and inset to keep the selection signal soft —
    // visible at a glance but not visually adding height to the
    // chip card.
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: tokens.accent,
        shape: BoxShape.circle,
        border: Border.all(color: tokens.surface, width: 1.5),
      ),
      child: Icon(Icons.check_rounded, size: 10, color: tokens.onBrand),
    );
  }
}
