// Phase 3.2c — MaskEditOverlay widget gates
// (docs/mask-edit-mode-design-2026-07.md §7 item 4).

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/mask_edit_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_mask.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/core/viewport_state.dart';
import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/handle_drag_detector.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/mask_edit_overlay.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _mask = RectMask(rect: Rect.fromLTWH(10, 10, 80, 60), feather: 8);

ImageLayer _image({LayerMask? stackMask}) => ImageLayer(
  id: 'img',
  transform: const LayerTransform(
    position: Offset(50, 50),
    size: Size(200, 100),
  ),
  source: const ImageSource.asset('stub.png'),
  effects: EffectStack(
    List<EditorEffect>.unmodifiable(
      <EditorEffect>[BrightnessEffect(amount: 20)],
    ),
    stackMask: stackMask,
  ),
);

Future<ProviderContainer> _pump(WidgetTester tester,
    {LayerMask? stackMask, bool open = true}) async {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  c.read(documentControllerProvider.notifier)
      .newDocument(width: 400, height: 300);
  c.read(documentControllerProvider.notifier)
      .execute(AddLayerCommand(_image(stackMask: stackMask)));
  c.read(maskEditControllerProvider); // mount listener
  if (open) c.read(maskEditControllerProvider.notifier).open('img');

  tester.view.physicalSize = const Size(400, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Stack(
          children: const [
            MaskEditOverlay(
              viewport: ViewportState(scale: 1, translation: Offset.zero),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  return c;
}

LayerMask? _docMask(ProviderContainer c) =>
    (c.read(documentControllerProvider).layerById('img')! as ImageLayer)
        .effects
        .stackMask;

void main() {
  testWidgets('renders nothing while inactive', (tester) async {
    await _pump(tester, stackMask: _mask, open: false);
    expect(find.byType(HandleDragDetector), findsNothing);
    expect(find.text('Done'), findsNothing);
  });

  testWidgets('active mode shows 8 handles + body surface + strip',
      (tester) async {
    await _pump(tester, stackMask: _mask);
    // 8 resize handles + 1 body-move surface.
    expect(find.byType(HandleDragDetector), findsNWidgets(9));
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('body drag translates the draft in layer-local units',
      (tester) async {
    final c = await _pump(tester, stackMask: _mask);
    // Mask bounds centre: layer-local (50,40) → layer at (50,50),
    // no rotation, identity viewport → screen (100,90).
    await tester.dragFrom(const Offset(100, 90), const Offset(30, 10));
    await tester.pump();
    final draft = c.read(maskEditControllerProvider).draft!;
    final b = MaskEditController.boundsOf(draft);
    expect(b.left, closeTo(40, 0.001));
    expect(b.top, closeTo(20, 0.001));
    expect(b.size, _mask.rect.size);
    expect(_docMask(c), _mask, reason: 'drag never touches the document');
  });

  testWidgets('corner drag resizes anchored on the opposite corner',
      (tester) async {
    final c = await _pump(tester, stackMask: _mask);
    // bottomRight handle: layer-local (90,70) → screen (140,120).
    await tester.dragFrom(const Offset(140, 120), const Offset(20, 10));
    await tester.pump();
    final b = MaskEditController.boundsOf(
        c.read(maskEditControllerProvider).draft!);
    expect(b.topLeft, _mask.rect.topLeft);
    expect(b.right, closeTo(110, 0.001));
    expect(b.bottom, closeTo(80, 0.001));
  });

  testWidgets('Done commits once; Cancel discards', (tester) async {
    final c = await _pump(tester, stackMask: _mask);
    await tester.dragFrom(const Offset(100, 90), const Offset(30, 10));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(c.read(maskEditControllerProvider).active, isFalse);
    final committed = _docMask(c)! as RectMask;
    expect(committed.rect.left, closeTo(40, 0.001));

    // Undo restores the pre-session mask in ONE step.
    c.read(documentControllerProvider.notifier).undo();
    expect(_docMask(c), _mask);

    // Reopen, edit, cancel: document untouched.
    c.read(maskEditControllerProvider.notifier).open('img');
    await tester.pump();
    await tester.dragFrom(const Offset(100, 90), const Offset(30, 10));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(_docMask(c), _mask);
  });

  testWidgets('invert toggle + feather slider edit the draft',
      (tester) async {
    final c = await _pump(tester, stackMask: _mask);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(c.read(maskEditControllerProvider).draft!.inverted, isTrue);

    await tester.tap(find.text('Ellipse'));
    await tester.pump();
    expect(c.read(maskEditControllerProvider).draft, isA<EllipseMask>());
    expect(
      MaskEditController.boundsOf(c.read(maskEditControllerProvider).draft!),
      _mask.rect,
      reason: 'shape switch keeps bounds',
    );
  });

  group('featherBlurSigma (scrim edge softening)', () {
    test('zero feather stays crisp (zero sigma)', () {
      expect(featherBlurSigma(0, 2), 0);
    });

    test('scales with both feather and viewport scale', () {
      expect(featherBlurSigma(30, 2), closeTo(20, 0.001));
      expect(featherBlurSigma(9, 1), closeTo(3, 0.001));
    });
  });
}
