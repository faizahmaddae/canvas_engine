import 'package:canvas_engine/features/editor/ui/editor_tier_gap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('EditorTierGap is a 13px gutter with a 1x28 hairline', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: EditorTierGap())),
    );
    final outer = tester.widget<Container>(
      find.byType(Container).first,
    );
    expect(outer.constraints?.maxWidth ?? (outer.constraints!.minWidth), 13);

    final hairline = tester
        .widgetList<Container>(find.byType(Container))
        .last;
    expect(hairline.constraints!.maxWidth, 1);
    expect(hairline.constraints!.maxHeight, 28);
  });
}
