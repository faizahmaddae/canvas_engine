import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../l10n/l10n.dart';
import '../../application/document_controller.dart';
import '../../engine/core/editor_layer.dart';
import '../../engine/core/viewport_state.dart';
import 'floating_toolbar_positioner.dart';
import 'layer_actions.dart';

/// Small floating pill hovering near the selected layer with the
/// highest-frequency structural actions: duplicate, order, lock, delete.
///
/// This is deliberately a **helper, not a toolbar replacement** — the
/// main bottom dock still owns exhaustive layer operations. The quick
/// bar exists so the two most-common follow-ups to selecting something
/// (clone it, remove it) are reachable in one tap at the object,
/// without a trip to the layers panel.
///
/// Visibility is owned by the canvas (same pattern as the text / paint
/// floating toolbars): the bar is mounted only when a single layer is
/// selected, not while inline-editing, and not while a transform
/// gesture is in flight. See `_buildQuickActionsOverlay` in
/// `editor_canvas.dart`.
///
/// Positioning: prefers **above** the selection. When a type-specific
/// floating toolbar (text/paint) is also shown above, the quick bar
/// stacks above that toolbar so neither occludes the other. Falls back
/// below the selection when the stacked position would clip the top of
/// the screen (notch / dynamic island aware via `MediaQuery.padding`).
///
/// All actions route through existing engine commands
/// ([AddLayerCommand], [RemoveLayerCommand], [ReorderLayerCommand]) so
/// undo/redo and the command-history merge protocol are preserved.
class QuickActionsOverlay extends ConsumerWidget {
  const QuickActionsOverlay({
    super.key,
    required this.layer,
    required this.viewport,
  });

  final EditorLayer layer;
  final ViewportState viewport;

  static const double _barHeight = 44;
  static const double _gap = 10;
  static const double _horizontalMargin = 12;

  // Estimated bar width — used only to clamp horizontally. The bar
  // sizes itself via IntrinsicWidth, but we need a reasonable bound
  // for the clamp; covers five 44 dp pills + 4 dividers + padding.
  static const double _estWidth = 269;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final doc = ref.watch(documentControllerProvider);

    // Bring-forward availability: off when already topmost. We still
    // render the pill (with disabled styling) so the bar's width is
    // stable across selections — the pill doesn't flicker in and out
    // of existence as the user reorders layers.
    final index = doc.indexOf(layer.id);
    final canBringForward = index != null && index < doc.layers.length - 1;
    final canSendBackward = index != null && index > 0;

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

    if (anchor.isHidden) return const SizedBox.shrink();

    final bar = _BarContent(
      scheme: scheme,
      isDark: isDark,
      canBringForward: canBringForward,
      canSendBackward: canSendBackward,
      isLocked: layer.locked,
      onDuplicate: () => LayerActions.duplicate(ref, layer),
      onDelete: () => LayerActions.delete(context, ref, layer),
      onBringForward: canBringForward ? () => _bringForward(ref) : null,
      onSendBackward: canSendBackward ? () => _sendBackward(ref) : null,
      onToggleLock: () => LayerActions.toggleLock(ref, layer),
    );

    return AnimatedPositioned(
      left: anchor.left,
      top: anchor.top,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      // Scale-in on appear so the pill reads as "popped from the
      // selection" rather than just teleporting in. Keyed by
      // layer.id so a fresh selection always re-plays the entrance.
      child: SizedBox(
        height: _barHeight,
        child: _PopIn(key: ValueKey(layer.id), child: bar),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Actions — thin delegations to [LayerActions] so the bottom-sheet
  // overflow menu and this overlay never drift apart.
  // ------------------------------------------------------------------

  void _bringForward(WidgetRef ref) {
    LayerActions.bringForward(ref, layer);
  }

  void _sendBackward(WidgetRef ref) {
    LayerActions.sendBackward(ref, layer);
  }
}

class _BarContent extends StatelessWidget {
  const _BarContent({
    required this.scheme,
    required this.isDark,
    required this.canBringForward,
    required this.canSendBackward,
    required this.isLocked,
    required this.onDuplicate,
    required this.onDelete,
    required this.onBringForward,
    required this.onSendBackward,
    required this.onToggleLock,
  });

  final ColorScheme scheme;
  final bool isDark;
  final bool canBringForward;
  final bool canSendBackward;
  final bool isLocked;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback? onBringForward;
  final VoidCallback? onSendBackward;
  final VoidCallback onToggleLock;

  @override
  Widget build(BuildContext context) {
    // Glass pill — matches the visual language of the text / paint
    // floating toolbars so the three bars read as one system. Shadow
    // is slightly heavier than on the style bars because this one is
    // structural (its actions are destructive/duplicative) and we
    // want it to read a touch stronger against busy canvas content.
    // v2: paper/ink tokens instead of raw white/black glass.
    final tokens = AppTokens.of(context);
    final bg = tokens.surface.withValues(alpha: isDark ? 0.90 : 0.94);
    final fg = tokens.textPrimary;
    final dividerColor = tokens.border.withValues(alpha: 0.8);

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tokens.border),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ActionPill(
              icon: Icons.content_copy_rounded,
              tooltip: context.l10n.duplicateAction,
              color: fg,
              onTap: onDuplicate,
            ),
            _Divider(color: dividerColor),
            _ActionPill(
              icon: isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
              tooltip: isLocked
                  ? context.l10n.unlockAction
                  : context.l10n.lockAction,
              // Locked state tints the pill saffron so the user
              // sees the lock is engaged at a glance — matches the
              // layers panel highlight semantics.
              color: isLocked ? tokens.accent : fg,
              onTap: onToggleLock,
            ),
            _Divider(color: dividerColor),
            _ActionPill(
              icon: Icons.flip_to_back_rounded,
              tooltip: context.l10n.sendBackwardAction,
              color: fg,
              enabled: canSendBackward,
              onTap: onSendBackward,
            ),
            _Divider(color: dividerColor),
            _ActionPill(
              icon: Icons.flip_to_front_rounded,
              tooltip: context.l10n.bringForwardAction,
              color: fg,
              enabled: canBringForward,
              onTap: onBringForward,
            ),
            _Divider(color: dividerColor),
            _ActionPill(
              icon: Icons.delete_outline_rounded,
              tooltip: context.l10n.deleteAction,
              // Destructive action — tint red so it's visually
              // distinct from the neutral pills and the user has a
              // beat of recognition before committing.
              color: scheme.error,
              onTap: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // 44 dp touch target — satisfies both Material (48) in spirit and
    // Apple HIG (44). Visually the icon is 20 dp; the remaining area
    // is invisible hit-box.
    final effectiveColor = enabled ? color : color.withValues(alpha: 0.35);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 20, color: effectiveColor),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 20, color: color);
  }
}

/// Brief scale + fade entrance used when the quick-action bar
/// first attaches to a fresh selection. Ships at 0.85 → 1.0 over
/// 180ms (easeOutBack) so the pill reads as "popped" out of the
/// layer rather than flashed in. Re-keyed by layer.id at the
/// callsite so each new selection re-plays the animation.
class _PopIn extends StatefulWidget {
  const _PopIn({super.key, required this.child});
  final Widget child;

  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _scale = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).chain(CurveTween(curve: Curves.easeOutBack)).animate(_ctrl);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
