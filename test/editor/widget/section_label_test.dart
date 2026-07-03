import 'package:canvas_engine/features/editor/presentation/widgets/section_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('default: sentence case, letterSpacing 0 (existing '
      'consumers unaffected)', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SectionLabel('Alignment'))),
    );
    expect(find.text('Alignment'), findsOneWidget);
    final text = tester.widget<Text>(find.text('Alignment'));
    expect(text.style!.letterSpacing, 0);
  });

  testWidgets('uppercase: true renders upper-cased text (Paint '
      '_Label/_SectionLabel parity)', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SectionLabel('opacity', uppercase: true, letterSpacing: 0.8),
        ),
      ),
    );
    expect(find.text('OPACITY'), findsOneWidget);
    expect(find.text('opacity'), findsNothing);
    final text = tester.widget<Text>(find.text('OPACITY'));
    expect(text.style!.letterSpacing, 0.8);
  });
}
