import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../color_picker/presentation/color_picker_sheet.dart';
import '../../engine/core/viewport_state.dart';
import '../../engine/modules/text/text_layer.dart';
import '../../presentation/widgets/floating_toolbar_positioner.dart';
import '../../presentation/widgets/layer_actions.dart';
import '../../presentation/widgets/recent_colors_controller.dart';
import '../../text/presentation/text_resize_mode_picker.dart';
import '../application/text_tool_controller.dart';
import 'text_input_flow_sheet.dart';

/// Compact glass pill that hovers near the selected text layer.
///
/// Holds exactly four contextual actions, in order:
///   Aa font picker (opens the dock font sheet)
///   ●  color swatch
///   Aa size readout (opens the dock size sheet)
///   ⋯  more (opens the text actions sheet — Edit text, B/I/U,
///        layer actions)
///
/// Anything heavier (alignment, spacing, effects) lives in the
/// bottom-dock category sheets. This bar is the fast path only.
///
/// Visibility is owned by the canvas: the bar is mounted only when a
/// single text layer is selected and is unmounted while inline-editing
/// or while a transform gesture is in flight (see
/// `_buildTextFloatingToolbar` in `editor_canvas.dart`).
class TextFloatingToolbar extends ConsumerWidget {
  const TextFloatingToolbar({
    super.key,
    required this.layer,
    required this.viewport,
  });

  final TextLayer layer;
  final ViewportState viewport;

  static const double _barHeight = 40;
  static const double _gap = 16;
  static const double _horizontalMargin = 12;
  // Estimated bar width — used only to clamp horizontally. The bar
  // sizes itself via IntrinsicWidth, but we need a reasonable bound
  // for the clamp; 240 covers the four pills + padding.
  static const double _estWidth = 240;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final style = layer.style;

    final anchor = FloatingToolbarPositioner.resolve(
      layerPosition: layer.transform.position,
      layerSize: layer.transform.size,
      layerCenter: layer.transform.center,
      layerRotation: layer.transform.rotation,
      viewport: viewport,
      screenSize: size,
      safePadding: media.padding,
      barWidth: _estWidth,
      barHeight: _barHeight,
      gap: _gap,
      horizontalMargin: _horizontalMargin,
      bottomReserved: FloatingToolbarPositioner.dockHeight(
        screen: size,
        orientation: media.orientation,
      ),
    );
    final ctrl = ref.read(textToolControllerProvider.notifier);

    if (anchor.isHidden) return const SizedBox.shrink();

    // The bar updates in place — no AnimatedSwitcher, no per-property
    // remount. AnimatedPositioned smooths the anchor when the layer's
    // transform changes; properties (color/size) just rebuild the
    // child widgets without flicker.
    final bar = _BarContent(
      scheme: scheme,
      brightness: brightness,
      style: style,
      onPickFont: () => ctrl.openSheet('font'),
      onPickColor: () async {
        final original = layer.style.color;
        final picked = await showColorPickerSheet(
          context,
          initial: original,
          recents: ref.read(recentColorsControllerProvider),
          onLiveChange: ctrl.setColor,
          title: 'Text color',
        );
        if (picked == null) {
          ctrl.setColor(original);
          return;
        }
        ctrl.setColor(picked);
        ctrl.rememberRecentColor(picked);
      },
      // Size opens the SAME bottom-dock sheet ('size') the dock tile
      // uses — single source of truth, single chrome (Done pill,
      // sibling swipe, undo chip). No more standalone modal.
      onPickSize: () => ctrl.openSheet('size'),
      // More: text-specific action sheet. Hosts the moved Edit-text
      // entry, the B/I/U toggles (relocated from a standalone Bold
      // pill on this bar) and the existing layer actions.
      onMore: () => showTextMoreSheet(context, ref, layer),
    );

    return AnimatedPositioned(
      left: anchor.left,
      top: anchor.top,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: SizedBox(height: _barHeight, child: bar),
    );
  }
}

class _BarContent extends StatelessWidget {
  const _BarContent({
    required this.scheme,
    required this.brightness,
    required this.style,
    required this.onPickFont,
    required this.onPickColor,
    required this.onPickSize,
    required this.onMore,
  });

