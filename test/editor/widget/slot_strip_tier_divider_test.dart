/// Widget-level coverage for [SlotStrip] tier-divider rendering.
///
/// Slots carry a [SlotTier]; the strip must insert a hairline
/// divider whenever consecutive slots belong to different tiers.
/// Single-tier strips render no dividers at all.
library;

import 'package:canvas_engine/features/editor/toolbar/domain/toolbar_slot.dart';
import 'package:canvas_engine/features/editor/toolbar/presentation/slot_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ToolbarSlot _slot(String id, IconData icon, SlotTier tier) => ToolbarSlot(
      id: id,
      icon: icon,
      label: id,
      tier: tier,
      onTap: () {},
    );

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SizedBox(width: 800, height: 80, child: child)));

/// Finder for the divider's 1-dp wide × 28-dp tall hairline. The
/// divider widget itself is private so we identify it via its visible
/// `Container` geometry — stable enough for a regression check
/// without coupling to the internal class name.
Finder _hairlineFinder() => find.byWidgetPredicate((w) {
      if (w is! Container) return false;
      final c = w.constraints;
      if (c == null) return false;
      return c.maxWidth == 1 && c.maxHeight == 28;
    });

void main() {
  group('SlotStrip tier dividers', () {
    testWidgets('no divider when every slot is in the same tier',
        (tester) async {
      await tester.pumpWidget(_wrap(SlotStrip(slots: [
        _slot('a', Icons.looks_one_rounded, SlotTier.tier1),
        _slot('b', Icons.looks_two_rounded, SlotTier.tier1),
        _slot('c', Icons.looks_3_rounded, SlotTier.tier1),
      ])));
      expect(_hairlineFinder(), findsNothing);
    });

    testWidgets('single divider between tier1 and tier2', (tester) async {
      await tester.pumpWidget(_wrap(SlotStrip(slots: [
        _slot('a', Icons.looks_one_rounded, SlotTier.tier1),
        _slot('b', Icons.looks_two_rounded, SlotTier.tier1),
        _slot('c', Icons.looks_3_rounded, SlotTier.tier2),
      ])));
      expect(_hairlineFinder(), findsOneWidget);
    });

    testWidgets('two dividers across three tiers (tier1→tier2→tier3)',
        (tester) async {
      // This mirrors the main editor toolbar layout (Add ·
      // Photo edits · Document) and is the regression check for
      // the editor strip's grouped grammar.
      await tester.pumpWidget(_wrap(SlotStrip(slots: [
        _slot('a', Icons.looks_one_rounded, SlotTier.tier1),
        _slot('b', Icons.looks_two_rounded, SlotTier.tier1),
        _slot('c', Icons.looks_3_rounded, SlotTier.tier2),
        _slot('d', Icons.looks_4_rounded, SlotTier.tier2),
        _slot('e', Icons.looks_5_rounded, SlotTier.tier3),
      ])));
      expect(_hairlineFinder(), findsNWidgets(2));
    });

    testWidgets('divider position respects slot order, not tier value',
        (tester) async {
      // tier3 → tier1 transition still inserts a divider (renderer
      // is data-driven, not order-of-tier based).
      await tester.pumpWidget(_wrap(SlotStrip(slots: [
        _slot('a', Icons.looks_one_rounded, SlotTier.tier3),
        _slot('b', Icons.looks_two_rounded, SlotTier.tier1),
      ])));
      expect(_hairlineFinder(), findsOneWidget);
    });
  });
}
