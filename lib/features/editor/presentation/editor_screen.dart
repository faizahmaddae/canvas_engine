import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' as picker;
import 'package:uuid/uuid.dart';

import '../../../core/utils/haptics.dart';
import '../../../core/utils/user_error.dart';
import '../../../l10n/l10n.dart';
import '../application/autosave_controller.dart';
import '../application/context_toolbar_controller.dart';
import '../application/document_controller.dart';
import '../application/image_import_service.dart';
import '../application/live_overlay_controller.dart';
import '../application/editor_lifecycle.dart';
import '../application/editor_session.dart';
import '../application/mask_edit_controller.dart';
import '../application/project_save_service.dart';
import '../application/selection_controller.dart';
import '../application/viewport_controller.dart';
import '../canvas/application/canvas_tool_controller.dart';
import '../canvas/presentation/canvas_panel_body.dart';
import '../crop/application/crop_controller.dart';
import '../crop/presentation/crop_mode_overlay.dart';
import '../engine/commands/transform_commands.dart';
import '../engine/commands/shape_commands.dart';
import '../engine/core/canvas_sizing.dart';
import '../engine/core/editor_document.dart';
import '../engine/core/editor_layer.dart';
import '../engine/core/layer_transform.dart';
import '../engine/core/selection_state.dart';
import '../engine/modules/image/image_layer.dart';
import '../engine/modules/shape/shape_defaults.dart';
import '../engine/modules/shape/shape_layer.dart';
import '../engine/modules/text/text_layer.dart';
import '../image/application/image_target_resolver.dart';
import '../image/application/image_tool_controller.dart';
import '../image/presentation/image_border_body.dart';
import '../image/presentation/image_filters_body.dart';
import '../image/presentation/image_mode_toolbar.dart';
import '../image/presentation/image_adjust_body.dart';
import '../image/presentation/image_effects_body.dart';
import '../image/presentation/image_style_body.dart';
import 'sticker_picker_sheet.dart';
import '../image/presentation/image_shadow_body.dart';
import '../image/presentation/image_shape_body.dart';
import '../paint/application/paint_tool_controller.dart';
import '../paint/domain/paint_tool_type.dart';
import '../paint/presentation/paint_mode_toolbar.dart';
import '../shape/application/shape_tool_controller.dart';
import '../shape/presentation/shape_border_body.dart';
import '../shape/presentation/shape_shadow_body.dart';
import '../shape/presentation/shape_mode_toolbar.dart';
import '../shape/presentation/shape_style_body.dart';
import 'shape_picker_sheet.dart';
import '../sticker/application/sticker_tool_controller.dart';
import '../sticker/presentation/sticker_mode_toolbar.dart';
import '../text/application/text_tool_controller.dart';
import '../text/presentation/add_text_composer_state.dart';
import '../text/presentation/text_input_flow_sheet.dart';
import '../text/presentation/text_mode_toolbar.dart';
import '../toolbar/presentation/mode_done_button.dart';
import 'widgets/editor_canvas.dart';
import 'widgets/editor_tool_dock.dart';
import '../toolbar/domain/toolbar_slot.dart';
import 'widgets/context_tool_panel.dart';
import 'widgets/editor_toolbar.dart';
import 'widgets/export_action_sheet.dart';
import 'widgets/layers_panel.dart';
import 'widgets/multi_select_mode_toolbar.dart';
import 'widgets/new_document_dialog.dart';

const _uuid = Uuid();

