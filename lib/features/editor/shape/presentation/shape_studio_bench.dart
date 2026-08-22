import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_icons.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/editor_value_format.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../application/context_toolbar_controller.dart';
import '../../engine/core/background_fill.dart';
import '../../engine/modules/shape/shape_layer.dart';
import '../../presentation/shape_picker_sheet.dart';
import '../../presentation/widgets/editor_breakpoints.dart';
import '../../presentation/widgets/layer_overflow_sheet.dart';
import '../application/shape_tool_controller.dart';

/// The Shape Studio bench — shape mode's persistent dock surface
/// (`docs/shape-studio-redesign-2026-08.md` §4).
///
/// Two rows, the bench family's two questions:
///
///  * **identity row** (top) — *what this shape is*: a live specimen
///    chip (the layer's actual silhouette in its actual dress — fill,
///    radius, stroke — and the door to the Replace picker), and a
///    fact cluster: the layer's size with its resize-mode lock (the
///    toggle that decides what corner-drag does to those numbers)
///    and its opacity (opens the shared opacity panel).
///  * **aspect row** (bottom) — *which aspect you are dressing*:
///    four segments in one connected track — رنگ / کادر / سایه /
///    بیشتر — with badges for the treatments that are live.
///
/// Replaces the six-chip `SlotStrip` (`ShapeModeToolbar`), the last
/// mode still wearing the strip: anonymous icons that said nothing
/// about the shape they edited.
class ShapeStudioBench extends ConsumerWidget {
  const ShapeStudioBench({
    super.key,
    required this.layer,
    required this.onReplaceTap,
  });

  final ShapeLayer layer;

  /// Invoked when the specimen chip is tapped — wired by
  /// editor_screen so the Replace-picker logic stays in one place.
  final VoidCallback onReplaceTap;

  /// Dock strip height while shape mode owns it. The shared bench
  /// envelope, so mode switches reflow between same-sized benches.
  static double dockHeight(BuildContext context) =>
      EditorBreakpoints.isCompact(context) ? 108 : 124;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compact = EditorBreakpoints.isCompact(context);
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(12, compact ? 4 : 8, 12, 6),
      child: Column(
        key: const ValueKey('shape-studio-bench'),
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            // 46 keeps the cluster's tap zones at the 44dp floor once
            // its 1px border is spent on each edge.
            height: compact ? 42 : 46,
            child: _IdentityRow(layer: layer, onReplaceTap: onReplaceTap),
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
  const _IdentityRow({required this.layer, required this.onReplaceTap});

  final ShapeLayer layer;
  final VoidCallback onReplaceTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final values = EditorValueFormat.of(context);
    final contextPanel = ref.watch(contextToolbarControllerProvider);
    final size = layer.transform.size;
    final isScale = layer.effectiveResizeMode == ShapeResizeMode.scale;
    return Row(
      children: [
        Expanded(
          child: _SpecimenChip(
            layer: layer,
            onTap: () {
              EditorHaptics.tap();
              ref.read(shapeToolControllerProvider.notifier).closePanel();
              ref.read(contextToolbarControllerProvider.notifier).closePanel();
              onReplaceTap();
            },
          ),
        ),
        const SizedBox(width: 8),
        _FactCluster(
          sizeLabel: values.dimensionsPlain(
            size.width.round(),
            size.height.round(),
          ),
          isScale: isScale,
          opacityLabel: values.percent((layer.opacity * 100).round()),
          opacityActive: contextPanel == ContextToolPanel.opacity,
          onSizeTap: () {
            // The toggle that governs the numbers shown: what
            // corner-drag does to W × H. Same affordance as the
            // overflow sheet's resize-behaviour row, one undo entry.
            EditorHaptics.toggle();
            ref
                .read(shapeToolControllerProvider.notifier)
                .setResizeMode(
                  isScale ? ShapeResizeMode.free : ShapeResizeMode.scale,
                );
          },
          onOpacityTap: () {
            EditorHaptics.tap();
            ref.read(shapeToolControllerProvider.notifier).closePanel();
            ref
                .read(contextToolbarControllerProvider.notifier)
                .toggle(ContextToolPanel.opacity);
          },
        ),
      ],
    );
  }
}

/// The live specimen: the layer's actual silhouette in its actual
/// dress — fill (solid or gradient), corner radius, stroke — plus
/// the kind's localized name. The picture IS the state display, and
/// tapping it changes the shape (the Replace picker), the same door
/// grammar as the image bench's specimen.
class _SpecimenChip extends StatelessWidget {
  const _SpecimenChip({required this.layer, required this.onTap});

