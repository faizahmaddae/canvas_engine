import 'package:flutter/material.dart';

import '../../../../l10n/l10n.dart';
import '../../engine/commands/shape_commands.dart';
import '../../engine/modules/shape/shape_layer.dart';
import '../../presentation/widgets/layer_shadow_body.dart';
import 'shape_panel_shell.dart';

/// Expanded panel body for the Shape sub-tool's "Shadow" tab.
///
/// Thin [ShadowPanelAdapter] wiring around the shared
/// [LayerShadowBody] (Phase 4 plan §4.1) — mirrors [ImageShadowBody]
/// one-to-one so users only learn the shadow grammar once.
class ShapeShadowBody extends StatelessWidget {
  const ShapeShadowBody({super.key, required this.layer});

  final ShapeLayer layer;

  @override
  Widget build(BuildContext context) {
    return LayerShadowBody<ShapeLayer>(
      layer: layer,
      adapter: ShadowPanelAdapter<ShapeLayer>(
        command: ({
          required layerId,
          color,
          blur,
          offset,
          opacity,
          live = false,
        }) => SetShapeShadowCommand(
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
        shell: ({required child}) => ShapePanelShell(
          title: context.l10n.shadowTool,
          icon: Icons.layers_outlined,
          child: child,
        ),
      ),
    );
  }
}
