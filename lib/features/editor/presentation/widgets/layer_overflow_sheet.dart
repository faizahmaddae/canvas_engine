import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
import '../../application/alignment_controller.dart';
import '../../application/context_toolbar_controller.dart';
import '../../application/document_controller.dart';
import '../../engine/core/editor_layer.dart';
import '../../engine/modules/paint/paint_layer.dart';
import '../../engine/modules/shape/shape_layer.dart';
import '../../engine/modules/text/text_layer.dart';
import '../../paint/application/paint_tool_controller.dart';
import '../../shape/application/shape_tool_controller.dart';
import '../../text/application/text_tool_controller.dart';
import '../../text/presentation/text_direction_mode_picker.dart';
import '../../../../app/ui/app_modal_sheet.dart';
import '../../text/presentation/text_edit_flow.dart';
import '../../text/presentation/text_resize_mode_picker.dart';
import 'layer_actions.dart';
import '../../../../app/theme/app_icons.dart';

/// THE layer overflow sheet — the single «⋯ / بیشتر» destination for
/// every layer type and for multi-selection (tb2 7/16; replaces the
/// three drifted copies `layer_actions_sheet.dart`,
/// `selected_layer_actions_sheet.dart` and `panels/text/more_sheet.dart`).
///
/// Row-spec driven: [_buildRows] assembles the canonical row order
/// once, and each row appears only when the selected layer type has
/// the capability. Canonical order (interaction contract §1 class M):
///
///   1. Edit text (text)            7. Bring forward / Send backward
///   2. Align → context panel       8. Lock/Unlock (ACTION icon)
///   3. Opacity → context panel     9. Resize behavior (text/shape/paint)
///   5. Rename                     10. Text direction (text)
///   6. Duplicate                  11. Layers → end drawer
///                                 12. Delete (danger)
///
/// (Row 4 was the B/I/U inline toggle row; it moved to the استایل
/// dock panel — live toggles need a visible canvas, not a full scrim.
/// Numbering kept so the row-order tests read against history.)
///
/// Multi-selection renders the batch variant: count header + Align +
/// batch Duplicate / Lock / Delete (each ONE CompositeCommand → one
/// undo entry) + Layers.
///
/// Interaction-contract class M, full barrier — hosted by the
/// shared editor modal host ([showAppSheet], tb2 8/16).
/// Delete runs the ONE canonical sequence for every entry point:
/// confirm (protected/base cases) BEFORE the sheet pops, then
/// dismiss, then execute.
Future<void> showLayerOverflowSheet(
  BuildContext context,
  WidgetRef ref, {
  required EditorLayer layer,
  List<EditorLayer>? selectedLayers,
  VoidCallback? onOpenLayers,
}) {
  final layers = (selectedLayers == null || selectedLayers.length <= 1)
      ? <EditorLayer>[layer]
      : selectedLayers;
  // FULL barrier (contract §9: overflow sheets). Card + handle come
  // from the shared modal host (tb2 8/16); the 9/16 height clamp the
  // old non-isScrollControlled route provided is preserved
  // explicitly so short devices keep every row reachable by scroll.
  return showAppSheet<void>(
    context,
    maxHeightFraction: 9 / 16,
    builder: (ctx) => _LayerOverflowSheet(
      hostContext: context,
      layer: layer,
      selectedLayers: layers,
      parentRef: ref,
      onOpenLayers: onOpenLayers,
    ),
  );
}

class _LayerOverflowSheet extends StatelessWidget {
  const _LayerOverflowSheet({
    required this.hostContext,
    required this.layer,
    required this.selectedLayers,
    required this.parentRef,
    this.onOpenLayers,
  });

  /// The editor-screen context that outlives the sheet. Follow-up
  /// surfaces (rename dialog, pickers, the text edit flow) open on
  /// this context AFTER the sheet pops so they never sit on a
  /// deactivated route.
  final BuildContext hostContext;

  final EditorLayer layer;
  final List<EditorLayer> selectedLayers;

  /// The parent screen's [WidgetRef]: the modal sheet mounts under
  /// the root navigator, which sits OUTSIDE the editor
  /// `ProviderScope` in some embedder configurations — provider
  /// access must go through the ref the caller was already using.
  final WidgetRef parentRef;

  final VoidCallback? onOpenLayers;

