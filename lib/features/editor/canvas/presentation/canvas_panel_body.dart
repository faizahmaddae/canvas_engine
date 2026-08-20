import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_icons.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/ui/size_picker_dialog.dart';
import '../../../../core/utils/editor_value_format.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import '../../../color_picker/presentation/color_picker_body.dart';
import '../../application/document_controller.dart';
import '../../application/editor_session.dart';
import '../../application/live_overlay_controller.dart';
import '../../engine/commands/editor_command.dart';
import '../../engine/commands/transform_commands.dart' show CompositeCommand;
import '../../engine/core/editor_document.dart';
import '../../engine/rendering/background_fill_box.dart';
import '../../presentation/widgets/editor_breakpoints.dart';
import '../../presentation/widgets/editor_tool_panel_shell.dart';
import '../../presentation/widgets/section_label.dart';
import '../../toolbar/presentation/widgets/preset_chip.dart';
import '../../ui/editor_slider_row.dart';
import '../../ui/fill_mode_section.dart'
    show kGradientPresets, kDefaultGradientAngle;
import '../application/canvas_commands.dart';
import '../application/canvas_resize.dart';
import '../application/canvas_tool_controller.dart';
import 'aspect_thumb.dart';
import 'widgets/canvas_checkerboard.dart';

/// Expanded panel body for the Canvas tool
/// (`docs/canvas-tool-redesign-2026-08.md`).
///
/// A **document card** over two one-tap rows:
///
///   * The card is the state display and the §10 W-scope statement in
///     one — the actual background (checkerboard when transparent) in
///     a mini-frame at the document's own aspect ratio, beside the
///     project name, exact dimensions and format word, with the
///     rotate-canvas action (hidden for a square document).
///   * **Size** — the four aspect presets (each captioned with its
///     target dimensions) + Custom… into the shared size form. The
///     anchor policy is unchanged (see [buildCanvasResize]); a resize
///     that strands layers wholly outside the canvas says so in a
///     floating whisper.
///   * **Background** — one row in the paint-bench swatch grammar:
///     a checkerboard chip for transparent, curated document grounds,
///     a gradient chip that discloses the preset + angle controls
///     inline, and a custom dot into the shared colour-picker sheet
///     (barrier none; drags preview through the §2 overlay channel).
///     Picking a colour while transparent commits ONE composite
///     (mode → color + fill), so leaving transparency is one undo.
///
/// The old form grammar — two stacked segmented controls with the
/// full picker embedded below the fold — died with this redesign.
class CanvasPanelBody extends ConsumerStatefulWidget {
  const CanvasPanelBody({super.key});

  /// Curated document grounds. CONTENT colours (like the gradient
  /// presets): pixels of the user's document, identical in both
  /// themes, deliberately not resolved through [AppTokens].
  static const List<Color> groundSwatches = <Color>[
    Color(0xFFFFFFFF), // white
    Color(0xFFF3EDDF), // warm paper
    Color(0xFF6B7280), // grey (shared picker palette)
    Color(0xFF000000), // black
    Color(0xFFF5B942), // saffron (gradient-preset seed)
  ];

  @override
  ConsumerState<CanvasPanelBody> createState() => _CanvasPanelBodyState();
}

class _CanvasPanelBodyState extends ConsumerState<CanvasPanelBody> {
  // ─── Contract §2 colour preview channel (ux-audit P2-8) ─────────
  //
  // Drags stage the live overlay's background override; the settled
  // value commits ONE non-live command. True while a preview is
  // staged and uncommitted so dispose can drop an orphaned override
  // if the panel dies mid-gesture (§7).
  bool _previewStaged = false;

  /// Explicit user toggle for the gradient disclosure; `null` means
  /// "follow the fill" (open exactly when the committed fill IS a
  /// gradient). The chip always toggles — an installed gradient's
  /// section can still be collapsed to reach Size without scrolling.
  bool? _gradientOpenOverride;

