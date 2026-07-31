// Contract §10.3 — the three states a P-scope control can be in, and
// the two that are easy to confuse.
//
// Crop and Look target the protected base photo. In a PHOTO project
// with no qualifying target (deleted, or hidden from the layers
// drawer) they are UNAVAILABLE: dimmed but live, because a disabled
// slot does not fire `onTap` and would take the recovery with it.
// In a DESIGN project they are ABSENT — the scope itself does not
// apply there, which `toolbar_group_order_test.dart` pins.
//
// Unavailable therefore has to be legible and announceable: it is a
// state the user is expected to find and press, not a dead control.

import 'package:canvas_engine/features/editor/presentation/widgets/dock_tool_tile.dart';
import 'package:canvas_engine/features/editor/toolbar/domain/toolbar_slot.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

    // Previously this asserted the two states looked IDENTICAL, on the
    // reasoning that "both mean not-now". They do not mean the same
    // thing, and the identical treatment was an accessibility defect:
    // at the shared 35% alpha the unavailable tile's icon measured
    // 1.65:1 and its label 2.16:1 against the dock surface — under the
    // 3:1 floor for non-text UI, let alone AA — on a control that is
    // deliberately live and that the user is expected to find and
    // press (the two tests above pin exactly that distinction). WCAG's
    // inactive-component exemption covers `enabled: false`; it does
    // not cover this. So the contract is now: recessed, but plainly
    // more legible than truly disabled.
    testWidgets('unavailable is dimmed — but readably more than disabled', (
      tester,
    ) async {
      await pump(tester, enabled: true, unavailable: true, onTap: () {});
      final unavailable = labelColour(tester)!;

      await pump(tester, enabled: false, unavailable: false, onTap: () {});
      final disabled = labelColour(tester)!;

      await pump(tester, enabled: true, unavailable: false, onTap: () {});
      final normal = labelColour(tester)!;

      expect(
        unavailable,
        isNot(normal),
        reason: 'unavailable must still read as recessed',
      );
      expect(
        unavailable,
        isNot(disabled),
        reason: 'a tappable tile must not look inert',
      );
      expect(
        unavailable.a,
        greaterThan(disabled.a),
        reason: 'the tappable state carries the higher contrast',
      );
    });

    // §10.3: the dim is invisible to a screen reader. Without a hint
    // the node said "Look, button" on a blank canvas exactly as it
    // did on a full one — the tile was honest to sighted users and
    // silent to everyone else.
    testWidgets('unavailable announces its precondition, and still reports '
        'itself enabled so the recovery stays reachable', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: DockToolTile(
                icon: Icons.abc,
                label: 'Look',
                unavailable: true,
                unavailableHint: 'Needs a visible photo',
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      final node = tester.getSemantics(find.byType(DockToolTile));
      expect(node.label, 'Look');
      expect(
        node.hint,
        'Needs a visible photo',
        reason: 'the unmet precondition must reach assistive tech',
      );
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: 'announcing it inert would hide the recovery (§10.3)',
      );
      handle.dispose();
    });

    testWidgets('an available tile carries no hint', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: DockToolTile(
                icon: Icons.abc,
                label: 'Look',
                unavailableHint: 'Needs a visible photo',
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      final node = tester.getSemantics(find.byType(DockToolTile));
      expect(node.hint, isEmpty);
      handle.dispose();
    });
  });
}
