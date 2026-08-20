import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/editor_value_format.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import '../../../../app/ui/size_picker_dialog.dart';
import '../../application/document_controller.dart';
import '../../application/live_overlay_controller.dart';
import '../../canvas/presentation/widgets/canvas_checkerboard.dart';
import '../../engine/core/editor_document.dart';
import '../../engine/rendering/background_fill_box.dart';
import '../../presentation/widgets/editor_tool_panel_shell.dart';
import '../../presentation/widgets/section_label.dart';
import '../../toolbar/presentation/widgets/preset_chip.dart';
import '../../ui/editor_segmented_control.dart';
import '../../ui/fill_mode_section.dart';
import '../application/canvas_commands.dart';
import '../application/canvas_resize.dart';
import '../application/canvas_tool_controller.dart';
import 'aspect_thumb.dart';
import '../../../../app/theme/app_icons.dart';

/// Expanded panel body for the Canvas tool. Three sections:
///
///   * **Size** — the document's own dimensions: a locale-digit
///     readout, four aspect presets that recentre the composition,
///     and a Custom… escape hatch into the shared size form (see
///     [buildCanvasResize] for the anchor policy).
///   * Background **mode** — solid colour vs. transparent (alpha-
///     preserving on PNG export, checkerboard preview in the editor).
///   * Background **fill** — only relevant in colour mode; Solid |
///     Gradient, both dispatched through [SetCanvasBackgroundCommand].
///
/// The header reads "Canvas" (matching the dock tile that opens it)
/// rather than "Background": with Size on top, a Background-titled
/// panel would mislabel half its own content. Both sections carry
/// their own [SectionLabel] now that there is more than one.
///
/// Mode is independent from the colour value: flipping to
/// transparent does not erase the user's last colour pick. In photo
/// projects the panel renders an info note explaining that the
/// background only shows behind transparent or uncovered parts of
/// the photo -- the common point of confusion users hit when they
/// change the colour and see "nothing happen" because the imported
/// photo covers the canvas.
///
/// **No prev/next** is wired here: the Canvas tool exposes only one
/// panel (no slot concept on `CanvasToolController`), so sibling
/// swipe would have nothing to navigate to.
class CanvasPanelBody extends ConsumerStatefulWidget {
  const CanvasPanelBody({super.key});

  @override
  ConsumerState<CanvasPanelBody> createState() => _CanvasPanelBodyState();
}

class _CanvasPanelBodyState extends ConsumerState<CanvasPanelBody> {
  // ─── Contract §2 colour preview channel (ux-audit P2-8) ─────────
  //
  // The canvas background is a DOCUMENT property, so a picker drag
  // stages its preview as the live overlay's background override
  // (the board paints the merged view) and the settled value commits
  // ONE non-live command. A discrete swatch tap flows preview→commit
  // within the tap — its own undo entry every time. This replaces
  // the old per-tick `live: true` committed stream, whose undo
  // grouping depended on the wall-clock merge window: two quick taps
  // collapsed into one entry, a slow drag split into several.
  //
  // True while a preview is staged and uncommitted, so dispose can
  // drop an orphaned override if the panel dies mid-gesture (§7) —
  // same guard as ShapeStyleBody's pending slider command.
  bool _previewStaged = false;

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

  void _commit(Color c) => _commitFill(SolidBackground(color: c));

  void _commitFill(BackgroundFill fill) {
    _previewStaged = false;
    // Clear-then-execute in one synchronous run — no flash-back
    // frame. A commit at the value the gesture started on (cancelled
    // eyedrop) no-ops inside HistoryStack, so no net-zero entries
    // (§3).
    ref.read(liveOverlayProvider.notifier).clear();
    ref
        .read(documentControllerProvider.notifier)
        .execute(SetCanvasBackgroundCommand(fill: fill));
  }

