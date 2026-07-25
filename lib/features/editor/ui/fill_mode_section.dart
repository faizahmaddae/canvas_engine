import 'package:flutter/material.dart';

import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/utils/editor_value_format.dart';
import '../../../core/utils/haptics.dart';
import '../../../l10n/l10n.dart';
import '../../color_picker/presentation/color_picker_sheet.dart';
import '../engine/core/background_fill.dart';
import 'editor_segmented_control.dart';
import 'editor_slider_row.dart';
import '../../../app/theme/app_icons.dart';

/// Solid | Gradient fill control shared by the shape Style panel and
/// the canvas Background panel (tb4 2/14).
///
/// The engine has carried gradient fills since the template system
/// shipped — `BackgroundFill` is sealed over solid/linear/radial, both
/// `SetShapeFillCommand` and `SetCanvasBackgroundCommand` install and
/// invert a full descriptor — but there was no way to *author* one.
/// A user who tapped a swatch on a template's gradient shape replaced
/// it with a flat colour and could never get it back except by undo.
///
/// Scope is deliberately two stops: a curated preset row plus an angle
/// for linear gradients. A per-stop editor (arbitrary colours, N stops,
/// radial focal point) is backlog — this closes the authoring hole
/// without inventing a second colour system.
///
/// Radial gradients (templates author them) are recognised and shown
/// as "Gradient", and any edit converts them to the linear form the
/// presets speak. Nothing silently discards them: until the user edits,
/// the radial fill is preserved verbatim.
class FillModeSection extends StatelessWidget {
  const FillModeSection({
    super.key,
    required this.fill,
    required this.solidTitle,
    required this.onSolidChanged,
    required this.onSolidCommitted,
    required this.onFillChanged,
    required this.onFillCommitted,
  });

  /// The fill currently on the layer / document.
  final BackgroundFill fill;

  /// Title for the embedded colour picker in Solid mode.
  final String solidTitle;

  /// Streaming (live) solid-colour updates from a picker drag.
  final ValueChanged<Color> onSolidChanged;

  /// The settled solid colour — one undo entry.
  final ValueChanged<Color> onSolidCommitted;

  /// Streaming (live) gradient updates from the angle drag.
  final ValueChanged<BackgroundFill> onFillChanged;

  /// The settled gradient — one undo entry.
  final ValueChanged<BackgroundFill> onFillCommitted;

  bool get _isGradient => fill is! SolidBackground;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EditorSegmentedControl<bool>(
          value: _isGradient,
          segments: [
            EditorSegment(
              value: false,
              label: l10n.solidOption,
              itemKey: const ValueKey('fill-mode-solid'),
            ),
            EditorSegment(
              value: true,
              label: l10n.effectGradientLabel,
              itemKey: const ValueKey('fill-mode-gradient'),
            ),
          ],
          onChanged: (wantGradient) {
            if (wantGradient == _isGradient) return;
            EditorHaptics.toggle();
            if (wantGradient) {
              onFillCommitted(_gradientFromSeed(_seedColor(fill)));
            } else {
              onSolidCommitted(_seedColor(fill));
            }
          },
        ),
        const SizedBox(height: 12),
        if (!_isGradient)
          ColorPickerBody(
            initial: _seedColor(fill),
            title: solidTitle,
            onChanged: onSolidChanged,
            onCommitted: onSolidCommitted,
          )
        else
          _GradientControls(
            fill: fill,
            onChanged: onFillChanged,
            onCommitted: onFillCommitted,
          ),
      ],
    );
  }
}

/// Preset row + angle slider. Stateful so the settled command is
/// built from the value the user actually released on, not from
/// whatever the host echoed back mid-stream.
class _GradientControls extends StatefulWidget {
  const _GradientControls({
    required this.fill,
    required this.onChanged,
    required this.onCommitted,
  });

  final BackgroundFill fill;
  final ValueChanged<BackgroundFill> onChanged;
  final ValueChanged<BackgroundFill> onCommitted;

  @override
  State<_GradientControls> createState() => _GradientControlsState();
}

class _GradientControlsState extends State<_GradientControls> {
  /// Non-null only while an angle drag is in flight.
  double? _dragAngle;