  @override
  void dispose() {
    if (_previewStaged) {
      ref.read(liveOverlayProvider.notifier).clear();
    }
    super.dispose();
  }

  void _preview(BackgroundFill fill) {
    _previewStaged = true;
    ref.read(liveOverlayProvider.notifier).stageBackground(fill);
  }

  /// Commit [fill], flipping out of transparent mode in the same
  /// undoable step when needed — leaving transparency is one act for
  /// the user, so it must be one entry on the stack.
  void _commitFill(BackgroundFill fill) {
    _previewStaged = false;
    final doc = ref.read(documentControllerProvider);
    final commands = <EditorCommand>[
      if (doc.backgroundMode == CanvasBackgroundMode.transparent)
        const SetCanvasBackgroundModeCommand(CanvasBackgroundMode.color),
      if (doc.background != fill) SetCanvasBackgroundCommand(fill: fill),
    ];
    // Clear-then-execute in one synchronous run — no flash-back
    // frame; a commit at the starting value no-ops (§3).
    ref.read(liveOverlayProvider.notifier).clear();
    if (commands.isEmpty) return;
    ref
        .read(documentControllerProvider.notifier)
        .execute(
          commands.length == 1
              ? commands.single
              : CompositeCommand(commands, labelOverride: 'Canvas background'),
        );
  }

  void _commitTransparent() {
    final doc = ref.read(documentControllerProvider);
    if (doc.backgroundMode == CanvasBackgroundMode.transparent) return;
    EditorHaptics.toggle();
    ref
        .read(documentControllerProvider.notifier)
        .execute(
          const SetCanvasBackgroundModeCommand(
            CanvasBackgroundMode.transparent,
          ),
        );
  }

