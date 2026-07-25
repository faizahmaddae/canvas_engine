import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/editor_value_format.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import '../../../../app/ui/size_picker_dialog.dart';
import '../../application/document_controller.dart';
import '../../engine/core/editor_document.dart';
import '../../presentation/widgets/editor_tool_panel_shell.dart';
import '../../presentation/widgets/section_label.dart';
import '../../toolbar/presentation/widgets/preset_chip.dart';
import '../../ui/editor_segmented_control.dart';
import '../../ui/fill_mode_section.dart';
import '../application/canvas_commands.dart';
import '../application/canvas_resize.dart';
import '../application/canvas_tool_controller.dart';
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
class CanvasPanelBody extends ConsumerWidget {
  const CanvasPanelBody({super.key});

  void _commit(WidgetRef ref, Color c, {bool live = false}) {
    ref
        .read(documentControllerProvider.notifier)
        .execute(SetCanvasBackgroundCommand(color: c, live: live));
  }

  void _commitFill(WidgetRef ref, BackgroundFill fill, {bool live = false}) {
    ref
        .read(documentControllerProvider.notifier)
        .execute(SetCanvasBackgroundCommand(fill: fill, live: live));
  }

  void _commitMode(WidgetRef ref, CanvasBackgroundMode mode) {
    ref
        .read(documentControllerProvider.notifier)
        .execute(SetCanvasBackgroundModeCommand(mode));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final doc = ref.watch(documentControllerProvider);
    final currentFill = doc.background;
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
          SectionLabel(context.l10n.sizeTool),
          const _CanvasSizeSection(),
          const SizedBox(height: 14),
          if (isPhotoProject)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PhotoProjectHint(tokens: tokens),
            ),
          SectionLabel(context.l10n.backgroundTool),
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
              _commitMode(ref, next);
            },
          ),
          const SizedBox(height: 12),
          Opacity(
            opacity: isTransparent ? 0.4 : 1.0,
            child: IgnorePointer(
              ignoring: isTransparent,
              // Solid | Gradient, with the shared two-level picker
              // embedded in the solid branch. Drags stream live
              // (transient) commits; settled changes commit for real.
              // Recents and alpha policy live inside the picker.
              //
              // The canvas background is the contract's §2 exemption:
              // it has no layer to stage on the live overlay, so it
              // previews through merging live commands instead.
              child: FillModeSection(
                fill: currentFill,
                solidTitle: context.l10n.canvasBackgroundTitle,
                onSolidChanged: (c) => _commit(ref, c, live: true),
                onSolidCommitted: (c) => _commit(ref, c),
                onFillChanged: (f) => _commitFill(ref, f, live: true),
                onFillCommitted: (f) => _commitFill(ref, f),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One aspect preset in the Size row. The four cover the surfaces a
/// casual user actually re-frames for (feed square, 4:5 portrait,
/// full-bleed story, 16:9 landscape); anything else is a job for
/// Custom… rather than a longer scroller nobody reads to the end of.
class _AspectPreset {
  const _AspectPreset(this.width, this.height, this.icon);
  final double width;
  final double height;
  final IconData icon;
}

const _aspectPresets = <_AspectPreset>[
  _AspectPreset(1080, 1080, AppIcons.squareShape),
  _AspectPreset(1080, 1350, AppIcons.aspectPortrait),
  _AspectPreset(1080, 1920, AppIcons.storyPreset),
  _AspectPreset(1280, 720, AppIcons.landscapeBox),
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
    final tokens = AppTokens.of(context);
    final l10n = context.l10n;
    final width = ref.watch(documentControllerProvider.select((d) => d.width));
    final height = ref.watch(
      documentControllerProvider.select((d) => d.height),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 8),
          child: Text(
            EditorValueFormat.of(
              context,
            ).dimensions(width.round(), height.round()),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
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
                return PresetChip.option(
                  key: const ValueKey('canvas-size-custom'),
                  width: 76,
                  selected: false,
                  icon: AppIcons.precisionAdjust,
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
                icon: preset.icon,
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