  final ShapeLayer layer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = context.l10n;
    return Semantics(
      button: true,
      label: l10n.replaceShapeTitle,
      child: Material(
        key: const ValueKey('shape-specimen'),
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
            padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 10, 4),
            child: Row(
              children: [
                _ShapeThumb(layer: layer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    shapeKindLabel(l10n, layer.kind),
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

/// The specimen's picture: the real silhouette painted with the
/// layer's real fill/stroke, scaled into a thumb box so the chip
/// never lies about the treatment.
class _ShapeThumb extends StatelessWidget {
  const _ShapeThumb({required this.layer});

  final ShapeLayer layer;

  static const double _extent = 30;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _extent,
      height: _extent,
      child: CustomPaint(painter: _ShapeThumbPainter(layer)),
    );
  }
}

class _ShapeThumbPainter extends CustomPainter {
  const _ShapeThumbPainter(this.layer);

  final ShapeLayer layer;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // Corner radius scaled with the thumb so a rounded rectangle
    // reads exactly as round as the layer on canvas does.
    final layerShort = layer.transform.size.shortestSide;
    final radius = layerShort > 0
        ? layer.cornerRadius * (size.shortestSide / layerShort)
        : 0.0;
    final path = shapeOutlinePath(layer.kind, size, cornerRadius: radius);
    if (isStrokedShapeKind(layer.kind)) {
      // Line-family kinds: the fill colour IS the stroke colour.
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 3
          ..color = layer.fillColor,
      );
      return;
    }
    final fill = layer.effectiveFill;
    final paint = Paint()..style = PaintingStyle.fill;
    switch (fill) {
      case SolidBackground(:final color):
        paint.color = color.withValues(
          alpha: color.a * layer.fillOpacity.clamp(0.0, 1.0),
        );
      case LinearGradientBackground():
        paint.shader = fill.toFlutterGradient().createShader(
          Offset.zero & size,
        );
      case RadialGradientBackground():
        paint.shader = fill.toFlutterGradient().createShader(
          Offset.zero & size,
        );
    }
    canvas.drawPath(path, paint);
    if (layer.strokeColor != null && layer.strokeWidth > 0) {
      // A 2dp indicator stroke — says the border is on, not to
      // scale (mirrors the image specimen's mask stroke).
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 2
          ..color = layer.strokeColor!,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ShapeThumbPainter old) =>
      old.layer.kind != layer.kind ||
      old.layer.fillColor != layer.fillColor ||
      old.layer.fill != layer.fill ||
      old.layer.fillOpacity != layer.fillOpacity ||
      old.layer.strokeColor != layer.strokeColor ||
      old.layer.strokeWidth != layer.strokeWidth ||
      old.layer.cornerRadius != layer.cornerRadius ||
      old.layer.transform.size != layer.transform.size;
}

/// The shape's two headline numbers as one bordered instrument (the
/// shared fact-cluster grammar): size — with the resize-mode lock
/// that decides what corner-drag does to it — and opacity, which
/// opens the shared opacity panel.
class _FactCluster extends StatelessWidget {
  const _FactCluster({
    required this.sizeLabel,
    required this.isScale,
    required this.opacityLabel,
    required this.opacityActive,
    required this.onSizeTap,
    required this.onOpacityTap,
  });

  final String sizeLabel;
  final bool isScale;
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
            onTap: onTap,
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
            key: const ValueKey('shape-pill-size'),
            semanticLabel: isScale
                ? context.l10n.resizeBehaviorScaleSemantics
                : context.l10n.resizeBehaviorFreeSemantics,
            active: false,
            onTap: onSizeTap,
            radius: const BorderRadiusDirectional.horizontal(start: innerR),
            constraints: const BoxConstraints(minWidth: 84, maxWidth: 132),
            // scaleDown: a huge canvas (or a wide test font) shrinks
            // the glyph+number pair slightly instead of clipping a
            // digit — dimensions must never lie by truncation.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The same glyph pair as the overflow sheet's
                  // resize-behaviour row, so the state reads as one
                  // concept everywhere.
                  Icon(
                    isScale ? AppIcons.canvasSize : AppIcons.freeRegion,
                    size: 13,
                    color: tokens.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Text(
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
                ],
              ),
            ),
          ),
          Container(
            width: 1,
            height: 20,
            color: tokens.border.withValues(alpha: 0.7),
          ),
          zone(
            key: const ValueKey('shape-pill-opacity'),
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

  final ShapeLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(shapeToolControllerProvider.notifier);
    final contextCtrl = ref.read(contextToolbarControllerProvider.notifier);
    final openSlot = ref.watch(
      shapeToolControllerProvider.select((s) => s.openSlot),
    );
    final l10n = context.l10n;
    final tokens = AppTokens.of(context);

    // Treatment badges: which parts of the dress are live right now,
    // in their own colours — the segment says what is on before its
    // panel opens.
    final styleBadges = <Color>[
      if (layer.effectiveFill is! SolidBackground) tokens.accent,
    ];
    final borderBadges = <Color>[
      if (!isStrokedShapeKind(layer.kind) &&
          layer.strokeColor != null &&
          layer.strokeWidth > 0)
        layer.strokeColor!,
    ];
    final shadowBadges = <Color>[
      if (layer.shadowOpacity > 0) layer.shadowColor,
    ];

    void toggleSlot(ShapeToolSlot slot) {
      contextCtrl.closePanel();
      ctrl.toggleSlot(slot);
    }

    // ONE connected track, four faces — the bench family's aspect
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
              key: const ValueKey('shape-aspect-style'),
              icon: AppIcons.colorTool,
              label: l10n.colorLabel,
              active: openSlot == ShapeToolSlot.style,
              badges: styleBadges,
              onTap: () => toggleSlot(ShapeToolSlot.style),
            ),
          ),
          _segmentDivider(tokens),
          Expanded(
            child: _AspectSegment(
              key: const ValueKey('shape-aspect-border'),
              icon: AppIcons.borderTool,
              label: l10n.borderTool,
              active: openSlot == ShapeToolSlot.border,
              badges: borderBadges,
              onTap: () => toggleSlot(ShapeToolSlot.border),
            ),
          ),
          _segmentDivider(tokens),
          Expanded(
            child: _AspectSegment(
              key: const ValueKey('shape-aspect-shadow'),
              icon: AppIcons.shadowTool,
              label: l10n.shadowTool,
              active: openSlot == ShapeToolSlot.shadow,
              badges: shadowBadges,
              onTap: () => toggleSlot(ShapeToolSlot.shadow),
            ),
          ),
          _segmentDivider(tokens),
          Expanded(
            child: _AspectSegment(
              key: const ValueKey('shape-aspect-more'),
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
