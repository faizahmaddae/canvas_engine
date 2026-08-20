// Extracted verbatim from paint_mode_toolbar.dart (tb1 4/17); behaviour-preserving.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/paint_tool_controller.dart';
import '../paint_size_body.dart';

/// Paint Size body wrapper — thin Riverpod adapter around the
/// shared `PaintSizeBody`. Source values come from the style view
/// (selected layer, else session defaults);
/// ticks route through `previewStrokeWidth` and each commit (chip
/// tap or drag end) through `commitStrokeWidth`, so the overlay
/// preview channel and selected-layer mirroring stay in the
/// controller (contract §2).
/// (The stale "Fill body" doc fragment that used to sit above this
/// wrapper — a pre-split leftover — died with the dash plumbing.)
class PaintSizeEntryBody extends ConsumerWidget {
  const PaintSizeEntryBody({super.key, required this.view});

  final PaintStyleView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    // Contract §2 (tb2 3/16): ticks preview (session + overlay when
    // a layer is selected), the chip tap / drag end commits ONE
    // undoable command via the controller.
    return PaintSizeBody(
      value: view.strokeWidth,
      color: view.strokeColor,
      onPreview: ctrl.previewStrokeWidth,
      onCommit: ctrl.commitStrokeWidth,
    );
  }
}