  Future<void> _openCustomColor() async {
    final doc = ref.read(documentControllerProvider);
    // While transparent, the live preview cannot show on the canvas
    // (the overlay overrides the fill, not the mode) — the picker's
    // own swatch carries the preview and the commit flips the mode.
    await showColorPickerSheet(
      context,
      initial: _seed(doc.background),
      title: context.l10n.canvasBackgroundTitle,
      onLiveChange: (c) => _preview(SolidBackground(color: c)),
      onCommitted: (c) => _commitFill(SolidBackground(color: c)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = context.l10n;
    final doc = ref.watch(documentControllerProvider);
    // The card and chips read the MERGED view so a staged drag tracks
    // live, matching the board; select() keeps foreign preview ticks
    // from rebuilding the panel.
    final currentFill = ref.watch(
      renderedDocumentProvider.select((d) => d.background),
    );
    final transparent = doc.backgroundMode == CanvasBackgroundMode.transparent;
    final isGradient = !transparent && currentFill is! SolidBackground;
    final gradientOpen = _gradientOpenOverride ?? isGradient;
    final isPhotoProject = doc.projectKind == ProjectKind.photo;

    return EditorToolPanelShell(
      title: l10n.canvasTool,
      icon: AppIcons.canvasSize,
      onClose: () =>
          ref.read(canvasToolControllerProvider.notifier).closePanel(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DocumentCard(doc: doc, fill: currentFill, transparent: transparent),
          const SizedBox(height: 10),
          // Background first: re-grounding a design is the panel's
          // most frequent act; the format is usually set once.
          SectionLabel(l10n.backgroundTool),
          if (isPhotoProject)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PhotoProjectHint(tokens: tokens),
            ),
          _BackgroundRow(
            fill: currentFill,
            transparent: transparent,
            gradientSelected: isGradient,
            gradientOpen: gradientOpen,
            onTransparent: () {
              // Leaving the gradient world re-arms follow-the-fill.
              setState(() => _gradientOpenOverride = null);
              _commitTransparent();
            },
            onSolid: (c) {
              EditorHaptics.tap();
              setState(() => _gradientOpenOverride = null);
              _commitFill(SolidBackground(color: c));
            },
            onGradientTap: () {
              EditorHaptics.tap();
              setState(() => _gradientOpenOverride = !gradientOpen);
            },
            onCustom: _openCustomColor,
          ),
          // Gradient disclosure — a CHILD of the row, collapsed when
          // not in use so the panel's resting height stays one screen.
          AnimatedSize(
            duration: AppMotion.of(context, AppMotion.reveal),
            curve: AppMotion.curve,
            alignment: Alignment.topCenter,
            child: !gradientOpen
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _GradientSection(
                      fill: currentFill,
                      isGradient: isGradient,
                      onPreview: _preview,
                      onCommit: _commitFill,
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          SectionLabel(l10n.sizeTool),
          const _CanvasSizeSection(),
        ],
      ),
    );
  }
}

/// The single colour that best represents [fill] — the seed for the
/// custom picker and for authoring a gradient from a solid.
Color _seed(BackgroundFill fill) => switch (fill) {
  SolidBackground(:final color) => color,
  LinearGradientBackground(:final startColor) => startColor,
  RadialGradientBackground(:final centerColor) => centerColor,
};

// ─────────────────────────────────────────────────────────────────
// Document card
// ─────────────────────────────────────────────────────────────────

/// "What is my canvas right now" — name, exact dimensions, format
/// word and the live background in a frame at the document's own
/// ratio. The rotate action lives here because orientation is a fact
/// of the document, not a preset.
class _DocumentCard extends ConsumerWidget {
  const _DocumentCard({
    required this.doc,
    required this.fill,
    required this.transparent,
  });

  final EditorDocument doc;
  final BackgroundFill fill;
  final bool transparent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final l10n = context.l10n;
    final values = EditorValueFormat.of(context);
    final name = ref.watch(editorSessionProvider)?.name ?? l10n.appName;
    final square = doc.width == doc.height;
    // Clamped so a story frame stays readable and a wide banner
    // cannot swallow the card.
    final ratio = (doc.width / doc.height).clamp(0.45, 2.4);

    return Container(
      key: const ValueKey('canvas-doc-card'),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: tokens.surfaceMuted.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          SizedBox(
            height: 42,
            child: AspectRatio(
              aspectRatio: ratio,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: tokens.borderStrong),
                ),
                // Same renderers the canvas itself uses, so the frame
                // IS the background, not an approximation of it.
                child: transparent
                    ? const CanvasCheckerboard(tile: 5)
                    : BackgroundFillBox(fill: fill),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${values.dimensions(doc.width.round(), doc.height.round())}'
                  ' · ${_formatWord(l10n, doc.width, doc.height)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: tokens.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          // Swapping a square's sides is a no-op — the control is not
          // shown rather than shown dead (§10.3).
          if (!square)
            Semantics(
              button: true,
              label: l10n.rotateCanvasAction,
              child: IconButton(
                key: const ValueKey('canvas-rotate'),
                tooltip: l10n.rotateCanvasAction,
                icon: Icon(
                  AppIcons.canvasRotation,
                  size: 20,
                  color: tokens.textPrimary,
                ),
                onPressed: () {
                  EditorHaptics.toggle();
                  resizeCanvasFromPanel(
                    context,
                    ref,
                    width: doc.height,
                    height: doc.width,
                    recenterLayers: true,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

String _formatWord(AppLocalizations l10n, double width, double height) {
  if (width == height) return l10n.squareGroup;
  if (width > height) return l10n.landscapeGroup;
  return height / width >= 16 / 9 ? l10n.storyGroup : l10n.portraitGroup;
}

// ─────────────────────────────────────────────────────────────────
// Size section
// ─────────────────────────────────────────────────────────────────

class _AspectPreset {
  const _AspectPreset(this.width, this.height);
  final double width;
  final double height;
}

/// The four surfaces a casual user actually re-frames for; anything
/// else is a job for Custom… and the shared size form's full
/// catalogue.
const _aspectPresets = <_AspectPreset>[
  _AspectPreset(1080, 1080),
  _AspectPreset(1080, 1350),
  _AspectPreset(1080, 1920),
  _AspectPreset(1280, 720),
];

/// Dispatches one undoable resize and, when the new bounds strand at
/// least one layer wholly outside the canvas, surfaces the
/// audit-documented silent consequence as a floating whisper. Shared
/// by the presets, the custom form and the card's rotate action.
void resizeCanvasFromPanel(
  BuildContext context,
  WidgetRef ref, {
  required double width,
  required double height,
  required bool recenterLayers,
}) {
  final doc = ref.read(documentControllerProvider);
  ref
      .read(documentControllerProvider.notifier)
      .execute(
        buildCanvasResize(
          doc,
          width: width,
          height: height,
          recenterLayers: recenterLayers,
        ),
      );
  final after = ref.read(documentControllerProvider);
  final canvas = Rect.fromLTWH(0, 0, after.width, after.height);
  final stranded = after.layers.any((layer) {
    final t = layer.transform;
    final bounds = Rect.fromLTWH(
      t.position.dx,
      t.position.dy,
      t.size.width,
      t.size.height,
    );
    // Axis-aligned bounds; rotation is ignored — a hint, not a
    // hit-test, and the approximation only ever under-reports.
    return !bounds.overlaps(canvas);
  });
  if (!stranded || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(context.l10n.layersOutsideCanvasNote),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

class _CanvasSizeSection extends ConsumerWidget {
  const _CanvasSizeSection();

  Future<void> _openCustom(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final doc = ref.read(documentControllerProvider);
    final picked = await SizePickerDialog.show(
      context,
      title: l10n.customSizeTitle,
      body: l10n.resizeCanvasBody,
      confirmLabel: l10n.useSizeAction,
      initial: CanvasSize(doc.width, doc.height),
    );
    if (picked == null || !context.mounted) return;
    // Typed numbers keep the top-left anchor — see buildCanvasResize.
    resizeCanvasFromPanel(
      context,
      ref,
      width: picked.width,
      height: picked.height,
      recenterLayers: false,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final tokens = AppTokens.of(context);
    final values = EditorValueFormat.of(context);
    final width = ref.watch(documentControllerProvider.select((d) => d.width));
    final height = ref.watch(
      documentControllerProvider.select((d) => d.height),
    );

    // The ratio is the picture, the numbers are the caption — every
    // chip says exactly what canvas it produces.
    Widget chipPreview(_AspectPreset? preset) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        preset == null
            ? const AspectThumb(width: 1, height: 1, dashed: true)
            : AspectThumb(width: preset.width, height: preset.height),
        const SizedBox(height: 4),
        Text(
          preset == null
              ? '· · ·'
              : values.dimensions(preset.width.round(), preset.height.round()),
          maxLines: 1,
          style: TextStyle(
            fontSize: 9.5,
            height: 1,
            fontWeight: FontWeight.w600,
            color: tokens.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );

    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: _aspectPresets.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          if (i == _aspectPresets.length) {
            return PresetChip.option(
              key: const ValueKey('canvas-size-custom'),
              width: 76,
              selected: false,
              preview: chipPreview(null),
              label: l10n.customLabel,
              onTap: () => _openCustom(context, ref),
            );
          }
          final preset = _aspectPresets[i];
          final selected = width == preset.width && height == preset.height;
          return PresetChip.option(
            key: ValueKey(
              'canvas-size-preset-'
              '${preset.width.toInt()}x${preset.height.toInt()}',
            ),
            width: 76,
            selected: selected,
            preview: chipPreview(preset),
            label: _aspectLabel(l10n, preset),
            onTap: () {
              if (selected) return;
              EditorHaptics.toggle();
              resizeCanvasFromPanel(
                context,
                ref,
                width: preset.width,
                height: preset.height,
                recenterLayers: true,
              );
            },
          );
        },
      ),
    );
  }
}

String _aspectLabel(AppLocalizations l10n, _AspectPreset preset) =>
    _formatWord(l10n, preset.width, preset.height);

// ─────────────────────────────────────────────────────────────────
// Background row
// ─────────────────────────────────────────────────────────────────

/// One row of direct choices: transparent · curated grounds ·
/// gradient · custom. Each chip is a mini-canvas (rounded rect, the
/// value it installs painted inside), 44dp hit targets throughout.
class _BackgroundRow extends StatelessWidget {
  const _BackgroundRow({
    required this.fill,
    required this.transparent,
    required this.gradientSelected,
    required this.gradientOpen,
    required this.onTransparent,
    required this.onSolid,
    required this.onGradientTap,
    required this.onCustom,
  });

  final BackgroundFill fill;
  final bool transparent;
  final bool gradientSelected;
  final bool gradientOpen;
  final VoidCallback onTransparent;
  final ValueChanged<Color> onSolid;
  final VoidCallback onGradientTap;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final solid = !transparent && fill is SolidBackground
        ? (fill as SolidBackground).color
        : null;
    // The gradient chip previews the CURRENT gradient when one is
    // installed, the first preset otherwise.
    final gradientPreview = gradientSelected
        ? fill
        : const LinearGradientBackground(
            startColor: Color(0xFFF5B942),
            endColor: Color(0xFFE2703A),
            angleDegrees: kDefaultGradientAngle,
          );

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          _BackgroundChip(
            key: const ValueKey('canvas-bg-transparent'),
            semanticLabel: l10n.transparentOption,
            selected: transparent,
            onTap: onTransparent,
            child: const CanvasCheckerboard(tile: 6),
          ),
          _rowGap,
          _divider(context),
          _rowGap,
          for (final ground in CanvasPanelBody.groundSwatches) ...[
            _BackgroundChip(
              key: ValueKey(
                'canvas-bg-solid-'
                '${ground.toARGB32().toRadixString(16).padLeft(8, '0')}',
              ),
              semanticLabel: l10n.canvasBackgroundTitle,
              selected: solid != null && solid.toARGB32() == ground.toARGB32(),
              onTap: () => onSolid(ground),
              child: ColoredBox(color: ground),
            ),
            _rowGap,
          ],
          _divider(context),
          _rowGap,
          _BackgroundChip(
            key: const ValueKey('canvas-bg-gradient'),
            semanticLabel: l10n.effectGradientLabel,
            selected: gradientSelected,
            expanded: gradientOpen,
            onTap: onGradientTap,
            child: BackgroundFillBox(fill: gradientPreview),
          ),
          _rowGap,
          _BackgroundChip(
            key: const ValueKey('canvas-bg-custom'),
            semanticLabel: l10n.customLabel,
            selected: false,
            round: true,
            onTap: onCustom,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: SweepGradient(
                  colors: [
                    Color(0xFFEF4444),
                    Color(0xFFF59E0B),
                    Color(0xFF22C55E),
                    Color(0xFF06B6D4),
                    Color(0xFF8B5CF6),
                    Color(0xFFEC4899),
                    Color(0xFFEF4444),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _rowGap = SizedBox(width: 6);

  Widget _divider(BuildContext context) => Center(
    child: Container(
      width: 1,
      height: 22,
      color: AppTokens.of(context).border.withValues(alpha: 0.8),
    ),
  );
}

class _BackgroundChip extends StatelessWidget {
  const _BackgroundChip({
    super.key,
    required this.semanticLabel,
    required this.selected,
    required this.child,
    required this.onTap,
    this.expanded = false,
    this.round = false,
  });

  final String semanticLabel;
  final bool selected;
  final Widget child;
  final VoidCallback onTap;

  /// Disclosure state for the gradient chip (its sheet-like child
  /// section is open). Announced separately from selection.
  final bool expanded;

  /// The custom dot renders as a circle so it reads as "picker", not
  /// as another installable ground.
  final bool round;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final border = selected || expanded
        ? tokens.accent
        : tokens.border.withValues(alpha: 0.9);
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: kMinHitTarget,
          child: Center(
            child: AnimatedContainer(
              duration: AppMotion.state,
              curve: AppMotion.curve,
              width: selected ? 38 : 34,
              height: selected ? 38 : 34,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                shape: round ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: round ? null : BorderRadius.circular(10),
                border: Border.all(
                  color: border,
                  width: selected || expanded ? 2 : 1,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Gradient disclosure
// ─────────────────────────────────────────────────────────────────

/// Preset swatches + the angle slider. Presets commit through the
/// same composite path as the solids (one undo out of transparency);
/// the angle only exists once a gradient is installed.
class _GradientSection extends StatefulWidget {
  const _GradientSection({
    required this.fill,
    required this.isGradient,
    required this.onPreview,
    required this.onCommit,
  });

  final BackgroundFill fill;
  final bool isGradient;
  final ValueChanged<BackgroundFill> onPreview;
  final ValueChanged<BackgroundFill> onCommit;

  @override
  State<_GradientSection> createState() => _GradientSectionState();
}

class _GradientSectionState extends State<_GradientSection> {
  /// Non-null only while an angle drag is in flight.
  double? _dragAngle;

  LinearGradientBackground? get _linear =>
      widget.fill is LinearGradientBackground
      ? widget.fill as LinearGradientBackground
      : null;

  LinearGradientBackground _withAngle(double angle) {
    final linear = _linear;
    if (linear != null) {
      return LinearGradientBackground(
        startColor: linear.startColor,
        endColor: linear.endColor,
        angleDegrees: angle,
        stops: linear.stops,
      );
    }
    final seed = _seed(widget.fill);
    return LinearGradientBackground(
      startColor: seed,
      endColor: seed,
      angleDegrees: angle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final linear = _linear;
    final angle = _dragAngle ?? linear?.angleDegrees ?? kDefaultGradientAngle;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: kGradientPresets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final preset = kGradientPresets[i];
              final selected =
                  linear != null &&
                  linear.startColor == preset.$1 &&
                  linear.endColor == preset.$2;
              return Center(
                child: _GradientPresetSwatch(
                  key: ValueKey('canvas-gradient-preset-$i'),
                  start: preset.$1,
                  end: preset.$2,
                  angleDegrees: angle,
                  selected: selected,
                  onTap: () {
                    EditorHaptics.toggle();
                    widget.onCommit(
                      LinearGradientBackground(
                        startColor: preset.$1,
                        endColor: preset.$2,
                        angleDegrees: angle,
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
        // The angle belongs to an installed gradient; before one is
        // picked there is nothing for it to rotate.
        if (widget.isGradient) ...[
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
              widget.onPreview(_withAngle(v));
            },
            // Fires on pointer-cancel too, so an interrupted drag
            // still commits the last previewed angle (§7).
            onDragEnd: () {
              final settled = _dragAngle;
              setState(() => _dragAngle = null);
              if (settled != null) widget.onCommit(_withAngle(settled));
            },
          ),
        ] else
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 2, top: 6),
            child: Text(
              context.l10n.gradientPickHint,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: tokens.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

/// A wide swatch painted with the gradient it installs — same grammar
/// as the shape panel's presets so the two surfaces read as one
/// system.
class _GradientPresetSwatch extends StatelessWidget {
  const _GradientPresetSwatch({
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
        duration: AppMotion.state,
        curve: AppMotion.curve,
        width: 56,
        height: 38,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
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
            borderRadius: BorderRadius.circular(9),
          ),
          child: selected
              ? Center(
                  child: Icon(
                    AppIcons.confirm,
                    size: 15,
                    color: tokens.onBrand,
                  ),
                )
              : const SizedBox.expand(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Photo hint
// ─────────────────────────────────────────────────────────────────

/// Why changing the background can appear to do "nothing" in a photo
/// project: the imported photo can cover the whole canvas.
class _PhotoProjectHint extends StatelessWidget {
  const _PhotoProjectHint({required this.tokens});

  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: tokens.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.info, size: 16, color: tokens.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.photoBackgroundHint,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: tokens.textPrimary.withValues(alpha: 0.78),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
