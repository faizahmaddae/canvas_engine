import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
import '../../engine/modules/text/text_layer.dart';
import '../application/add_text_composer_state.dart';
import '../application/text_tool_controller.dart';
import 'text_input_flow_sheet.dart';

Future<void> showEditTextLayerFlow(
  BuildContext context,
  WidgetRef ref,
  TextLayer layer,
) async {
  final l10n = context.l10n;
  final ctrl = ref.read(textToolControllerProvider.notifier);
  ctrl.beginEditText();
  // Session-registry flag (contract §6): the edit flow is a draft
  // session exactly like the add composer — while the sheet is up,
  // undo affordances go inert so history can't mutate the document
  // under the live session. Reset in `finally` so a thrown error or
  // unexpected pop can never leave the registry stuck open.
  final flowFlag = ref.read(textEditFlowOpenProvider.notifier);
  flowFlag.setOpen(true);
  final String? result;
  try {
    result = await showTextInputFlowSheet(
      context,
      initial: layer.content,
      title: l10n.editTextAction,
      confirmLabel: l10n.applyAction,
      textDirectionMode: layer.textDirectionMode,
      onLiveChange: ctrl.previewContent,
    );
  } finally {
    flowFlag.setOpen(false);
  }
  if (result == null) {
    ctrl.cancelLiveEdit();
  } else {
    ctrl.commitLiveEdit(result);
  }
}
