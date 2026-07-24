// tb1 9/17: the unified slot model's new capabilities — swatch /
// font-family resolvers flowing into DockToolTile, and
// scroll-into-view when the active slot changes (the gap that let
// an 11-tile strip lose its highlight off-screen after swipes).

import 'package:canvas_engine/features/editor/presentation/widgets/dock_tool_tile.dart';
import 'package:canvas_engine/features/editor/toolbar/domain/toolbar_slot.dart';
import 'package:canvas_engine/features/editor/toolbar/presentation/slot_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<ToolbarSlot> _slots(int n) => [
  for (var i = 0; i < n; i++)
    ToolbarSlot(
      id: 'slot$i',
      icon: Icons.circle,
      label: 'S$i',
      onTap: () {},
      swatchColor: i == 0 ? () => const Color(0xFF123456) : null,
      fontFamily: i == 1 ? () => 'Vazir' : null,
    ),
];

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(height: 90, child: child)),
);

void main() {
  testWidgets('swatch and font-family resolvers reach DockToolTile', (
    tester,
  ) async {
    await tester.pumpWidget(_host(SlotStrip(slots: _slots(3))));
    final tiles = tester
        .widgetList<DockToolTile>(find.byType(DockToolTile))
        .toList();
    expect(tiles[0].swatchColor, const Color(0xFF123456));
    expect(tiles[0].fontFamily, isNull);
    expect(tiles[1].fontFamily, 'Vazir');
    expect(tiles[1].swatchColor, isNull);
  });

  testWidgets('activating an off-screen slot scrolls it into view', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final slots = _slots(15);
    await tester.pumpWidget(
      _host(SlotStrip(slots: slots, controller: controller)),
    );
    expect(controller.offset, 0);

    await tester.pumpWidget(
      _host(
        SlotStrip(slots: slots, controller: controller, activeId: 'slot14'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      controller.offset,
      greaterThan(0),
      reason: 'active tile must be auto-scrolled into view',
    );
    // And it clamps to the scrollable range.
    expect(
      controller.offset,
      lessThanOrEqualTo(controller.position.maxScrollExtent),
    );
  });
}
