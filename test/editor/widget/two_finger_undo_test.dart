// Pointer-level safety net for the multi-finger undo/redo shortcut
// (toolbar redesign roadmap tb1, Stage 1 item 1.1). Drives real
// simultaneous pointers against a pumped EditorScreen and pins the
// CURRENT contract of the outer Listener in editor_canvas.dart: a
// clean 2-finger tap on the canvas fires exactly one undo and a
// 3-finger tap fires redo — but ONLY when the opt-in
// `multiFingerUndoRedoEnabled` setting is on. The abort conditions
// are pinned too: any pointer moving beyond kTouchSlop turns the
// sequence into a pan/pinch (no undo), a peak of more than three
// fingers aborts, and a sequence slower than 250ms wall-clock is a
// deliberate gesture, not a tap. Later toolbar/mode refactors must
// keep this matrix intact. tb2 13/16 adds the session-registry gate
// (contract §6): the shortcut is inert while any draft session is
// open — pinned here through a live mask-edit session.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/mask_edit_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:canvas_engine/features/settings/application/settings_controller.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Pumps EditorScreen with a 1080² document holding ONE committed
  /// layer (a single AddLayerCommand in history) and nothing
  /// selected. [enabled] toggles the opt-in multi-finger setting via
  /// a provider override; the default (no override) mirrors the real
  /// default of `false`.
  Future<ProviderContainer> pumpEditor(
    WidgetTester tester, {
    required bool enabled,
  }) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final container = ProviderContainer(
      overrides: [
        if (enabled)
          appSettingsProvider.overrideWithValue(
            const AppSettings(multiFingerUndoRedoEnabled: true),
          ),
      ],
    );
    addTearDown(container.dispose);
    final ctrl = container.read(documentControllerProvider.notifier);
    ctrl.newDocument(width: 1080, height: 1080);
    ctrl.execute(
      AddLayerCommand(
        ShapeLayer(
          id: 'shape-1',
          transform: const LayerTransform(
            position: Offset(40, 40),
            size: Size(200, 200),
          ),
          kind: ShapeKind.rectangle,
        ),
      ),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('fa'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const EditorScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  /// Anchor for the tap fingers: low in the canvas pane, away from
  /// the seeded layer (which sits near the board's top-left).
  Offset tapAnchor(WidgetTester tester) {
    final rect = tester.getRect(find.byType(EditorCanvas));
    return Offset(rect.center.dx, rect.bottom - 120);
  }

  /// Puts [count] fingers down around [anchor], optionally moves the
  /// first one by [moveFirstBy], then lifts them all. No pumps
  /// between down and up so the sequence stays well inside the
  /// 250ms wall-clock tap window the canvas enforces.
  Future<void> multiFingerTap(
    WidgetTester tester,
    Offset anchor,
    int count, {
    Offset moveFirstBy = Offset.zero,
  }) async {
    final gestures = <TestGesture>[];
    for (var i = 0; i < count; i++) {
      gestures.add(await tester.startGesture(anchor + Offset(30.0 * i, 0)));
    }
    if (moveFirstBy != Offset.zero) {
      await gestures.first.moveBy(moveFirstBy);
    }
    for (final g in gestures) {
      await g.up();
    }
    await tester.pump();
    // The canvas root GestureDetector owns onDoubleTapDown, so every
    // tap arms a 300ms double-tap-window timer; pump past it or the
    // test ends with pending timers.
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('two-finger tap fires exactly one undo when enabled', (
    tester,
  ) async {
    final container = await pumpEditor(tester, enabled: true);
    expect(container.read(documentControllerProvider).layers, hasLength(1));

    await multiFingerTap(tester, tapAnchor(tester), 2);

    final docCtl = container.read(documentControllerProvider.notifier);
    expect(
      container.read(documentControllerProvider).layers,
      isEmpty,
      reason: 'two-finger tap must undo the AddLayerCommand',
    );
    // Exactly ONE undo: history is now at the very start with the
    // add available to redo.
    expect(docCtl.canUndo, isFalse);
    expect(docCtl.canRedo, isTrue);
  });

  testWidgets('three-finger tap fires redo after an undo when enabled', (
    tester,
  ) async {
    final container = await pumpEditor(tester, enabled: true);
    container.read(documentControllerProvider.notifier).undo();
    await tester.pump();
    expect(container.read(documentControllerProvider).layers, isEmpty);

    await multiFingerTap(tester, tapAnchor(tester), 3);

    expect(
      container.read(documentControllerProvider).layers,
      hasLength(1),
      reason: 'three-finger tap must redo the undone AddLayerCommand',
    );
    expect(
      container.read(documentControllerProvider).layerById('shape-1'),
      isNotNull,
    );
  });

  testWidgets('two-finger tap is inert when the setting is disabled', (
    tester,
  ) async {
    // No override: the real default (multiFingerUndoRedoEnabled:
    // false) applies, and every pointer-down aborts the tap window.
    final container = await pumpEditor(tester, enabled: false);

    await multiFingerTap(tester, tapAnchor(tester), 2);

    expect(
      container.read(documentControllerProvider).layers,
      hasLength(1),
      reason: 'disabled shortcut must never undo',
    );
    expect(container.read(documentControllerProvider.notifier).canUndo, isTrue);
  });

  testWidgets('two-finger gesture that moves beyond kTouchSlop aborts', (
    tester,
  ) async {
    final container = await pumpEditor(tester, enabled: true);

    // One finger travels 2×kTouchSlop — the movement discriminator
    // must classify this as a pan/pinch, not a tap, so no undo fires.
    await multiFingerTap(
      tester,
      tapAnchor(tester),
      2,
      moveFirstBy: const Offset(kTouchSlop * 2, 0),
    );

    expect(
      container.read(documentControllerProvider).layers,
      hasLength(1),
      reason: 'movement beyond the slop bound must abort the shortcut',
    );
  });

  testWidgets('four-finger tap aborts (only 2 and 3 are shortcuts)', (
    tester,
  ) async {
    final container = await pumpEditor(tester, enabled: true);

    await multiFingerTap(tester, tapAnchor(tester), 4);

    expect(
      container.read(documentControllerProvider).layers,
      hasLength(1),
      reason: 'a peak pointer count above 3 must never fire undo/redo',
    );
  });

  testWidgets('two-finger tap is inert while a mask-edit session is open', (
    tester,
  ) async {
    // Contract §6 (tb2 13/16): a draft session in the registry makes
    // the shortcut abort on pointer-down. Mask is the one session
    // that rides on the LIVE canvas (no opaque overlay/barrier), so
    // it is the strictest pin of the registry gate. Mask sessions
    // only open on image layers — add one (a second history entry).
    final container = await pumpEditor(tester, enabled: true);
    container
        .read(documentControllerProvider.notifier)
        .execute(
          AddLayerCommand(
            ImageLayer(
              id: 'img-1',
              transform: const LayerTransform(
                position: Offset(300, 60),
                size: Size(300, 200),
              ),
              source: const ImageSource.asset('assets/missing-mask.png'),
            ),
          ),
        );
    container.read(maskEditControllerProvider.notifier).open('img-1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(documentControllerProvider).layers, hasLength(2));

    await multiFingerTap(tester, tapAnchor(tester), 2);

    expect(
      container.read(documentControllerProvider).layers,
      hasLength(2),
      reason: 'undo shortcut must stay inert during a draft session',
    );

    // Session over → the shortcut works again (undoes the image add).
    container.read(maskEditControllerProvider.notifier).cancel();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await multiFingerTap(tester, tapAnchor(tester), 2);
    expect(container.read(documentControllerProvider).layers, hasLength(1));
  });

  testWidgets('two-finger hold longer than the 250ms tap window aborts', (
    tester,
  ) async {
    final container = await pumpEditor(tester, enabled: true);
    final anchor = tapAnchor(tester);

    final g1 = await tester.startGesture(anchor);
    final g2 = await tester.startGesture(anchor + const Offset(30, 0));
    // The tap window is measured in WALL-CLOCK time (DateTime.now()),
    // so fake-async pumps can't age it — let real time pass instead.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 320)),
    );
    await g1.up();
    await g2.up();
    await tester.pump();
    // Lapse the canvas double-tap window so no timer leaks.
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      container.read(documentControllerProvider).layers,
      hasLength(1),
      reason: 'a slow multi-finger sequence is not a tap — no undo',
    );
  });
}
