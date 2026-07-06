// Background/Border/Shadow decoration sub-tool panels for the
// text-mode toolbar, split out of text_mode_toolbar.dart. Part file:
// every symbol resolves via the library root's imports — add
// imports there, never here.
part of 'text_mode_toolbar.dart';

/// "Adjust precisely" disclosure for the Background panel. Same
/// flat header treatment as `_SizePrecisionAdvanced` and the
/// Layout cards: whole row is tappable, single chevron, no nested
/// arrows. Hosts four [EditorSliderRow]s when expanded.
class _BackgroundPrecisionAdvanced extends ConsumerWidget {
  const _BackgroundPrecisionAdvanced({required this.style});
  final TextStyleSpec style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final bg = style.backgroundColor;
    final labelStyle = flatSliderLabelStyle(context);
    final readoutStyle = flatSliderReadoutStyle(context);
    return PrecisionDisclosure(
      titleClosed: context.l10n.adjustPrecisely,
      titleOpen: context.l10n.hidePreciseControls,
      chevronSize: 18,
      children: [
        const PrecisionDivider(),
        EditorSliderRow(
          label: context.l10n.roundnessLabel,
          labelWidth: 96,
          // backgroundRadius is a percent (0..1) of the box's
          // shorter side; UI drives 0..100 directly.
          value: (style.backgroundRadius * 100).clamp(0.0, 100.0),
          max: 100,
          format: (v) => '${v.toStringAsFixed(0)}%',
          onChanged: (v) => ctrl.setBackgroundRadius(v / 100),
          onDragStart: ctrl.beginStyleDrag,
          onDragEnd: ctrl.endStyleDrag,
          haptics: EditorSliderHaptics.startTickEnd,
          labelStyle: labelStyle,
          readoutStyle: readoutStyle,
        ),
        EditorSliderRow(
          label: context.l10n.verticalPaddingLabel,
          labelWidth: 96,
          value: style.backgroundPaddingY,
          max: 64,
          format: (v) => '${v.toStringAsFixed(0)}px',
          onChanged: ctrl.setBackgroundPaddingY,
          onDragStart: ctrl.beginStyleDrag,
          onDragEnd: ctrl.endStyleDrag,
          haptics: EditorSliderHaptics.startTickEnd,
          labelStyle: labelStyle,
          readoutStyle: readoutStyle,
        ),
        EditorSliderRow(
          label: context.l10n.horizontalPaddingLabel,
          labelWidth: 96,
          value: style.backgroundPaddingX,
          max: 64,
          format: (v) => '${v.toStringAsFixed(0)}px',
          onChanged: ctrl.setBackgroundPaddingX,
          onDragStart: ctrl.beginStyleDrag,
          onDragEnd: ctrl.endStyleDrag,
          haptics: EditorSliderHaptics.startTickEnd,
          labelStyle: labelStyle,
          readoutStyle: readoutStyle,
        ),
        if (bg != null)
          EditorSliderRow(
            label: context.l10n.opacityLabel,
            labelWidth: 96,
            value: bg.a * 100,
            max: 100,
            format: (v) => '${v.toStringAsFixed(0)}%',
            onChanged: (v) =>
                ctrl.setBackgroundColor(bg.withValues(alpha: v / 100)),
            onDragStart: ctrl.beginStyleDrag,
            onDragEnd: ctrl.endStyleDrag,
            haptics: EditorSliderHaptics.startTickEnd,
            labelStyle: labelStyle,
            readoutStyle: readoutStyle,
          ),
      ],
    );
  }
}

/// "Adjust precisely" disclosure for the Border panel. Same
/// flat header treatment as `_BackgroundPrecisionAdvanced`: whole
/// row tappable, single chevron, no nested arrows. Hosts thickness
/// and opacity sliders inline when expanded.
class _BorderPrecisionAdvanced extends ConsumerWidget {
  const _BorderPrecisionAdvanced({required this.style});
  final TextStyleSpec style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final outline = style.outlineColor;
    final labelStyle = flatSliderLabelStyle(context);
    final readoutStyle = flatSliderReadoutStyle(context);
    return PrecisionDisclosure(
      titleClosed: context.l10n.adjustPrecisely,
      titleOpen: context.l10n.hidePreciseControls,
      chevronSize: 18,
      children: [
        const PrecisionDivider(),
        EditorSliderRow(
          label: context.l10n.thicknessLabel,
          labelWidth: 96,
          value: style.outlineWidth,
          max: 12,
          format: (v) => '${v.toStringAsFixed(0)}px',
          onChanged: ctrl.setOutlineWidth,
          onDragStart: ctrl.beginStyleDrag,
          onDragEnd: ctrl.endStyleDrag,
          haptics: EditorSliderHaptics.startTickEnd,
          labelStyle: labelStyle,
          readoutStyle: readoutStyle,
        ),
        if (outline != null)
          EditorSliderRow(
            label: context.l10n.opacityLabel,
            labelWidth: 96,
            value: outline.a * 100,
            max: 100,
            format: (v) => '${v.toStringAsFixed(0)}%',
            onChanged: (v) =>
                ctrl.setOutlineColor(outline.withValues(alpha: v / 100)),
            onDragStart: ctrl.beginStyleDrag,
            onDragEnd: ctrl.endStyleDrag,
            haptics: EditorSliderHaptics.startTickEnd,
            labelStyle: labelStyle,
            readoutStyle: readoutStyle,
          ),
      ],
    );
  }
}

