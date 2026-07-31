// Contract §5 row 1: while a mask session is open, the session
// overlay owns the pointer wherever it lands.
//
// The audit's P2-1: the scrim was an `IgnorePointer`, so a tap on the
// pasteboard fell through to the always-mounted canvas detector, was
// read as an empty-canvas tap, and reached `dismissActiveEditing` ->
// `maskEditController.cancel()`. Cancel restores the entry mask with
// ZERO commands, so a minute of mask tuning vanished and undo could
// not reach it — while crop, the same §1-D session class, swallowed
// the identical tap because its overlay is an opaque Material.
//
// The existing suites could not catch it: `mask_edit_overlay_test`
// drives the strip's buttons only, and `mask_edit_controller_test`
// exercises the seam at the controller API, encoding the mechanism
// without asking whether the seam should fire at all. These tests go
// through the real EditorScreen so the gesture path is the shipped one.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/editor_lifecycle.dart';
import 'package:canvas_engine/features/editor/application/mask_edit_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_mask.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _entry = RectMask(rect: Rect.fromLTWH(10, 10, 80, 60), feather: 8);
const _moved = RectMask(rect: Rect.fromLTWH(30, 30, 80, 60), feather: 20);

ImageLayer _image({LayerMask? stackMask}) => ImageLayer(
  id: 'img',
  transform: const LayerTransform(
    position: Offset(120, 300),
    size: Size(200, 160),
  ),
  source: const ImageSource.asset('stub.png'),
  effects: EffectStack(
    List<EditorEffect>.unmodifiable(<EditorEffect>[
      BrightnessEffect(amount: 20),
    ]),
    stackMask: stackMask,
  ),
);

