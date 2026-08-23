import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' as picker;
import 'package:uuid/uuid.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/engine_constants.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/user_error.dart';
import '../../../l10n/l10n.dart';
import '../../home/application/project_store.dart';
import '../application/autosave_controller.dart';
import '../application/context_toolbar_controller.dart';
import '../application/document_controller.dart';
import '../application/edit_session_registry.dart';
import '../application/image_import_service.dart';
import '../application/live_overlay_controller.dart';
import '../application/editor_lifecycle.dart';
import '../application/editor_mode_controller.dart';
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
import '../engine/commands/layer_state_commands.dart';
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
import '../image/application/image_target.dart';
import '../image/application/image_tool_controller.dart';
import '../image/application/main_strip_image_entry.dart';
import '../image/presentation/image_look_body.dart';
import '../image/presentation/image_style_body.dart';
import 'widgets/history_browser_sheet.dart';
import '../image/presentation/image_studio_bench.dart';
import 'sticker_picker_sheet.dart';
import '../paint/application/paint_tool_controller.dart';
import '../paint/domain/paint_tool_type.dart';
import '../paint/presentation/paint_bench.dart';
import '../paint/presentation/paint_mode_expansion.dart';
import '../paint/presentation/paint_size_rail.dart';
import '../shape/application/shape_tool_controller.dart';
import '../shape/presentation/shape_border_body.dart';
import '../shape/presentation/shape_shadow_body.dart';
import '../shape/presentation/shape_studio_bench.dart';
import '../shape/presentation/shape_style_body.dart';
import 'shape_picker_sheet.dart';
import '../sticker/application/sticker_tool_controller.dart';
import '../sticker/presentation/sticker_mode_toolbar.dart';
import '../text/application/text_tool_controller.dart';
import '../text/application/add_text_composer_state.dart';
import '../text/presentation/text_input_flow_sheet.dart';
import '../text/presentation/text_studio_bench.dart';
import '../toolbar/presentation/mode_done_button.dart';
import 'widgets/editor_canvas.dart';
import 'widgets/mask_edit_overlay.dart' show confirmAbandonMaskEdit;
import 'widgets/image_source_sheet.dart';
import 'widgets/editor_tool_dock.dart';
import '../toolbar/domain/toolbar_slot.dart';
import 'widgets/context_tool_panel.dart';
import 'widgets/editor_toolbar.dart';
import 'widgets/export_action_sheet.dart';
import 'widgets/layers_panel.dart';
import 'widgets/multi_select_mode_toolbar.dart';
import '../../../core/utils/editor_value_format.dart';
import '../../../core/utils/text_measure.dart';
import '../../../app/theme/app_icons.dart';

const _uuid = Uuid();

