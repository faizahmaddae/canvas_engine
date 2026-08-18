// Phase 4 plan §9 (a11y sweep remainder): dock tiles, preset chips,
// and segmented preset tiles are shared single-source-of-truth
// widgets used across every editor toolbar/panel, but attached no
// Semantics of their own -- selection state and, for DockToolTile's
// value display, the category label were invisible to a screen
// reader. Pins the fix so it can't silently regress back to a bare
// GestureDetector/InkWell with no accessible name or selected state.

import 'package:canvas_engine/features/editor/presentation/widgets/dock_tool_tile.dart';
import 'package:canvas_engine/features/editor/toolbar/presentation/widgets/preset_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('DockToolTile', () {
    testWidgets('exposes label, selected and a tap action', (tester) async {
      await tester.pumpWidget(
        host(
          DockToolTile(
            icon: Icons.brush,
            label: 'Paint',
            active: true,
            onTap: () {},
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(DockToolTile)),
        matchesSemantics(
          label: 'Paint',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('valueText becomes the semantics value, not the label', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          DockToolTile(
            icon: Icons.format_size,
            label: 'Font Size',
            valueText: '24 pt',
            onTap: () {},
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(DockToolTile)),
        matchesSemantics(
          label: 'Font Size',
          value: '24 pt',
          isButton: true,
          hasSelectedState: true,
          isSelected: false,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('disabled tile reports enabled: false and no tap action', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          DockToolTile(
            icon: Icons.brush,
            label: 'Paint',
            enabled: false,
            onTap: () {},
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(DockToolTile)),
        matchesSemantics(
          label: 'Paint',
          isButton: true,
          hasSelectedState: true,
          isSelected: false,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
    });
  });

  group('PresetChip', () {
    testWidgets('exposes label, selected and a tap action', (tester) async {
      await tester.pumpWidget(
        host(PresetChip(label: '24', selected: true, onTap: () {})),
      );

      expect(
        tester.getSemantics(find.byType(PresetChip)),
        matchesSemantics(
          label: '24',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
    });
  });

  group('PresetChip.option (tile mode)', () {
    testWidgets('exposes label, selected and a tap action', (tester) async {
      await tester.pumpWidget(
        host(
          PresetChip.option(
            selected: true,
            icon: Icons.crop_square,
            label: 'Original',
            onTap: () {},
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(PresetChip)),
        matchesSemantics(
          label: 'Original',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('unselected tile reports selected: false', (tester) async {
      await tester.pumpWidget(
        host(
          PresetChip.option(
            selected: false,
            icon: Icons.crop_square,
            label: 'Pop',
            onTap: () {},
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(PresetChip)),
        matchesSemantics(
          label: 'Pop',
          isButton: true,
          hasSelectedState: true,
          isSelected: false,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('disabled option reports enabled false and has no action', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          PresetChip.option(
            selected: false,
            enabled: false,
            icon: Icons.crop_square,
            label: 'Unavailable',
            onTap: () {},
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(PresetChip)),
        matchesSemantics(
          label: 'Unavailable',
          isButton: true,
          hasSelectedState: true,
          isSelected: false,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
    });
  });
}
