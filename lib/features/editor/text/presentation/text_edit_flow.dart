import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
import '../../engine/modules/text/text_layer.dart';
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
  final result = await showTextInputFlowSheet(
    context,
    initial: layer.content,
    title: l10n.editTextAction,
    confirmLabel: l10n.applyAction,
    textDirectionMode: layer.textDirectionMode,
    onLiveChange: ctrl.previewContent,
  );
  if (result == null) {
    ctrl.cancelLiveEdit();
  } else {
    ctrl.commitLiveEdit(result);
  }
}
