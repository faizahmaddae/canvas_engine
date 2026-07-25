import 'package:canvas_engine/features/editor/presentation/widgets/floating_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/editor_breakpoints.dart';
import 'package:flutter_test/flutter_test.dart';

/// Smoke tests for the shared floating-bar primitives. These widgets
/// back the Paint and Shape floating toolbars; if their public API or
/// the active-state colour rule regresses, both bars regress in
/// lock-step. Keeping the contract pinned here is cheaper than two
/// duplicated golden tests on the bars themselves.
void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.light}) {
    return MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        colorSchemeSeed: const Color(0xFF1976D2),
      ),
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('FloatingPillButton fires onTap and is wrapped in Semantics', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        FloatingPillButton(
          semanticLabel: 'Demo',
          onTap: () => taps++,
          child: const Text('hi'),
        ),
      ),
    );
    // Find the Semantics widget by its label property — proves the
    // pill is reachable to a screen reader. We can't use
    // `find.bySemanticsLabel` because the test environment doesn't
    // mount the SemanticsService.
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Demo',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('hi'));
    expect(taps, 1);
  });

  testWidgets(
    'FloatingPillButton active=true tints fill with primary; idle stays '
    'transparent',
    (tester) async {
      Future<Color?> background(bool active) async {
        await tester.pumpWidget(
          host(
            FloatingPillButton(
              semanticLabel: 'Toggle',
              active: active,
              onTap: () {},
              child: const SizedBox(width: 1, height: 1),
            ),
          ),
        );
        // Settle the active-state animation.
        await tester.pumpAndSettle();
        final container = tester.widget<AnimatedContainer>(
          find.byType(AnimatedContainer),
        );
        final decoration = container.decoration as BoxDecoration;
        return decoration.color;
      }

      expect(await background(false), Colors.transparent);
      final activeBg = await background(true);
      // Idle vs active must differ (active = primary @16% alpha, idle =
      // transparent). We don't pin the exact rgba so seed colour can
      // change in the design system without breaking the test.
      expect(activeBg, isNot(Colors.transparent));
    },
  );

  testWidgets('FloatingGlassBar lays out its child without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const SizedBox(
          width: 200,
          height: kFloatingBarHeight,
          child: FloatingGlassBar(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [Text('a'), SizedBox(width: 4), Text('b')],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('every pill clears the 44dp touch floor', (tester) async {
    // The bar's ClipRRect clips hit-testing, so a pill can never be
    // taller than the shell around it. tb2's a11y pass got the pills
    // to the full bar height and recorded the 40dp shell as a
    // structural ceiling it could not pass; the shell is now
    // kMinHitTarget, which is what actually lifts them onto the floor.
    // The PAINTED pill row stays 32dp — only the halo grew.
    await tester.pumpWidget(
      host(
        SizedBox(
          height: kFloatingBarHeight,
          child: FloatingGlassBar(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingPillButton(
                  key: const ValueKey('pill-a'),
                  onTap: () {},
                  semanticLabel: 'a',
                  child: const Text('a'),
                ),
                FloatingPillButton(
                  key: const ValueKey('pill-b'),
                  onTap: () {},
                  semanticLabel: 'b',
                  child: const Text('b'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    for (final key in const [ValueKey('pill-a'), ValueKey('pill-b')]) {
      expect(
        tester.getSize(find.byKey(key)).height,
        greaterThanOrEqualTo(kMinHitTarget),
        reason: '$key is below the editor-wide touch floor',
      );
    }

    // And the pill still PAINTS at 32.
    final painted = tester.getSize(
      find.descendant(
        of: find.byKey(const ValueKey('pill-a')),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(painted.height, 32);
  });

  testWidgets('FloatingColorDot paints the requested colour as fill', (
    tester,
  ) async {
    const swatch = Color(0xFFFF3B30);
    await tester.pumpWidget(host(const FloatingColorDot(color: swatch)));
    final container = tester.widget<Container>(find.byType(Container).first);
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, swatch);
    expect(decoration.shape, BoxShape.circle);
  });
}