/// "Adjust precisely" disclosure for the Shadow panel. Mirrors the
/// Background/Border treatment — single chevron, whole-row tappable,
/// no nested arrows. Hosts blur and opacity sliders inline.
class _ShadowPrecisionAdvanced extends ConsumerWidget {
  const _ShadowPrecisionAdvanced({required this.style});
  final TextStyleSpec style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final shadow = style.shadowColor;
    final labelStyle = flatSliderLabelStyle(context);
    final readoutStyle = flatSliderReadoutStyle(context);
    return PrecisionDisclosure(
      titleClosed: context.l10n.adjustPrecisely,
      titleOpen: context.l10n.hidePreciseControls,
      chevronSize: 18,
      children: [
        const PrecisionDivider(),
        EditorSliderRow(
          label: context.l10n.blurLabel,
          labelWidth: 96,
          value: style.shadowBlur,
          max: 40,
          format: (v) => '${v.toStringAsFixed(0)}px',
          onChanged: ctrl.setShadowBlur,
          onDragStart: ctrl.beginStyleDrag,
          onDragEnd: ctrl.endStyleDrag,
          haptics: EditorSliderHaptics.startTickEnd,
          labelStyle: labelStyle,
          readoutStyle: readoutStyle,
        ),
        if (shadow != null)
          EditorSliderRow(
            label: context.l10n.opacityLabel,
            labelWidth: 96,
            value: shadow.a * 100,
            max: 100,
            format: (v) => '${v.toStringAsFixed(0)}%',
            onChanged: (v) =>
                ctrl.setShadowColor(shadow.withValues(alpha: v / 100)),
            onDragStart: ctrl.beginStyleDrag,
            onDragEnd: ctrl.endStyleDrag,
            haptics: EditorSliderHaptics.startTickEnd,
            labelStyle: labelStyle,
            readoutStyle: readoutStyle,
          ),
      ],
    );
  }
}

/// Background preset matcher (extracted from the Phase-A widget so
/// the new tile-row code path can re-use the same tolerance rules).
bool _bgMatches(TextStyleSpec style, _BgPreset p) {
  // Radius is a percent (0..1) now — "Pill" matches anything at
  // (or essentially at) full roundness.
  final pillish = p.id == 'pill' && style.backgroundRadius >= 0.99;
  final radiusEq = pillish || (style.backgroundRadius - p.radius).abs() < 0.02;
  return radiusEq &&
      (style.backgroundPaddingX - p.padX).abs() < 0.5 &&
      (style.backgroundPaddingY - p.padY).abs() < 0.5;
}

void _applyBgPreset(WidgetRef ref, _BgPreset p) {
  final ctrl = ref.read(textToolControllerProvider.notifier);
  ctrl.beginStyleDrag();
  final r = p.id == 'pill' ? 1.0 : p.radius;
  ctrl.setBackgroundRadius(r);
  ctrl.setBackgroundPaddingX(p.padX);
  ctrl.setBackgroundPaddingY(p.padY);
  ctrl.endStyleDrag();
}

bool _shadowMatches(TextStyleSpec style, _ShadowPreset p) {
  final c = style.shadowColor;
  if (c == null) return false;
  return (style.shadowBlur - p.blur).abs() < 0.5 &&
      (c.a - p.opacity).abs() < 0.02;
}

void _applyShadowPreset(
  WidgetRef ref,
  _ShadowPreset p, {
  required Color baseColor,
}) {
  final ctrl = ref.read(textToolControllerProvider.notifier);
  ctrl.beginStyleDrag();
  ctrl.setShadowBlur(p.blur);
  ctrl.setShadowColor(baseColor.withValues(alpha: p.opacity));
  ctrl.endStyleDrag();
}

const List<IconData> _shadowPresetIcons = [
  Icons.cloud_outlined, // Soft
  Icons.crop_din_rounded, // Hard
  Icons.flare_rounded, // Glow
  Icons.vertical_align_top_rounded, // Lift
];

