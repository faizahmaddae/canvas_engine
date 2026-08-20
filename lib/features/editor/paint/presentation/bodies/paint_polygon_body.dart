import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_tokens.dart';
import '../../../../../core/utils/editor_value_format.dart';
import '../../../../../l10n/l10n.dart';
import '../../../engine/modules/paint/paint_layer.dart';
import '../../../toolbar/presentation/widgets/preset_slider_control.dart';
import '../../application/paint_tool_controller.dart';

/// Polygon Sides body — the same hero + [PresetSliderControl]
/// composition Size uses, so every numeric paint tool speaks one
/// grammar. The old body offered eight fixed chips over an engine
/// range of 3–24: any other value was unreachable and got clobbered
/// the moment a chip was tapped (ux-audit: preset-clobbers). The
/// slider now covers the whole range; the presets stay as the fast
/// picks.
///
/// The hero renders through the ENGINE's [PaintLayerPainter] — for
/// polygon the bounding box IS the shape and `normalizedPoints` is
/// unused — so the preview cannot drift from what a committed layer
/// draws (the old `_PolygonHeroPainter` was a third hand-copy of the
/// vertex-angle formula; ux-audit: vertex-math-triplicated).
class PaintPolygonBody extends ConsumerWidget {
  const PaintPolygonBody({super.key, required this.view});

  final PaintStyleView view;

  static const List<double> _presets = [3, 4, 5, 6, 8, 12];
  static const double _min = 3;
  static const double _max = 24;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    final values = EditorValueFormat.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PolygonHero(
          sides: view.sides,
          strokeColor: view.strokeColor,
          strokeWidth: view.strokeWidth,
          fillColor: view.fillColor,
        ),
        const SizedBox(height: 14),
        PresetSliderControl(
          value: view.sides.toDouble(),
          min: _min,
          max: _max,
          presets: _presets,
          presetLabels: [for (final p in _presets) values.digits(p.round())],
          formatValue: (v) => context.l10n.sidesCount(v.round()),
          onPreview: (v) => ctrl.previewPolygonSides(v.round()),
          onCommit: (v) => ctrl.commitPolygonSides(v.round()),
        ),
      ],
    );
  }
}

/// Live preview of the polygon at the current side count, drawn by
/// the engine painter in the user's own stroke/fill.
class _PolygonHero extends StatelessWidget {
  const _PolygonHero({
    required this.sides,
    required this.strokeColor,
    required this.strokeWidth,
    required this.fillColor,
  });

  final int sides;
  final Color strokeColor;
  final double strokeWidth;
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      height: 88,
      decoration: BoxDecoration(
        color: tokens.surfaceMuted.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderStrong),
      ),
      padding: const EdgeInsets.all(12),
      child: Center(
        // Square so the polygon renders regular, exactly like a
        // committed square-box layer.
        child: AspectRatio(
          aspectRatio: 1,
          child: CustomPaint(
            painter: PaintLayerPainter(
              kind: PaintKind.polygon,
              normalizedPoints: const [],
              strokeColor: strokeColor,
              // The hero is a thumbnail of a canvas-scale shape:
              // clamp the visual stroke so an 80px width doesn't
              // swallow the 64px preview box.
              strokeWidth: strokeWidth.clamp(1, 6),
              fillColor: fillColor,
              sides: sides,
            ),
          ),
        ),
      ),
    );
  }
}
