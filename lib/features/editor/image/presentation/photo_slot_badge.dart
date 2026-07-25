// On-canvas affordance for template photo slots (roadmap 4.11).
//
// A template ships its photo area as an ordinary [ImageLayer] pointing
// at bundled placeholder pixels. Without a cue, that art reads as
// "part of the design" rather than "your photo goes here", so the
// slot silently survives into the export. This badge is the cue.
//
// It is deliberately NOT a second replace path: the tap routes into
// the same [replaceImageLayer] flow the Image mode toolbar uses, so
// the gallery/camera sheet, the import ceiling, the persisted-file
// copy, and the single [ReplaceImageSourceCommand] undo entry are all
// shared. Once the source is a file the predicate goes false and the
// badge disappears on the next frame — no separate state to clear.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../l10n/l10n.dart';
import '../../../templates/domain/template_placeholder.dart';
import '../../application/canvas_chrome_visibility.dart';
import '../../application/interaction_controller.dart';
import '../../application/selection_controller.dart';
import '../../engine/core/editor_layer.dart';
import '../../engine/core/viewport_state.dart';
import '../../engine/modules/image/image_layer.dart';
import 'image_replace_flow.dart';
import '../../../../app/theme/app_icons.dart';

/// Screen-space badges for every unfilled photo slot in [layers].
///
/// Lives in the canvas's screen-space chrome stack (outside the
/// viewport transform) so the pill keeps its readable size at any zoom
/// — only its anchor moves. Selection-independent on purpose: the
/// point is that a user who has never tapped the slot still sees it.
class PhotoSlotBadges extends ConsumerWidget {
  const PhotoSlotBadges({
    super.key,
    required this.layers,
    required this.viewport,
  });

  final List<EditorLayer> layers;
  final ViewportState viewport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Same suppression signals the quick capsule honours: while the
    // user is transforming something, or the canvas has asked for a
    // clean frame (capture/preview), chrome gets out of the way.
    if (ref.watch(canvasChromeSuppressedProvider)) {
      return const SizedBox.shrink();
    }
    if (ref.watch(interactionControllerProvider.select((s) => s.isActive))) {
      return const SizedBox.shrink();
    }

    final badges = <Widget>[];
    for (final layer in layers) {
      if (!layer.visible || layer.locked) continue;
      if (!isTemplatePlaceholderImage(layer)) continue;
      // Rotation is irrelevant to the anchor: a rectangle's centre is
      // invariant under rotation about that centre.
      final anchor =
          layer.transform.center * viewport.scale + viewport.translation;
      badges.add(
        Positioned(
          left: anchor.dx,
          top: anchor.dy,
          child: FractionalTranslation(
            translation: const Offset(-0.5, -0.5),
            child: _PhotoSlotBadge(layer: layer as ImageLayer),
          ),
        ),
      );
    }
    if (badges.isEmpty) return const SizedBox.shrink();
    return Stack(clipBehavior: Clip.none, children: badges);
  }
}

/// The pill itself. Token-styled and direction-agnostic — the [Row]
/// resolves against the ambient [Directionality], so the icon sits on
/// the leading edge in both RTL and LTR.
class _PhotoSlotBadge extends ConsumerWidget {
  const _PhotoSlotBadge({required this.layer});

  final ImageLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final label = context.l10n.photoSlotTapToReplace;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('photo-slot-badge-${layer.id}'),
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            // Select first so the bottom bar switches to Image tools
            // behind the sheet — the badge is an accelerator into the
            // normal selected-image workflow, not a bypass of it.
            ref.read(selectionControllerProvider.notifier).select(layer.id);
            replaceImageLayer(
              context,
              ref,
              layer,
              debugLabel: 'image/photoSlotBadge',
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: tokens.brand.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.photoTool, size: 16, color: tokens.onBrand),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: tokens.onBrand,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
