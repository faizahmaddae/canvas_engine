import 'package:flutter/material.dart';

import '../../../../l10n/l10n.dart';
import '../../engine/commands/shape_commands.dart';
import '../../engine/modules/shape/shape_layer.dart';
import '../../presentation/widgets/layer_border_body.dart';
import 'shape_panel_shell.dart';
import '../../../../app/theme/app_icons.dart';

/// Expanded panel body for the Shape sub-tool's "Border" tab.
///
/// Thin [BorderPanelAdapter] wiring around the shared
/// [LayerBorderBody] (Phase 4 plan §4.2): 4 thickness chips (None /
/// Thin / Medium / Bold) + a colour swatch row, both committed via
/// [SetShapeStrokeCommand]. Picking a colour while the stroke is
/// currently `None` auto-promotes width to medium so the user sees
/// their pick land instead of nothing happening.
///
/// Stroked shape kinds (line/arrow) reuse `strokeWidth` for line
/// thickness with colour coming from `fillColor` instead — for
/// those kinds this panel shows thickness only (no "None" chip, no
/// Colour section), expressed via [BorderPanelAdapter.isStrokedKind].
class ShapeBorderBody extends StatelessWidget {
  const ShapeBorderBody({super.key, required this.layer});

  final ShapeLayer layer;

  @override
  Widget build(BuildContext context) {
    return LayerBorderBody<ShapeLayer>(
      layer: layer,
      adapter: BorderPanelAdapter<ShapeLayer>(
        command:
            ({
              required layerId,
              color,
              clearColor = false,
              width,
              live = false,
            }) => SetShapeStrokeCommand(
              layerId: layerId,
              color: color,
              clearColor: clearColor,
              width: width,
              live: live,
            ),
        read: (l) => (color: l.strokeColor, width: l.strokeWidth),
        hasColor: (l) => l.strokeColor != null,
        isStrokedKind: (l) => isStrokedShapeKind(l.kind),
        colorToPromote: (l) => isStrokedShapeKind(l.kind)
            ? null
            : (l.strokeColor ?? const Color(0xFF000000)),
        shell: ({required child}) => ShapePanelShell(
          title: context.l10n.borderTool,
          icon: AppIcons.borderTool,
          child: child,
        ),
      ),
    );
  }
}
