import 'package:flutter/material.dart';

import '../../../../l10n/l10n.dart';
import '../../engine/commands/image_commands.dart';
import '../../engine/modules/image/image_layer.dart';
import '../../presentation/widgets/layer_border_body.dart';
import 'image_panel_shell.dart';

/// Expanded panel body for the Image sub-tool's "Border" tab.
///
/// Thin [BorderPanelAdapter] wiring around the shared
/// [LayerBorderBody] (Phase 4 plan §4.2). Unlike the Shape border
/// panel, `borderColor` is always set (no clear-colour / stroked-
/// kind gating), and this panel additionally exposes a precision
/// slider under the "Adjust precisely" disclosure
/// ([BorderPanelAdapter.showPrecisionSlider]).
class ImageBorderBody extends StatelessWidget {
  const ImageBorderBody({super.key, required this.layer});

  final ImageLayer layer;

  @override
  Widget build(BuildContext context) {
    return LayerBorderBody<ImageLayer>(
      layer: layer,
      adapter: BorderPanelAdapter<ImageLayer>(
        command: ({
          required layerId,
          color,
          clearColor = false,
          width,
          live = false,
        }) => SetImageBorderCommand(
          layerId: layerId,
          color: color,
          width: width,
          live: live,
        ),
        read: (l) => (color: l.borderColor, width: l.borderWidth),
        hasColor: (_) => true,
        showPrecisionSlider: true,
        shell: ({required child}) => ImagePanelShell(
          title: context.l10n.borderTool,
          icon: Icons.border_outer_rounded,
          child: child,
        ),
      ),
    );
  }
}