  @override
  Widget build(BuildContext context) {
    final fill = widget.fill;
    final onChanged = widget.onChanged;
    final onCommitted = widget.onCommitted;
    final linear = fill is LinearGradientBackground ? fill : null;
    final angle = _dragAngle ?? linear?.angleDegrees ?? kDefaultGradientAngle;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsetsDirectional.fromSTEB(2, 0, 12, 0),
            itemCount: kGradientPresets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final preset = kGradientPresets[i];
              final selected =
                  linear != null &&
                  linear.startColor == preset.$1 &&
                  linear.endColor == preset.$2;
              return _GradientSwatch(
                key: ValueKey('gradient-preset-$i'),
                start: preset.$1,
                end: preset.$2,
                angleDegrees: angle,
                selected: selected,
                onTap: () {
                  EditorHaptics.toggle();
                  onCommitted(
                    LinearGradientBackground(
                      startColor: preset.$1,
                      endColor: preset.$2,
                      angleDegrees: angle,
                    ),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        EditorSliderRow(
          label: context.l10n.angleLabel,
          labelWidth: 56,
          readoutWidth: 52,
          value: angle,
          max: 360,
          format: (v) => EditorValueFormat.of(context).degrees(v.round()),
          semanticLabel: context.l10n.angleLabel,
          onChanged: (v) {
            setState(() => _dragAngle = v);
            onChanged(_withAngle(fill, v));
          },
          // Fires on pointer-cancel too, so an interrupted drag still
          // commits the last previewed angle (contract §7).
          onDragEnd: () {
            final settled = _dragAngle;
            setState(() => _dragAngle = null);
            if (settled != null) onCommitted(_withAngle(fill, settled));
          },
        ),
      ],
    );
  }
}

/// A rounded chip painted with the gradient it installs.
class _GradientSwatch extends StatelessWidget {
  const _GradientSwatch({
    super.key,
    required this.start,
    required this.end,
    required this.angleDegrees,
    required this.selected,
    required this.onTap,
  });

  final Color start;
  final Color end;
  final double angleDegrees;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final gradient = LinearGradientBackground(
      startColor: start,
      endColor: end,
      angleDegrees: angleDegrees,
    ).toFlutterGradient();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.standard,
        curve: AppMotion.curve,
        width: 56,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? tokens.accent
                : tokens.border.withValues(alpha: 0.4),
            width: selected ? 2 : 1,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(11),
          ),
          child: selected
              ? Center(
                  child: Icon(
                    AppIcons.confirm,
                    size: 16,
                    color: tokens.onBrand,
                  ),
                )
              : const SizedBox.expand(),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fill helpers
// ---------------------------------------------------------------------------

/// Default flow direction for a freshly authored gradient: the
/// top-left → bottom-right diagonal `LinearGradientBackground` already
/// documents as its own default.
const double kDefaultGradientAngle = 135;

/// Curated two-stop pairs. These are CONTENT (like the filter
/// preset matrices), not theme chrome: they must look identical in
/// light and dark because they are pixels of the user's document, so
/// they deliberately do not resolve through [AppTokens].
const List<(Color, Color)> kGradientPresets = <(Color, Color)>[
  (Color(0xFFF5B942), Color(0xFFE2703A)), // saffron → ember
  (Color(0xFFFFB36B), Color(0xFFE05A8A)), // apricot → rose
  (Color(0xFFF4A6C0), Color(0xFFB3577E)), // blossom → plum
  (Color(0xFF8FD3F4), Color(0xFF4A6CF7)), // sky → indigo
  (Color(0xFF5FD3C4), Color(0xFF2A7B8C)), // mint → teal
  (Color(0xFFB7F8C8), Color(0xFF3FA796)), // leaf → pine
  (Color(0xFFFFF6E5), Color(0xFFE8CFA0)), // paper → sand
  (Color(0xFF3A3A55), Color(0xFF101018)), // dusk → ink
];

/// The single colour that best represents [fill] — what Solid mode
/// shows when the user switches away from a gradient.
Color _seedColor(BackgroundFill fill) => switch (fill) {
  SolidBackground(:final color) => color,
  LinearGradientBackground(:final startColor) => startColor,
  RadialGradientBackground(:final centerColor) => centerColor,
};

/// Build a gradient that reads as "the current colour, but graded":
/// the seed flows into a deeper, slightly warmer variant of itself so
/// switching modes is a visible-but-recognisable change rather than a
/// jump to an unrelated palette.
LinearGradientBackground _gradientFromSeed(Color seed) {
  final hsl = HSLColor.fromColor(seed);
  final end = hsl
      .withLightness((hsl.lightness - 0.22).clamp(0.0, 1.0))
      .withSaturation((hsl.saturation + 0.12).clamp(0.0, 1.0))
      .toColor();
  return LinearGradientBackground(
    startColor: seed,
    endColor: end,
    angleDegrees: kDefaultGradientAngle,
  );
}

/// Re-angle [fill]. A radial fill converts to the linear form the
/// angle control speaks, keeping its two colours.
LinearGradientBackground _withAngle(BackgroundFill fill, double angleDegrees) =>
    switch (fill) {
      LinearGradientBackground(
        :final startColor,
        :final endColor,
        :final stops,
      ) =>
        LinearGradientBackground(
          startColor: startColor,
          endColor: endColor,
          angleDegrees: angleDegrees,
          stops: stops,
        ),
      RadialGradientBackground(:final centerColor, :final edgeColor) =>
        LinearGradientBackground(
          startColor: centerColor,
          endColor: edgeColor,
          angleDegrees: angleDegrees,
        ),
      SolidBackground(:final color) => LinearGradientBackground(
        startColor: color,
        endColor: color,
        angleDegrees: angleDegrees,
      ),
    };