class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final selection = ref.watch(selectionControllerProvider);
    // Subscribe to commit ticks only. The screen-level rebuild is
    // a defensive lifecycle pump — it must fire when the document
    // truly changes (execute / undo / redo) but stay silent during
    // mid-gesture overlay previews. Reading committed-doc directly
    // worked only because nothing routes through liveReplace today;
    // commit-version makes the contract explicit so the next
    // accidental in-place mutation can't regress this.
    ref.watch(documentCommitVersionProvider);
    // Selection-change seam: when the user picks a different layer
    // (or deselects to empty), collapse every object-tool's
    // currently-open sub-panel (Image/Shape/Sticker `openSlot`).
    // The tool controllers are global non-autoDispose Notifiers,
    // so without this their `openSlot` would silently re-mount the
    // last-used panel (e.g. Image Border) on the next reselection
    // — even when the user dismissed it implicitly by moving on
    // to another layer. Mirrors `dismissActiveEditing`'s contract
    // (which fires on tap-on-empty); this fires on tap-on-layer
    // and on programmatic selection changes (layers panel, etc.).
    // Saved layer styles are NOT touched.
    ref.listen<SelectionState>(selectionControllerProvider, (prev, next) {
      if (prev?.selectedId == next.selectedId) return;
      closeObjectSubPanels(ref);
    });
    // Keep the autosave controller alive for the lifetime of the
    // editor screen. It listens to `documentCommitVersionProvider`
    // and writes the active project to disk on a debounce — but
    // only when the session has a `projectId` (i.e. the user has
    // saved at least once). See `AutosaveController` for the full
    // contract.
    ref.watch(autosaveControllerProvider);
    // Crop Mode owns the entire screen — when active we suppress
    // the editor's normal AppBar, floating rails and bottom dock
    // so the centralised [CropModeOverlay] feels like a dedicated
    // full-screen mode (Instagram / Canva style) instead of a
    // sheet floating over the editor chrome.
    final cropActive = ref.watch(
      cropControllerProvider.select((s) => s.active),
    );
    // Mask-edit mode hides the same chrome: its bottom strip is the
    // only editing surface while the user shapes the region, and the
    // undo rail must hide because a mid-draft undo would mutate the
    // document under the mode (the doc listener would then cancel
    // the session — technically safe, but jarring).
    final maskEditActive = ref.watch(
      maskEditControllerProvider.select((s) => s.active),
    );

    return _AutosaveLifecycleScope(
      child: PopScope(
        canPop: !cropActive && !maskEditActive,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && maskEditActive) {
            // Back = Cancel, restoring the pre-mode toolbar context.
            ref
                .read(maskEditControllerProvider.notifier)
                .cancel(restoreSelection: true);
            return;
          }
          if (!didPop && cropActive) {
            ref.read(cropControllerProvider.notifier).cancelCrop();
            return;
          }
          if (didPop) {
            // User is leaving the editor — flush any pending
            // debounced autosave so the last <=1.5 s of edits
            // survive the navigation pop. Fire-and-forget; the
            // widget tree is already on its way out.
            // The dispose() in [_AutosaveLifecycleScopeState] also
            // flushes as a final safety net, but doing it here is
            // earlier and lets the write race with route teardown
            // rather than after it.
            unawaited(
              ref
                  .read(autosaveControllerProvider.notifier)
                  .flushNow(sessionEnding: true),
            );
          }
        },
        child: Scaffold(
          appBar: cropActive || maskEditActive
              ? null
              : AppBar(
                  title: _DocumentTitle(),
                  actions: [
                    Builder(
                      builder: (ctx) => IconButton(
                        tooltip: l10n.editorSaveProject,
                        onPressed: () => _saveProject(ctx, ref),
                        icon: const Icon(Icons.save_outlined),
                      ),
                    ),
                    Builder(
                      builder: (ctx) => IconButton(
                        tooltip: l10n.editorExport,
                        onPressed: () => ExportActionSheet.open(ctx),
                        icon: const Icon(Icons.ios_share_outlined),
                      ),
                    ),
                    Builder(
                      builder: (ctx) => IconButton(
                        tooltip: l10n.layersTooltip,
                        onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                        icon: const Icon(Icons.layers_outlined),
                      ),
                    ),
                    Builder(
                      builder: (ctx) => PopupMenuButton<_OverflowAction>(
                        tooltip: l10n.moreTooltip,
                        icon: const Icon(Icons.more_vert),
                        onSelected: (action) =>
                            _handleOverflowAction(ctx, ref, action),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: _OverflowAction.save,
                            child: ListTile(
                              leading: const Icon(Icons.bookmark_add_outlined),
                              title: Text(l10n.editorSaveProject),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          PopupMenuItem(
                            value: _OverflowAction.export,
                            child: ListTile(
                              leading: const Icon(Icons.ios_share_outlined),
                              title: Text(l10n.editorExport),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: _OverflowAction.fit,
                            child: ListTile(
                              leading: const Icon(Icons.fit_screen_outlined),
                              title: Text(l10n.editorFitToScreen),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          PopupMenuItem(
                            value: _OverflowAction.newDoc,
                            child: ListTile(
                              leading: const Icon(Icons.note_add_outlined),
                              title: Text(l10n.editorNewDocument),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
          endDrawer: const LayersPanel(),
          body: Stack(
            children: [
              const EditorCanvas(),
              // Floating undo/redo rail anchored top-left of the
              // canvas — keeps the AppBar slim while giving the two
              // most-used commands a permanent, thumb-reachable home
              // that mirrors the Done pill's top-right anchor for
              // visual symmetry. Hidden in Crop Mode.
              if (!cropActive && !maskEditActive)
                const Positioned(
                  top: 8,
                  left: 8,
                  child: SafeArea(child: _UndoRedoRail()),
                ),
              // Always-visible exit pill anchored top-right of the
              // canvas. Shows whenever a tool mode (paint / text) is
              // active so the user has a permanent, discoverable way
              // out — replaces reliance on the invisible
              // canvas-tap-to-deselect gesture for new users while
              // keeping that gesture as the pro shortcut. Hidden in
              // Crop Mode.
              if (!cropActive && !maskEditActive)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: SafeArea(child: _ModeExitPill()),
                ),
              // Centralised Crop Mode overlay — full-screen, owns the
              // entire scaffold body when active. Mounted **last** so
              // it paints above any residual floating rails / chrome.
              const Positioned.fill(child: CropModeOverlay()),
            ],
          ),
          bottomNavigationBar: Builder(
            builder: (dockContext) {
              // Crop Mode owns the screen — hide the regular dock so
              // the Crop bottom bar is the only chrome the user sees.
              final cropActive = ref.watch(
                cropControllerProvider.select((s) => s.active),
              );
              if (cropActive) return const SizedBox.shrink();
              // Mask-edit: its bottom strip replaces the dock.
              final maskActive = ref.watch(
                maskEditControllerProvider.select((s) => s.active),
              );
              if (maskActive) return const SizedBox.shrink();
              final paintOpen = ref.watch(
                paintToolControllerProvider.select((s) => s.panelOpen),
              );
              final textOpen = ref.watch(
                textToolControllerProvider.select((s) => s.panelOpen),
              );
              final paintOpenSlot = ref.watch(
                paintToolControllerProvider.select((s) => s.openSlot),
              );
              final textOpenSheet = ref.watch(
                textToolControllerProvider.select((s) => s.openSheet),
              );
              final contextPanel = ref.watch(contextToolbarControllerProvider);
              final selectedLayersForActions = selection.hasSelection
                  ? _selectedLayersForActions(ref, selection)
                  : const <EditorLayer>[];
              final multiSelected = selectedLayersForActions.length > 1;
              final selectedTextLayer = _selectedTextLayer(ref);
              final textSelected = selectedTextLayer != null && !multiSelected;
              final selectedStickerLayer = _selectedStickerLayer(ref);
              final stickerSelected =
                  selectedStickerLayer != null &&
                  !paintOpen &&
                  !textOpen &&
                  !textSelected &&
                  !multiSelected;
              final selectedImageLayer = _selectedImageLayer(ref);
              final imageSelected =
                  selectedImageLayer != null &&
                  !paintOpen &&
                  !textOpen &&
                  !textSelected &&
                  !stickerSelected &&
                  !multiSelected;
              final selectedShapeLayer = _selectedShapeLayer(ref);
              final shapeSelected =
                  selectedShapeLayer != null &&
                  !paintOpen &&
                  !textOpen &&
                  !textSelected &&
                  !stickerSelected &&
                  !imageSelected &&
                  !multiSelected;
              final modeKey = paintOpen
                  ? 'paint'
                  : (textOpen || textSelected)
                  ? 'text'
                  : multiSelected
                  ? 'multi'
                  : stickerSelected
                  ? 'sticker'
                  : imageSelected
                  ? 'image'
                  : shapeSelected
                  ? 'shape'
                  : 'main';

              // Resolve the dock's `expanded` slot. Text mode renders
              // its tool sheets here (Canva-style: canvas reflows above
              // the dock instead of being overlaid). Paint still uses
              // its small inline expansion row.
              Widget? expanded;
              Object? expandedKey;
              if (contextPanel != null && selectedLayersForActions.isNotEmpty) {
                expanded = ContextToolPanelBody(
                  panel: contextPanel,
                  layers: selectedLayersForActions,
                );
                expandedKey =
                    'context:${contextPanel.name}:'
                    '${selectedLayersForActions.map((l) => l.id).join(',')}';
              } else if ((textOpen || textSelected) &&
                  textSelected &&
                  textOpenSheet != null) {
                expanded = const TextModeSheetPanel();
                expandedKey = 'text-sheet:$textOpenSheet';
              } else if (paintOpen && paintOpenSlot != null) {
                expanded = const PaintModeInlineExpansion();
                expandedKey = 'paint-inline:$paintOpenSlot';
              } else if (stickerSelected) {
                final stickerOpenSlot = ref.watch(
                  stickerToolControllerProvider.select((s) => s.openSlot),
                );
                switch (stickerOpenSlot) {
                  case StickerToolSlot.size:
                    expanded = StickerSizeBody(layer: selectedStickerLayer);
                    expandedKey = 'sticker-size:${selectedStickerLayer.id}';
                  case StickerToolSlot.replace:
                    expanded = StickerReplaceBody(layer: selectedStickerLayer);
                    expandedKey = 'sticker-replace:${selectedStickerLayer.id}';
                  case StickerToolSlot.style:
                    expanded = StickerStyleBody(layer: selectedStickerLayer);
                    expandedKey = 'sticker-style:${selectedStickerLayer.id}';
                  case null:
                    break;
                }
              } else if (imageSelected) {
                final imageOpenSlot = ref.watch(
                  imageToolControllerProvider.select((s) => s.openSlot),
                );
                switch (imageOpenSlot) {
                  case ImageToolSlot.shape:
                    expanded = ImageShapeBody(layer: selectedImageLayer);
                    expandedKey = 'image-shape:${selectedImageLayer.id}';
                  case ImageToolSlot.style:
                    expanded = ImageStyleBody(layer: selectedImageLayer);
                    expandedKey = 'image-style:${selectedImageLayer.id}';
                  case ImageToolSlot.border:
                    expanded = ImageBorderBody(layer: selectedImageLayer);
                    expandedKey = 'image-border:${selectedImageLayer.id}';
                  case ImageToolSlot.shadow:
                    expanded = ImageShadowBody(layer: selectedImageLayer);
                    expandedKey = 'image-shadow:${selectedImageLayer.id}';
                  case ImageToolSlot.adjust:
                    expanded = ImageAdjustBody(layer: selectedImageLayer);
                    expandedKey = 'image-adjust:${selectedImageLayer.id}';
                  case ImageToolSlot.effects:
                    expanded = ImageEffectsBody(layer: selectedImageLayer);
                    expandedKey = 'image-effects:${selectedImageLayer.id}';
                  case ImageToolSlot.filters:
                    expanded = ImageFiltersBody(layer: selectedImageLayer);
                    expandedKey = 'image-filters:${selectedImageLayer.id}';
                  case ImageToolSlot.crop:
                  case ImageToolSlot.replace:
                  case null:
                    // 'crop' opens the full-screen CropModeOverlay;
                    // 'replace' is a one-shot picker. Neither owns an
                    // inline dock body.
                    break;
                }
              } else if (shapeSelected) {
                final shapeOpenSlot = ref.watch(
                  shapeToolControllerProvider.select((s) => s.openSlot),
                );
                switch (shapeOpenSlot) {
                  case ShapeToolSlot.style:
                    expanded = ShapeStyleBody(layer: selectedShapeLayer);
                    expandedKey = 'shape-style:${selectedShapeLayer.id}';
                  case ShapeToolSlot.border:
                    expanded = ShapeBorderBody(layer: selectedShapeLayer);
                    expandedKey = 'shape-border:${selectedShapeLayer.id}';
                  case ShapeToolSlot.shadow:
                    expanded = ShapeShadowBody(layer: selectedShapeLayer);
                    expandedKey = 'shape-shadow:${selectedShapeLayer.id}';
                  case ShapeToolSlot.replace:
                  case null:
                    break;
                }
              } else {
                // No layer selected. The Canvas tool is the only entry
                // that opens a panel from this state — it edits the
                // document itself, not a layer.
                final canvasOpen = ref.watch(
                  canvasToolControllerProvider.select((s) => s.panelOpen),
                );
                if (canvasOpen) {
                  expanded = const CanvasPanelBody();
                  expandedKey = 'canvas-panel';
                }
              }

              return EditorToolDock(
                modeKey: modeKey,
                expanded: expanded,
                expandedKey: expandedKey,
                child: paintOpen
                    ? const PaintModeToolbar()
                    : (textOpen || textSelected)
                    ? const TextModeToolbar()
                    : multiSelected
                    ? MultiSelectModeToolbar(
                        layers: selectedLayersForActions,
                        onOpenLayers: () =>
                            Scaffold.of(dockContext).openEndDrawer(),
                      )
                    : stickerSelected
                    ? StickerModeToolbar(layer: selectedStickerLayer)
                    : imageSelected
                    ? ImageModeToolbar(layer: selectedImageLayer)
                    : shapeSelected
                    ? ShapeModeToolbar(
                        layer: selectedShapeLayer,
                        onReplaceTap: () => _openReplaceShapePicker(
                          context,
                          ref,
                          selectedShapeLayer,
                        ),
                      )
                    : EditorToolbar(
                        activeId: _activeToolId(ref),
                        items: _buildToolbarItems(context, ref),
                      ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Build the main toolbar tile list.
  ///
  /// Items are organised into three [SlotTier] groups so the strip
  /// reads as a clear "what do you want to do?" list, with a hairline
  /// divider between groups (rendered automatically by [SlotStrip]):
  ///
  ///   tier1 — **Add** something to the canvas
  ///     Image · Text · Sticker · Shape · Paint
  ///
  ///   tier2 — **Edit the photo** (operate on an existing image
  ///     layer; resolves the target via [resolveImageTarget] so the
  ///     user doesn't have to select the photo first)
  ///     Crop · Adjust · Filters
  ///
  ///   tier3 — **Document**
  ///     Canvas (size / background)
  ///
  /// Order is the same on every project kind — design and photo
  /// projects both see the full set so nothing is hidden, but the
  /// grouping makes the photo flow obvious to a user who imported
  /// a photo and the design flow obvious to one who started blank.
  List<ToolbarItem> _buildToolbarItems(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return [
      // ── tier 1 — Add ────────────────────────────────────────────
      ToolbarItem(
        id: 'image',
        icon: Icons.add_photo_alternate_outlined,
        label: l10n.photoTool,
        onTap: () => _addImage(context, ref),
      ),
      ToolbarItem(
        id: 'text',
        icon: Icons.text_fields_rounded,
        label: l10n.textTool,
        onTap: () => _startTextInputFlow(context, ref),
      ),
      ToolbarItem(
        id: 'sticker',
        icon: Icons.emoji_emotions_outlined,
        label: l10n.stickerTool,
        onTap: () => _addSticker(context, ref),
      ),
      ToolbarItem(
        id: 'shape',
        icon: Icons.category_outlined,
        label: l10n.shapeTool,
        onTap: () => _openShapePicker(context, ref),
      ),
      ToolbarItem(
        id: 'paint',
        icon: Icons.brush_outlined,
        label: l10n.drawTool,
        onTap: () {
          final ctrl = ref.read(paintToolControllerProvider.notifier);
          final session = ref.read(paintToolControllerProvider);
          ref.read(textToolControllerProvider.notifier).closePanel();
          if (session.panelOpen) {
            ctrl.closePanel();
          } else if (session.activeTool == null) {
            ctrl.selectTool(PaintToolType.freestyle);
          } else {
            ctrl.openPanel();
          }
        },
      ),
      // ── tier 2 — Edit the photo ─────────────────────────────────
      ToolbarItem(
        id: 'crop',
        icon: Icons.crop_rotate_rounded,
        label: l10n.cropTool,
        tier: SlotTier.tier2,
        onTap: () => _openCrop(context, ref),
      ),
      ToolbarItem(
        id: 'adjust',
        icon: Icons.tune_rounded,
        label: l10n.adjustTool,
        tier: SlotTier.tier2,
        onTap: () => _openAdjust(context, ref),
      ),
      ToolbarItem(
        id: 'filters',
        icon: Icons.auto_fix_high_outlined,
        label: l10n.filtersTool,
        tier: SlotTier.tier2,
        onTap: () => _openFilters(context, ref),
      ),
      // ── tier 3 — Document ───────────────────────────────────────
      ToolbarItem(
        id: 'canvas',
        icon: Icons.aspect_ratio_rounded,
        label: l10n.canvasTool,
        tier: SlotTier.tier3,
        onTap: () => _openCanvas(ref),
      ),
    ];
  }

  List<EditorLayer> _selectedLayersForActions(
    WidgetRef ref,
    SelectionState selection,
  ) {
    final doc = ref.watch(documentControllerProvider);
    final out = <EditorLayer>[];
    for (final id in selection.selectedIds) {
      final layer = doc.layerById(id);
      if (layer == null || doc.isProtectedBasePhoto(id)) continue;
      out.add(layer);
    }
    return out;
  }

  TextLayer? _selectedTextLayer(WidgetRef ref) {
    final selection = ref.watch(selectionControllerProvider);
    if (!selection.hasSelection) return null;
    final layer = ref
        .watch(renderedDocumentProvider)
        .layerById(selection.selectedId!);
    // Emoji-sticker text layers are visually text but conceptually
    // stickers — routing them to the Text toolbar would expose
    // font/color/layout controls that don't apply to a single
    // emoji glyph. Treat them as non-text for selection purposes
    // so the dock falls back to the default toolbar; transform
    // handles still come from the layer's own capabilities.
    if (layer is TextLayer && !layer.isSticker) return layer;
    return null;
  }

  /// Selected layer when it's an [ImageLayer], else `null`. Used to
  /// swap in [ImageModeToolbar] for image-specific sub-tools.
  ImageLayer? _selectedImageLayer(WidgetRef ref) {
    final selection = ref.watch(selectionControllerProvider);
    if (!selection.hasSelection) return null;
    final layer = ref
        .watch(renderedDocumentProvider)
        .layerById(selection.selectedId!);
    return layer is ImageLayer ? layer : null;
  }

  /// Selected layer when it's a [ShapeLayer], else `null`. Used to
  /// swap in [ShapeModeToolbar] for shape-specific sub-tools.
  ShapeLayer? _selectedShapeLayer(WidgetRef ref) {
    final selection = ref.watch(selectionControllerProvider);
    if (!selection.hasSelection) return null;
    final layer = ref
        .watch(renderedDocumentProvider)
        .layerById(selection.selectedId!);
    return layer is ShapeLayer ? layer : null;
  }

  /// Selected layer when it's an emoji-sticker [TextLayer], else
  /// `null`. Drives the Sticker mode toolbar; normal text layers are
  /// excluded so they continue to route to [TextModeToolbar].
  TextLayer? _selectedStickerLayer(WidgetRef ref) {
    final selection = ref.watch(selectionControllerProvider);
    if (!selection.hasSelection) return null;
    final layer = ref
        .watch(renderedDocumentProvider)
        .layerById(selection.selectedId!);
    return (layer is TextLayer && layer.isSticker) ? layer : null;
  }

  Future<void> _startTextInputFlow(BuildContext context, WidgetRef ref) async {
    ref.read(paintToolControllerProvider.notifier).closePanel();
    final textCtrl = ref.read(textToolControllerProvider.notifier);
    // Stage an empty text layer at the canvas center so the user sees
    // the bounding box appear as soon as the sheet opens — typing then
    // streams content into that staged layer in real time. Cancel /
    // empty input removes it; non-empty input commits a single
    // AddLayerCommand on apply.
    textCtrl.beginAddText();
    // Flip the composer-open flag so EditorCanvas hides selection
    // handles, transform HUD, floating contextual toolbars and the
    // quick-action pill while the sheet is up. The staged layer is
    // still rendered (it shows the user where their text will land),
    // but every piece of edit-chrome that competes with the input is
    // suppressed. Always reset in `finally` so a thrown error or
    // unexpected pop never leaves chrome muted.
    final composerFlag = ref.read(addTextComposerOpenProvider.notifier);
    composerFlag.setOpen(true);
    String? content;
    try {
      content = await showTextInputFlowSheet(
        context,
        title: context.l10n.addTextTitle,
        confirmLabel: context.l10n.addAction,
        onLiveChange: textCtrl.previewContent,
      );
    } finally {
      composerFlag.setOpen(false);
    }
    if (content == null) {
      textCtrl.cancelLiveEdit();
      return;
    }
    textCtrl.commitLiveEdit(content);
    if (textCtrl.selectedTextLayer() != null) {
      textCtrl.openPanel();
    }
  }

  Offset _centerInDoc(WidgetRef ref, Size size) {
    final doc = ref.read(documentControllerProvider);
    return Offset(
      doc.width / 2 - size.width / 2,
      doc.height / 2 - size.height / 2,
    );
  }

  Future<void> _addImage(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final source = await pickImageSource(context);
    if (source == null || !context.mounted) return;

    final pick = picker.ImagePicker();
    final picker.XFile? picked;
    try {
      picked = await pick.pickImage(source: source, imageQuality: 92);
    } catch (e, st) {
      debugLogError('editor/_addImage/pickImage', e, st);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userMessageFor(
              e,
              fallback: l10n.couldntOpenPhoto,
              permissionDeniedMessage: l10n.allowPhotoAccessSettings,
              genericMessage: l10n.somethingWentWrong,
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (picked == null || !context.mounted) return;

    final Size dims;
    try {
      dims = await resolveImageSize(File(picked.path));
    } catch (e, st) {
      debugLogError('editor/_addImage/_resolveImageSize', e, st);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userMessageFor(
              e,
              fallback: l10n.couldntOpenPhoto,
              permissionDeniedMessage: l10n.allowPhotoAccessSettings,
              genericMessage: l10n.somethingWentWrong,
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Copy out of the temp picker dir into app-documents so the path
    // remains valid across app restarts and project reloads.
    final stablePath = await persistPickedImage(picked.path);
    if (!context.mounted) return;

    final doc = ref.read(documentControllerProvider);
    final fitted = _fitInsideCanvas(dims, doc.width, doc.height);
    final id = _uuid.v4();
    // In photo-mode projects, the very first imported image becomes
    // the locked base photo (matches the home-screen import flow).
    // In design mode, no locking -- we still claim the base-photo
    // pointer if vacant so Crop / Filters / Adjust resolve cleanly,
    // but the layer behaves like any other image.
    final shouldClaimBase = doc.basePhotoLayerId == null;
    final lockAsBasePhoto =
        shouldClaimBase && doc.projectKind == ProjectKind.photo;
    final layer = ImageLayer(
      id: id,
      transform: LayerTransform(
        position: _centerInDoc(ref, fitted),
        size: fitted,
      ),
      source: ImageSource.file(stablePath),
      locked: lockAsBasePhoto,
    );
    if (shouldClaimBase) {
      ref
          .read(documentControllerProvider.notifier)
          .execute(
            CompositeCommand([
              AddLayerCommand(layer),
              SetBasePhotoCommand(id),
            ], labelOverride: l10n.importPhotoCommand),
          );
    } else {
      ref
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(layer));
    }
    ref.read(selectionControllerProvider.notifier).select(id);
  }

  /// Scale [natural] uniformly so it fits inside ~80% of the canvas
  /// while preserving aspect ratio. Avoids dropping a huge import
  /// off-canvas; never upscales beyond the image's natural size.
  Size _fitInsideCanvas(Size natural, double canvasW, double canvasH) {
    const fillRatio = 0.8;
    final maxW = canvasW * fillRatio;
    final maxH = canvasH * fillRatio;
    final scaleW = maxW / natural.width;
    final scaleH = maxH / natural.height;
    final scale = (scaleW < scaleH ? scaleW : scaleH).clamp(0.0, 1.0);
    return Size(natural.width * scale, natural.height * scale);
  }

  void _addShape(BuildContext context, WidgetRef ref, ShapeKind kind) {
    final id = _uuid.v4();
    final liveDoc = ref.read(documentControllerProvider);
    // Author-time defaults are tuned against the 1080-px reference
    // canvas; CanvasSizing rescales them so the shape reads at the
    // same visual proportion on tiny sticker canvases and on huge
    // photo / poster canvases (e.g. 6720×4480) alike.
    final size = CanvasSizing.scaleSize(_defaultShapeSize(kind), liveDoc);
    // Smart default: choose a fill that is visible against the
    // current canvas background colour. Reads the live document
    // value so dropping a shape onto a dark canvas yields a light
    // fill (and vice versa) automatically. When the canvas is in
    // transparent mode the editor draws a light checkerboard, so
    // treat the backdrop as light and pick a dark fill.
    final canvasBackground =
        liveDoc.backgroundMode == CanvasBackgroundMode.transparent
        ? kDefaultCanvasBackground
        : liveDoc.backgroundColor;
    final layer = ShapeLayer(
      id: id,
      transform: LayerTransform(position: _centerInDoc(ref, size), size: size),
      kind: kind,
      fillColor: ShapeDefaults.fillColorForCanvas(canvasBackground, kind),
      // RoundedRectangle is a picker shortcut for "rectangle that
      // already has a sensible radius" — prime the layer so the
      // shape lands looking rounded without the user opening Style.
      // Reference 28-px radius is canvas-rescaled so the corner
      // reads at the same visual proportion on tiny stickers and
      // on huge poster canvases (mirrors the size scaling above).
      cornerRadius: kind == ShapeKind.roundedRectangle
          ? CanvasSizing.scaleDimension(28, liveDoc)
          : 0,
      // Stroked kinds need a non-zero default thickness or they
      // would render at the painter's fallback width — store the
      // chosen value so Border chips reflect reality. Same
      // canvas-aware rescaling so a freshly-dropped line is
      // legible on every canvas size.
      strokeWidth: isStrokedShapeKind(kind)
          ? CanvasSizing.scaleDimension(6, liveDoc)
          : 0,
    );
    ref
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(layer));
    ref.read(selectionControllerProvider.notifier).select(id);
    // No auto-open: the shape is fully formed on insert, so the user
    // typically wants to position / resize first. The Shape toolbar
    // remains visible and the user can tap Style whenever they like.
  }

  /// Default insertion size per kind. Filled shapes get a square
  /// 220x220 footprint; horizontal stroked line/arrow get a wide
  /// 280x80 strip; vertical arrows get the transposed 80x280
  /// footprint so the shaft is the long axis from the moment it
  /// lands on the canvas.
  Size _defaultShapeSize(ShapeKind kind) {
    switch (kind) {
      case ShapeKind.line:
      case ShapeKind.arrow:
      case ShapeKind.arrowLeft:
        return const Size(280, 80);
      case ShapeKind.arrowUp:
      case ShapeKind.arrowDown:
        return const Size(80, 280);
      case ShapeKind.speechBubble:
      case ShapeKind.quoteBubble:
        // Bubbles read better as a wide rectangle so the body has
        // room for text the user is likely to add on top.
        return const Size(280, 200);
      case ShapeKind.rectangle:
      case ShapeKind.roundedRectangle:
      case ShapeKind.oval:
      case ShapeKind.circle:
      case ShapeKind.triangle:
      case ShapeKind.diamond:
      case ShapeKind.hexagon:
      case ShapeKind.star:
      case ShapeKind.heart:
      case ShapeKind.plus:
      case ShapeKind.check:
      case ShapeKind.cross:
        return const Size(220, 220);
    }
  }

  /// Phase 1 sticker insertion: open the picker, drop the chosen
  /// emoji onto the canvas as a [TextLayer]. Reusing TextLayer
  /// (rather than introducing a StickerLayer) gives us free
  /// move/scale/rotate handles, undo/redo, JSON, and the text
  /// toolbar — at zero cost. Sized as a square so corner-drag
  /// uniform scale (the default [TextResizeMode.scaleText])
  /// behaves like users expect from an icon-shaped object.
  Future<void> _addSticker(BuildContext context, WidgetRef ref) async {
    EditorHaptics.tap();
    // Make sure the text panel isn't open behind the picker — the
    // sticker is visually a TextLayer but conceptually a separate
    // tool, and surfacing the text editor right after insert would
    // look like a bug.
    ref.read(textToolControllerProvider.notifier).closePanel();
    ref.read(paintToolControllerProvider.notifier).closePanel();
    final glyph = await showStickerPickerSheet(context);
    if (glyph == null || !context.mounted) return;
    final id = _uuid.v4();
    // Author-time default is a 240-px square (designed against the
    // 1080 reference). CanvasSizing rescales so the sticker reads
    // at the same visual proportion on every canvas size. The
    // glyph itself uses `BoxFit.contain`-style layout via the
    // text painter, so font-size doesn't need to be rescaled
    // here — the box size carries the visual weight.
    final liveDoc = ref.read(documentControllerProvider);
    final size = CanvasSizing.scaleSize(const Size(240, 240), liveDoc);
    final layer = TextLayer(
      id: id,
      transform: LayerTransform(position: _centerInDoc(ref, size), size: size),
      content: glyph,
      kind: TextLayerKind.emojiSticker,
      style: const TextStyleSpec(
        fontSize: 200,
        // Emoji glyphs render in their own colour palette; the
        // foreground colour only matters for non-emoji fallback,
        // so default white is fine.
        color: Colors.white,
      ),
    );
    ref
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(layer));
    ref.read(selectionControllerProvider.notifier).select(id);
  }

  String? _activeToolId(WidgetRef ref) {
    final paintOpen = ref.watch(
      paintToolControllerProvider.select((s) => s.panelOpen),
    );
    if (paintOpen) return 'paint';
    final textOpen = ref.watch(
      textToolControllerProvider.select((s) => s.panelOpen),
    );
    if (textOpen) return 'text';

    final selection = ref.watch(selectionControllerProvider);
    if (!selection.hasSelection) return null;
    final layer = ref
        .watch(renderedDocumentProvider)
        .layerById(selection.selectedId!);
    // Emoji-sticker text layers route to the Sticker tab so the
    // Text mode pill doesn't light up for what the user perceives
    // as a sticker. Normal text continues to map to the Text tab.
    if (layer is TextLayer) return layer.isSticker ? 'sticker' : 'text';
    if (layer is ShapeLayer) return 'shape';
    if (layer is ImageLayer) return 'image';
    return null;
  }

  Future<void> _openShapePicker(BuildContext context, WidgetRef ref) async {
    final kind = await pickShapeKind(context);
    if (kind == null || !context.mounted) return;
    _addShape(context, ref, kind);
  }

  /// Open the picker as a Replace flow for [layer]. Same UI as the
  /// add-shape flow; on selection dispatches a [ReplaceShapeKindCommand]
  /// instead of inserting a new layer. Preserves transform, fill,
  /// stroke and cornerRadius.
  Future<void> _openReplaceShapePicker(
    BuildContext context,
    WidgetRef ref,
    ShapeLayer layer,
  ) async {
    final kind = await pickShapeKind(
      context,
      title: context.l10n.replaceShapeTitle,
      subtitle: context.l10n.replaceShapeSubtitle,
      currentKind: layer.kind,
    );
    if (kind == null || kind == layer.kind || !context.mounted) return;
    EditorHaptics.confirm();
    ref
        .read(documentControllerProvider.notifier)
        .execute(ReplaceShapeKindCommand(layerId: layer.id, kind: kind));
  }

  /// Resolves which [ImageLayer] a main-toolbar image action should
  /// target. See [resolveImageTarget] for the priority order. This
  /// async wrapper additionally:
  ///   - on `AutoSelect`, mutates the selection so the dock's
  ///     image-mode branch picks up the layer;
  ///   - on `Ambiguous`, opens an image chooser sheet and treats
  ///     the user's pick as a manual selection;
  ///   - on `NoneAvailable`, shows a snackbar.
  ///
  /// Returns `null` when no target was resolved (no images, or the
  /// user dismissed the chooser); callers should bail.
  Future<ImageLayer?> _resolveImageTarget(
    BuildContext context,
    WidgetRef ref, {
    required String actionVerb,
  }) async {
    final doc = ref.read(documentControllerProvider);
    final selectedId = ref.read(selectionControllerProvider).selectedId;
    final outcome = resolveImageTarget(doc, selectedId: selectedId);
    switch (outcome) {
      case ImageTargetSelected(:final layer):
        return layer;
      case ImageTargetAutoSelect(:final layer):
        ref.read(selectionControllerProvider.notifier).select(layer.id);
        return layer;
      case ImageTargetNoneAvailable():
        // Don't dead-end — offer a one-tap recovery so the user
        // can satisfy the precondition without hunting for the
        // Photo tile. The action verb is woven into the message so
        // Crop / Adjust / Filters each surface as a coherent
        // sentence ("Import a photo to crop").
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(context.l10n.importPhotoToAction(actionVerb)),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: context.l10n.addPhotoAction,
              onPressed: () => _addImage(context, ref),
            ),
          ),
        );
        return null;
      case ImageTargetAmbiguous(:final candidates):
        final picked = await _pickImageFromCanvas(
          context,
          candidates: candidates,
          actionVerb: actionVerb,
        );
        if (picked == null) return null;
        ref.read(selectionControllerProvider.notifier).select(picked.id);
        return picked;
    }
  }

  /// Bottom sheet listing every [ImageLayer] currently on the
  /// canvas. Used by [_resolveImageTarget] to disambiguate when the
  /// document has multiple images, none is selected, and there is no
  /// base-photo fallback. Returns the user's choice, or `null` on
  /// dismiss/cancel.
  Future<ImageLayer?> _pickImageFromCanvas(
    BuildContext context, {
    required List<ImageLayer> candidates,
    required String actionVerb,
  }) {
    return showModalBottomSheet<ImageLayer>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  context.l10n.pickImageToAction(actionVerb),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final layer = candidates[i];
                    return ListTile(
                      leading: const Icon(Icons.image_outlined),
                      title: Text(context.l10n.imageLayerTitle(i + 1)),
                      subtitle: Text(
                        '${layer.transform.size.width.round()} '
                        '\u00d7 ${layer.transform.size.height.round()}',
                      ),
                      onTap: () => Navigator.of(ctx).pop(layer),
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  /// Opens the centralised [CropModeOverlay] for the resolved
  /// [ImageLayer] (selected -> only-image -> base-photo ->
  /// chooser).
  ///
  /// We snapshot the **prior** selection BEFORE
  /// [_resolveImageTarget] (which may auto-select an image to
  /// resolve a target) and pass it into [CropController.openCrop].
  /// On Done/Cancel that snapshot is restored, so opening Crop
  /// from the main toolbar lands the user back on the main toolbar
  /// instead of stranding them in the image sub-tools.
  Future<void> _openCrop(BuildContext context, WidgetRef ref) async {
    final priorSelectionId = ref.read(selectionControllerProvider).selectedId;
    final layer = await _resolveImageTarget(
      context,
      ref,
      actionVerb: context.l10n.cropActionVerb,
    );
    if (layer == null) return;
    EditorHaptics.tap();
    ref
        .read(cropControllerProvider.notifier)
        .openCrop(layer.id, priorSelectionId: priorSelectionId);
  }

  /// Opens the Filters dock panel for the resolved [ImageLayer].
  /// Routing through [imageToolControllerProvider]'s
  /// [ImageToolSlot.filters] slot lets the existing image-mode dock
  /// branch render [ImageFiltersBody] without a parallel code path.
  Future<void> _openFilters(BuildContext context, WidgetRef ref) async {
    final layer = await _resolveImageTarget(
      context,
      ref,
      actionVerb: context.l10n.applyFilterActionVerb,
    );
    if (layer == null) return;
    EditorHaptics.tap();
    final ctrl = ref.read(imageToolControllerProvider.notifier);
    if (ref.read(imageToolControllerProvider).openSlot !=
        ImageToolSlot.filters) {
      ctrl.toggleSlot(ImageToolSlot.filters);
    }
  }

  /// Opens the Adjust dock panel for the resolved [ImageLayer].
  Future<void> _openAdjust(BuildContext context, WidgetRef ref) async {
    final layer = await _resolveImageTarget(
      context,
      ref,
      actionVerb: context.l10n.adjustActionVerb,
    );
    if (layer == null) return;
    EditorHaptics.tap();
    final ctrl = ref.read(imageToolControllerProvider.notifier);
    if (ref.read(imageToolControllerProvider).openSlot !=
        ImageToolSlot.adjust) {
      ctrl.toggleSlot(ImageToolSlot.adjust);
    }
  }

  /// Toggles the Canvas dock panel. Unlike Filters/Adjust, Canvas
  /// edits the document itself so it doesn't require a selected
  /// layer — we also clear the current selection so the dock falls
  /// through to the no-selection branch and renders the panel.
  void _openCanvas(WidgetRef ref) {
    EditorHaptics.tap();
    ref.read(selectionControllerProvider.notifier).clear();
    ref.read(canvasToolControllerProvider.notifier).togglePanel();
  }

  void _handleOverflowAction(
    BuildContext context,
    WidgetRef ref,
    _OverflowAction action,
  ) {
    switch (action) {
      case _OverflowAction.save:
        _saveProject(context, ref);
      case _OverflowAction.export:
        ExportActionSheet.open(context);
      case _OverflowAction.fit:
        _fitViewport(context, ref);
      case _OverflowAction.newDoc:
        _openNewDocumentDialog(context, ref);
    }
  }

  Future<void> _saveProject(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      final project = await ref.read(projectSaveServiceProvider).save(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.savedProject(project.name)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e, st) {
      debugLogError('editor/save', e, st);
      messenger.showSnackBar(
        SnackBar(
          content: Text(userMessageFor(e, fallback: l10n.somethingWentWrong)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openNewDocumentDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final choice = await showDialog<NewDocumentChoice>(
      context: context,
      builder: (_) => const NewDocumentDialog(),
    );
    if (choice == null) return;

    final docCtrl = ref.read(documentControllerProvider.notifier);
    docCtrl.newDocument(width: choice.width, height: choice.height);
    ref.read(selectionControllerProvider.notifier).clear();

    if (choice.imageUrl != null) {
      final id = _uuid.v4();
      docCtrl.execute(
        AddLayerCommand(
          ImageLayer(
            id: id,
            transform: LayerTransform(
              position: Offset.zero,
              size: Size(choice.width, choice.height),
            ),
            source: ImageSource.network(choice.imageUrl!),
          ),
        ),
      );
      ref.read(selectionControllerProvider.notifier).select(id);
    }
  }

  void _fitViewport(BuildContext context, WidgetRef ref) {
    // Replays the most recent fit the [EditorCanvas] auto-ran, which
    // was sized against its real `LayoutBuilder` constraints — i.e.
    // the actual visible canvas pane (already excludes app bar,
    // bottom dock, FABs, safe areas). Recomputing the pane from
    // `MediaQuery` here would silently disagree with the layout (we
    // don't know the dock height from this seam) and shift the
    // canvas downward. The auto-fit is the source of truth; this
    // button just re-applies it.
    final ok = ref.read(viewportControllerProvider.notifier).refit();
    if (ok) return;
    // Fallback for the (unreachable in practice) case where the
    // canvas has never measured itself yet — e.g. test harnesses
    // that drive the menu without mounting [EditorCanvas]. Use a
    // best-effort screen rect so the controller still lands on a
    // sensible state instead of a no-op.
    final doc = ref.read(documentControllerProvider);
    final media = MediaQuery.of(context);
    final appBar = kToolbarHeight + media.padding.top;
    final screen = Size(
      media.size.width,
      media.size.height - appBar - media.padding.bottom,
    );
    ref
        .read(viewportControllerProvider.notifier)
        .fit(screenSize: screen, canvasSize: Size(doc.width, doc.height));
  }
}

/// Owns the [WidgetsBindingObserver] for the editor and guarantees
/// any pending debounced autosave is flushed when the user
/// backgrounds the app or navigates away from the editor.
///
/// Kept as a small dedicated widget (rather than making
/// [EditorScreen] stateful) so the giant build method stays a
/// pure [ConsumerWidget]. The scope:
///
/// * On `paused` / `inactive` / `detached` / `hidden` — calls
///   [AutosaveController.flushNow]. iOS / Android may kill the app
///   shortly after `paused`, so this is the last reliable hook.
/// * On dispose — flushes again as a final safety net for the
///   normal "tap back, leave editor" path. Combined with the
///   eager flush in [EditorScreen]'s [PopScope] this means the
///   pending write either races route teardown (best case) or is
///   issued right after it (fallback).
///
/// All flushes are no-ops when the session has no `projectId`
/// (see [AutosaveController] rule 1) so this never auto-creates
/// throwaway projects. Multiple flushes for the same payload
/// collapse into a single `SharedPreferences` write because
/// `_flush` short-circuits on identical JSON.
class _AutosaveLifecycleScope extends ConsumerStatefulWidget {
  const _AutosaveLifecycleScope({required this.child});

  final Widget child;

  @override
  ConsumerState<_AutosaveLifecycleScope> createState() =>
      _AutosaveLifecycleScopeState();
}

class _AutosaveLifecycleScopeState
    extends ConsumerState<_AutosaveLifecycleScope>
    with WidgetsBindingObserver {
  /// Captured notifier reference. Stored so [dispose] can flush
  /// without touching `ref` — Riverpod 3 forbids `ref.read` after
  /// the consumer element has been unmounted (it relies on the
  /// already-deactivated `BuildContext`). Resolved lazily in
  /// [didChangeDependencies] so the notifier is bound to the
  /// current `ProviderScope`.
  AutosaveController? _autosave;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _autosave = ref.read(autosaveControllerProvider.notifier);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Final safety net: the user is leaving the editor for good.
    // Fire-and-forget; the autosave write is idempotent (no-op
    // skip on unchanged JSON) so the eager flush in [PopScope]
    // above plus this one will not double-write.
    //
    // Use the captured notifier — `ref.read` inside `dispose` is
    // unsafe in Riverpod 3 because `BuildContext` is already
    // deactivated by the time finalisation runs.
    unawaited(
      _autosave?.flushNow(sessionEnding: true) ?? Future<void>.value(),
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        final notifier = _autosave;
        if (notifier != null) {
          unawaited(notifier.flushNow());
        }
      case AppLifecycleState.resumed:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _DocumentTitle extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = ref.watch(
      documentControllerProvider.select(
        (EditorDocument d) => Size(d.width, d.height),
      ),
    );
    final scale = ref.watch(viewportControllerProvider.select((v) => v.scale));
    final session = ref.watch(editorSessionProvider);
    final title = session?.name ?? context.l10n.appName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, overflow: TextOverflow.ellipsis),
        Text(
          '${size.width.toInt()} × ${size.height.toInt()} • ${(scale * 100).toStringAsFixed(0)}%',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

enum _OverflowAction { save, export, fit, newDoc }

/// Floating undo/redo rail anchored top-left of the canvas. Mirrors
/// the [_ModeExitPill] geometry on the right edge so the canvas
/// frame reads as a symmetric, glass-on-canvas chrome layer rather
/// than a stack of unrelated chips.
///
/// Each button auto-dims via reduced opacity when its action is
/// unavailable instead of disappearing — keeps the rail's footprint
/// stable so muscle memory holds across edit states.
class _UndoRedoRail extends ConsumerWidget {
  const _UndoRedoRail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Undo/redo button enable state only changes on real commits —
    // never on overlay previews. Subscribe to the commit counter so
    // a 60-fps slider drag doesn't repaint this rail.
    ref.watch(documentCommitVersionProvider);
    final doc = ref.read(documentControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 36,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.surface.withValues(alpha: 0.96),
            scheme.surfaceContainerHighest.withValues(alpha: 0.88),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RailButton(
            icon: Icons.undo_rounded,
            tooltip: context.l10n.undoTooltip,
            enabled: doc.canUndo,
            onTap: () {
              EditorHaptics.tap();
              doc.undo();
            },
            tint: scheme.primary,
          ),
          Container(
            width: 0.5,
            height: 18,
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
          _RailButton(
            icon: Icons.redo_rounded,
            tooltip: context.l10n.redoTooltip,
            enabled: doc.canRedo,
            onTap: () {
              EditorHaptics.tap();
              doc.redo();
            },
            tint: scheme.primary,
          ),
        ],
      ),
    );
  }
}

class _RailButton extends StatefulWidget {
  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
    required this.tint,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;
  final Color tint;

  @override
  State<_RailButton> createState() => _RailButtonState();
}

class _RailButtonState extends State<_RailButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: widget.tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: widget.enabled ? widget.onTap : null,
          onHighlightChanged: (v) =>
              setState(() => _pressed = v && widget.enabled),
          child: AnimatedScale(
            scale: _pressed ? 0.88 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: SizedBox(
              width: 44,
              height: 36,
              child: ShaderMask(
                shaderCallback: (bounds) {
                  if (!widget.enabled) {
                    final c = scheme.onSurfaceVariant.withValues(alpha: 0.32);
                    return LinearGradient(colors: [c, c]).createShader(bounds);
                  }
                  return LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.tint,
                      Color.lerp(widget.tint, scheme.tertiary, 0.55) ??
                          widget.tint,
                    ],
                  ).createShader(bounds);
                },
                blendMode: BlendMode.srcIn,
                child: Icon(widget.icon, size: 18),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Floating exit pill shown top-right of the canvas while a tool
/// mode (paint or text) is active. Tapping it closes the active
/// mode panel and clears selection — a discoverable, always-visible
/// alternative to canvas-tap-to-deselect.
class _ModeExitPill extends ConsumerWidget {
  const _ModeExitPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paintOpen = ref.watch(
      paintToolControllerProvider.select((s) => s.panelOpen),
    );
    final textOpen = ref.watch(
      textToolControllerProvider.select((s) => s.panelOpen),
    );
    final selectionId = ref.watch(
      selectionControllerProvider.select((s) => s.selectedId),
    );
    final doc = ref.watch(renderedDocumentProvider);
    final selectedLayer = selectionId == null
        ? null
        : doc.layerById(selectionId);
    final hasTextSelection =
        selectedLayer is TextLayer && !selectedLayer.isSticker;
    // Protected base photo (photo project) is the canvas itself --
    // it is intentionally selectable for tool targeting but never
    // shows object-selection chrome (frame, quick actions). Done
    // belongs to that chrome family, so suppress it here too.
    final hasObjectSelection =
        selectedLayer != null &&
        !(selectionId != null && doc.isProtectedBasePhoto(selectionId));
    final inMode = paintOpen || textOpen || hasObjectSelection;
    if (!inMode) return const SizedBox.shrink();

    // Single canonical verb: every commit / dismiss path on the
    // canvas is "Done". Avoids Hick's-law confusion from flipping
    // between "Done" and "Deselect" for the same affordance.
    return ModeDoneButton(
      onPressed: () {
        if (paintOpen) {
          ref.read(paintToolControllerProvider.notifier).closePanel();
        }
        if (textOpen || hasTextSelection) {
          ref.read(textToolControllerProvider.notifier).closePanel();
        }
        // Always clear selection — covers shape / image / text and
        // closes any open mode panel above.
        ref.read(selectionControllerProvider.notifier).clear();
      },
    );
  }
}

