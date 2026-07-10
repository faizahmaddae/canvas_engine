import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../../color_picker/presentation/color_picker_sheet.dart';
import '../../application/document_controller.dart';
import '../../engine/core/editor_document.dart';
import '../../presentation/widgets/editor_tool_panel_shell.dart';
import '../application/canvas_commands.dart';
import '../application/canvas_tool_controller.dart';

/// Expanded panel body for the Canvas tool. Two sections:
///
///   * Background **mode** — solid colour vs. transparent (alpha-
///     preserving on PNG export, checkerboard preview in the editor).
///   * Background **colour** — only relevant in colour mode; the
///     palette + custom picker dispatch [SetCanvasBackgroundCommand].
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

  void _commitMode(WidgetRef ref, CanvasBackgroundMode mode) {
    ref
        .read(documentControllerProvider.notifier)
        .execute(SetCanvasBackgroundModeCommand(mode));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final doc = ref.watch(documentControllerProvider);
    final current = doc.backgroundColor;
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
          _BackgroundModeToggle(
            value: mode,
            onChanged: (next) {
              if (next == mode) return;
              EditorHaptics.toggle();
              _commitMode(ref, next);
            },
            tokens: tokens,
          ),
          const SizedBox(height: 12),
          Opacity(
            opacity: isTransparent ? 0.4 : 1.0,
            child: IgnorePointer(
              ignoring: isTransparent,
              // The shared two-level picker, embedded. Drags stream
              // live (transient) commits; settled changes commit
              // for real. Recents and alpha policy live inside it.
              child: ColorPickerBody(
                initial: current,
                title: context.l10n.canvasBackgroundTitle,
                onChanged: (c) => _commit(ref, c, live: true),
                onCommitted: (c) => _commit(ref, c),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two-tile segmented selector: Color | Transparent. Mirrors the
/// look of the dock's other segmented controls (rounded pill, tinted
/// active state) so the canvas panel feels at home.
class _BackgroundModeToggle extends StatelessWidget {
  const _BackgroundModeToggle({
    required this.value,
    required this.onChanged,
    required this.tokens,
  });

  final CanvasBackgroundMode value;
  final ValueChanged<CanvasBackgroundMode> onChanged;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tokens.surfaceMuted.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _ModeTile(
            key: const ValueKey('canvas-bg-mode-color'),
            label: context.l10n.colorLabel,
            selected: value == CanvasBackgroundMode.color,
            onTap: () => onChanged(CanvasBackgroundMode.color),
            tokens: tokens,
          ),
          _ModeTile(
            key: const ValueKey('canvas-bg-mode-transparent'),
            label: context.l10n.transparentOption,
            selected: value == CanvasBackgroundMode.transparent,
            onTap: () => onChanged(CanvasBackgroundMode.transparent),
            tokens: tokens,
          ),
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.tokens,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected
                ? tokens.accent.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: selected ? tokens.accentDeep : tokens.textSecondary,
            ),
          ),
        ),
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
