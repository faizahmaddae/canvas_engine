import 'package:flutter/material.dart';

import '../../../../l10n/l10n.dart';
import '../../engine/commands/image_commands.dart';
import '../../engine/modules/image/image_layer.dart';
import '../../presentation/widgets/layer_shadow_body.dart';
import 'image_panel_shell.dart';

/// Expanded panel body for the Image sub-tool's "Shadow" tab.
///
/// Thin [ShadowPanelAdapter] wiring around the shared
/// [LayerShadowBody] (Phase 4 plan §4.1) — mirrors [ShapeShadowBody]
/// one-to-one so users only learn the shadow grammar once.
class ImageShadowBody extends StatelessWidget {
  const ImageShadowBody({super.key, required this.layer});

  final ImageLayer layer;

  @override
  Widget build(BuildContext context) {
    return LayerShadowBody<ImageLayer>(
      layer: layer,
      adapter: ShadowPanelAdapter<ImageLayer>(
        command:
            ({required layerId, color, blur, offset, opacity, live = false}) =>
                SetImageShadowCommand(
                  layerId: layerId,
                  color: color,
                  blur: blur,
                  offset: offset,
                  opacity: opacity,
                  live: live,
                ),
        read: (l) => (
          color: l.shadowColor,
          blur: l.shadowBlur,
          offset: l.shadowOffset,
          opacity: l.shadowOpacity,
        ),
        shell: ({required child}) => ImagePanelShell(
          title: context.l10n.shadowTool,
          icon: Icons.layers_outlined,
          child: child,
        ),
      ),
    );
  }
}
