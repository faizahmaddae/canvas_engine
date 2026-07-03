import 'package:canvas_engine/features/editor/ui/precision_disclosure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('PrecisionDisclosure — icon-header grammar (shape/image)', () {
    testWidgets('starts collapsed; children hidden until tapped', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          PrecisionDisclosure(
            icon: Icons.tune_rounded,
            titleClosed: 'Adjust precisely',
            subtitle: 'Blur, direction, opacity',
            children: const [Text('inner-content')],
          ),
        ),
      );
      expect(find.text('Adjust precisely'), findsOneWidget);
      expect(find.text('Blur, direction, opacity'), findsOneWidget);
      expect(find.text('inner-content'), findsNothing);

      await tester.tap(find.text('Adjust precisely'));
      await tester.pumpAndSettle();
      expect(find.text('inner-content'), findsOneWidget);
      // Title text is unchanged on open for the icon-header family.
      expect(find.text('Adjust precisely'), findsOneWidget);
    });
  });

  group('PrecisionDisclosure — text-panel grammar (title swap, no icon)', () {
    testWidgets('title swaps to titleOpen; no icon, no subtitle', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          PrecisionDisclosure(
            titleClosed: 'Adjust precisely',
            titleOpen: 'Hide precise controls',
            children: const [Text('inner-content')],
          ),
        ),
      );
      expect(find.byIcon(Icons.tune_rounded), findsNothing);
      expect(find.text('Adjust precisely'), findsOneWidget);

      await tester.tap(find.text('Adjust precisely'));
      await tester.pumpAndSettle();
      expect(find.text('Hide precise controls'), findsOneWidget);
      expect(find.text('Adjust precisely'), findsNothing);
      expect(find.text('inner-content'), findsOneWidget);
    });
  });

  testWidgets('chevron rotates 0.25 turns when opened', (tester) async {
    await tester.pumpWidget(
      _host(
        PrecisionDisclosure(
          titleClosed: 'Adjust precisely',
          children: const [SizedBox.shrink()],
        ),
      ),
    );
    final before = tester.widget<AnimatedRotation>(
      find.byType(AnimatedRotation),
    );
    expect(before.turns, 0);
    await tester.tap(find.text('Adjust precisely'));
    await tester.pumpAndSettle();
    final after = tester.widget<AnimatedRotation>(
      find.byType(AnimatedRotation),
    );
    expect(after.turns, 0.25);
  });

  testWidgets('initiallyOpen starts expanded', (tester) async {
    await tester.pumpWidget(
      _host(
        PrecisionDisclosure(
          titleClosed: 'Adjust precisely',
          initiallyOpen: true,
          children: const [Text('inner-content')],
        ),
      ),
    );
    expect(find.text('inner-content'), findsOneWidget);
  });
}
