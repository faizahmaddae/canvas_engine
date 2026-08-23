import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_tokens.dart';
import '../../../../../core/utils/editor_value_format.dart';
import '../../../../../core/utils/haptics.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../../../l10n/l10n.dart';
import '../../../engine/modules/paint/paint_layer.dart';
import '../../../toolbar/presentation/widgets/preset_chip.dart';
import '../../../toolbar/presentation/widgets/preset_slider_control.dart';
import '../../application/paint_tool_controller.dart';
import '../../domain/paint_tool_type.dart';
import 'paint_fill_body.dart';

/// Shape sheet — everything a box shape is, in one place: the kind
/// (rectangle / circle / hexagon / polygon), the polygon's side
/// count, and the fill. Opened from the Shape rack slot (tap-again)
/// and the bench's fill/sides pills.
///
/// Kind previews render through the ENGINE's [PaintLayerPainter] in
/// the user's own ink, so the catalogue cannot drift from what a
/// committed layer draws. Picking a kind is an in-family variant
/// write ([PaintToolController.selectShapeKind]): a bound box shape
/// restyles in place, and the armed Shape slot keeps the variant.
class PaintShapeBody extends ConsumerWidget {
  const PaintShapeBody({super.key, required this.view});

  final PaintStyleView view;

  static const List<PaintToolType> _kinds = [
    PaintToolType.rectangle,
    PaintToolType.circle,
    PaintToolType.hexagon,
    PaintToolType.polygon,
  ];

  static const List<double> _sidePresets = [3, 4, 5, 6, 8, 12];

  static String _kindLabel(AppLocalizations l10n, PaintToolType kind) =>
      switch (kind) {
        PaintToolType.rectangle => l10n.squareLabel,
        PaintToolType.circle => l10n.circleLabel,
        PaintToolType.hexagon => l10n.hexagonLabel,
        PaintToolType.polygon => l10n.polygonLabel,
        _ => '',
      };

  static PaintToolType? _toolForKind(PaintKind? kind) => switch (kind) {
    PaintKind.rectangle => PaintToolType.rectangle,
    PaintKind.circle => PaintToolType.circle,
    PaintKind.hexagon => PaintToolType.hexagon,
    PaintKind.polygon => PaintToolType.polygon,
    _ => null,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final tokens = AppTokens.of(context);
    final session = ref.watch(paintToolControllerProvider);
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    final values = EditorValueFormat.of(context);
    // Bound kind wins the display (the sheet shows what the write
    // rule targets); otherwise the armed/remembered variant.
    final current =
        _toolForKind(view.layerKind) ??
        (session.activeTool != null && _kinds.contains(session.activeTool)
            ? session.activeTool!
            : session.lastShapeTool);
    final isPolygon = current == PaintToolType.polygon;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _kinds.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: PresetChip.option(
                  label: _kindLabel(l10n, _kinds[i]),
                  selected: current == _kinds[i],
                  maxLabelLines: 1,
                  preview: SizedBox(
                    width: 30,
                    height: 26,
                    child: CustomPaint(
                      painter: _ShapeKindPainter(
                        kind: paintKindForTool(_kinds[i])!,
                        sides: view.sides,
                        color: view.strokeColor.withValues(alpha: 1),
                        fillColor: view.fillColor,
                      ),
                    ),
                  ),
                  onTap: () {
                    EditorHaptics.snap();
                    ctrl.selectShapeKind(_kinds[i]);
                  },
                ),
              ),
            ],
          ],
        ),
        if (isPolygon) ...[
          const SizedBox(height: 14),
          PresetSliderControl(
            label: l10n.sidesTool,
            value: view.sides.toDouble(),
            min: 3,
            max: 24,
            presets: _sidePresets,
            presetLabels: [
              for (final p in _sidePresets) values.digits(p.round()),
            ],
            formatValue: (v) => l10n.sidesCount(v.round()),
            onPreview: (v) => ctrl.previewPolygonSides(v.round()),
            onCommit: (v) => ctrl.commitPolygonSides(v.round()),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          l10n.fillLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: tokens.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        PaintFillBody(view: view),
      ],
    );
  }
}

/// Engine-painter preview of one shape kind in the user's ink. The
/// stroke is clamped to thumbnail scale; fill shows when the user
/// has one, so the catalogue previews the real outcome.
class _ShapeKindPainter extends CustomPainter {
  _ShapeKindPainter({
    required this.kind,
    required this.sides,
    required this.color,
    required this.fillColor,
  });

  final PaintKind kind;
  final int sides;
  final Color color;
  final Color? fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Square box centred in the cell so circles stay circles.
    final side = size.shortestSide;
    final box = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: side,
      height: side,
    );
    canvas.save();
    canvas.translate(box.left, box.top);
    PaintLayerPainter(
      kind: kind,
      normalizedPoints: const [],
      strokeColor: color,
      strokeWidth: 2.2,
      fillColor: fillColor,
      sides: sides,
    ).paint(canvas, box.size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ShapeKindPainter old) =>
      old.kind != kind ||
      old.sides != sides ||
      old.color != color ||
      old.fillColor != fillColor;
}
