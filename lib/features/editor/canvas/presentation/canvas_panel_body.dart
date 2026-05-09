import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/haptics.dart';
import '../../../color_picker/presentation/color_picker_sheet.dart';
import '../../application/document_controller.dart';
import '../../engine/core/editor_document.dart';
import '../../presentation/widgets/editor_tool_panel_shell.dart';
import '../../presentation/widgets/inline_color_body.dart';
import '../../presentation/widgets/recent_colors_controller.dart';
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
    ref.read(documentControllerProvider.notifier).execute(
          SetCanvasBackgroundCommand(color: c, live: live),
        );
  }

  void _commitMode(WidgetRef ref, CanvasBackgroundMode mode) {
    ref.read(documentControllerProvider.notifier).execute(
          SetCanvasBackgroundModeCommand(mode),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final doc = ref.watch(documentControllerProvider);
    final current = doc.backgroundColor;
    final mode = doc.backgroundMode;
    final isPhotoProject = doc.projectKind == ProjectKind.photo;
    final isTransparent = mode == CanvasBackgroundMode.transparent;
    final recents = ref.watch(recentColorsControllerProvider);

    return EditorToolPanelShell(
      title: 'Background',
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
              child: _PhotoProjectHint(scheme: scheme),
            ),
          // Header already says "Background" — no duplicate SectionLabel.
          _BackgroundModeToggle(
            value: mode,
            onChanged: (next) {
              if (next == mode) return;
              EditorHaptics.toggle();
              _commitMode(ref, next);
            },
            scheme: scheme,
          ),
          const SizedBox(height: 12),
          Opacity(
            opacity: isTransparent ? 0.4 : 1.0,
            child: IgnorePointer(
              ignoring: isTransparent,
              child: InlineColorBody(
                current: current,
                recents: recents,
                palette: InlineColorBody.defaultPalette,
                onPick: (picked) {
                  EditorHaptics.toggle();
                  _commit(ref, picked);
                },
                onCustom: () async {
                  final original = current;
                  final picked = await showColorPickerSheet(
                    context,
                    initial: original,
                    recents: recents,
                    onLiveChange: (c) =>
                        _commit(ref, c, live: true),
                    title: 'Canvas background',
                  );
                  if (picked == null) {
                    // Cancelled — restore the original colour so
                    // the live-drag stream doesn't stick.
                    _commit(ref, original);
                    return;
                  }
                  ref
                      .read(recentColorsControllerProvider.notifier)
                      .remember(picked);
                },
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
    required this.scheme,
  });

  final CanvasBackgroundMode value;
  final ValueChanged<CanvasBackgroundMode> onChanged;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _ModeTile(
            key: const ValueKey('canvas-bg-mode-color'),
            label: 'Color',
            selected: value == CanvasBackgroundMode.color,
            onTap: () => onChanged(CanvasBackgroundMode.color),
            scheme: scheme,
          ),
          _ModeTile(
            key: const ValueKey('canvas-bg-mode-transparent'),
            label: 'Transparent',
            selected: value == CanvasBackgroundMode.transparent,
            onTap: () => onChanged(CanvasBackgroundMode.transparent),
            scheme: scheme,
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
    required this.scheme,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme scheme;

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
            color: selected ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
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
  const _PhotoProjectHint({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: scheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Background only shows behind transparent or uncovered '
              'areas of your photo.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: scheme.onSurface.withValues(alpha: 0.78),
              ),
            ),
          ),
        ],
      ),
    );
  }
}



