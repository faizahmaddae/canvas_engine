import 'package:canvas_engine/features/editor/image/application/image_tool_controller.dart';
import 'package:canvas_engine/features/editor/image/presentation/image_panel_shell.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/dock_sheet_chrome.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/editor_tool_panel_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:canvas_engine/app/theme/app_icons.dart';

void main() {
  group('EditorToolPanelShell', () {
    testWidgets(
      'renders title, icon and a neutral close (✕) action that fires onClose',
      (tester) async {
        var closed = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: EditorToolPanelShell(
                  title: 'Border',
                  icon: AppIcons.borderTool,
                  onClose: () => closed += 1,
                  child: const Text('body'),
                ),
              ),
            ),
          ),
        );

        expect(find.text('Border'), findsOneWidget);
        expect(find.byIcon(AppIcons.borderTool), findsOneWidget);
        expect(find.text('body'), findsOneWidget);
        // Header chip is the neutral ✕ icon — the honest close
        // affordance for panels that don't commit on exit.
        expect(find.text('Done'), findsNothing);
        expect(find.byIcon(AppIcons.close), findsOneWidget);

        await tester.tap(find.byIcon(AppIcons.close));
        await tester.pumpAndSettle();
        expect(closed, 1);
      },
    );

    testWidgets('showCloseAction:false hides the header ✕ — host owns exit', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: EditorToolPanelShell(
                title: 'Font',
                icon: AppIcons.textTool,
                onClose: () {},
                showCloseAction: false,
                child: const Text('body'),
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(AppIcons.close), findsNothing);
      expect(find.text('Done'), findsNothing);
    });

    testWidgets('onConfirm + confirmLabel renders a primary commit pill that '
        'fires the confirm callback (not onClose)', (tester) async {
      var closed = 0;
      var confirmed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: EditorToolPanelShell(
                title: 'Filter',
                icon: AppIcons.precisionAdjust,
                onClose: () => closed += 1,
                onConfirm: () => confirmed += 1,
                confirmLabel: 'Apply',
                child: const Text('body'),
              ),
            ),
          ),
        ),
      );

      // Confirm pill replaces the ✕ when both are set.
      expect(find.text('Apply'), findsOneWidget);
      expect(find.byIcon(AppIcons.close), findsNothing);

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(confirmed, 1);
      expect(closed, 0, reason: 'Confirm must not fire onClose');
    });

    testWidgets('renders an undo chip when onUndo is supplied', (tester) async {
      var undid = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: EditorToolPanelShell(
                title: 'Color',
                icon: AppIcons.colorTool,
                onClose: () {},
                onUndo: () => undid += 1,
                child: const Text('body'),
              ),
            ),
          ),
        ),
      );

      final undo = find.byIcon(AppIcons.undo);
      expect(undo, findsOneWidget);
      await tester.tap(undo);
      await tester.pumpAndSettle();
      expect(undid, 1);
    });

    testWidgets('caps height at min(screen * fraction, maxHeightDp)', (
      tester,
    ) async {
      // Tall viewport — fraction wins (800 * 0.3 = 240 < 420 cap).
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: EditorToolPanelShell(
                title: 'Tall',
                icon: Icons.expand_more,
                onClose: () {},
                maxHeightFraction: 0.3,
                child: SizedBox(height: 1000),
              ),
            ),
          ),
        ),
      );

      final shellSize = tester.getSize(find.byType(EditorToolPanelShell));
      expect(shellSize.height, lessThanOrEqualTo(800 * 0.3 + 0.5));
    });

    testWidgets('dp ceiling clamps the panel when fraction would exceed it', (
      tester,
    ) async {
      // 0.9 * 1200 = 1080 dp; cap is 420. Verify the ceiling bites.
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: EditorToolPanelShell(
                title: 'Cap',
                icon: Icons.expand_more,
                onClose: () {},
                maxHeightFraction: 0.9,
                child: SizedBox(height: 5000),
              ),
            ),
          ),
        ),
      );

      final shellSize = tester.getSize(find.byType(EditorToolPanelShell));
      expect(
        shellSize.height,
        lessThanOrEqualTo(kEditorPanelMaxHeightDp + 0.5),
        reason: 'Panel must respect kEditorPanelMaxHeightDp',
      );
    });

    testWidgets(
      'body padding is owned by the shell and is not double-applied',
      (tester) async {
        // If the chrome were also adding its old (12,0,12,12) gutter,
        // the body would sit 12 dp further from the edge than asked.
        const tag = ValueKey('padding-probe');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: EditorToolPanelShell(
                  title: 'Pad',
                  icon: AppIcons.snapToGuides,
                  onClose: () {},
                  bodyPadding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: SizedBox(key: tag, width: double.infinity, height: 12),
                ),
              ),
            ),
          ),
        );

        final shellRect = tester.getRect(find.byType(DockSheetChrome));
        final bodyRect = tester.getRect(find.byKey(tag));
        expect(
          (bodyRect.left - shellRect.left).round(),
          20,
          reason: 'Chrome must contribute zero horizontal padding',
        );
      },
    );
  });

  group('ImagePanelShell', () {
    testWidgets('header ✕ closes the image tool panel through the controller', (
      tester,
    ) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: ImagePanelShell(
                      title: 'Shape',
                      icon: AppIcons.squareShape,
                      child: const Text('image-body'),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );

      container
          .read(imageToolControllerProvider.notifier)
          .toggleSlot(ImageToolSlot.style);
      expect(
        container.read(imageToolControllerProvider).openSlot,
        equals(ImageToolSlot.style),
      );

      expect(find.text('Shape'), findsOneWidget);
      expect(find.text('image-body'), findsOneWidget);

      await tester.tap(find.byIcon(AppIcons.close));
      await tester.pumpAndSettle();

      expect(container.read(imageToolControllerProvider).openSlot, isNull);
    });

    test('asserts onConfirm and confirmLabel are supplied together', () {
      expect(
        () => EditorToolPanelShell(
          title: 'X',
          icon: Icons.close,
          onClose: () {},
          onConfirm: () {},
          // confirmLabel intentionally omitted
          child: const SizedBox(),
        ),
        throwsAssertionError,
      );
      expect(
        () => EditorToolPanelShell(
          title: 'X',
          icon: Icons.close,
          onClose: () {},
          confirmLabel: 'Apply',
          // onConfirm intentionally omitted
          child: const SizedBox(),
        ),
        throwsAssertionError,
      );
    });

    testWidgets(
      'wires onPrev / onNext via horizontal swipe gestures on the body',
      (tester) async {
        var prev = 0;
        var next = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: EditorToolPanelShell(
                  title: 'Style',
                  icon: AppIcons.styleTool,
                  onClose: () {},
                  onPrev: () => prev += 1,
                  onNext: () => next += 1,
                  child: const SizedBox(
                    height: 60,
                    child: Center(child: Text('swipe-me')),
                  ),
                ),
              ),
            ),
          ),
        );

        // Swipe left → next
        await tester.fling(find.text('swipe-me'), const Offset(-220, 0), 900);
        await tester.pumpAndSettle();
        expect(next, 1);
        expect(prev, 0);

        // Swipe right → prev
        await tester.fling(find.text('swipe-me'), const Offset(220, 0), 900);
        await tester.pumpAndSettle();
        expect(prev, 1);
      },
    );
  });
}
