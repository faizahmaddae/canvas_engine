// Extracted verbatim from paint_mode_toolbar.dart (tb1 4/17); behaviour-preserving.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/paint_tool_controller.dart';
import '../paint_size_body.dart';

/// Fill body — toggle row + colour swatch grid. Enables/disables
/// fill while preserving the last-used fill colour.
/// Paint Size body wrapper — thin Riverpod adapter around the
/// shared `PaintSizeBody`. Source values come from the session;
/// commits route through `setStrokeWidth` so undo coalescing
/// (`UpdatePaintStyleCommand.mergeWith`) and selected-layer
/// mirroring stay verbatim.
class PaintSizeEntryBody extends ConsumerWidget {
  const PaintSizeEntryBody({super.key, required this.session});

  final PaintSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    return PaintSizeBody(
      value: session.strokeWidth,
      color: session.strokeColor,
      dashPattern: session.dashPattern,
      onChange: ctrl.setStrokeWidth,
    );
  }
}
