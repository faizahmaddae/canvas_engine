import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../application/document_controller.dart';
import '../../engine/core/editor_document.dart';
import '../../presentation/widgets/editor_tool_panel_shell.dart';
import '../../ui/editor_segmented_control.dart';
import '../../ui/fill_mode_section.dart';
import '../application/canvas_commands.dart';
import '../application/canvas_tool_controller.dart';

/// Expanded panel body for the Canvas tool. Two sections:
///
///   * Background **mode** — solid colour vs. transparent (alpha-
///     preserving on PNG export, checkerboard preview in the editor).
///   * Background **fill** — only relevant in colour mode; Solid |
///     Gradient, both dispatched through [SetCanvasBackgroundCommand].
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
      title: context.l10n.backgroundTool,
      icon: Icons.image_outlined,
      onClose: () =>
          ref.read(canvasToolControllerProvider.notifier).closePanel(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isPhotoProject)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PhotoProjectHint(tokens: tokens),
            ),
          // Header already says "Background" — no duplicate SectionLabel.
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
          Icon(Icons.info_outline_rounded, size: 16, color: tokens.accent),
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