/// A second, non-image layer so a selection change away from the
/// masked image is a real user-reachable state (layers panel tap).
ShapeLayer _shape() => ShapeLayer(
  id: 'shp',
  transform: const LayerTransform(
    position: Offset(300, 80),
    size: Size(60, 60),
  ),
  kind: ShapeKind.rectangle,
  fillColor: const Color(0xFF112233),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c
        .read(documentControllerProvider.notifier)
        .newDocument(width: 400, height: 400);
    c
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(_image(stackMask: _entry)));
    c
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(_shape()));
    // Seeding is not history under test — clear it so `canUndo`
    // answers only for what the mask session did.
    c.read(documentControllerProvider.notifier).clearHistory();
    c.read(maskEditControllerProvider); // mount the document listener
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Stack(children: [EditorScreen(), _RefProbe()]),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return c;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// A real [WidgetRef] borrowed from the tree — `WidgetRef` is sealed,
  /// so lifecycle helpers cannot be called with a hand-made shim.
  WidgetRef probeRef(WidgetTester tester) =>
      tester.state<ConsumerState<_RefProbe>>(find.byType(_RefProbe)).ref;

  /// Open the session and move the draft away from the entry mask, so
  /// leaving now would destroy work.
  void openDirty(ProviderContainer c) {
    final ctl = c.read(maskEditControllerProvider.notifier);
    ctl.open('img');
    ctl.updateDraft(_moved);
  }

  group('the session owns the pointer', () {
    testWidgets('a tap on the pasteboard does NOT cancel a modified draft', (
      tester,
    ) async {
      final c = await pumpEditor(tester);
      openDirty(c);
      await settle(tester);
      expect(c.read(maskEditControllerProvider).active, isTrue);
      expect(c.read(maskEditControllerProvider).isDirty, isTrue);

      // Top-left corner: outside the canvas, outside the region, and
      // exactly where the old empty-tap branch fired.
      await tester.tapAt(const Offset(8, 300));
      await settle(tester);

      expect(
        c.read(maskEditControllerProvider).active,
        isTrue,
        reason: 'an off-canvas tap must not end the session',
      );
      expect(
        c.read(maskEditControllerProvider).draft,
        _moved,
        reason: 'and must not touch the draft',
      );
    });

    testWidgets('a tap on the pasteboard does not clear the selection either', (
      tester,
    ) async {
      final c = await pumpEditor(tester);
      c.read(selectionControllerProvider.notifier).select('img');
      openDirty(c);
      await settle(tester);

      await tester.tapAt(const Offset(8, 300));
      await settle(tester);

      expect(
        c.read(selectionControllerProvider).selectedId,
        'img',
        reason: 'the session is mid-flight; nothing outside it may deselect',
      );
    });

    testWidgets('dismissActiveEditing is inert while a session is open', (
      tester,
    ) async {
      // Direct call: guards the non-canvas callers (lifecycle hooks,
      // future sheets) that AbsorbPointer cannot cover.
      final c = await pumpEditor(tester);
      openDirty(c);
      await settle(tester);

      dismissActiveEditing(probeRef(tester));
      await settle(tester);

      expect(c.read(maskEditControllerProvider).active, isTrue);
      expect(c.read(maskEditControllerProvider).draft, _moved);
    });
  });

  // Gap closed after the first pass: `closeObjectSubPanels` still
  // called `cancel()`, so a selection change discarded a tuned mask
  // with no command to undo. It was unreachable from the canvas once
  // the overlay absorbed pointers — but "unreachable" is not a
  // guarantee, and the layers panel and any future programmatic
  // selection reach it directly.
  group('no dismiss seam may discard a draft', () {
    testWidgets('closeObjectSubPanels is inert while a session is open', (
      tester,
    ) async {
      final c = await pumpEditor(tester);
      openDirty(c);
      await settle(tester);

      closeObjectSubPanels(probeRef(tester));
      await settle(tester);

      expect(c.read(maskEditControllerProvider).active, isTrue);
      expect(c.read(maskEditControllerProvider).draft, _moved);
    });

    testWidgets('a selection change to another layer keeps the draft', (
      tester,
    ) async {
      // Goes through EditorScreen's real selection listener, which is
      // what the layers panel drives.
      final c = await pumpEditor(tester);
      c.read(selectionControllerProvider.notifier).select('img');
      openDirty(c);
      await settle(tester);

      c.read(selectionControllerProvider.notifier).select('shp');
      await settle(tester);

      expect(
        c.read(maskEditControllerProvider).active,
        isTrue,
        reason: 'selecting another layer is not a request to lose work',
      );
      expect(c.read(maskEditControllerProvider).draft, _moved);
    });

    testWidgets('deselecting everything keeps the draft', (tester) async {
      final c = await pumpEditor(tester);
      c.read(selectionControllerProvider.notifier).select('img');
      openDirty(c);
      await settle(tester);

      c.read(selectionControllerProvider.notifier).clear();
      await settle(tester);

      expect(c.read(maskEditControllerProvider).active, isTrue);
      expect(c.read(maskEditControllerProvider).draft, _moved);
    });

    testWidgets('the layer genuinely losing its meaning DOES end the '
        'session — that backstop stays', (tester) async {
      // The counterpart to the rules above: when the target layer is
      // deleted the draft has nothing to describe, so the controller's
      // own document listener ends the session. Not a silent loss of
      // reachable work — the work's subject is gone.
      final c = await pumpEditor(tester);
      openDirty(c);
      await settle(tester);

      c
          .read(documentControllerProvider.notifier)
          .execute(const RemoveLayerCommand('img'));
      await settle(tester);

      expect(c.read(maskEditControllerProvider).active, isFalse);
    });

    testWidgets('the project boundary discards unconditionally — it cannot '
        'ask, and the document is already gone', (tester) async {
      final c = await pumpEditor(tester);
      openDirty(c);
      await settle(tester);

      resetEditorEphemeralState(probeRef(tester));
      await settle(tester);

      expect(c.read(maskEditControllerProvider).active, isFalse);
    });
  });

  group('abandoning is explicit and confirmed', () {
    testWidgets('Cancel on a MODIFIED draft asks first, and Keep editing '
        'returns to the session', (tester) async {
      final c = await pumpEditor(tester);
      openDirty(c);
      await settle(tester);

      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(find.text('Discard mask changes?'), findsOneWidget);
      expect(
        c.read(maskEditControllerProvider).active,
        isTrue,
        reason: 'the dialog must not pre-emptively end the session',
      );

      await tester.tap(find.text('Keep editing'));
      await settle(tester);
      expect(c.read(maskEditControllerProvider).active, isTrue);
      expect(c.read(maskEditControllerProvider).draft, _moved);
    });

    testWidgets('Cancel on a modified draft, confirmed, discards it', (
      tester,
    ) async {
      final c = await pumpEditor(tester);
      openDirty(c);
      await settle(tester);

      await tester.tap(find.text('Cancel'));
      await settle(tester);
      await tester.tap(find.text('Discard'));
      await settle(tester);

      expect(c.read(maskEditControllerProvider).active, isFalse);
      // Cancel is still a true no-op on the document: the layer keeps
      // the mask it had at open, and nothing landed on the history.
      final layer =
          c.read(documentControllerProvider).layerById('img') as ImageLayer;
      expect(layer.effects.stackMask, _entry);
      expect(c.read(documentControllerProvider.notifier).canUndo, isFalse);
    });

    testWidgets('Cancel on an UNMODIFIED draft leaves silently — a dialog '
        'with nothing to lose is noise', (tester) async {
      final c = await pumpEditor(tester);
      c.read(maskEditControllerProvider.notifier).open('img');
      await settle(tester);
      expect(c.read(maskEditControllerProvider).isDirty, isFalse);

      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(find.text('Discard mask changes?'), findsNothing);
      expect(c.read(maskEditControllerProvider).active, isFalse);
    });

    // On iOS the interactive back-swipe never reaches the router now
    // (the overlay absorbs it, exactly as crop's opaque Material
    // does), so this is the only place the PopScope branch can be
    // exercised. It shares `confirmAbandonMaskEdit` with the Cancel
    // button so the two exits cannot diverge.
    testWidgets('system back on a MODIFIED draft asks before discarding', (
      tester,
    ) async {
      final c = await pumpEditor(tester);
      openDirty(c);
      await settle(tester);

      await tester.binding.handlePopRoute();
      await settle(tester);

      expect(find.text('Discard mask changes?'), findsOneWidget);
      expect(c.read(maskEditControllerProvider).active, isTrue);

      await tester.tap(find.text('Keep editing'));
      await settle(tester);
      expect(c.read(maskEditControllerProvider).draft, _moved);

      await tester.binding.handlePopRoute();
      await settle(tester);
      await tester.tap(find.text('Discard'));
      await settle(tester);
      expect(c.read(maskEditControllerProvider).active, isFalse);
    });

    testWidgets('system back on an UNMODIFIED draft leaves without asking', (
      tester,
    ) async {
      final c = await pumpEditor(tester);
      c.read(maskEditControllerProvider.notifier).open('img');
      await settle(tester);

      await tester.binding.handlePopRoute();
      await settle(tester);

      expect(find.text('Discard mask changes?'), findsNothing);
      expect(c.read(maskEditControllerProvider).active, isFalse);
    });

    testWidgets('Done still commits exactly one entry', (tester) async {
      final c = await pumpEditor(tester);
      openDirty(c);
      await settle(tester);

      await tester.tap(find.text('Done'));
      await settle(tester);

      expect(c.read(maskEditControllerProvider).active, isFalse);
      final layer =
          c.read(documentControllerProvider).layerById('img') as ImageLayer;
      expect(layer.effects.stackMask, _moved);
      expect(c.read(documentControllerProvider.notifier).canUndo, isTrue);

      c.read(documentControllerProvider.notifier).undo();
      final after =
          c.read(documentControllerProvider).layerById('img') as ImageLayer;
      expect(after.effects.stackMask, _entry);
    });
  });
}

/// Zero-size consumer whose only job is to hand the test a real
/// [WidgetRef] bound to the same container as the editor.
class _RefProbe extends ConsumerStatefulWidget {
  const _RefProbe();

  @override
  ConsumerState<_RefProbe> createState() => _RefProbeState();
}

class _RefProbeState extends ConsumerState<_RefProbe> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
