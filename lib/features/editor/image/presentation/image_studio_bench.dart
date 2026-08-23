import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_icons.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/editor_value_format.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../application/context_toolbar_controller.dart';
import '../../crop/application/crop_controller.dart';
import '../../engine/modules/image/image_layer.dart';
import '../../engine/modules/image/image_source_provider.dart';
import '../../presentation/widgets/editor_breakpoints.dart';
import '../../presentation/widgets/layer_overflow_sheet.dart';
import '../application/image_tool_controller.dart';
import 'image_replace_flow.dart';

/// The Image Studio bench — image mode's persistent dock surface
/// (`docs/image-studio-redesign-2026-08.md` §2).
///
/// Two rows, the bench family's two questions:
///
///  * **identity row** (top) — *what this photo is*: a live specimen
///    chip (the layer's pixels with their real treatment — filter,
///    silhouette, border — and the door to the replace flow), and a
///    fact cluster: the layer's canvas size (opens Crop, the tool
///    that changes the number) and its opacity (opens the shared
///    opacity panel).
///  * **aspect row** (bottom) — *which aspect you are dressing*:
///    four segments in one connected track — برش / نما / سبک /
///    بیشتر — with the نما and سبک segments carrying badges for the
///    treatments that are live right now.
///
/// Replaces the ten-tile `SlotStrip` (`ImageModeToolbar`): ten
/// anonymous icons, four past the scroll fold, none of which said
/// anything about the photo they edited.
class ImageStudioBench extends ConsumerWidget {
  const ImageStudioBench({super.key, required this.layer});

  final ImageLayer layer;

  /// Dock strip height while image mode owns it. The paint/text
  /// benches' envelope, so mode switches reflow between same-sized
  /// benches.
  static double dockHeight(BuildContext context) =>
      EditorBreakpoints.isCompact(context) ? 108 : 124;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compact = EditorBreakpoints.isCompact(context);
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(12, compact ? 4 : 8, 12, 6),
      child: Column(
        key: const ValueKey('image-studio-bench'),
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            // 46 keeps the cluster's tap zones at the 44dp floor once
            // its 1px border is spent on each edge.
            height: compact ? 42 : 46,
            child: _IdentityRow(layer: layer),
          ),
          SizedBox(height: compact ? 4 : 8),
          Expanded(child: _AspectRow(layer: layer)),
        ],
      ),
    );
  }
}

/// D-e (tb5 accessibility decision): editor chrome clamps its text
/// scale to 1.0–1.3 — the bench's fixed two-row envelope cannot grow
/// with the system setting.
TextScaler _benchTextScaler(BuildContext context) => MediaQuery.textScalerOf(
  context,
).clamp(minScaleFactor: 1.0, maxScaleFactor: 1.3);

// ─────────────────────────────────────────────────────────────────
// Identity row
// ─────────────────────────────────────────────────────────────────

class _IdentityRow extends ConsumerWidget {
  const _IdentityRow({required this.layer});