  bool get isMulti => selectedLayers.length > 1;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      // The union list is tall; compact density + a scroll guard keep
      // every row reachable on short devices (the sheet opens without
      // isScrollControlled, clamped to 9/16 of screen height).
      child: ListTileTheme(
        data: const ListTileThemeData(
          dense: true,
          visualDensity: VisualDensity.compact,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...(isMulti ? _buildMultiRows(context) : _buildRows(context)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Pop the sheet, then run [action] against the host context on
  /// the next microtask-safe boundary. The shared tail of every
  /// link-out row.
  void _popThen(BuildContext sheetContext, VoidCallback action) {
    Navigator.of(sheetContext).pop();
    if (!hostContext.mounted) return;
    action();
  }

  // ─── single-layer variant ────────────────────────────────────────

  List<Widget> _buildRows(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    // Emoji stickers are stored as TextLayer but expose none of the
    // text capabilities (edit flow, B/I/U, resize/direction modes).
    final textLayer = (layer is TextLayer && !(layer as TextLayer).isSticker)
        ? layer as TextLayer
        : null;
    final shapeLayer = layer is ShapeLayer ? layer as ShapeLayer : null;
    final paintLayer = layer is PaintLayer ? layer as PaintLayer : null;
    final canForward = LayerActions.canBringForward(parentRef, layer);
    final canBackward = LayerActions.canSendBackward(parentRef, layer);
    // Align moves a layer, and AlignmentController refuses layers that
    // cannot move: locked ones, and the protected base photo (it IS
    // the canvas, so "align to canvas" is meaningless for it by
    // construction — hit-testing skips it, InteractionController
    // declines drag/resize/rotate). Rendering the row live in those
    // states gave the user six buttons that silently did nothing —
    // worse than an unavailable row, because it looks like it worked
    // (audit P2-7). Greyed out instead, the same treatment the reorder
    // rows above already use — and gated by THE eligibility rule the
    // controller commits through, so row and command cannot drift.
    final canAlign = AlignmentEligibility.of(
      parentRef.read(documentControllerProvider),
      [layer],
    ).canAlign;

    return [
      // 1 — Edit text
      if (textLayer != null)
        ListTile(
          leading: const Icon(AppIcons.editText),
          title: Text(l10n.editTextAction),
          onTap: () => _popThen(context, () {
            showEditTextLayerFlow(hostContext, parentRef, textLayer);
          }),
        ),
      // 2 — Align (context panel link)
      ListTile(
        enabled: canAlign,
        leading: const Icon(AppIcons.alignLeft),
        title: Text(l10n.alignAction),
        trailing: canAlign ? const Icon(AppIcons.drillIn) : null,
        onTap: !canAlign
            ? null
            : () => _popThen(context, () {
                parentRef
                    .read(contextToolbarControllerProvider.notifier)
                    .open(ContextToolPanel.align);
              }),
      ),
      // 3 — Opacity (context panel link)
      ListTile(
        leading: const Icon(AppIcons.opacity),
        title: Text(l10n.opacityLabel),
        trailing: const Icon(AppIcons.drillIn),
        onTap: () => _popThen(context, () {
          parentRef
              .read(contextToolbarControllerProvider.notifier)
              .open(ContextToolPanel.opacity);
        }),
      ),
      // (B/I/U moved to the استایل panel — a dock panel is a live
      // surface with the canvas visible, which is what document-
      // mutating toggles need; here they mutated behind a full scrim
      // in a list where every other row pops-then-acts. ux-audit P3-2)
      // 5 — Rename
      ListTile(
        leading: const Icon(AppIcons.rename),
        title: Text(l10n.renameAction),
        onTap: () => _popThen(context, () {
          LayerActions.rename(hostContext, parentRef, layer);
        }),
      ),
      // 6 — Duplicate
      ListTile(
        leading: const Icon(AppIcons.duplicate),
        title: Text(l10n.duplicateAction),
        onTap: () => _popThen(context, () {
          LayerActions.duplicate(parentRef, layer);
        }),
      ),
      // 6b — Flip. Whole-layer and decisive rather than tunable,
      // which is why it lives here and not on a strip.
      ListTile(
        leading: const Icon(AppIcons.flipHorizontal),
        title: Text(l10n.flipHorizontalAction),
        onTap: () => _popThen(context, () {
          LayerActions.flip(parentRef, layer, horizontal: true);
        }),
      ),
      ListTile(
        leading: const Icon(AppIcons.flipVertical),
        title: Text(l10n.flipVerticalAction),
        onTap: () => _popThen(context, () {
          LayerActions.flip(parentRef, layer, horizontal: false);
        }),
      ),
      // 7 — Reorder
      ListTile(
        enabled: canForward,
        leading: const Icon(AppIcons.bringForward),
        title: Text(l10n.bringForwardAction),
        onTap: !canForward
            ? null
            : () => _popThen(context, () {
                LayerActions.bringForward(parentRef, layer);
              }),
      ),
      ListTile(
        enabled: canBackward,
        leading: const Icon(AppIcons.sendBackward),
        title: Text(l10n.sendBackwardAction),
        onTap: !canBackward
            ? null
            : () => _popThen(context, () {
                LayerActions.sendBackward(parentRef, layer);
              }),
      ),
      // 8 — Lock/Unlock. ACTION-icon convention: the glyph previews
      // what the tap DOES (lock_open while locked = "tap to unlock"),
      // matching the row's action-verb label.
      ListTile(
        leading: Icon(layer.locked ? AppIcons.unlock : AppIcons.lock),
        title: Text(
          layer.locked ? l10n.unlockLayerAction : l10n.lockLayerAction,
        ),
        onTap: () => _popThen(context, () {
          LayerActions.toggleLock(parentRef, layer);
        }),
      ),
      // 9 — Resize behavior
      if (textLayer != null)
        ListTile(
          leading: Icon(textResizeModeIcon(textLayer.resizeMode)),
          title: Text(l10n.resizeBehaviorTitle),
          subtitle: Text(
            localizedTextResizeModeLabel(context, textLayer.resizeMode),
          ),
          trailing: const Icon(AppIcons.drillIn),
          onTap: () => _popThen(context, () async {
            final current = textLayer.resizeMode;
            final picked = await pickTextResizeMode(hostContext, current);
            if (picked != null && picked != current) {
              parentRef
                  .read(textToolControllerProvider.notifier)
                  .setResizeMode(picked);
            }
          }),
        ),
      if (shapeLayer != null)
        _ResizeModeToggleRow(
          initialIsScale:
              shapeLayer.effectiveResizeMode == ShapeResizeMode.scale,
          onChanged: (isScale) => parentRef
              .read(shapeToolControllerProvider.notifier)
              .setResizeMode(
                isScale ? ShapeResizeMode.scale : ShapeResizeMode.free,
              ),
        ),
      if (paintLayer != null)
        _ResizeModeToggleRow(
          initialIsScale: paintLayer.resizeMode == PaintResizeMode.scale,
          onChanged: (isScale) => parentRef
              .read(paintToolControllerProvider.notifier)
              .setResizeMode(
                isScale ? PaintResizeMode.scale : PaintResizeMode.free,
              ),
        ),
      // 10 — Text direction
      if (textLayer != null)
        ListTile(
          leading: Icon(textDirectionModeIcon(textLayer.textDirectionMode)),
          title: Text(l10n.textDirectionTitle),
          subtitle: Text(
            localizedTextDirectionModeLabel(
              context,
              textLayer.textDirectionMode,
            ),
          ),
          trailing: const Icon(AppIcons.drillIn),
          onTap: () => _popThen(context, () async {
            final current = textLayer.textDirectionMode;
            final picked = await pickTextDirectionMode(hostContext, current);
            if (picked != null && picked != current) {
              parentRef
                  .read(textToolControllerProvider.notifier)
                  .setTextDirectionMode(picked);
            }
          }),
        ),
      // 11 — Layers drawer link
      if (onOpenLayers != null)
        ListTile(
          leading: const Icon(AppIcons.layersPanel),
          title: Text(l10n.layersTooltip),
          trailing: const Icon(AppIcons.drillIn),
          onTap: () => _popThen(context, onOpenLayers!),
        ),
      // 12 — Delete (danger)
      const Divider(height: 1),
      ListTile(
        leading: Icon(AppIcons.delete, color: scheme.error),
        title: Text(l10n.deleteAction, style: TextStyle(color: scheme.error)),
        onTap: () => _deleteSingle(context),
      ),
    ];
  }

  /// The ONE canonical delete sequence (all entry points): resolve
  /// the protected/base-photo confirm while the sheet is still up,
  /// THEN dismiss the sheet, THEN execute.
  Future<void> _deleteSingle(BuildContext sheetContext) async {
    final removeBasePhotoLabel = sheetContext.l10n.removeBasePhotoCommand;
    final confirmed = await LayerActions.confirmDelete(
      sheetContext,
      parentRef,
      layer,
    );
    if (!sheetContext.mounted) return;
    Navigator.of(sheetContext).pop();
    if (!confirmed) return;
    LayerActions.deleteWithoutConfirm(
      parentRef,
      layer,
      removeBasePhotoLabel: removeBasePhotoLabel,
    );
  }

  // ─── multi-selection variant ─────────────────────────────────────

  List<Widget> _buildMultiRows(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final allLocked = selectedLayers.every((l) => l.locked);
    // Align/distribute drop ineligible (locked / non-movable) members,
    // so an all-locked batch — or a mixed one with a single movable
    // member — would open a panel whose every tile silently no-ops
    // (audit P2-7). Same grammar as the single-layer row: disabled at
    // the source, from the controller's own eligibility rule.
    final canAlign = AlignmentEligibility.of(
      parentRef.read(documentControllerProvider),
      selectedLayers,
    ).canAlign;

    return [
      // Count header — identifies the batch the rows below act on.
      ListTile(
        leading: const Icon(AppIcons.multiSelectCount),
        title: Text(l10n.multiSelectCount(selectedLayers.length)),
      ),
      // Align (canonical row 2)
      ListTile(
        enabled: canAlign,
        leading: const Icon(AppIcons.alignLeft),
        title: Text(l10n.alignAction),
        trailing: canAlign ? const Icon(AppIcons.drillIn) : null,
        onTap: !canAlign
            ? null
            : () => _popThen(context, () {
                parentRef
                    .read(contextToolbarControllerProvider.notifier)
                    .open(ContextToolPanel.align);
              }),
      ),
      // Batch duplicate (canonical row 6) — one composite, clones
      // become the new multi selection.
      ListTile(
        leading: const Icon(AppIcons.duplicate),
        title: Text(l10n.duplicateAction),
        onTap: () {
          final label = l10n.duplicateAction;
          _popThen(context, () {
            LayerActions.duplicateMany(parentRef, selectedLayers, label: label);
          });
        },
      ),
      // Batch flip — each layer about its OWN centre, one composite.
      ListTile(
        leading: const Icon(AppIcons.flipHorizontal),
        title: Text(l10n.flipHorizontalAction),
        onTap: () {
          final label = l10n.flipHorizontalAction;
          _popThen(context, () {
            LayerActions.flipMany(
              parentRef,
              selectedLayers,
              horizontal: true,
              label: label,
            );
          });
        },
      ),
      ListTile(
        leading: const Icon(AppIcons.flipVertical),
        title: Text(l10n.flipVerticalAction),
        onTap: () {
          final label = l10n.flipVerticalAction;
          _popThen(context, () {
            LayerActions.flipMany(
              parentRef,
              selectedLayers,
              horizontal: false,
              label: label,
            );
          });
        },
      ),
      // Batch lock/unlock (canonical row 8, ACTION icon) — one
      // composite; unlocks only when EVERY member is locked.
      ListTile(
        leading: Icon(allLocked ? AppIcons.unlock : AppIcons.lock),
        title: Text(allLocked ? l10n.unlockLayerAction : l10n.lockLayerAction),
        onTap: () {
          final label = allLocked
              ? l10n.unlockLayerAction
              : l10n.lockLayerAction;
          _popThen(context, () {
            LayerActions.setLockedMany(
              parentRef,
              selectedLayers,
              locked: !allLocked,
              label: label,
            );
          });
        },
      ),
      // Layers drawer link (canonical row 11)
      if (onOpenLayers != null)
        ListTile(
          leading: const Icon(AppIcons.layersPanel),
          title: Text(l10n.layersTooltip),
          trailing: const Icon(AppIcons.drillIn),
          onTap: () => _popThen(context, onOpenLayers!),
        ),
      // Batch delete (canonical row 12) — one composite, one undo
      // entry. The protected base photo is never part of a batch
      // (see LayerActions.deleteMany), so no confirm is required.
      const Divider(height: 1),
      ListTile(
        leading: Icon(AppIcons.delete, color: scheme.error),
        title: Text(l10n.deleteAction, style: TextStyle(color: scheme.error)),
        onTap: () {
          final label = l10n.deleteAction;
          _popThen(context, () {
            LayerActions.deleteMany(parentRef, selectedLayers, label: label);
          });
        },
      ),
    ];
  }
}

/// Shape/paint resize-behavior row: an inline Scale ↔ Free toggle
/// mirroring the floating-bar pill (these types have exactly two
/// modes, so a picker detour would be ceremony). Taps stay inline —
/// like the B/I/U row — so the user can flip and immediately see the
/// subtitle update. Local flag state, seeded at open time: the modal
/// sheet can mount outside the editor `ProviderScope`, so provider
/// watching here is not reliable; writes go through the owning
/// controller via the parent ref.
class _ResizeModeToggleRow extends StatefulWidget {
  const _ResizeModeToggleRow({
    required this.initialIsScale,
    required this.onChanged,
  });

  final bool initialIsScale;
  final ValueChanged<bool> onChanged;

  @override
  State<_ResizeModeToggleRow> createState() => _ResizeModeToggleRowState();
}

class _ResizeModeToggleRowState extends State<_ResizeModeToggleRow> {
  late bool _isScale = widget.initialIsScale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListTile(
      leading: Icon(_isScale ? AppIcons.canvasSize : AppIcons.freeRegion),
      title: Text(l10n.resizeBehaviorTitle),
      subtitle: Text(_isScale ? l10n.scaleLabel : l10n.freeLabel),
      onTap: () {
        setState(() => _isScale = !_isScale);
        widget.onChanged(_isScale);
      },
    );
  }
}