// ─────────────────────────────────────────────────────────────────────
// Compact sheet building blocks
// ─────────────────────────────────────────────────────────────────────
//
// All five category sheets are built from these primitives. The goal
// is uniformity and density: every row is ~44 px tall (vs ~64 px for
// a `ListTile`), so a 4-row sheet fits in ~190 px instead of ~320 px,
// leaving the canvas visible while the user adjusts values.

//
// Macro preset records used by the new tile-row sub-tools. Each
// preset is applied via the controller's [beginStyleDrag] /
// [endStyleDrag] coalescing window so the whole macro lands as a
// single undo entry.

/// Macro preset for the Background sub-tool. Each preset writes
/// radius + padding X + padding Y in one shot. Color and opacity
/// stay user-controlled.
///
/// [id] is a stable internal identity, never displayed — display
/// text is always looked up separately via l10n at the call site
/// (see `_backgroundPresets` consumers). Matching/apply logic keys
/// off [id], not a display string, so renaming a preset's shown
/// name can never silently break the "Pill" special-case below.
class _BgPreset {
  const _BgPreset({
    required this.id,
    required this.radius,
    required this.padX,
    required this.padY,
  });
  final String id;
  final double radius;
  final double padX;
  final double padY;
}

const List<_BgPreset> _backgroundPresets = [
  _BgPreset(id: 'none', radius: 0, padX: 0, padY: 0),
  _BgPreset(id: 'pill', radius: 1, padX: 24, padY: 8),
  _BgPreset(id: 'card', radius: 0.3, padX: 16, padY: 12),
  _BgPreset(id: 'tag', radius: 0.5, padX: 8, padY: 4),
];

/// Macro preset for the Shadow sub-tool. Writes blur + opacity in
/// one shot. Color and offset stay user-controlled (those are intent,
/// not aesthetic style).
///
/// [id] is a stable internal identity used only for matching/l10n
/// lookup (see [_shadowPresetLabel]) — never rendered directly.
class _ShadowPreset {
  const _ShadowPreset({
    required this.id,
    required this.blur,
    required this.opacity,
  });
  final String id;
  final double blur;
  final double opacity; // 0..1
}

const List<_ShadowPreset> _shadowPresets = [
  _ShadowPreset(id: 'soft', blur: 16, opacity: 0.30),
  _ShadowPreset(id: 'hard', blur: 2, opacity: 0.80),
  _ShadowPreset(id: 'glow', blur: 24, opacity: 0.60),
  _ShadowPreset(id: 'lift', blur: 8, opacity: 0.50),
];

String _shadowPresetLabel(AppLocalizations l10n, _ShadowPreset preset) {
  return switch (preset.id) {
    'soft' => l10n.softOption,
    'hard' => l10n.hardOption,
    'glow' => l10n.glowOption,
    'lift' => l10n.liftOption,
    _ => preset.id,
  };
}

// ─── Canva-style sub-tool helpers ───────────────────────────────────
//
// Shared widgets for the "presets-first, advanced-hidden" sub-tool
// redesign. The canvas above each sheet is the live preview, so these
// helpers focus on fast 1-tap choices instead of large preview tiles.

/// Single-select tile group for visual style presets (Background
/// shape, Shadow style, Border style, etc). Each tile renders
/// through the shared [PanelOptionTile] so selection / hover /
/// pressed states match the Adjust preset chip.
class _StyleTileRow extends StatelessWidget {
  const _StyleTileRow({required this.tiles});

  final List<_StyleTile> tiles;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: tiles.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final t = tiles[i];
          return PanelOptionTile(
            icon: t.icon,
            iconSize: t.iconSize,
            label: t.label,
            selected: t.selected,
            onTap: () {
              EditorHaptics.toggle();
              t.onTap();
            },
            width: 76,
          );
        },
      ),
    );
  }
}

/// Value spec consumed by [_StyleTileRow]. Keeps the call sites
/// declarative — actual chrome lives in [PanelOptionTile].
class _StyleTile {
  const _StyleTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.iconSize = 22,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Icon size override — e.g. border thickness presets render the
  /// same horizontal-rule glyph at 16/22/28 so the preview itself
  /// communicates Thin / Medium / Thick.
  final double iconSize;
}

/// Fixed magnitude for [PanelDirectionPad] direction taps on the
/// Shadow panel. Uses the current offset's own magnitude if the
/// user already dialled a distance, otherwise a sensible default
/// that reads as a real shadow on canvas.
double _shadowDirectionMagnitude(Offset offset) {
  final m = offset.distance;
  return m < 1.0 ? 6.0 : m.clamp(2.0, 24.0);
}
