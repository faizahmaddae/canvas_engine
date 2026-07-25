// Crop and Look act on an ImageLayer, so in a document with no photo
// neither can do anything. They used to look exactly as available as
// Shape or Draw, and only admitted otherwise once you tapped them —
// which is what made a user ask whether the app was broken.
//
// Disabling them outright would have been worse: a disabled slot does
// not fire `onTap`, so it can neither explain itself nor offer a way
// out, and the one-tap "Add photo" recovery would have gone with it.
//
// Hence a third state. `availableBuilder` renders the tile dimmed —
// honest before it is pressed — while leaving it tappable, so the tap
// still reaches the handler that offers to import a photo.

import 'package:canvas_engine/features/editor/presentation/widgets/dock_tool_tile.dart';
import 'package:canvas_engine/features/editor/toolbar/domain/toolbar_slot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolbarSlot', () {
    test('a slot is available unless it says otherwise', () {
      final slot = ToolbarSlot(
        id: 'a',
        icon: Icons.abc,
        label: 'a',
        onTap: () {},
      );
      expect(slot.isAvailable, isTrue);
      expect(slot.isEnabled, isTrue);
    });

    test('availability is independent of enabled', () {
      // The two answer different questions: "can this act on anything
      // right now" vs "should this respond at all".
      final slot = ToolbarSlot(
        id: 'look',
        icon: Icons.abc,
        label: 'Look',
        onTap: () {},
        availableBuilder: () => false,
      );
      expect(slot.isAvailable, isFalse);
      expect(
        slot.isEnabled,
        isTrue,
        reason: 'unavailable must NOT imply inert — the tap is the recovery',
      );
    });

    test('availability is re-resolved, not captured', () {
      var hasPhoto = false;
      final slot = ToolbarSlot(
        id: 'crop',
        icon: Icons.abc,
        label: 'Crop',
        onTap: () {},
        availableBuilder: () => hasPhoto,
      );
      expect(slot.isAvailable, isFalse);
      hasPhoto = true;
      expect(
        slot.isAvailable,
        isTrue,
        reason: 'importing a photo has to re-light the tile',
      );
    });
  });

  group('DockToolTile', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool enabled,
      required bool unavailable,
      required VoidCallback onTap,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: DockToolTile(
                key: const ValueKey('tile'),
                icon: Icons.abc,
                label: 'Look',
                enabled: enabled,
                unavailable: unavailable,
                onTap: onTap,
              ),
            ),
          ),
        ),
      );
    }

    Color? labelColour(WidgetTester tester) =>
        tester.widget<Text>(find.text('Look')).style?.color;

    testWidgets('unavailable still dispatches its tap', (tester) async {
      var taps = 0;
      await pump(tester, enabled: true, unavailable: true, onTap: () => taps++);
      await tester.tap(find.byKey(const ValueKey('tile')));
      await tester.pump();
      expect(
        taps,
        1,
        reason: 'the tap is how the user is offered a photo to work on',
      );
    });

    testWidgets('disabled does NOT dispatch — the distinction is the point', (
      tester,
    ) async {
      var taps = 0;
      await pump(
        tester,
        enabled: false,
        unavailable: false,
        onTap: () => taps++,
      );
      await tester.tap(find.byKey(const ValueKey('tile')), warnIfMissed: false);
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('unavailable reads as dimmed as disabled', (tester) async {
      await pump(tester, enabled: true, unavailable: true, onTap: () {});
      final dimmed = labelColour(tester);

      await pump(tester, enabled: false, unavailable: false, onTap: () {});
      expect(
        labelColour(tester),
        dimmed,
        reason: 'both mean "not now", so both must look the same',
      );

      await pump(tester, enabled: true, unavailable: false, onTap: () {});
      expect(labelColour(tester), isNot(dimmed));
    });
  });
}