  final ImageLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final values = EditorValueFormat.of(context);
    final contextPanel = ref.watch(contextToolbarControllerProvider);
    final size = layer.transform.size;
    return Row(
      children: [
        Expanded(
          child: _SpecimenChip(
            layer: layer,
            onTap: () {
              EditorHaptics.tap();
              ref.read(imageToolControllerProvider.notifier).closePanel();
              ref.read(contextToolbarControllerProvider.notifier).closePanel();
              replaceImageLayer(
                context,
                ref,
                layer,
                debugLabel: 'imageBench/replaceImageLayer',
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        _FactCluster(
          sizeLabel: values.dimensionsPlain(
            size.width.round(),
            size.height.round(),
          ),
          opacityLabel: values.percent((layer.opacity * 100).round()),
          opacityActive: contextPanel == ContextToolPanel.opacity,
          onSizeTap: () {
            EditorHaptics.tap();
            ref.read(contextToolbarControllerProvider.notifier).closePanel();
            // Close any open dock sheet first so leaving crop mode
            // doesn't reveal a stale panel.
            ref.read(imageToolControllerProvider.notifier).closePanel();
            // Launched from the image bench: the user clearly wants
            // the image to stay selected after Done.
            ref
                .read(cropControllerProvider.notifier)
                .openCrop(layer.id, priorSelectionId: layer.id);
          },
          onOpacityTap: () {
            EditorHaptics.tap();
            ref.read(imageToolControllerProvider.notifier).closePanel();
            ref
                .read(contextToolbarControllerProvider.notifier)
                .toggle(ContextToolPanel.opacity);
          },
        ),
      ],
    );
  }
}

/// The live specimen: the layer's own pixels with their real
/// treatment — filter matrix, silhouette mask, border — on a card.
/// The picture IS the state display, and tapping it changes the
/// picture (the replace flow), the analog of the text specimen's
/// door back to writing.
class _SpecimenChip extends StatelessWidget {
  const _SpecimenChip({required this.layer, required this.onTap});

  final ImageLayer layer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      label: imageReplacementActionLabel(context, layer),
      child: Material(
        key: const ValueKey('image-specimen'),
        color: tokens.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tokens.border.withValues(alpha: 0.7)),
            ),
            padding: const EdgeInsetsDirectional.fromSTEB(6, 4, 10, 4),
            child: Row(
              children: [
                _TreatedThumb(layer: layer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    imageReplacementTileLabel(context, layer),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: _benchTextScaler(context),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                Icon(AppIcons.replace, size: 16, color: tokens.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The specimen's picture: decoded small, graded with the layer's
/// composed look matrix, clipped by its silhouette mask, and — when
/// a border is on — stroked along that same path, so the thumb never
/// lies about the treatment.
class _TreatedThumb extends StatelessWidget {
  const _TreatedThumb({required this.layer});

  final ImageLayer layer;

  static const double _extent = 34;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final provider = imageProviderFor(layer.source);
    Widget pixels = provider == null
        ? Icon(AppIcons.replace, size: 18, color: tokens.textSecondary)
        : Image(
            image: ResizeImage(provider, width: 128),
            width: _extent,
            height: _extent,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => DecoratedBox(
              decoration: BoxDecoration(color: tokens.surfaceMuted),
              child: Icon(
                AppIcons.replace,
                size: 16,
                color: tokens.textSecondary,
              ),
            ),
          );
    final matrix = _lookMatrix(layer);
    if (matrix != null) {
      pixels = ColorFiltered(
        colorFilter: ColorFilter.matrix(matrix),
        child: pixels,
      );
    }
    return SizedBox(
      width: _extent,
      height: _extent,
      child: ClipPath(
        clipper: _MaskThumbClipper(layer.mask),
        child: Stack(
          fit: StackFit.expand,
          children: [
            pixels,
            if (layer.borderWidth > 0)
              IgnorePointer(
                child: CustomPaint(
                  painter: _MaskStrokePainter(
                    mask: layer.mask,
                    color: layer.borderColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Filter preset ∘ effect-stack adjustments, in render order —
  /// the same composition `ImageLayer.buildContent` applies.
  static List<double>? _lookMatrix(ImageLayer layer) {
    final filter = imageFilterMatrix(layer.filterPreset);
    final adjustments = layer.effects.composedColorMatrix;
    if (filter == null) return adjustments;
    if (adjustments == null) return filter;
    return composeColorMatrices(adjustments, filter);
  }
}

class _MaskThumbClipper extends CustomClipper<Path> {
  const _MaskThumbClipper(this.mask);
  final ImageMask mask;

  @override
  Path getClip(Size size) => imageMaskPath(mask, size);

  @override
  bool shouldReclip(covariant _MaskThumbClipper old) => old.mask != mask;
}

/// A 2dp stroke of the layer's border colour along the mask path —
/// an indicator that the border is on, not a to-scale rendering.
class _MaskStrokePainter extends CustomPainter {
  const _MaskStrokePainter({required this.mask, required this.color});
  final ImageMask mask;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      imageMaskPath(mask, size),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _MaskStrokePainter old) =>
      old.mask != mask || old.color != color;
}

/// The photo's two headline numbers as one bordered instrument (the
/// text bench's type-cluster grammar): canvas size — which opens
/// Crop, the tool that changes it — and opacity, which opens the
/// shared opacity panel.
class _FactCluster extends StatelessWidget {
  const _FactCluster({
    required this.sizeLabel,
    required this.opacityLabel,
    required this.opacityActive,
    required this.onSizeTap,
    required this.onOpacityTap,
  });

  final String sizeLabel;
  final String opacityLabel;
  final bool opacityActive;
  final VoidCallback onSizeTap;
  final VoidCallback onOpacityTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    Widget zone({
      required Key key,
      required String semanticLabel,
      required bool active,
      required VoidCallback onTap,
      required Widget child,
      required BorderRadiusDirectional radius,
      required BoxConstraints constraints,
    }) {
      return Semantics(
        button: true,
        label: semanticLabel,
        child: Material(
          color: active
              ? tokens.accent.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: radius.resolve(Directionality.of(context)),
          child: InkWell(
            key: key,
            borderRadius: radius.resolve(Directionality.of(context)),
            onTap: () {
              EditorHaptics.tap();
              onTap();
            },
            child: Container(
              constraints: constraints,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              child: ExcludeSemantics(child: child),
            ),
          ),
        ),
      );
    }

    // The inner radius hugs the outer 12 minus the 1px border.
    const innerR = Radius.circular(11);
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          zone(
            key: const ValueKey('image-pill-size'),
            semanticLabel: context.l10n.cropImageAction,
            active: false,
            onTap: onSizeTap,
            radius: const BorderRadiusDirectional.horizontal(start: innerR),
            constraints: const BoxConstraints(minWidth: 72, maxWidth: 118),
            child: Text(
              sizeLabel,
              maxLines: 1,
              // A dimension pair reads width-then-height in every
              // locale — pinned LTR like the editor's other value
              // readouts.
              textDirection: TextDirection.ltr,
              textScaler: _benchTextScaler(context),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Container(
            width: 1,
            height: 20,
            color: tokens.border.withValues(alpha: 0.7),
          ),
          zone(
            key: const ValueKey('image-pill-opacity'),
            semanticLabel: context.l10n.opacityLabel,
            active: opacityActive,
            onTap: onOpacityTap,
            radius: const BorderRadiusDirectional.horizontal(end: innerR),
            constraints: const BoxConstraints(minWidth: 52, maxWidth: 76),
            child: Text(
              opacityLabel,
              textScaler: _benchTextScaler(context),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: opacityActive ? tokens.accentText : tokens.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Aspect row
// ─────────────────────────────────────────────────────────────────

class _AspectRow extends ConsumerWidget {
  const _AspectRow({required this.layer});

  final ImageLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(imageToolControllerProvider.notifier);
    final contextCtrl = ref.read(contextToolbarControllerProvider.notifier);
    final openSlot = ref.watch(
      imageToolControllerProvider.select((s) => s.openSlot),
    );
    final l10n = context.l10n;
    final tokens = AppTokens.of(context);

    // Treatment badges: which parts of the look/silhouette are live
    // right now, in their own colours where they have one — the chip
    // says what is on before any sheet opens.
    final lookBadges = <Color>[
      if (layer.filterPreset != ImageFilterPreset.none) tokens.accent,
      if (layer.effects.effects.isNotEmpty) tokens.textSecondary,
    ];
    final styleBadges = <Color>[
      if (layer.mask != ImageMask.original) tokens.accent,
      if (layer.borderWidth > 0) layer.borderColor,
      if (layer.shadowOpacity > 0) layer.shadowColor,
    ];

    void toggleSlot(ImageToolSlot slot) {
      contextCtrl.closePanel();
      ctrl.toggleSlot(slot);
    }

    // ONE connected track, four faces — the text bench's aspect
    // grammar verbatim so mode switches feel like the same room.
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceMuted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: tokens.border.withValues(alpha: 0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        // Stretch, not center: a segment's tap target is the track's
        // full height, never the 18dp its icon+label happen to need.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _AspectSegment(
              key: const ValueKey('image-aspect-crop'),
              icon: AppIcons.cropTool,
              label: l10n.cropTool,
              active: false,
              onTap: () {
                contextCtrl.closePanel();
                // Close any open sheet so leaving crop mode doesn't
                // reveal a stale panel.
                ctrl.closePanel();
                ref
                    .read(cropControllerProvider.notifier)
                    .openCrop(layer.id, priorSelectionId: layer.id);
              },
            ),
          ),
          _segmentDivider(tokens),
          Expanded(
            child: _AspectSegment(
              key: const ValueKey('image-aspect-look'),
              icon: AppIcons.lookTool,
              label: l10n.lookTool,
              active: openSlot == ImageToolSlot.look,
              badges: lookBadges,
              onTap: () => toggleSlot(ImageToolSlot.look),
            ),
          ),
          _segmentDivider(tokens),
          Expanded(
            child: _AspectSegment(
              key: const ValueKey('image-aspect-style'),
              icon: AppIcons.stylePresets,
              label: l10n.styleTool,
              active: openSlot == ImageToolSlot.style,
              badges: styleBadges,
              onTap: () => toggleSlot(ImageToolSlot.style),
            ),
          ),
          _segmentDivider(tokens),
          Expanded(
            child: _AspectSegment(
              key: const ValueKey('image-aspect-more'),
              icon: AppIcons.moreActions,
              label: l10n.moreLabel,
              active: false,
              onTap: () {
                ctrl.closePanel();
                contextCtrl.closePanel();
                final scaffold = Scaffold.maybeOf(context);
                showLayerOverflowSheet(
                  context,
                  ref,
                  layer: layer,
                  onOpenLayers: scaffold == null
                      ? null
                      : () => scaffold.openEndDrawer(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static Widget _segmentDivider(AppTokens tokens) => Container(
    width: 1,
    margin: const EdgeInsets.symmetric(vertical: 8),
    color: tokens.border.withValues(alpha: 0.55),
  );
}

/// One segment of the aspect track: icon + label (+ treatment
/// badges). The active segment carries the accent tint edge-to-edge
/// inside the shared track.
class _AspectSegment extends StatelessWidget {
  const _AspectSegment({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badges = const <Color>[],
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final List<Color> badges;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: active
            ? tokens.accent.withValues(alpha: 0.14)
            : Colors.transparent,
        child: InkWell(
          onTap: () {
            EditorHaptics.tap();
            onTap();
          },
          child: ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: active ? tokens.accentText : tokens.textSecondary,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: _benchTextScaler(context),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: active ? tokens.accentText : tokens.textPrimary,
                    ),
                  ),
                ),
                if (badges.isNotEmpty) ...[
                  const SizedBox(width: 5),
                  for (final c in badges)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 2),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: tokens.surface.withValues(alpha: 0.8),
                            width: 0.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
