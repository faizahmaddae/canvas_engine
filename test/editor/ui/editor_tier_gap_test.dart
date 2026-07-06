import 'package:canvas_engine/features/editor/ui/editor_tier_gap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('EditorTierGap is a 20px gutter with a 1x30 hairline', (
    tester,
  ) async {
    // Chrome-separation pass: the divider widened (13→20) and its
    // hairline grew (28→30 @ 70% alpha) so it reads as an
    // INTENTIONAL group boundary, not an accidental gap.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: EditorTierGap())),
    );
    final outer = tester.widget<Container>(
      find.byType(Container).first,
    );
    expect(outer.constraints?.maxWidth ?? (outer.constraints!.minWidth), 20);

    final hairline = tester
        .widgetList<Container>(find.byType(Container))
        .last;
    expect(hairline.constraints!.maxWidth, 1);
    expect(hairline.constraints!.maxHeight, 30);
  });
}
