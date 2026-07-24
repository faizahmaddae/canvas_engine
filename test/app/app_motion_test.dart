// tb5 3/9: the motion vocabulary, and the accessibility setting it
// exists to honour.

import 'package:canvas_engine/app/theme/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<Duration> resolve(
    WidgetTester tester, {
    required bool disableAnimations,
  }) async {
    late Duration seen;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Builder(
          builder: (context) {
            seen = AppMotion.of(context, AppMotion.standard);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return seen;
  }

  testWidgets('normally the role duration passes through', (tester) async {
    expect(
      await resolve(tester, disableAnimations: false),
      AppMotion.standard,
    );
  });

  testWidgets('Reduce Motion collapses the tween to zero', (tester) async {
    expect(
      await resolve(tester, disableAnimations: true),
      Duration.zero,
      reason: 'the end state still happens — it just arrives without '
          'the animation',
    );
  });

  testWidgets('no MediaQuery at all is not an error', (tester) async {
    late Duration seen;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          seen = AppMotion.of(context, AppMotion.reveal);
          return const SizedBox.shrink();
        },
      ),
    );
    expect(seen, AppMotion.reveal);
  });

  test('the roles are ordered shortest to longest', () {
    expect(AppMotion.state < AppMotion.standard, isTrue);
    expect(AppMotion.standard < AppMotion.reveal, isTrue);
    expect(AppMotion.reveal < AppMotion.surface, isTrue);
  });
}