class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final tokens = AppTokens.of(context);
    final selection = ref.watch(selectionControllerProvider);
    // Subscribe to commit ticks only. The screen-level rebuild is
    // a defensive lifecycle pump — it must fire when the document
    // truly changes (execute / undo / redo) but stay silent during
    // mid-gesture overlay previews. Reading committed-doc directly
    // worked only because nothing routes through liveReplace today;
    // commit-version makes the contract explicit so the next
    // accidental in-place mutation can't regress this.
    ref.watch(documentCommitVersionProvider);
    // Selection-integrity owner (tb0 0.8): undo/redo mutate the
    // document with no selection call, so dead selected ids linger —
    // ghost counts in the multi chip, a never-firing selection seam,
    // and sub-panels that silently remount on redo. Prune on every
    // commit tick, BEFORE the selection-change listener below reacts:
    // pruning changes selectedId, so the existing seam then closes
    // the dead layer's panels through its normal path. Both listeners
    // are idempotent.
    // The crash net going down is the one background failure the
    // user has to hear about: the journal swallows write errors by
    // design (it must never take the editor with it), so without
    // this a full disk silently stops protecting their work
    // (tb5 8/9). Once per session — a full disk does not un-fill
    // itself between two debounced writes.
    ref.listen<bool>(journalWriteFailedProvider, (prev, next) {
      if (prev == true || !next || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.journalWriteFailedWarning),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    });
    ref.listen<int>(documentCommitVersionProvider, (prev, next) {
      if (prev == next) return;
      // Prune only — deliberately NO multi-mode collapse here
      // (ux-audit P2-5). The mode stays armed at any member count
      // until an explicit exit, and the chip — gated on the mode
      // flag, labelled with the actionable count — stays visible
      // through the prune. The count-triggered exit this listener
      // used to carry was one of three divergent below-2 rules, and
      // it only ever fired on a commit tick, never on a user toggle.
      ref
          .read(selectionControllerProvider.notifier)
          .pruneMissing(ref.read(documentControllerProvider));
    });
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
      // Canvas panel: selecting a layer hides the no-selection dock
      // branch that hosts it, but its `panelOpen` used to survive —
      // and the panel silently RE-MOUNTED on the next deselect
      // (contract §4: E3 must not resurrect chrome; audit
      // shell:canvas-panel-resurrects). Closing the moment a
      // selection APPEARS kills every resurrect path at the root
      // (Done pill, delete, undo-prune…). Deselect transitions
      // deliberately do not touch it — the no-selection branch is
      // exactly where the panel is allowed to live, and the E3
      // seams (`dismissActiveEditing`, the Done pill) already close
      // it explicitly.
      if (next.selectedId != null) {
        ref.read(canvasToolControllerProvider.notifier).closePanel();
      }
    });
    // Main-strip Adjust/Filters exit seam (contract §4, tb2 10/16):
    // when the panel that a main-strip entry opened closes, restore
    // the selection captured at entry — mirrors Crop's
    // priorSelectionId round-trip so the user lands back where they
    // started instead of stranded in image mode. All the "who wins"
    // rules live in the controller; this listener only forwards the
    // slot transition.
    ref.listen<ImageToolSession>(imageToolControllerProvider, (prev, next) {
      if (prev?.openSlot == next.openSlot) return;
      ref
          .read(mainStripImageEntryProvider.notifier)
          .handleSlotChange(prev?.openSlot, next.openSlot);
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
    final textFlowOpen =
        ref.watch(addTextComposerOpenProvider) ||
        ref.watch(textEditFlowOpenProvider);
    // Mask-edit mode hides the same chrome: its bottom strip is the
    // only editing surface while the user shapes the region, and the
    // undo rail must hide because a mid-draft undo would mutate the
    // document under the mode (the doc listener would then cancel
    // the session — technically safe, but jarring).
    final maskEditActive = ref.watch(
      maskEditControllerProvider.select((s) => s.active),
    );
    // System Back unwinds editing chrome one level per press (§4)
    // before the route may pop — see [editorBackStepProvider].
    final backOwned = ref.watch(editorBackStepProvider) != EditorBackStep.none;
    // Single resolution of the dock's mode/expanded panel, shared by
    // the bottomNavigationBar builder below.
    final dock = _resolveDock(ref, selection);

    // D-e (tb5 2/9): the editor's own chrome clamps text scaling to
    // 1.0–1.3. Below 1.0 the dock's 11sp value labels stop being
    // legible at all; above ~1.3 the strip tiles, the sub-tool
    // sheets and the crop control card each overflow, and a user who
    // needs larger text ends up with an editor they cannot operate.
    // The clamp deliberately covers CHROME only — the canvas renders
    // document pixels, where the user's own font sizes are content
    // and must never be rescaled by an accessibility setting.
    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 1.0,
      maxScaleFactor: 1.3,
      child: _AutosaveLifecycleScope(
        child: PopScope(
          canPop: !cropActive && !maskEditActive && !backOwned,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && maskEditActive) {
              // Back = Cancel, restoring the pre-mode toolbar context
              // — but a modified draft is confirmed first, because
              // cancel() discards with zero commands and undo cannot
              // reach it. Same gate as the overlay's Cancel button so
              // the two exits cannot diverge.
              unawaited(() async {
                if (!await confirmAbandonMaskEdit(context, ref)) return;
                ref
                    .read(maskEditControllerProvider.notifier)
                    .cancel(restoreSelection: true);
              }());
              return;
            }
            if (!didPop && cropActive) {
              ref.read(cropControllerProvider.notifier).cancelCrop();
              return;
            }
            if (!didPop) {
              // Contract §4 ladder: one Back press unwinds one level
              // (E1 close the open sheet, then E2 exit the armed
              // mode/session) before the route may pop. Re-read the
              // step at fire time — the build-time value may be a
              // frame stale.
              performEditorBackStep(ref, ref.read(editorBackStepProvider));
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
            // v2 top bar: slim, surface-on-tokens, ink icons, hairline
            // bottom. Primary actions stay visible (back, title
            // tap-to-rename, export); secondary ones (layers, save,
            // fit, new document) live in the «⋮» overflow.
            appBar: cropActive || maskEditActive
                ? null
                : AppBar(
                    toolbarHeight: 52,
                    backgroundColor: tokens.surface,
                    foregroundColor: tokens.textPrimary,
                    bottom: PreferredSize(
                      preferredSize: const Size.fromHeight(1),
                      child: Container(height: 1, color: tokens.border),
                    ),
                    title: const _DocumentTitle(),
                    // Three actions, no overflow menu (tb4 5/14). The
                    // «⋮» held Layers, Save, Fit and New document —
                    // four unrelated things behind one anonymous glyph.
                    // Layers is frequent enough to earn its own icon;
                    // Save and Fit belong to the DOCUMENT, so they live
                    // in the title's menu next to Rename; New document
                    // leaves the editor entirely (Home creates).
                    actions: [
                      const _UndoRedoActions(),
                      Builder(
                        builder: (ctx) => IconButton(
                          tooltip: l10n.layersTooltip,
                          onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                          icon: const Icon(AppIcons.layersPanel),
                        ),
                      ),
                      Builder(
                        builder: (ctx) => IconButton(
                          tooltip: l10n.editorExport,
                          onPressed: () => ExportActionSheet.open(ctx),
                          icon: const Icon(AppIcons.share),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
            endDrawer: const LayersPanel(),
            // Contract §6: the Layers drawer's edge-swipe is disabled
            // while any draft session is open (crop/mask own the
            // screen; compose/edit/export sit behind modal barriers —
            // this closes the edge-gesture hole those barriers leave
            // at the screen edge). The ⋮ → Layers menu path and the
            // toolbars' explicit openEndDrawer() calls are unaffected.
            endDrawerEnableOpenDragGesture: !ref.watch(
              anyDraftSessionOpenProvider,
            ),
            body: Stack(
              children: [
                // NO scrim over the canvas while control panels are
                // open — this is an editor: the user must see the live
                // effect of colour/size/font changes. The panel's own
                // elevation (rounded top + upward shadow + hairline)
                // is what separates it from the canvas.
                const EditorCanvas(),
                // Always-visible exit pill anchored at the top TRAILING
                // edge of the canvas (physical left under RTL — the
                // hard `right: 8` was an LTR-ism; tb1 17/17, pinned by
                // rtl_strip_pins_test). Shows whenever a tool mode
                // (paint / text) is active so the user has a permanent,
                // discoverable way out — replaces reliance on the
                // invisible canvas-tap-to-deselect gesture for new
                // users while keeping that gesture as the pro shortcut.
                // Hidden in Crop Mode.
                // top 4 (not 8): the pill's hit box is 44dp with the
                // painted 36dp pill centred (tb2 a11y pass), so the
                // 4dp transparent halo puts the VISIBLE pill exactly
                // where it has always been (8dp from the top edge).
                // …and NOT while a text composer/edit flow owns the
                // screen. The pill reads «تمام» — the app's own commit
                // word — and floats directly above a sheet whose commit
                // button says «افزودن», both pill-shaped, both on the
                // physical left. But the pill belongs to the route
                // UNDER the modal, so a tap aimed at it lands on the
                // sheet's dismissible barrier: pop(null) → cancelLiveEdit
                // → everything typed is gone, with no confirm and
                // nothing on the undo stack. Every other piece of canvas
                // chrome already suppresses itself on these flags; the
                // pill was the one that didn't.
                if (!cropActive && !maskEditActive && !textFlowOpen)
                  const PositionedDirectional(
                    top: 4,
                    end: 8,
                    child: SafeArea(child: _ModeExitPill()),
                  ),
                // Canvas-side stroke-width rail — floating paint
                // chrome; renders nothing unless an inking paint
                // tool is armed (see PaintSizeRail.visibleFor).
                if (!cropActive && !maskEditActive && !textFlowOpen)
                  const Positioned.fill(
                    child: SafeArea(child: PaintSizeRailHost()),
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
                // Mask-edit: its bottom strip replaces the dock.
                if (cropActive || maskEditActive) {
                  return const SizedBox.shrink();
                }
                return EditorToolDock(
                  modeKey: dock.modeKey,
                  expanded: dock.expanded,
                  expandedKey: dock.expandedKey,
                  // The paint and text benches are two rows (style/
                  // identity + rack/aspects); every other mode keeps
                  // the standard strip height.
                  height: dock.paintOpen
                      ? PaintBench.dockHeight(dockContext)
                      : dock.textMode
                      ? TextStudioBench.dockHeight(dockContext)
                      : dock.selectedImageLayer != null && !dock.multiSelected
                      ? ImageStudioBench.dockHeight(dockContext)
                      : dock.selectedShapeLayer != null && !dock.multiSelected
                      ? ShapeStudioBench.dockHeight(dockContext)
                      : null,
                  child: dock.paintOpen
                      ? const PaintBench()
                      : dock.textMode
                      ? const TextStudioBench()
                      : dock.multiSelected
                      ? MultiSelectModeToolbar(
                          layers: dock.selectedLayersForActions,
                          onOpenLayers: () =>
                              Scaffold.of(dockContext).openEndDrawer(),
                        )
                      : dock.selectedStickerLayer != null
                      ? StickerModeToolbar(layer: dock.selectedStickerLayer!)
                      : dock.selectedImageLayer != null
                      ? ImageStudioBench(layer: dock.selectedImageLayer!)
                      : dock.selectedShapeLayer != null
                      ? ShapeStudioBench(
                          layer: dock.selectedShapeLayer!,
                          onReplaceTap: () => _openReplaceShapePicker(
                            context,
                            ref,
                            dock.selectedShapeLayer!,
                          ),
                        )
                      : EditorToolbar(
                          // The idle strip renders only when no mode
                          // owns the dock, so no tile is ever active —
                          // the old _activeToolId re-derivation was
                          // provably dead on every branch.
                          activeId: null,
                          items: _buildToolbarItems(context, ref),
                        ),
                );
              },
            ),
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
  ///   tier2 — **Edit the photo** — the P-scope group (contract §10).
  ///     Crop · Look, targeting the protected base photo and nothing
  ///     else. PHOTO PROJECTS ONLY: a design document has no such
  ///     role, so it does not render this group at all (§10.1). That
  ///     is absence, not unavailability — the distinction §10.3 draws.
  ///
  ///   tier3 — **Document**
  ///     Canvas (size / background)
  ///
  /// Group ORDER follows project kind, because the strip does not
  /// fit. Eight slots need ~560dp of a 402dp content width, so the
  /// sixth tile is always cut and the rest are behind a scroll whose
  /// only affordance is a 24dp fade. With tier 1 leading, the three
  /// tools past the fold were Crop, Look and Canvas — i.e. a user who
  /// arrived through «ویرایش عکس» found the five verbs they did not
  /// come for and had to discover a scroll to reach the two they did.
  ///
  /// So a photo project leads with the photo group; a design project
  /// has only Add + Document to order, and keeps Add first.
  /// Handedness still never reorders anything (see
  /// [SlotStrip.fitAlignment]) — only project kind does.
  ///
  /// Whether the P-scope role target qualifies — the precondition
  /// Crop and Look share (§10.2). Distinct from "is this a photo
  /// project": the group is CONSTRUCTED on project kind and made
  /// AVAILABLE on this, which is §10.4's separation of placement
  /// from availability.
  static bool _roleTargetAvailable(WidgetRef ref) =>
      resolveRoleTarget(ref.watch(documentControllerProvider)) != null;

  /// Whether this document is a PHOTO project — the stable property
  /// the group order keys off.
  ///
  /// Deliberately not "does any image layer exist". A design project
  /// where the user dropped in one decorative image is still an
  /// add-content workflow, and keying off layer contents reshuffled the
  /// strip on undo/redo of ANY image add — chrome moving as a
  /// side-effect of an unrelated edit.
  ///
  /// This does not make the order undo-invariant, and the earlier
  /// version of this comment wrongly implied it did.
  /// `SetProjectKindCommand` is part of the base-photo delete composite
  /// (`LayerActions.deleteWithoutConfirm`) and is inverted on undo, so
  /// removing the base photo — and undoing that removal — does reorder
  /// the strip. That is the one edit where the workflow genuinely
  /// changes, and it is the trade being made: one deliberate flip
  /// instead of one per image layer touched.
  static bool _isPhotoProject(WidgetRef ref) => ref.watch(
    documentControllerProvider.select(
      (d) => d.projectKind == ProjectKind.photo,
    ),
  );

  List<ToolbarSlot> _buildToolbarItems(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final hasPhoto = _isPhotoProject(ref);
    final add = <ToolbarSlot>[
      // ── tier 1 — Add ────────────────────────────────────────────
      ToolbarSlot(
        id: 'image',
        icon: AppIcons.photoTool,
        label: l10n.photoTool,
        onTap: () => _addImage(context, ref),
      ),
      ToolbarSlot(
        id: 'text',
        icon: AppIcons.textTool,
        label: l10n.textTool,
        onTap: () => _startTextInputFlow(context, ref),
      ),
      ToolbarSlot(
        id: 'sticker',
        icon: AppIcons.stickerTool,
        label: l10n.stickerTool,
        onTap: () => _addSticker(context, ref),
      ),
      ToolbarSlot(
        id: 'shape',
        icon: AppIcons.shapeTool,
        label: l10n.shapeTool,
        onTap: () => _openShapePicker(context, ref),
      ),
      ToolbarSlot(
        id: 'paint',
        icon: AppIcons.drawTool,
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
    ];
    // ── tier 2 — Edit the photo (P scope, §10) ────────────────────
    //
    // Built ONLY for a photo project — see `hasPhoto` below. Both
    // target the protected base photo, a role `ProjectKind.design`
    // does not have, and §10.1 keeps a control off a surface whose
    // scope is inadmissible there rather than dimming it forever.
    //
    // Where the group DOES exist and its target does not qualify
    // (deleted, or hidden from the layers drawer), the tiles stay
    // VISIBLE and TAPPABLE and render dimmed — the tap is what
    // explains the precondition and offers to satisfy it. That is
    // §10.3's split: absent when the scope cannot apply, dimmed when
    // it applies and the target is missing. Never present-and-inert.
    final photo = <ToolbarSlot>[
      ToolbarSlot(
        id: 'crop',
        icon: AppIcons.cropTool,
        label: l10n.cropTool,
        tier: SlotTier.tier2,
        availableBuilder: () => _roleTargetAvailable(ref),
        unavailableHint: l10n.toolNeedsPhotoHint,
        onTap: () => _openCrop(context, ref),
      ),
      ToolbarSlot(
        id: 'look',
        icon: AppIcons.lookTool,
        label: l10n.lookTool,
        tier: SlotTier.tier2,
        availableBuilder: () => _roleTargetAvailable(ref),
        unavailableHint: l10n.toolNeedsPhotoHint,
        onTap: () => _openLook(context, ref),
      ),
    ];
    // ── tier 3 — Document ─────────────────────────────────────────
    final document = <ToolbarSlot>[
      ToolbarSlot(
        id: 'canvas',
        icon: AppIcons.canvasSize,
        label: l10n.canvasTool,
        tier: SlotTier.tier3,
        onTap: () => _openCanvas(ref),
      ),
    ];
    // Photo group first in a photo project — see the doc above. A
    // design project omits the group entirely (§10.1), so its strip
    // is Add + Document and carries one divider instead of two.
    return hasPhoto ? [...photo, ...document, ...add] : [...add, ...document];
  }

  /// Resolves everything the bottom dock renders — mode key, chip
  /// strip variant flags and the optional expanded panel — in ONE
  /// place, so the canvas scrim (which dims whenever a panel is
  /// open) and the dock itself can never disagree. The `selected*`
  /// layer fields are pre-gated: non-null only when that mode owns
  /// the strip. Text mode renders its tool sheets in the expanded
  /// slot (Canva-style: canvas reflows above the dock instead of
  /// being overlaid); paint keeps its small inline expansion row.
  _DockResolution _resolveDock(WidgetRef ref, SelectionState selection) {
    // ONE mode source (tb1 7/17): the priority ladder that used to
    // be hand-negated here — and re-derived in the dock child chain
    // and _activeToolId — now lives in editorToolModeProvider. This
    // method only resolves per-mode PAYLOADS: which layer object a
    // strip or panel renders against (read from the merged view so
    // in-flight overlay previews stay live inside panels), and which
    // expanded body is open.
    final mode = ref.watch(editorToolModeProvider);
    final paintOpen = mode == EditorToolMode.paint;
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
    final multiSelected = mode == EditorToolMode.multi;
    final textSelected =
        mode == EditorToolMode.text && _selectedTextLayer(ref) != null;
    final selectedStickerLayer = mode == EditorToolMode.sticker
        ? _selectedStickerLayer(ref)
        : null;
    final stickerSelected = selectedStickerLayer != null;
    final selectedImageLayer = mode == EditorToolMode.image
        ? _selectedImageLayer(ref)
        : null;
    final imageSelected = selectedImageLayer != null;
    final selectedShapeLayer = mode == EditorToolMode.shape
        ? _selectedShapeLayer(ref)
        : null;
    final shapeSelected = selectedShapeLayer != null;
    final modeKey = switch (mode) {
      EditorToolMode.paint => 'paint',
      EditorToolMode.text => 'text',
      EditorToolMode.multi => 'multi',
      EditorToolMode.sticker => 'sticker',
      EditorToolMode.image => 'image',
      EditorToolMode.shape => 'shape',
      EditorToolMode.idle => 'main',
    };

    Widget? expanded;
    Object? expandedKey;
    final contextPanelLayers = contextPanel == null
        ? const <EditorLayer>[]
        : _layersForContextPanel(ref, selection, contextPanel);
    if (contextPanel != null && contextPanelLayers.isNotEmpty) {
      expanded = ContextToolPanelBody(
        panel: contextPanel,
        layers: contextPanelLayers,
      );
      expandedKey =
          'context:${contextPanel.name}:'
          '${contextPanelLayers.map((l) => l.id).join(',')}';
    } else if (textSelected && textOpenSheet != null) {
      expanded = const TextStudioSheetPanel();
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
        case ImageToolSlot.look:
          expanded = ImageLookBody(layer: selectedImageLayer);
          expandedKey = 'image-look:${selectedImageLayer.id}';
        case ImageToolSlot.style:
          expanded = ImageStyleBody(layer: selectedImageLayer);
          expandedKey = 'image-style:${selectedImageLayer.id}';
        case null:
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
        case null:
          break;
      }
    } else {
      // No layer selected. The Canvas tool is the only entry that
      // opens a panel from this state — it edits the document
      // itself, not a layer.
      final canvasOpen = ref.watch(
        canvasToolControllerProvider.select((s) => s.panelOpen),
      );
      if (canvasOpen) {
        expanded = const CanvasPanelBody();
        expandedKey = 'canvas-panel';
      }
    }

    return (
      expanded: expanded,
      expandedKey: expandedKey,
      modeKey: modeKey,
      paintOpen: paintOpen,
      textMode: mode == EditorToolMode.text,
      multiSelected: multiSelected,
      selectedLayersForActions: selectedLayersForActions,
      selectedStickerLayer: stickerSelected ? selectedStickerLayer : null,
      selectedImageLayer: imageSelected ? selectedImageLayer : null,
      selectedShapeLayer: shapeSelected ? selectedShapeLayer : null,
    );
  }

  List<EditorLayer> _selectedLayersForActions(
    WidgetRef ref,
    SelectionState selection, {
    bool includeProtectedBase = false,
  }) {
    final doc = ref.watch(documentControllerProvider);
    final out = <EditorLayer>[];
    for (final id in selection.selectedIds) {
      final layer = doc.layerById(id);
      if (layer == null) continue;
      if (!includeProtectedBase && doc.isProtectedBasePhoto(id)) continue;
      out.add(layer);
    }
    return out;
  }

  /// Layers the open [ContextToolPanel] should act on.
  ///
  /// Splits on the panel because the base-photo protection is not
  /// uniform across them: Align moves a layer, which the base photo
  /// must never do, so it only ever sees the actionable list. (Align
  /// was briefly given the base to stop the «تراز» row swallowing its
  /// tap — but that made the panel MOUNT for a layer whose every
  /// align button `AlignmentController` refuses (it bails on
  /// `locked`), turning a vanishing sheet into six buttons that
  /// silently did nothing, which reads as working and is harder to
  /// diagnose. The row is gated off at its source instead
  /// (`layer_overflow_sheet`): the base photo IS the canvas, so
  /// aligning it to the canvas has no meaning.)
  ///
  /// Opacity, by contrast, genuinely applies to the base photo —
  /// fading it toward the canvas background is meaningful, reversible
  /// and non-destructive — but only when the base is what the chrome
  /// claims to target: selected ALONE, where the dock shows the Image
  /// strip with the «عکس پایه» badge (tb15's fix for that strip's
  /// شفافیت dead-end). In a mixed base+layer selection every piece of
  /// chrome counts WITHOUT the base (`_actionableCount` drives the
  /// dock mode and the multi chip; the multi strip's own layer list is
  /// the filtered one), so unconditionally including it handed the
  /// panel one MORE layer than the chrome named and the slider
  /// silently faded the user's photo too (audit P2-4). The rule now:
  /// the panel targets exactly the actionable selection, and falls
  /// back to the base photo only when it is the selection's sole
  /// member — the one state whose chrome names it (contract §10: a
  /// bound control's target is what the surface discloses, never a
  /// silent extra member).
  List<EditorLayer> _layersForContextPanel(
    WidgetRef ref,
    SelectionState selection,
    ContextToolPanel panel,
  ) {
    final actionable = _selectedLayersForActions(ref, selection);
    if (panel != ContextToolPanel.opacity || actionable.isNotEmpty) {
      return actionable;
    }
    return _selectedLayersForActions(
      ref,
      selection,
      includeProtectedBase: true,
    );
  }

  /// Merged-view layer for the selected id, narrowed to the ONE
  /// layer object (tb1 16/17). The old full renderedDocumentProvider
  /// watch re-ran the whole screen build on EVERY overlay preview
  /// tick of ANY layer; selecting layerById keeps panel payloads
  /// live for the layer they show while foreign previews no longer
  /// touch the screen. (The selected layer's own preview ticks still
  /// rebuild — that's the payload updating, by design.)
  EditorLayer? _selectedMergedLayer(WidgetRef ref) {
    final selectedId = ref.watch(
      selectionControllerProvider.select((s) => s.selectedId),
    );
    if (selectedId == null) return null;
    return ref.watch(
      renderedDocumentProvider.select((d) => d.layerById(selectedId)),
    );
  }

  TextLayer? _selectedTextLayer(WidgetRef ref) {
    final layer = _selectedMergedLayer(ref);
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
    final layer = _selectedMergedLayer(ref);
    return layer is ImageLayer ? layer : null;
  }

  /// Selected layer when it's a [ShapeLayer], else `null`. Used to
  /// swap in [ShapeStudioBench] for shape-specific sub-tools.
  ShapeLayer? _selectedShapeLayer(WidgetRef ref) {
    final layer = _selectedMergedLayer(ref);
    return layer is ShapeLayer ? layer : null;
  }

  /// Selected layer when it's an emoji-sticker [TextLayer], else
  /// `null`. Drives the Sticker mode toolbar; normal text layers are
  /// excluded so they continue to route to [TextStudioBench].
  TextLayer? _selectedStickerLayer(WidgetRef ref) {
    final layer = _selectedMergedLayer(ref);
    return (layer is TextLayer && layer.isSticker) ? layer : null;
  }

  Future<void> _startTextInputFlow(BuildContext context, WidgetRef ref) async {
    ref.read(paintToolControllerProvider.notifier).closePanel();
    final textCtrl = ref.read(textToolControllerProvider.notifier);
    // Stage an empty text layer at the visible-viewport centre so the
    // user sees the bounding box appear as soon as the sheet opens —
    // typing then streams content into that staged layer in real time.
    // Cancel / empty input removes it; non-empty input commits a
    // single AddLayerCommand on apply.
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

  /// Canvas-space position for a newly-inserted layer of [size]:
  /// centred on the point of the document the user is currently
  /// looking at — the visible-viewport centre — clamped so the layer
  /// lands fully inside the document whenever it fits (ux-audit
  /// P2-12: the old doc-centre insert dropped new layers off-screen
  /// when the user was zoomed into a corner, and the unchanged canvas
  /// invited duplicate taps). At the default fitted viewport the pane
  /// centre IS the document centre, so untouched viewports keep the
  /// historical geometry exactly. Falls back to the document centre
  /// when no fit has seeded the viewport yet (first frame, tests).
  Offset _insertPositionFor(WidgetRef ref, Size size) {
    final doc = ref.read(documentControllerProvider);
    final docSize = Size(doc.width, doc.height);
    final visible = ref
        .read(viewportControllerProvider.notifier)
        .visibleCanvasRect;
    return ViewportController.insertPositionFor(
      visibleCentre: visible?.center ?? docSize.center(Offset.zero),
      layerSize: size,
      docSize: docSize,
    );
  }

  Future<void> _addImage(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final source = await pickImageSource(context);
    if (source == null || !context.mounted) return;

    final pick = picker.ImagePicker();
    final picker.XFile? picked;
    try {
      picked = await pick.pickImage(
        source: source,
        imageQuality: 92,
        // Longest-side import ceiling — the OS downscales
        // aspect-preserving before the bitmap enters the app. See
        // [EngineConstants.kMaxImportDimension].
        maxWidth: EngineConstants.kMaxImportDimension,
        maxHeight: EngineConstants.kMaxImportDimension,
      );
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
      // Belt-and-braces cap: the picker already downscaled, but the
      // layer geometry derived here must never exceed the ceiling
      // even if a platform path slips past it.
      dims = capImportSize(await resolveImageSize(File(picked.path)));
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
    //
    // A design project claims NOTHING (§10.1). It used to claim the
    // pointer "so Crop / Filters / Adjust resolve cleanly", which is
    // how a design document came to carry a marker that silently
    // aimed those tools at whichever image happened to be imported
    // first, while `isProtectedBasePhoto` — kind-gated — rendered no
    // chrome for it anywhere. Nothing reads the pointer in a design
    // project now, so nothing may write one.
    final claimAsBasePhoto =
        doc.basePhotoLayerId == null && doc.projectKind == ProjectKind.photo;
    final layer = ImageLayer(
      id: id,
      transform: LayerTransform(
        position: _insertPositionFor(ref, fitted),
        size: fitted,
      ),
      source: ImageSource.file(stablePath),
      locked: claimAsBasePhoto,
    );
    if (claimAsBasePhoto) {
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
      transform: LayerTransform(
        position: _insertPositionFor(ref, size),
        size: size,
      ),
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
      case ShapeKind.thoughtBubble:
        // Bubbles read better as a wide rectangle so the body has
        // room for text the user is likely to add on top.
        return const Size(280, 200);
      case ShapeKind.parallelogram:
      case ShapeKind.trapezoid:
      case ShapeKind.cloud:
        // Wide free-form quads / the cloud land in their natural
        // landscape proportion instead of a square.
        return const Size(280, 180);
      case ShapeKind.semicircle:
        // A dome is half a circle — half the height, too.
        return const Size(260, 130);
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
      case ShapeKind.pentagon:
      case ShapeKind.octagon:
      case ShapeKind.rightTriangle:
      case ShapeKind.ring:
      case ShapeKind.sparkle:
      case ShapeKind.seal:
      case ShapeKind.bolt:
      case ShapeKind.shield:
      case ShapeKind.crescent:
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
      transform: LayerTransform(
        position: _insertPositionFor(ref, size),
        size: size,
      ),
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

  /// Resolves the [ImageLayer] a main-strip P-scope command targets
  /// — the protected base photo, or nothing (contract §10.2). There
  /// is no ladder, no fallback to another image and no chooser: see
  /// [resolveRoleTarget].
  ///
  /// Selects the target so the dock's image-mode branch renders
  /// against it; callers snapshot the prior selection first and §4
  /// restores it on exit.
  ///
  /// On `null` the control was unavailable and this shows the
  /// recovery matching the precondition that failed (§10.3) —
  /// unhide for a hidden photo, import for a missing one. Callers
  /// bail.
  ImageLayer? _resolveImageTarget(
    BuildContext context,
    WidgetRef ref, {
    required String actionVerb,
  }) {
    final doc = ref.read(documentControllerProvider);
    final layer = resolveRoleTarget(doc);
    if (layer != null) {
      ref.read(selectionControllerProvider.notifier).select(layer.id);
      return layer;
    }
    // Don't dead-end — offer a one-tap recovery so the user can
    // satisfy the precondition without hunting for the tool that
    // does. The action verb is woven in so each command surfaces as
    // a coherent sentence ("Import a photo to crop").
    final l10n = context.l10n;
    final hidden = roleTargetBlock(doc) == RoleTargetBlock.hidden;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          hidden
              ? l10n.showPhotoToAction(actionVerb)
              : l10n.importPhotoToAction(actionVerb),
        ),
        behavior: SnackBarBehavior.floating,
        // A SnackBar's dismiss timer only starts once its entrance
        // animation completes, and that animation stops advancing
        // when a full-screen route covers the messenger
        // (TickerMode goes false) — which is how one of these was
        // observed still on screen fourteen minutes and three
        // documents later, parked over the crop panel's own
        // controls. No duration can fix a timer that never starts,
        // so the real cure is the `clearSnackBars()` calls at every
        // full-screen entry point; this is just the ordinary
        // Material default, stated rather than inherited.
        duration: const Duration(seconds: 4),
        action: hidden
            ? SnackBarAction(
                label: l10n.showAction,
                // The base photo is hideable from the layers drawer,
                // which is the only way to reach this branch.
                onPressed: () => ref
                    .read(documentControllerProvider.notifier)
                    .execute(
                      SetLayerVisibilityCommand(
                        layerId: doc.basePhotoLayerId!,
                        visible: true,
                      ),
                    ),
              )
            : SnackBarAction(
                label: l10n.addPhotoAction,
                onPressed: () => _addImage(context, ref),
              ),
      ),
    );
    return null;
  }

  /// Opens the centralised [CropModeOverlay] for the P-scope role
  /// target — the protected base photo, or nothing (§10.2).
  ///
  /// We snapshot the **prior** selection BEFORE
  /// [_resolveImageTarget] (which selects the role target so the
  /// dock renders against it) and pass it into
  /// [CropController.openCrop].
  /// On Done/Cancel that snapshot is restored, so opening Crop
  /// from the main toolbar lands the user back on the main toolbar
  /// instead of stranding them in the image sub-tools.
  void _openCrop(BuildContext context, WidgetRef ref) {
    final priorSelectionId = ref.read(selectionControllerProvider).selectedId;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final layer = _resolveImageTarget(
      context,
      ref,
      actionVerb: context.l10n.cropActionVerb,
    );
    if (layer == null) return;
    EditorHaptics.tap();
    // Nothing transient may survive into a full-screen session: it
    // would freeze there (see the duration note above) and it floats
    // exactly where the crop card's own buttons are.
    messenger?.clearSnackBars();
    ref
        .read(cropControllerProvider.notifier)
        .openCrop(layer.id, priorSelectionId: priorSelectionId);
  }

  /// Opens the Look dock panel for the resolved [ImageLayer].
  /// Routing through [imageToolControllerProvider]'s
  /// [ImageToolSlot.look] slot lets the existing image-mode dock
  /// branch render [ImageLookBody] without a parallel code path.
  ///
  /// One entry for what used to be two main-strip tiles (Adjust and
  /// Filters): both channels now live in the same panel (tb4 1/14).
  void _openLook(BuildContext context, WidgetRef ref) {
    // Snapshot BEFORE resolution (which selects the role target) —
    // same prior-selection semantics as [_openCrop], restored when
    // the panel closes (contract §4, tb2 10/16).
    final priorSelectionId = ref.read(selectionControllerProvider).selectedId;
    final layer = _resolveImageTarget(
      context,
      ref,
      actionVerb: context.l10n.lookActionVerb,
    );
    if (layer == null) return;
    EditorHaptics.tap();
    ref
        .read(mainStripImageEntryProvider.notifier)
        .record(
          slot: ImageToolSlot.look,
          targetLayerId: layer.id,
          priorSelectionId: priorSelectionId,
        );
    final ctrl = ref.read(imageToolControllerProvider.notifier);
    if (ref.read(imageToolControllerProvider).openSlot != ImageToolSlot.look) {
      ctrl.toggleSlot(ImageToolSlot.look);
    }
  }
}

/// Fit-to-screen action, shared by the overflow menu item and the
/// app-bar zoom-readout tap target (tb3 7/7) — top-level because both
/// hosts are different widgets and the action owns no widget state.
///
/// Replays the most recent fit the [EditorCanvas] auto-ran, which
/// was sized against its real `LayoutBuilder` constraints — i.e.
/// the actual visible canvas pane (already excludes app bar,
/// bottom dock, FABs, safe areas). Recomputing the pane from
/// `MediaQuery` here would silently disagree with the layout (we
/// don't know the dock height from this seam) and shift the
/// canvas downward. The auto-fit is the source of truth; this
/// action just re-applies it.
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

/// Toggles the Canvas dock panel. Unlike Filters/Adjust, Canvas
/// edits the document itself so it doesn't require a selected
/// layer — we also clear the current selection so the dock falls
/// through to the no-selection branch and renders the panel.
void _openCanvas(WidgetRef ref) {
  EditorHaptics.tap();
  ref.read(selectionControllerProvider.notifier).clear();
  ref.read(canvasToolControllerProvider.notifier).togglePanel();
}

void _fitViewport(BuildContext context, WidgetRef ref) {
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
    unawaited(_autosave?.flushNow(sessionEnding: true) ?? Future<void>.value());
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
  const _DocumentTitle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final size = ref.watch(
      documentControllerProvider.select(
        (EditorDocument d) => Size(d.width, d.height),
      ),
    );
    final scale = ref.watch(viewportControllerProvider.select((v) => v.scale));
    final session = ref.watch(editorSessionProvider);
    final title = session?.name ?? context.l10n.appName;
    final unsaved = session?.projectId == null;

    // Sized to the full toolbar height with the visual block centred
    // inside — pixel-identical to letting the AppBar centre the
    // intrinsic block itself (same (toolbar − block)/2 math), but the
    // extra transparent height is what lets the zoom-readout tap
    // target below reach the 44dp floor without moving a glyph.
    return SizedBox(
      height: kToolbarHeight,
      child: Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [
          Tooltip(
            message: context.l10n.documentMenuTooltip,
            child: InkWell(
              key: const ValueKey('appbar-title-menu'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => _openTitleMenu(context, ref),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary,
                      ),
                    ),
                    // The subtitle has three segments of different
                    // importance, and the old single ellipsised Text
                    // cut whatever ran off the end — which on a
                    // narrow phone was the ZOOM. That is the one
                    // segment that must never be cut: the invisible
                    // fit-to-screen tap target below is pinned to the
                    // trailing end precisely because the zoom lives
                    // there, so a truncated subtitle left a 48×44
                    // button sitting on top of an ellipsis (tb8 1/2).
                    //
                    // The dimensions DROP rather than ellipsise. A
                    // half-rendered number pair ("۱۳… ۱۰۸۰ ×") is
                    // worse than absent — it reads as a wrong number
                    // rather than as missing information, which is
                    // the same failure mode the RTL swap had.
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final values = EditorValueFormat.of(context);
                        final style = Theme.of(context).textTheme.labelSmall!
                            .copyWith(color: tokens.textSecondary);
                        final dims =
                            '${values.dimensions(size.width.toInt(), size.height.toInt())} ';
                        final zoom = values.percent((scale * 100).round());
                        // The bullet joins segments of the SAME kind.
                        // On a narrow phone `dims` drops out (below),
                        // and «ذخیره‌نشده • ٪۱۶» then read as "16%
                        // saved" — a progress bar, not a zoom level.
                        // So the separator is only a bullet when there
                        // is a middle segment to separate, and the zoom
                        // carries its own glyph either way so the
                        // number can never borrow its meaning from the
                        // word next to it.
                        // The zoom glyph is a WidgetSpan, so `textFits`
                        // cannot see it; reserve its 11dp box + 2dp gap
                        // or the measurement says "fits", the icon is
                        // drawn, and the zoom itself ellipsises away —
                        // the exact segment the fit-to-screen tap
                        // target below is pinned to.
                        const zoomGlyphWidth = 13.0;
                        final fitsDims = textFits(
                          context,
                          unsaved
                              ? '${context.l10n.unsavedBadge} • $dims$zoom'
                              : '$dims$zoom',
                          style: style,
                          maxWidth: constraints.maxWidth - zoomGlyphWidth,
                        );
                        final badge = unsaved
                            ? '${context.l10n.unsavedBadge}${fitsDims ? ' • ' : '  '}'
                            : '';
                        final fits = fitsDims;
                        return Text.rich(
                          TextSpan(
                            children: [
                              // Dirty state, said once: a document
                              // that has never been saved lives only
                              // in the crash journal, and nothing in
                              // the old top bar admitted that. Once
                              // it IS a project, autosave keeps it
                              // current and the badge disappears
                              // rather than blinking on every
                              // keystroke.
                              if (unsaved)
                                TextSpan(
                                  text: badge,
                                  style: TextStyle(
                                    // Glyph stop. accentDeep measured
                                    // 3.88:1 on cream at 11sp w700 —
                                    // normal text, so 4.5:1 applies.
                                    color: tokens.accentText,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              if (fits) TextSpan(text: dims),
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    end: 2,
                                  ),
                                  child: Icon(
                                    AppIcons.fitToScreen,
                                    size: 11,
                                    color: tokens.textSecondary,
                                  ),
                                ),
                              ),
                              // Own LTR run so the `٪` lands on the
                              // same side of the digits as every other
                              // readout in the app (dock tiles, slider
                              // rows). As a bare TextSpan it inherited
                              // this RTL paragraph and painted «٪۱۶»
                              // while the dock painted «۱۰۰٪».
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: Text(zoom, style: style),
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: style,
                          semanticsLabel: [
                            if (unsaved) context.l10n.unsavedBadge,
                            if (fits)
                              values.dimensionsPlain(
                                size.width.toInt(),
                                size.height.toInt(),
                              ),
                            '${context.l10n.editorFitToScreen} $zoom',
                          ].join(' · '),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Invisible fit-to-screen target over the zoom% readout
          // (tb3 7/7): the subtitle's trailing end IS the zoom value,
          // so a 48×44 hit box pinned bottom-end covers it — meeting
          // the 44dp floor without adding a single visible pixel. Tap
          // = fit-to-screen, same seam as the overflow item (which
          // stays for discoverability). Deliberately tap-only: no
          // long-press-for-100% — one hidden gesture on a readout is
          // discoverable, two is a lottery. Trade-off: the box also
          // overlaps the trailing ~48px of the title line, where
          // rename loses to fit — the title text itself (leading)
          // keeps the rename tap.
          PositionedDirectional(
            end: 0,
            bottom: 0,
            child: Semantics(
              button: true,
              label: context.l10n.editorFitToScreen,
              child: GestureDetector(
                key: const ValueKey('appbar-zoom-fit-target'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _fitViewport(context, ref),
                child: const SizedBox(width: 48, height: 44),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The document's own menu, hung off its name in the top bar.
  ///
  /// Rename, Resize, Fit and Save all act on the DOCUMENT rather than
  /// on a layer, and they were previously split between an anonymous
  /// «⋮» and a tap on the title that only ever renamed. Putting them
  /// together under the thing they operate on is the whole point:
  /// the title is the document.
  Future<void> _openTitleMenu(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final tokens = AppTokens.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final topStart = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomEnd = box.localToGlobal(
      box.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final action = await showMenu<_DocumentAction>(
      context: context,
      color: tokens.surface,
      position: RelativeRect.fromLTRB(
        topStart.dx,
        bottomEnd.dy,
        overlay.size.width - bottomEnd.dx,
        0,
      ),
      items: [
        _menuItem(
          _DocumentAction.rename,
          AppIcons.rename,
          l10n.renameAction,
          tokens,
        ),
        _menuItem(
          _DocumentAction.resize,
          AppIcons.canvasSize,
          l10n.resizeCanvasAction,
          tokens,
        ),
        _menuItem(
          _DocumentAction.fit,
          AppIcons.fitToScreen,
          l10n.editorFitToScreen,
          tokens,
        ),
        const PopupMenuDivider(),
        _menuItem(
          _DocumentAction.history,
          AppIcons.history,
          l10n.documentHistoryAction,
          tokens,
        ),
        _menuItem(
          _DocumentAction.save,
          AppIcons.saveProject,
          l10n.editorSaveProject,
          tokens,
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _DocumentAction.rename:
        await _renameFlow(context, ref);
      case _DocumentAction.resize:
        _openCanvas(ref);
      case _DocumentAction.fit:
        _fitViewport(context, ref);
      case _DocumentAction.history:
        await showHistoryBrowser(context, ref);
      case _DocumentAction.save:
        await _saveProject(context, ref);
    }
  }

  /// Same dialog contract as the Projects grid rename: prefilled
  /// name, empty/no-op guarded. Renames the live session so the top
  /// bar updates immediately; a persisted project is renamed in the
  /// store too so the change survives without an explicit re-save.
  Future<void> _renameFlow(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final session = ref.read(editorSessionProvider);
    final controller = TextEditingController(
      text: session?.name ?? l10n.appName,
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.renameProjectTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.projectNameLabel),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.saveAction),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    if (name == session?.name) return;
    ref.read(editorSessionProvider.notifier).state =
        session?.copyWith(name: name) ?? EditorSession(name: name);
    final projectId = session?.projectId;
    if (projectId != null) {
      await ref.read(projectStoreProvider.notifier).rename(projectId, name);
    }
  }
}

/// Everything [_resolveDock] hands the dock + scrim. The `selected*`
/// layer fields are pre-gated to the mode that owns the chip strip
/// (null otherwise), so the dock child picks its toolbar by simple
/// null checks in priority order.
typedef _DockResolution = ({
  Widget? expanded,
  Object? expandedKey,
  String modeKey,
  bool paintOpen,
  bool textMode,
  bool multiSelected,
  List<EditorLayer> selectedLayersForActions,
  TextLayer? selectedStickerLayer,
  ImageLayer? selectedImageLayer,
  ShapeLayer? selectedShapeLayer,
});

/// Undo/redo, promoted into the top bar (v2): the two most-used
/// commands sit beside Export instead of floating over the canvas,
/// freeing the workspace for the document itself.
///
/// Each button disables (theme-dimmed) when its action is
/// unavailable instead of disappearing — keeps the bar's footprint
/// stable so muscle memory holds across edit states.
class _UndoRedoActions extends ConsumerWidget {
  const _UndoRedoActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Undo/redo button enable state only changes on real commits —
    // never on overlay previews. Subscribe to the commit counter so
    // a 60-fps slider drag doesn't repaint these buttons.
    ref.watch(documentCommitVersionProvider);
    final doc = ref.read(documentControllerProvider.notifier);
    // Contract §6: while any draft session is open (text compose /
    // edit, export render+save — crop and mask unmount this AppBar
    // entirely) history must not mutate under the session, so the
    // buttons go visibly inert instead of firing through a sheet's
    // scrim.
    final sessionOpen = ref.watch(anyDraftSessionOpenProvider);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: context.l10n.undoTooltip,
          onPressed: (!sessionOpen && doc.canUndo)
              ? () {
                  EditorHaptics.tap();
                  doc.undo();
                }
              : null,
          icon: const Icon(AppIcons.undo),
        ),
        IconButton(
          tooltip: context.l10n.redoTooltip,
          onPressed: (!sessionOpen && doc.canRedo)
              ? () {
                  EditorHaptics.tap();
                  doc.redo();
                }
              : null,
          icon: const Icon(AppIcons.redo),
        ),
      ],
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
    // ONE mode derivation (tb6 4/5): this pill used to re-derive its
    // own `inMode` from paint/text `panelOpen` — a second ladder
    // beside `editorToolModeProvider`, and one that disagreed with it
    // about text (the provider keys on the add-composer, the pill
    // keyed on the sheet). Two ladders drift; that is the whole
    // reason tb1 collapsed the original three. The pill now reads the
    // provider and adds exactly one rule of its own, below.
    final mode = ref.watch(editorToolModeProvider);
    final selectionId = ref.watch(
      selectionControllerProvider.select((s) => s.selectedId),
    );
    // COMMITTED doc, narrowly selected (tb1 16/17): the pill only
    // needs the protection flag of the selected layer — a fact that
    // changes on commits, never on 60fps overlay preview ticks. The
    // old full renderedDocumentProvider watch made this pill (and
    // with it the screen-level Positioned subtree) rebuild every
    // preview frame.
    final isProtectedBase = ref.watch(
      documentControllerProvider.select(
        (d) => selectionId != null && d.isProtectedBasePhoto(selectionId),
      ),
    );
    // The pill's ONE additional rule: the protected base photo (photo
    // project) is the canvas itself — intentionally selectable for
    // tool targeting, but it never shows object-selection chrome
    // (frame, quick actions). Done belongs to that chrome family, so
    // it is suppressed there even though the mode ladder correctly
    // reports `image`. Every other non-idle mode shows the pill.
    if (mode == EditorToolMode.idle || isProtectedBase) {
      return const SizedBox.shrink();
    }

    // Single canonical verb: every commit / dismiss path on the
    // canvas is "Done". Avoids Hick's-law confusion from flipping
    // between "Done" and "Deselect" for the same affordance.
    //
    // ONE lifecycle call (contract §4, tb2 10/16): the pill is E2
    // and E2 implies E1, so it must close EVERY open panel — the
    // hand-rolled paint/text closes it used to carry missed the
    // canvas panel and the object openSlot panels, which is what
    // let the canvas panel resurrect after a Done-tap deselect.
    // `dismissActiveEditing` is exactly the E3 scope (E1+E2+clear
    // selection). Crop/mask are safe: the pill never renders in
    // those modes (guarded at the mount site) and the seam's
    // mask-cancel is an idempotent no-op when no session is open.
    return ModeDoneButton(onPressed: () => dismissActiveEditing(ref));
  }
}

/// The four document-level actions behind the title.
enum _DocumentAction { rename, resize, fit, history, save }

PopupMenuItem<_DocumentAction> _menuItem(
  _DocumentAction value,
  IconData icon,
  String label,
  AppTokens tokens,
) => PopupMenuItem<_DocumentAction>(
  value: value,
  child: ListTile(
    leading: Icon(icon),
    iconColor: tokens.textSecondary,
    textColor: tokens.textPrimary,
    title: Text(label),
    contentPadding: EdgeInsets.zero,
  ),
);