  final ColorScheme scheme;
  final Brightness brightness;
  final TextStyleSpec style;
  final VoidCallback onPickFont;
  final VoidCallback onPickColor;
  final VoidCallback onPickSize;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final isDark = brightness == Brightness.dark;
    final borderColor = (isDark ? Colors.white : Colors.black).withValues(
      alpha: 0.10,
    );
    final fg = isDark ? Colors.white : const Color(0xFF1A1A1A);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: isDark ? 0.55 : 0.78),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 0.6),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PillButton(
                onTap: onPickFont,
                semanticLabel: 'Font',
                child: Icon(Icons.text_fields_rounded, size: 18, color: fg),
              ),
              const SizedBox(width: 4),
              _PillButton(
                onTap: onPickColor,
                semanticLabel: 'Text color',
                child: _ColorDot(color: style.color),
              ),
              const SizedBox(width: 4),
              _PillButton(
                onTap: onPickSize,
                semanticLabel: 'Font size',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Aa',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: fg,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      style.fontSize.round().toString(),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: fg.withValues(alpha: 0.72),
                        fontFeatures: const [FontFeature.tabularFigures()],
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              _PillButton(
                onTap: onMore,
                semanticLabel: 'More actions',
                child: Icon(Icons.more_horiz_rounded, size: 20, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact pill used by font / color / size / more. Idle is fully
/// transparent so the row reads as a single connected glass pill.
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.onTap,
    required this.child,
    this.semanticLabel,
  });

  final VoidCallback onTap;
  final Widget child;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          splashColor: scheme.primary.withValues(alpha: 0.10),
          highlightColor: scheme.primary.withValues(alpha: 0.05),
          child: Container(
            constraints: const BoxConstraints(minWidth: 40, minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Text-specific overflow sheet opened by the floating bar's `⋯`
/// pill. Combines:
///   * Edit text — opens the inline keyboard editor with live preview.
///   * Bold / Italic / Underline — relocated from the standalone Bold
///     pill that used to live on the floating bar.
///   * Standard layer ops (duplicate, reorder, lock, resize behavior,
///     delete) — kept here so every text action is reachable in ≤ 2
///     taps without crowding the floating bar.
Future<void> showTextMoreSheet(
  BuildContext context,
  WidgetRef ref,
  TextLayer layer,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => _TextMoreSheet(layer: layer, parentRef: ref),
  );
}

class _TextMoreSheet extends StatelessWidget {
  const _TextMoreSheet({required this.layer, required this.parentRef});

  final TextLayer layer;
  // We use the parent screen's [WidgetRef] for the same reason
  // [_LayerActionsSheet] does — the modal sheet is mounted in a root
  // [Navigator] which sits OUTSIDE the editor `ProviderScope` in some
  // embedder configurations.
  final WidgetRef parentRef;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canForward = LayerActions.canBringForward(parentRef, layer);
    final canBackward = LayerActions.canSendBackward(parentRef, layer);
    final style = layer.style;

    return SafeArea(
      // The action list (Edit · B/I/U · Duplicate · Reorder · Lock ·
      // Resize · Delete) is too tall to fit in the default modal
      // sheet height on shorter devices. Wrap in a scroll view so
      // the bottom rows stay reachable instead of overflowing.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Edit text'),
              onTap: () async {
                Navigator.of(context).pop();
                final ctrl = parentRef.read(
                  textToolControllerProvider.notifier,
                );
                ctrl.beginEditText();
                final result = await showTextInputFlowSheet(
                  context,
                  initial: layer.content,
                  title: 'Edit text',
                  confirmLabel: 'Apply',
                  onLiveChange: ctrl.previewContent,
                );
                if (result == null) {
                  ctrl.cancelLiveEdit();
                } else {
                  ctrl.commitLiveEdit(result);
                }
              },
            ),
            const Divider(height: 1),
            // B / I / U toggles — closing the sheet on each tap would
            // be jarring, so they stay inline and the user can flip
            // multiple flags before dismissing.
            ListTile(
              leading: Icon(
                Icons.format_bold_rounded,
                color: style.isBold ? scheme.primary : null,
              ),
              title: const Text('Bold'),
              trailing: style.isBold
                  ? Icon(Icons.check_rounded, color: scheme.primary)
                  : null,
              onTap: () => parentRef
                  .read(textToolControllerProvider.notifier)
                  .setBold(!style.isBold),
            ),
            ListTile(
              leading: Icon(
                Icons.format_italic_rounded,
                color: style.italic ? scheme.primary : null,
              ),
              title: const Text('Italic'),
              trailing: style.italic
                  ? Icon(Icons.check_rounded, color: scheme.primary)
                  : null,
              onTap: () => parentRef
                  .read(textToolControllerProvider.notifier)
                  .setItalic(!style.italic),
            ),
            ListTile(
              leading: Icon(
                Icons.format_underline_rounded,
                color: style.underline ? scheme.primary : null,
              ),
              title: const Text('Underline'),
              trailing: style.underline
                  ? Icon(Icons.check_rounded, color: scheme.primary)
                  : null,
              onTap: () => parentRef
                  .read(textToolControllerProvider.notifier)
                  .setUnderline(!style.underline),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: const Text('Duplicate'),
              onTap: () {
                Navigator.of(context).pop();
                LayerActions.duplicate(parentRef, layer);
              },
            ),
            ListTile(
              enabled: canForward,
              leading: const Icon(Icons.flip_to_front_rounded),
              title: const Text('Bring forward'),
              onTap: !canForward
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      LayerActions.bringForward(parentRef, layer);
                    },
            ),
            ListTile(
              enabled: canBackward,
              leading: const Icon(Icons.flip_to_back_rounded),
              title: const Text('Send backward'),
              onTap: !canBackward
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      LayerActions.sendBackward(parentRef, layer);
                    },
            ),
            ListTile(
              leading: Icon(
                layer.locked
                    ? Icons.lock_open_rounded
                    : Icons.lock_outline_rounded,
              ),
              title: Text(layer.locked ? 'Unlock layer' : 'Lock layer'),
              onTap: () {
                Navigator.of(context).pop();
                LayerActions.toggleLock(parentRef, layer);
              },
            ),
            ListTile(
              leading: Icon(textResizeModeIcon(layer.resizeMode)),
              title: const Text('Resize behavior'),
              subtitle: Text(textResizeModeLabel(layer.resizeMode)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                Navigator.of(context).pop();
                final current = layer.resizeMode;
                final picked = await pickTextResizeMode(context, current);
                if (picked != null && picked != current) {
                  parentRef
                      .read(textToolControllerProvider.notifier)
                      .setResizeMode(picked);
                }
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
              title: Text('Delete', style: TextStyle(color: scheme.error)),
              onTap: () async {
                await LayerActions.delete(context, parentRef, layer);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.28),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}