  void _commitMode(CanvasBackgroundMode mode) {
    ref
        .read(documentControllerProvider.notifier)
        .execute(SetCanvasBackgroundModeCommand(mode));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final doc = ref.watch(documentControllerProvider);
    // The background reads from the MERGED view so the header swatch
    // and the picker track a staged drag live, matching the board.
    // select() keeps foreign preview ticks (a text drag, a slider on
    // some layer) from rebuilding this panel at 60 fps.
    final currentFill = ref.watch(
      renderedDocumentProvider.select((d) => d.background),
    );
    final mode = doc.backgroundMode;
    final isPhotoProject = doc.projectKind == ProjectKind.photo;
    final isTransparent = mode == CanvasBackgroundMode.transparent;

    return EditorToolPanelShell(
      title: context.l10n.canvasTool,
      icon: AppIcons.canvasSize,
      onClose: () =>
          ref.read(canvasToolControllerProvider.notifier).closePanel(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(
            context.l10n.sizeTool,
            // The dimensions ride on the label's line rather than
            // owning a row of their own — a whole row to restate one
            // short value, in the surface with the least room.
            trailing: Text(
              EditorValueFormat.of(
                context,
              ).dimensions(doc.width.round(), doc.height.round()),
              textAlign: TextAlign.end,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
          ),
          const _CanvasSizeSection(),
          const SizedBox(height: 14),
          if (isPhotoProject)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PhotoProjectHint(tokens: tokens),
            ),
          SectionLabel(
            context.l10n.backgroundTool,
            // What colour IS it? The swatch used to live below the
            // fold, under two rows of chips, so the panel could tell
            // you the background was a solid colour without ever
            // showing you which one.
            trailing: _BackgroundSwatch(
              fill: currentFill,
              transparent: isTransparent,
            ),
          ),
          EditorSegmentedControl<CanvasBackgroundMode>(
            value: mode,
            segments: [
              EditorSegment(
                value: CanvasBackgroundMode.color,
                label: context.l10n.colorLabel,
                itemKey: const ValueKey('canvas-bg-mode-color'),
              ),
              EditorSegment(
                value: CanvasBackgroundMode.transparent,
                label: context.l10n.transparentOption,
                itemKey: const ValueKey('canvas-bg-mode-transparent'),
              ),
            ],
            onChanged: (next) {
              if (next == mode) return;
              EditorHaptics.toggle();
              _commitMode(next);
            },
          ),
          // Collapsed, not dimmed. Solid/Gradient is a CHILD of the
          // colour mode — greying it out left a dead half-panel of
          // controls that still claimed the space and read as broken.
          AnimatedSize(
            duration: AppMotion.of(context, AppMotion.reveal),
            curve: AppMotion.curve,
            alignment: Alignment.topCenter,
            child: isTransparent
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    // Solid | Gradient, with the shared two-level picker
                    // embedded in the solid branch. Drags stage the
                    // overlay's background override; the settled change
                    // commits ONE undoable command (contract §2/§3,
                    // ux-audit P2-8). Recents and alpha policy live
                    // inside the picker.
                    child: FillModeSection(
                      fill: currentFill,
                      solidTitle: context.l10n.canvasBackgroundTitle,
                      onSolidChanged: (c) =>
                          _preview(SolidBackground(color: c)),
                      onSolidCommitted: _commit,
                      onFillChanged: _preview,
                      onFillCommitted: _commitFill,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The background's current value, shown on the Background label's own
/// line: the solid colour, the gradient's own sweep, or the
/// transparency checker.
///
/// Small but load-bearing — it is the only place in the panel that
/// answers "what is it right now" without the user opening anything.
class _BackgroundSwatch extends StatelessWidget {
  const _BackgroundSwatch({required this.fill, required this.transparent});

  final BackgroundFill fill;
  final bool transparent;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Container(
        width: 34,
        height: 18,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: tokens.border),
        ),
        // Same renderer the canvas itself uses, so a gradient reads
        // as the gradient rather than as an approximation of it.
        child: transparent
            ? const CanvasCheckerboard(tile: 5)
            : BackgroundFillBox(fill: fill),
      ),
    );
  }
}

/// One aspect preset in the Size row. The four cover the surfaces a
/// casual user actually re-frames for (feed square, 4:5 portrait,
/// full-bleed story, 16:9 landscape); anything else is a job for
/// Custom… rather than a longer scroller nobody reads to the end of.
class _AspectPreset {
  const _AspectPreset(this.width, this.height);
  final double width;
  final double height;
}

const _aspectPresets = <_AspectPreset>[
  _AspectPreset(1080, 1080),
  _AspectPreset(1080, 1350),
  _AspectPreset(1080, 1920),
  _AspectPreset(1280, 720),
];

/// Document-size controls: current dimensions + aspect presets +
/// Custom…. Split out of [CanvasPanelBody] so the async Custom flow
/// owns its own `context`/`mounted` pair instead of leaking an
/// awaited BuildContext through the parent's build method.
class _CanvasSizeSection extends ConsumerWidget {
  const _CanvasSizeSection();

  void _resize(
    WidgetRef ref, {
    required double width,
    required double height,
    required bool recenterLayers,
  }) {
    final controller = ref.read(documentControllerProvider.notifier);
    controller.execute(
      buildCanvasResize(
        ref.read(documentControllerProvider),
        width: width,
        height: height,
        recenterLayers: recenterLayers,
      ),
    );
  }

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
    if (picked == null) return;
    // Typed numbers keep the top-left anchor — see buildCanvasResize.
    _resize(
      ref,
      width: picked.width,
      height: picked.height,
      recenterLayers: false,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final width = ref.watch(documentControllerProvider.select((d) => d.width));
    final height = ref.watch(
      documentControllerProvider.select((d) => d.height),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: _aspectPresets.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              if (i == _aspectPresets.length) {
                // Custom has no ratio of its own, so it shows an
                // empty dashed frame — still a canvas, shape not
                // decided yet. A sliders glyph here read as a
                // different KIND of control than its four neighbours.
                return PresetChip.option(
                  key: const ValueKey('canvas-size-custom'),
                  width: 76,
                  selected: false,
                  preview: const AspectThumb(width: 1, height: 1, dashed: true),
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
                preview: AspectThumb(
                  width: preset.width,
                  height: preset.height,
                ),
                label: _aspectLabel(l10n, preset),
                onTap: () {
                  if (selected) return;
                  EditorHaptics.toggle();
                  _resize(
                    ref,
                    width: preset.width,
                    height: preset.height,
                    recenterLayers: true,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

String _aspectLabel(AppLocalizations l10n, _AspectPreset preset) {
  if (preset.width == preset.height) return l10n.squareGroup;
  if (preset.width > preset.height) return l10n.landscapeGroup;
  // Both portraits; the 9:16 one is the story format.
  return preset.height / preset.width >= 16 / 9
      ? l10n.storyGroup
      : l10n.portraitGroup;
}

/// Info card surfaced in photo projects so users understand why
/// changing the canvas colour might appear to do "nothing": the
/// imported photo can fully cover the canvas. Kept lightweight --
/// one short sentence with an icon -- so it doesn't shout over the
/// real controls.
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
