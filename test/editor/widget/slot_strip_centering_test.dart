/// Widget-level coverage for [SlotStrip] centering behaviour.
///
/// When a toolbar has few items that fit in the viewport, the strip
/// must center them (instead of leaving them huddled at the leading
/// edge). When items overflow the viewport, the strip must still be
/// scrollable and not crash.
library;

import 'package:canvas_engine/features/editor/toolbar/domain/toolbar_slot.dart';
import 'package:canvas_engine/features/editor/toolbar/presentation/slot_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Unique icons so each tile can be located individually.
const _iconA = Icons.looks_one_rounded;
const _iconB = Icons.looks_two_rounded;
const _iconC = Icons.looks_3_rounded;

ToolbarSlot _slot(String id, IconData icon) => ToolbarSlot(
      id: id,
      icon: icon,
      label: id,
      onTap: () {},
    );

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

void main() {
  group('SlotStrip centering: centerWhenFits is true by default', () {
    testWidgets('renders both items with the default centering path',
        (tester) async {
      // 800×600 viewport (landscape compact suppresses labels, but
      // icons are always rendered). Find by icon — stable regardless
      // of compact mode.
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 800,
            height: 80,
            child: SlotStrip(
              slots: [_slot('a', _iconA), _slot('b', _iconB)],
            ),
          ),
        ),
      );

      expect(find.byIcon(_iconA), findsOneWidget);
      expect(find.byIcon(_iconB), findsOneWidget);

      // Icon A is to the left of icon B.
      final aX = tester.getCenter(find.byIcon(_iconA)).dx;
      final bX = tester.getCenter(find.byIcon(_iconB)).dx;
      expect(aX, lessThan(bX),
          reason: 'left tile must precede right tile');

      // Both tiles are within the 800-dp box (no overflow).
      expect(aX, greaterThan(0));
      expect(bX, lessThan(800));
    });

    testWidgets('items are centered (equidistant from viewport mid-point)',
        (tester) async {
      const viewportWidth = 800.0;
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: viewportWidth,
            height: 80,
            child: SlotStrip(
              slots: [_slot('x', _iconA), _slot('y', _iconB)],
            ),
          ),
        ),
      );

      final xDx = tester.getCenter(find.byIcon(_iconA)).dx;
      final yDx = tester.getCenter(find.byIcon(_iconB)).dx;
      final midpoint = viewportWidth / 2;
      final distLeft = (xDx - midpoint).abs();
      final distRight = (yDx - midpoint).abs();

      // The two tiles are symmetric around the viewport centre
      // (within 1-px floating-point tolerance).
      expect(distLeft, closeTo(distRight, 1),
          reason: 'tiles must be symmetric around viewport midpoint');
    });

    testWidgets('three items also center correctly', (tester) async {
      const viewportWidth = 800.0;
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: viewportWidth,
            height: 80,
            child: SlotStrip(
              slots: [
                _slot('p', _iconA),
                _slot('q', _iconB),
                _slot('r', _iconC),
              ],
            ),
          ),
        ),
      );

      final pX = tester.getCenter(find.byIcon(_iconA)).dx;
      final rX = tester.getCenter(find.byIcon(_iconC)).dx;
      final mid = viewportWidth / 2;

      // Outer two tiles are equidistant from centre.
      expect((pX - mid).abs(), closeTo((rX - mid).abs(), 1));
    });

    testWidgets('explicit centerWhenFits: false left-aligns items',
        (tester) async {
      const viewportWidth = 800.0;
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: viewportWidth,
            height: 80,
            child: SlotStrip(
              slots: [_slot('p', _iconA), _slot('q', _iconB)],
              centerWhenFits: false,
            ),
          ),
        ),
      );

      final pDx = tester.getCenter(find.byIcon(_iconA)).dx;
      // With left-aligned ListView the first tile is near the leading edge.
      expect(pDx, lessThan(viewportWidth / 2));
    });
  });

  group('SlotStrip scrolling: many items do not crash', () {
    testWidgets('renders all items when they overflow the viewport',
        (tester) async {
      // 10 slots in a 240-dp wide container — they must overflow.
      final slots = List.generate(
        10,
        (i) => ToolbarSlot(
          id: 'tab$i',
          icon: Icons.circle,
          label: 'tab$i',
          onTap: () {},
        ),
      );
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 240,
            height: 80,
            child: SlotStrip(slots: slots),
          ),
        ),
      );

      // At least the first icon is visible; no exception was thrown.
      expect(find.byIcon(Icons.circle), findsWidgets);
    });

    testWidgets('scrolling to the last item makes it visible',
        (tester) async {
      final icons = List.generate(10, (i) => IconData(0xe000 + i));
      final slots = List.generate(
        10,
        (i) => ToolbarSlot(
          id: 'slot$i',
          icon: icons[i],
          label: 'slot$i',
          onTap: () {},
        ),
      );
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 240,
            height: 80,
            child: SlotStrip(slots: slots),
          ),
        ),
      );

      // Scroll right until the last item appears.
      await tester.scrollUntilVisible(
        find.byIcon(icons.last),
        60,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byIcon(icons.last), findsOneWidget);
    });
  });
}

