// Extracted verbatim from paint_mode_toolbar.dart (tb1 4/17); behaviour-preserving.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../l10n/l10n.dart';
import '../../../../color_picker/presentation/color_picker_sheet.dart';
import '../../application/paint_tool_controller.dart';

/// Stroke-colour body — the shared two-level picker, embedded so
/// it is the identical surface to the text colour body.
class PaintColorBody extends ConsumerWidget {
  const PaintColorBody({super.key, required this.current});

  final Color current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    // The shared two-level picker, embedded. Alpha preservation and
    // recents bookkeeping live inside the picker. Contract §2
    // (tb2 4/16): changes preview through the controller's stroke-
    // colour channel and onCommitted seals ONE undoable command.
    return ColorPickerBody(
      initial: current,
      title: context.l10n.strokeColorTitle,
      onChanged: ctrl.previewStrokeColor,
      onCommitted: (_) => ctrl.commitStrokeColor(),
    );
  }
}
