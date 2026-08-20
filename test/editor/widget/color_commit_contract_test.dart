// Pins the live/settled colour contract (tb2 4-5/16, interaction
// contract §2/§3): onChanged is preview-only, onCommitted seals
// EXACTLY one undoable commit, interactions that end where they
// started (cancelled eyedrop) leave history untouched, hex commits
// only on complete input, and preset-palette taps stay out of the
// recents MRU. The P2-8 group pins the last two migrated hosts
// (shape style, canvas panel): two quick swatch taps are TWO undo
// entries and one wheel drag is ONE, with no wall-clock dependence.

import 'package:canvas_engine/features/color_picker/presentation/color_picker_body.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/live_overlay_controller.dart';
import 'package:canvas_engine/features/editor/application/recent_colors_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/canvas/presentation/canvas_panel_body.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/background_fill.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/image/presentation/image_border_body.dart';
import 'package:canvas_engine/features/editor/paint/application/paint_tool_controller.dart';
import 'package:canvas_engine/features/editor/shape/presentation/shape_style_body.dart';
import 'package:canvas_engine/features/editor/text/application/text_tool_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    return c;
  }

  group('text colour drag session (tb2 4/16)', () {
    TextLayer addText(ProviderContainer c) {
      final layer = TextLayer(
        id: 't1',
        transform: const LayerTransform(
          position: Offset(50, 50),
          size: Size(200, 80),
        ),
        content: 'hello',
        style: const TextStyleSpec(),
      );
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(layer));
      c.read(selectionControllerProvider.notifier).select('t1');
      return layer;
    }

    test('shadow colour drag = one history entry', () {
      final c = makeContainer();
      addText(c);
      final ctrl = c.read(textToolControllerProvider.notifier);
      final v0 = c.read(documentCommitVersionProvider);

      // Picker wheel drag: session opens lazily on the first tick,
      // ticks stage overlay frames, onCommitted ends the session.
      ctrl.beginStyleDrag();
      ctrl.setShadowColor(const Color(0xFF112233));
      ctrl.setShadowColor(const Color(0xFF445566));
      expect(
        c.read(documentCommitVersionProvider),
        v0,
        reason: 'ticks stage overlay frames, not commits',
      );
      expect(
        c.read(liveOverlayProvider).replacements.containsKey('t1'),
        isTrue,
      );
      ctrl.endStyleDrag();

      expect(c.read(documentCommitVersionProvider), v0 + 1);
      final layer =
          c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(layer.style.shadowColor, const Color(0xFF445566));
      expect(c.read(liveOverlayProvider).isEmpty, isTrue);

      c.read(documentControllerProvider.notifier).undo();
      final undone =
          c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(
        undone.style.shadowColor,
        isNull,
        reason: 'one undo unwinds the whole drag',
      );
    });

    test('eyedrop-cancel sequence (restore + seal at original) leaves '
        'history unchanged', () {
      final c = makeContainer();
      final layer = addText(c);
      final ctrl = c.read(textToolControllerProvider.notifier);
      final original = layer.style.color;
      final v0 = c.read(documentCommitVersionProvider);

      // What the picker emits on a cancelled eyedrop after the D3
      // fix: live samples, then a restore to the original colour,
      // then a sealing onCommitted at that original value.
      ctrl.beginStyleDrag();
      ctrl.setColor(const Color(0xFF00FF00)); // sample
      ctrl.setColor(original); // restore
      ctrl.endStyleDrag(); // seal — must be a true no-op

      expect(
        c.read(documentCommitVersionProvider),
        v0,
        reason: 'no net-zero history entries (§3)',
      );
      expect(c.read(liveOverlayProvider).isEmpty, isTrue);
    });
  });

  group('paint stroke colour channel (tb2 4/16)', () {
    PaintLayer addStroke(ProviderContainer c) {
      final layer = PaintLayer(
        id: 'p1',
        transform: const LayerTransform(
          position: Offset(40, 40),
          size: Size(200, 100),
        ),
        kind: PaintKind.line,
        normalizedPoints: const [Offset(0, 0.5), Offset(1, 0.5)],
      );
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(layer));
      c.read(selectionControllerProvider.notifier).select('p1');
      return layer;
    }

    test('drag = one entry; defaults stay isolated; overlay stages', () {
      final c = makeContainer();
      addStroke(c);
      final ctrl = c.read(paintToolControllerProvider.notifier);
      final defaultColor = c.read(paintToolControllerProvider).strokeColor;
      final v0 = c.read(documentCommitVersionProvider);

      ctrl.previewStrokeColor(const Color(0xFF111111));
      ctrl.previewStrokeColor(const Color(0xFF222222));
      expect(c.read(documentCommitVersionProvider), v0);
      expect(
        c.read(liveOverlayProvider).replacements.containsKey('p1'),
        isTrue,
      );
      expect(
        c.read(paintToolControllerProvider).strokeColor,
        defaultColor,
        reason: 'restyling a bound stroke must not change the next stroke',
      );

      ctrl.commitStrokeColor();
      expect(c.read(documentCommitVersionProvider), v0 + 1);
      final layer =
          c.read(documentControllerProvider).layerById('p1') as PaintLayer;
      expect(layer.strokeColor, const Color(0xFF222222));
      expect(c.read(liveOverlayProvider).isEmpty, isTrue);
    });

    test('cancel path: commit at the original colour = zero entries', () {
      final c = makeContainer();
      final layer = addStroke(c);
      final ctrl = c.read(paintToolControllerProvider.notifier);
      final v1 = c.read(documentCommitVersionProvider);

      ctrl.previewStrokeColor(const Color(0xFF00FF00)); // sample
      ctrl.previewStrokeColor(layer.strokeColor); // restore
      ctrl.commitStrokeColor(); // seal → apply is identical → dropped
      expect(
        c.read(documentCommitVersionProvider),
        v1,
        reason: 'no net-zero history entries (§3)',
      );
      expect(c.read(liveOverlayProvider).isEmpty, isTrue);
    });
  });

  group('picker-level fixes (tb2 5/16)', () {
    Future<void> pumpPicker(
      WidgetTester tester,
      ProviderContainer container, {
      required Color initial,
      required List<Color> commits,
    }) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: ColorPickerBody(
                initial: initial,
                onChanged: (_) {},
                onCommitted: commits.add,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('hex commits only on complete input', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final commits = <Color>[];
      await pumpPicker(
        tester,
        container,
        initial: const Color(0xFFFF0000),
        commits: commits,
      );

      final field = find.byType(TextField);
      await tester.enterText(field, '#12');
      await tester.pump();
      expect(commits, isEmpty, reason: 'partial input must not commit');

      await tester.enterText(field, '#123');
      await tester.pump();
      expect(
        commits,
        isEmpty,
        reason: '3-char shorthand is a prefix — commits only on submit',
      );

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(commits, hasLength(1), reason: 'submit seals the shorthand');

      await tester.enterText(field, '#123456');
      await tester.pump();
      expect(
        commits,
        hasLength(2),
        reason: 'a complete 6-digit entry commits as typed',
      );
      expect(commits.last.toARGB32() & 0x00FFFFFF, 0x123456);
    });

    testWidgets('preset-palette tap does not write the recents MRU', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final commits = <Color>[];
      await pumpPicker(
        tester,
        container,
        initial: const Color(0xFF000000),
        commits: commits,
      );

      await tester.tap(
        find.byKey(const ValueKey('color-picker-swatch-EF4444')),
      );
      await tester.pump();
      expect(commits, hasLength(1), reason: 'tap still commits once');

      // Unmount → dispose runs the (deferred) recents bookkeeping.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(
        container.read(recentColorsControllerProvider),
        isEmpty,
        reason: 'palette colours never enter the recents MRU (tb2 5/16)',
      );
    });
  });

  group('embedded C-host wiring (tb2 5/16)', () {
    testWidgets(
      'border colour swatch tap commits ONE entry with width promotion',
      (tester) async {
        final layer = ImageLayer(
          id: 'img1',
          transform: const LayerTransform(
            position: Offset(40, 40),
            size: Size(200, 200),
          ),
          source: const ImageSource.asset('stub.png'),
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container
            .read(documentControllerProvider.notifier)
            .newDocument(width: 800, height: 800);
        container
            .read(documentControllerProvider.notifier)
            .execute(AddLayerCommand(layer));

        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ImageBorderBody(layer: layer),
                ),
              ),
            ),
          ),
        );

        final v0 = container.read(documentCommitVersionProvider);
        // The shelf is a 3×6 grid, so the palette rows sit lower in
        // this host than the old 2×6 did — far enough to fall outside
        // the scroll viewport at this surface size. Scroll the target
        // into view rather than tapping a coordinate that is merely
        // laid out: a widget below the fold is painted but not
        // hit-testable, and `tap` does not scroll.
        final swatch = find.byKey(const ValueKey('color-picker-swatch-3B82F6'));
        await tester.ensureVisible(swatch);
        await tester.pump();
        await tester.tap(swatch);
        await tester.pump();

        expect(container.read(documentCommitVersionProvider), v0 + 1);
        final updated =
            container.read(documentControllerProvider).layerById('img1')
                as ImageLayer;
        expect(updated.borderColor.toARGB32() & 0x00FFFFFF, 0x3B82F6);
        expect(
          updated.borderWidth,
          greaterThan(0),
          reason: 'first colour pick promotes width so it is visible',
        );
        expect(container.read(liveOverlayProvider).isEmpty, isTrue);
      },
    );
  });

  // ux-audit-2026-07-29 P2-8: shape style and the canvas panel were
  // the last two hosts routing colour through `live: true` committed
  // commands, so undo granularity depended on the wall-clock merge
  // window (two quick taps = one entry; a paused drag = several).
  // These pins hold them to the same structural fencing as every
  // other host: each discrete tap is its own entry, one drag is one
  // entry committed on release. Taps land milliseconds apart here —
  // well inside kLiveMergeWindow — which is exactly the adversarial
  // case for any time-based merging.
  group('P2-8 migrated hosts — gesture-fenced colour undo', () {
    const shapeSeed = Color(0xFF2196F3);

    Future<ProviderContainer> pumpHost(
      WidgetTester tester,
      Widget Function(ProviderContainer c) body,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(documentControllerProvider.notifier)
          .newDocument(width: 800, height: 800);
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: body(container))),
          ),
        ),
      );
      return container;
    }

    ShapeLayer addShape(ProviderContainer c) {
      const layer = ShapeLayer(
        id: 's1',
        kind: ShapeKind.rectangle,
        transform: LayerTransform(
          position: Offset(40, 40),
          size: Size(200, 200),
        ),
        fillColor: shapeSeed,
      );
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(layer));
      return layer;
    }

    Future<void> tapSwatch(WidgetTester tester, String hex6) async {
      final swatch = find.byKey(ValueKey('color-picker-swatch-$hex6'));
      await tester.ensureVisible(swatch);
      await tester.pump();
      await tester.tap(swatch);
      await tester.pump();
    }

    /// Opens the custom wheel sheet (embedded panels hand off to it)
    /// and drags the SV pad: down + two move ticks, asserting mid-drag
    /// that nothing has committed, then releases.
    Future<void> dragWheel(
      WidgetTester tester,
      ProviderContainer container, {
      required void Function() expectMidDragStaged,
    }) async {
      final custom = find.byKey(const ValueKey('color-picker-custom'));
      await tester.ensureVisible(custom);
      await tester.pump();
      await tester.tap(custom);
      await tester.pumpAndSettle();

      final v0 = container.read(documentCommitVersionProvider);
      final sv = find.byKey(const ValueKey('color-picker-sv'));
      final gesture = await tester.startGesture(tester.getCenter(sv));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 30));
      await tester.pump();
      await gesture.moveBy(const Offset(-15, 10));
      await tester.pump();

      expect(
        container.read(documentCommitVersionProvider),
        v0,
        reason: 'ticks stage overlay previews, never commits (§2)',
      );
      expectMidDragStaged();

      await gesture.up();
      await tester.pump();
    }

    testWidgets('shape fill: two quick swatch taps are two separate '
        'undo entries', (tester) async {
      final container = await pumpHost(
        tester,
        (c) => ShapeStyleBody(layer: addShape(c)),
      );
      final docCtrl = container.read(documentControllerProvider.notifier);
      final entries0 = docCtrl.historyTimeline.length;
      ShapeLayer shape() =>
          container.read(documentControllerProvider).layerById('s1')
              as ShapeLayer;

      await tapSwatch(tester, 'EF4444');
      await tapSwatch(tester, '3B82F6');

      expect(shape().fillColor.toARGB32(), 0xFF3B82F6);
      expect(
        docCtrl.historyTimeline.length,
        entries0 + 2,
        reason:
            'discrete taps are separate intents (§3), regardless '
            'of how close in time',
      );
      expect(container.read(liveOverlayProvider).isEmpty, isTrue);

      docCtrl.undo();
      expect(
        shape().fillColor.toARGB32(),
        0xFFEF4444,
        reason: 'one undo steps back exactly one tap',
      );
      docCtrl.undo();
      expect(shape().fillColor.toARGB32(), shapeSeed.toARGB32());
    });

    testWidgets('shape fill: one custom-wheel drag is ONE entry '
        'committed on release', (tester) async {
      final container = await pumpHost(
        tester,
        (c) => ShapeStyleBody(layer: addShape(c)),
      );
      final docCtrl = container.read(documentControllerProvider.notifier);
      final entries0 = docCtrl.historyTimeline.length;
      ShapeLayer shape() =>
          container.read(documentControllerProvider).layerById('s1')
              as ShapeLayer;

      await dragWheel(
        tester,
        container,
        expectMidDragStaged: () => expect(
          container.read(liveOverlayProvider).replacements.containsKey('s1'),
          isTrue,
          reason: 'the drag previews on the live overlay',
        ),
      );

      expect(
        docCtrl.historyTimeline.length,
        entries0 + 1,
        reason: 'fencing is structural: one gesture, one entry (§3)',
      );
      expect(container.read(liveOverlayProvider).isEmpty, isTrue);
      expect(shape().fillColor.toARGB32(), isNot(shapeSeed.toARGB32()));

      docCtrl.undo();
      expect(
        shape().fillColor.toARGB32(),
        shapeSeed.toARGB32(),
        reason: 'one undo unwinds the whole drag',
      );
    });

    testWidgets('canvas background: two quick swatch taps are two '
        'separate undo entries', (tester) async {
      final container = await pumpHost(tester, (_) => const CanvasPanelBody());
      final docCtrl = container.read(documentControllerProvider.notifier);
      final original = container.read(documentControllerProvider).background;
      final entries0 = docCtrl.historyTimeline.length;
      BackgroundFill bg() =>
          container.read(documentControllerProvider).background;

      // The redesigned panel's ground chips (the embedded picker died;
      // the custom wheel lives in the shared sheet now).
      Future<void> tapGround(String hex8) async {
        final chip = find.byKey(ValueKey('canvas-bg-solid-$hex8'));
        await tester.ensureVisible(chip);
        await tester.pump();
        await tester.tap(chip);
        await tester.pump();
      }

      await tapGround('fff5b942');
      await tapGround('ff6b7280');

      expect((bg() as SolidBackground).color.toARGB32(), 0xFF6B7280);
      expect(
        docCtrl.historyTimeline.length,
        entries0 + 2,
        reason:
            'each swatch tap is its own undoable click — the '
            'command docstring promise the live wiring used to break',
      );
      expect(container.read(liveOverlayProvider).isEmpty, isTrue);

      docCtrl.undo();
      expect((bg() as SolidBackground).color.toARGB32(), 0xFFF5B942);
      docCtrl.undo();
      expect(bg(), original);
    });

    testWidgets('canvas background: one custom-wheel drag is ONE entry '
        'committed on release', (tester) async {
      final container = await pumpHost(tester, (_) => const CanvasPanelBody());
      final docCtrl = container.read(documentControllerProvider.notifier);
      final original = container.read(documentControllerProvider).background;
      final entries0 = docCtrl.historyTimeline.length;

      // The panel hands custom colour off to the shared picker sheet.
      final customDot = find.byKey(const ValueKey('canvas-bg-custom'));
      await tester.ensureVisible(customDot);
      await tester.pump();
      await tester.tap(customDot);
      await tester.pumpAndSettle();

      await dragWheel(
        tester,
        container,
        expectMidDragStaged: () {
          expect(
            container.read(liveOverlayProvider).background,
            isNotNull,
            reason:
                'a document property previews as the overlay '
                'background override, not as committed live commands',
          );
          expect(
            container.read(documentControllerProvider).background,
            original,
            reason: 'the committed doc stays untouched mid-drag',
          );
          expect(
            container.read(renderedDocumentProvider).background,
            isNot(original),
            reason: 'the merged view shows the preview on the board',
          );
        },
      );

      expect(
        docCtrl.historyTimeline.length,
        entries0 + 1,
        reason: 'fencing is structural: one gesture, one entry (§3)',
      );
      expect(container.read(liveOverlayProvider).isEmpty, isTrue);
      expect(
        container.read(documentControllerProvider).background,
        isNot(original),
      );

      docCtrl.undo();
      expect(
        container.read(documentControllerProvider).background,
        original,
        reason: 'one undo unwinds the whole drag',
      );
    });
  });
}
