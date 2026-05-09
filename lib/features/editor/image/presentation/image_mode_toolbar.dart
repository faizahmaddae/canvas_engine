import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' as picker;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/utils/haptics.dart';
import '../../application/document_controller.dart';
import '../../application/selection_controller.dart';
import '../../crop/application/crop_controller.dart';
import '../../engine/commands/image_commands.dart';
import '../../engine/modules/image/image_layer.dart';
import '../../toolbar/domain/toolbar_slot.dart';
import '../../toolbar/presentation/slot_strip.dart';
import '../application/image_tool_controller.dart';

const _uuid = Uuid();

// Strip order and panel-vs-non-panel classification now live on
// [ImageToolSlot]. Use `ImageToolSlot.values` for the strip order
// and `kImagePanelSlotOrder` for the swipe-eligible subset.

/// Bottom toolbar shown when an [ImageLayer] is the current
/// selection. Same dock grammar as the text/paint mode toolbars
/// (shared `SlotStrip` → `DockToolTile`) so the active tab gets the
/// soft-primary tint + ring + glow treatment automatically.
///
/// Phase 1 wires only the **Replace** tab to a real action (re-uses
/// `image_picker`). The remaining tabs (Style, Crop, Shape, Border,
/// Shadow, Adjust) are visible but disabled until their
/// implementations land — this keeps the surface discoverable
/// without shipping snackbar placeholders that pretend to do
/// something.
class ImageModeToolbar extends ConsumerWidget {
  const ImageModeToolbar({super.key, required this.layer});

  final ImageLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openSlot = ref.watch(
      imageToolControllerProvider.select((s) => s.openSlot),
    );
    final imageCtrl = ref.read(imageToolControllerProvider.notifier);
    final slots = <ToolbarSlot>[
      ToolbarSlot(
        id: ImageToolSlot.style.name,
        icon: Icons.auto_awesome_outlined,
        label: 'Style',
        onTap: () => imageCtrl.toggleSlot(ImageToolSlot.style),
      ),
      ToolbarSlot(
        id: ImageToolSlot.crop.name,
        icon: Icons.crop_rotate_rounded,
        label: 'Crop',
        // Crop is a full-screen mode — it does NOT toggle the
        // dock's expanded slot. Instead we open the centralised
        // [CropModeOverlay] which is the same surface launched
        // by the main toolbar's Crop button.
        onTap: () {
          EditorHaptics.tap();
          // Close any other open dock slot first so leaving crop
          // mode doesn't reveal a stale panel.
          imageCtrl.closePanel();
          // Crop was launched from the image sub-tools, so the
          // user clearly wants the image to remain selected after
          // Done — preserve the existing selection across the crop
          // session.
          ref.read(cropControllerProvider.notifier).openCrop(
                layer.id,
                priorSelectionId: layer.id,
              );
        },
      ),
      ToolbarSlot(
        id: ImageToolSlot.shape.name,
        icon: Icons.crop_square_rounded,
        label: 'Shape',
        onTap: () => imageCtrl.toggleSlot(ImageToolSlot.shape),
      ),
      ToolbarSlot(
        id: ImageToolSlot.border.name,
        icon: Icons.border_outer_rounded,
        label: 'Border',
        onTap: () => imageCtrl.toggleSlot(ImageToolSlot.border),
      ),
      ToolbarSlot(
        id: ImageToolSlot.shadow.name,
        icon: Icons.layers_outlined,
        label: 'Shadow',
        onTap: () => imageCtrl.toggleSlot(ImageToolSlot.shadow),
      ),
      ToolbarSlot(
        id: ImageToolSlot.adjust.name,
        icon: Icons.tune_rounded,
        label: 'Adjust',
        onTap: () => imageCtrl.toggleSlot(ImageToolSlot.adjust),
      ),
      ToolbarSlot(
        id: ImageToolSlot.filters.name,
        icon: Icons.auto_fix_high_outlined,
        label: 'Filters',
        onTap: () => imageCtrl.toggleSlot(ImageToolSlot.filters),
      ),
      ToolbarSlot(
        id: ImageToolSlot.replace.name,
        icon: Icons.swap_horiz_rounded,
        label: 'Replace',
        onTap: () => _replace(context, ref),
      ),
    ];
    return SlotStrip(slots: slots, activeId: openSlot?.name);
  }

  Future<void> _replace(BuildContext context, WidgetRef ref) async {
    EditorHaptics.tap();
    final source = await _pickImageSource(context);
    if (source == null || !context.mounted) return;

    final pick = picker.ImagePicker();
    final picker.XFile? picked;
    try {
      picked = await pick.pickImage(source: source, imageQuality: 92);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not pick image: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (picked == null) return;

    final stable = await _persistPickedImage(picked.path);
    ref.read(documentControllerProvider.notifier).execute(
          ReplaceImageSourceCommand(
            layerId: layer.id,
            source: ImageSource.file(stable),
          ),
        );
    // Keep the same layer selected so the user stays in the Image
    // sub-tool after replace.
    ref.read(selectionControllerProvider.notifier).select(layer.id);
  }

  Future<picker.ImageSource?> _pickImageSource(BuildContext context) {
    return showModalBottomSheet<picker.ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Gallery'),
                onTap: () {
                  EditorHaptics.tap();
                  Navigator.pop(ctx, picker.ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Camera'),
                onTap: () {
                  EditorHaptics.tap();
                  Navigator.pop(ctx, picker.ImageSource.camera);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// Mirror of `_addImage`'s persistence step: copy out of the temp
  /// picker dir into app-documents so the path survives restart.
  Future<String> _persistPickedImage(String tempPath) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/imported_images');
    if (!await folder.exists()) await folder.create(recursive: true);
    final ext = tempPath.contains('.')
        ? tempPath.substring(tempPath.lastIndexOf('.'))
        : '.png';
    final dest = '${folder.path}/${_uuid.v4()}$ext';
    await File(tempPath).copy(dest);
    return dest;
  }
}
