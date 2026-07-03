import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ContextToolPanel { align, opacity }

class ContextToolbarController extends Notifier<ContextToolPanel?> {
  @override
  ContextToolPanel? build() => null;

  void open(ContextToolPanel panel) {
    if (state == panel) return;
    state = panel;
  }

  void toggle(ContextToolPanel panel) {
    state = state == panel ? null : panel;
  }

  void closePanel() {
    if (state == null) return;
    state = null;
  }
}

final contextToolbarControllerProvider =
    NotifierProvider<ContextToolbarController, ContextToolPanel?>(
      ContextToolbarController.new,
    );
