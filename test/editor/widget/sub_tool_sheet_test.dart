import 'package:canvas_engine/features/editor/presentation/widgets/dock_sheet_chrome.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/editor_tool_panel_shell.dart';
import 'package:canvas_engine/features/editor/toolbar/domain/sub_tool.dart';
import 'package:canvas_engine/features/editor/toolbar/presentation/sub_tool_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:canvas_engine/app/theme/app_icons.dart';

class _StubSubTool extends SubTool {
  const _StubSubTool();
  @override
  String get headerTitle => 'Color';
  @override
  IconData get headerIcon => AppIcons.colorTool;
  @override
  bool get supportsSiblingSwipe => true;
  @override
  double get maxHeightFraction => kEditorPanelMaxHeightFraction;
  @override
  Widget build(BuildContext context, WidgetRef ref) => const Text('sub-body');
}

void main() {
  group('SubToolSheet', () {
    testWidgets('delegates rendering to EditorToolPanelShell with the neutral '
        'close action by default', (tester) async {
      var closed = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SubToolSheet(
                  subTool: const _StubSubTool(),
                  onClose: () => closed += 1,
                ),
              ),
            ),
          ),
        ),
      );

      // Single source of truth: SubToolSheet must compose the
      // unified shell rather than reach into DockSheetChrome.
      expect(find.byType(EditorToolPanelShell), findsOneWidget);
      expect(find.text('Color'), findsOneWidget);
      expect(find.byIcon(AppIcons.colorTool), findsOneWidget);
      expect(find.text('sub-body'), findsOneWidget);
      // No "Done" — close action is the honest neutral ✕.
      expect(find.text('Done'), findsNothing);
      expect(find.byIcon(AppIcons.close), findsOneWidget);

      await tester.tap(find.byIcon(AppIcons.close));
      await tester.pumpAndSettle();
      expect(closed, 1);
    });

    testWidgets(
      'showCloseAction:false hides the header chip — host owns exit',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: SubToolSheet(
                    subTool: const _StubSubTool(),
                    onClose: () {},
                    showCloseAction: false,
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.byIcon(AppIcons.close), findsNothing);
        expect(find.text('Done'), findsNothing);
      },
    );

    testWidgets('onConfirm + confirmLabel renders the primary commit pill', (
      tester,
    ) async {
      var closed = 0;
      var confirmed = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SubToolSheet(
                  subTool: const _StubSubTool(),
                  onClose: () => closed += 1,
                  onConfirm: () => confirmed += 1,
                  confirmLabel: 'Apply',
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Apply'), findsOneWidget);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(confirmed, 1);
      expect(
        closed,
        0,
        reason: 'Confirm must not also fire onClose in SubToolSheet',
      );
    });
  });
}
