import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../l10n/l10n.dart';
import '../../../color_picker/presentation/color_picker_sheet.dart';
import '../../application/context_toolbar_controller.dart';
import '../../engine/core/viewport_state.dart';
import '../../engine/modules/text/text_layer.dart';
import '../../presentation/widgets/floating_toolbar_positioner.dart';
import '../../presentation/widgets/layer_actions.dart';
import '../../application/recent_colors_controller.dart';
import '../../text/presentation/text_direction_mode_picker.dart';
import '../../text/presentation/text_resize_mode_picker.dart';
import '../application/text_tool_controller.dart';
import 'text_edit_flow.dart';

/// Compact glass pill that hovers near the selected text layer.
///
/// Holds exactly five contextual actions, in order:
///   ✎  edit text
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
  // for the clamp; 288 covers the five pills + padding.
  static const double _estWidth = 288;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    final size = media.size;
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
    final contextCtrl = ref.read(contextToolbarControllerProvider.notifier);

    if (anchor.isHidden) return const SizedBox.shrink();

    // The bar updates in place — no AnimatedSwitcher, no per-property
    // remount. AnimatedPositioned smooths the anchor when the layer's
    // transform changes; properties (color/size) just rebuild the
    // child widgets without flicker.
    final bar = _BarContent(
      brightness: brightness,
      style: style,
      onEditText: () => showEditTextLayerFlow(context, ref, layer),
      onPickFont: () {
        contextCtrl.closePanel();
        ctrl.openSheet('font');
      },
      onPickColor: () async {
        contextCtrl.closePanel();
        final original = layer.style.color;
        final picked = await showColorPickerSheet(
          context,
          initial: original,
          recents: ref.read(recentColorsControllerProvider),
          onLiveChange: ctrl.setColor,
          title: context.l10n.textColorTitle,
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
      onPickSize: () {
        contextCtrl.closePanel();
        ctrl.openSheet('size');
      },
      // More: text-specific action sheet. Hosts the moved Edit-text
      // entry, the B/I/U toggles (relocated from a standalone Bold
      // pill on this bar) and the existing layer actions.
      onMore: () {
        contextCtrl.closePanel();
        showTextMoreSheet(context, ref, layer);
      },
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
    required this.brightness,
    required this.style,
    required this.onEditText,
    required this.onPickFont,
    required this.onPickColor,
    required this.onPickSize,
    required this.onMore,
  });

  final Brightness brightness;
  final TextStyleSpec style;
  final VoidCallback onEditText;
  final VoidCallback onPickFont;
  final VoidCallback onPickColor;
  final VoidCallback onPickSize;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final isDark = brightness == Brightness.dark;
    final borderColor = tokens.border;
    final fg = tokens.textPrimary;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: tokens.surface.withValues(alpha: isDark ? 0.55 : 0.78),
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
                onTap: onEditText,
                semanticLabel: context.l10n.editTextAction,
                child: Icon(Icons.edit_rounded, size: 18, color: fg),
              ),
              const SizedBox(width: 4),
              _PillButton(
                onTap: onPickFont,
                semanticLabel: context.l10n.fontTool,
                child: Icon(Icons.text_fields_rounded, size: 18, color: fg),
              ),
              const SizedBox(width: 4),
              _PillButton(
                onTap: onPickColor,
                semanticLabel: context.l10n.textColorTitle,
                child: _ColorDot(color: style.color),
              ),
              const SizedBox(width: 4),
              _PillButton(
                onTap: onPickSize,
                semanticLabel: context.l10n.fontSizeSemantics,
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
                semanticLabel: context.l10n.moreActionsSemantics,
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
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          splashColor: tokens.accent.withValues(alpha: 0.10),
          highlightColor: tokens.accent.withValues(alpha: 0.05),
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
    final tokens = AppTokens.of(context);
    final canForward = LayerActions.canBringForward(parentRef, layer);
    final canBackward = LayerActions.canSendBackward(parentRef, layer);
    final style = layer.style;
    final l10n = context.l10n;

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
              title: Text(l10n.editTextAction),
              onTap: () async {
                Navigator.of(context).pop();
                await showEditTextLayerFlow(context, parentRef, layer);
              },
            ),
            ListTile(
              leading: const Icon(Icons.align_horizontal_left_rounded),
              title: Text(l10n.alignAction),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.of(context).pop();
                parentRef
                    .read(contextToolbarControllerProvider.notifier)
                    .open(ContextToolPanel.align);
              },
            ),
            ListTile(
              leading: const Icon(Icons.opacity),
              title: Text(l10n.opacityLabel),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.of(context).pop();
                parentRef
                    .read(contextToolbarControllerProvider.notifier)
                    .open(ContextToolPanel.opacity);
              },
            ),
            const Divider(height: 1),
            // B / I / U toggles — closing the sheet on each tap would
            // be jarring, so they stay inline and the user can flip
            // multiple flags before dismissing.
            ListTile(
              leading: Icon(
                Icons.format_bold_rounded,
                color: style.isBold ? tokens.accent : null,
              ),
              title: Text(l10n.boldAction),
              trailing: style.isBold
                  ? Icon(Icons.check_rounded, color: tokens.accent)
                  : null,
              onTap: () => parentRef
                  .read(textToolControllerProvider.notifier)
                  .setBold(!style.isBold),
            ),
            ListTile(
              leading: Icon(
                Icons.format_italic_rounded,
                color: style.italic ? tokens.accent : null,
              ),
              title: Text(l10n.italicAction),
              trailing: style.italic
                  ? Icon(Icons.check_rounded, color: tokens.accent)
                  : null,
              onTap: () => parentRef
                  .read(textToolControllerProvider.notifier)
                  .setItalic(!style.italic),
            ),
            ListTile(
              leading: Icon(
                Icons.format_underline_rounded,
                color: style.underline ? tokens.accent : null,
              ),
              title: Text(l10n.underlineAction),
              trailing: style.underline
                  ? Icon(Icons.check_rounded, color: tokens.accent)
                  : null,
              onTap: () => parentRef
                  .read(textToolControllerProvider.notifier)
                  .setUnderline(!style.underline),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: Text(l10n.renameAction),
              onTap: () async {
                await LayerActions.rename(context, parentRef, layer);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: Text(l10n.duplicateAction),
              onTap: () {
                Navigator.of(context).pop();
                LayerActions.duplicate(parentRef, layer);
              },
            ),
            ListTile(
              enabled: canForward,
              leading: const Icon(Icons.flip_to_front_rounded),
              title: Text(l10n.bringForwardAction),
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
              title: Text(l10n.sendBackwardAction),
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
              title: Text(
                layer.locked ? l10n.unlockLayerAction : l10n.lockLayerAction,
              ),
              onTap: () {
                Navigator.of(context).pop();
                LayerActions.toggleLock(parentRef, layer);
              },
            ),
            ListTile(
              leading: Icon(textResizeModeIcon(layer.resizeMode)),
              title: Text(l10n.resizeBehaviorTitle),
              subtitle: Text(
                localizedTextResizeModeLabel(context, layer.resizeMode),
              ),
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
            ListTile(
              leading: Icon(textDirectionModeIcon(layer.textDirectionMode)),
              title: Text(l10n.textDirectionTitle),
              subtitle: Text(
                localizedTextDirectionModeLabel(
                  context,
                  layer.textDirectionMode,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                Navigator.of(context).pop();
                final current = layer.textDirectionMode;
                final picked = await pickTextDirectionMode(context, current);
                if (picked != null && picked != current) {
                  parentRef
                      .read(textToolControllerProvider.notifier)
                      .setTextDirectionMode(picked);
                }
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
              title: Text(
                l10n.deleteAction,
                style: TextStyle(color: scheme.error),
              ),
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
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppTokens.of(context).border, width: 1),
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
