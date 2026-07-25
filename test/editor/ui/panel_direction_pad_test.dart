import 'package:canvas_engine/features/editor/ui/panel_direction_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:canvas_engine/app/theme/app_icons.dart';

Widget _host(Widget child, {TextDirection dir = TextDirection.ltr}) =>
    MaterialApp(
      home: Directionality(
        textDirection: dir,
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  group('PanelDirectionPad — geometry', () {
    testWidgets('renders 9 cells', (tester) async {
      await tester.pumpWidget(
        _host(
          PanelDirectionPad(offset: Offset.zero, magnitude: 20, onPick: (_) {}),
        ),
      );
      expect(find.byType(InkWell), findsNWidgets(9));
    });

    testWidgets('centre cell picks Offset.zero', (tester) async {
      Offset? picked;
      await tester.pumpWidget(
        _host(
          PanelDirectionPad(
            offset: const Offset(20, 20),
            magnitude: 20,
            onPick: (o) => picked = o,
          ),
        ),
      );
      await tester.tap(find.byIcon(AppIcons.offsetCenter));
      expect(picked, Offset.zero);
    });

    testWidgets('a perimeter cell picks a magnitude-scaled offset', (
      tester,
    ) async {
      Offset? picked;
      await tester.pumpWidget(
        _host(
          PanelDirectionPad(
            offset: Offset.zero,
            magnitude: 15,
            onPick: (o) => picked = o,
          ),
        ),
      );
      final arrows = find.byIcon(AppIcons.offsetDirection);
      expect(arrows, findsNWidgets(8));
      await tester.tap(arrows.first);
      expect(picked, isNotNull);
      expect(picked!.distance, closeTo(15 * 1.41421356, 0.01));
    });

    testWidgets('activeThreshold controls which cell reads as active', (
      tester,
    ) async {
      // Below threshold on both axes -> centre reads active even
      // with a tiny non-zero offset.
      await tester.pumpWidget(
        _host(
          PanelDirectionPad(
            offset: const Offset(0.2, 0.2),
            magnitude: 20,
            activeThreshold: 0.5,
            onPick: (_) {},
          ),
        ),
      );
      final centerCell = tester.widget<Material>(
        find
            .ancestor(
              of: find.byIcon(AppIcons.offsetCenter),
              matching: find.byType(Material),
            )
            .first,
      );
      // Selected cells render with the primary-tint fill.
      expect((centerCell.color as Color).a, greaterThan(0));
    });
  });

  group('PanelDirectionPad — RTL fix (Phase 4 plan D3)', () {
    testWidgets('cell layout order is identical under LTR and RTL '
        'ambient Directionality (pinned internally)', (tester) async {
      Future<List<Offset>> cellCenters(TextDirection dir) async {
        await tester.pumpWidget(
          _host(
            PanelDirectionPad(
              offset: Offset.zero,
              magnitude: 20,
              onPick: (_) {},
            ),
            dir: dir,
          ),
        );
        return [
          for (final el in find.byType(InkWell).evaluate())
            tester.getCenter(find.byWidget(el.widget)),
        ];
      }

      final ltr = await cellCenters(TextDirection.ltr);
      final rtl = await cellCenters(TextDirection.rtl);
      expect(
        rtl,
        ltr,
        reason:
            'the pad must not mirror under an RTL ambient '
            'Directionality — a mirrored grid with physical-offset '
            'onPick would move the target the wrong way',
      );
    });

    testWidgets('a perimeter tap emits the same physical Offset under '
        'RTL as under LTR', (tester) async {
      Future<Offset?> tapFirstArrow(TextDirection dir) async {
        Offset? picked;
        await tester.pumpWidget(
          _host(
            PanelDirectionPad(
              offset: Offset.zero,
              magnitude: 20,
              onPick: (o) => picked = o,
            ),
            dir: dir,
          ),
        );
        await tester.tap(find.byIcon(AppIcons.offsetDirection).first);
        return picked;
      }

      final ltrPick = await tapFirstArrow(TextDirection.ltr);
      final rtlPick = await tapFirstArrow(TextDirection.rtl);
      expect(rtlPick, ltrPick);
    });
  });
}
