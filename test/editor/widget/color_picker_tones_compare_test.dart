// Contracts for the custom level's two studio additions: the tonal
// ramp (one-tap tints/shades of the live hue) and the before|after
// compare pill (tap the original half to restore the colour the
// picker opened on). Both ride the existing commit fence: a tone is
// a mixed pick (committed + recents-worthy); a restore is un-mixing
// (committed, never recorded).

import 'package:canvas_engine/features/color_picker/presentation/color_picker_body.dart';
import 'package:canvas_engine/features/editor/application/recent_colors_controller.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<
    ({ProviderContainer container, List<Color> changes, List<Color> commits})
  >
  pumpCustomLevel(
    WidgetTester tester, {
    Color initial = const Color(0xFFEF4444),
  }) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final changes = <Color>[];
    final commits = <Color>[];
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ColorPickerBody(
              initial: initial,
              startAtCustom: true,
              onClose: () {},
              onChanged: changes.add,
              onCommitted: commits.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (container: container, changes: changes, commits: commits);
  }

  testWidgets('a tone tap is a mixed pick: same hue, committed, '
      'recorded in recents', (tester) async {
    final h = await pumpCustomLevel(tester);

    await tester.tap(find.byKey(const ValueKey('color-picker-tone-5')));
    await tester.pumpAndSettle();

    expect(h.commits, hasLength(1));
    final tone = h.commits.single;
    final toneHsv = HSVColor.fromColor(tone);
    final initialHsv = HSVColor.fromColor(const Color(0xFFEF4444));
    expect(
      (toneHsv.hue - initialHsv.hue).abs(),
      lessThan(2),
      reason: 'the ramp derives tones of the CURRENT hue',
    );
    expect(
      toneHsv.value,
      lessThan(initialHsv.value),
      reason: 'tone-5 is the deep shade',
    );
    expect(
      h.container.read(recentColorsControllerProvider).map((c) => c.toARGB32()),
      contains(tone.toARGB32()),
      reason: 'a tone is mixed, so it earns a recents slot',
    );
  });

  testWidgets('the ramp preserves the working alpha', (tester) async {
    final h = await pumpCustomLevel(tester, initial: const Color(0x80EF4444));

    await tester.tap(find.byKey(const ValueKey('color-picker-tone-0')));
    await tester.pumpAndSettle();

    expect(h.commits, hasLength(1));
    expect(
      (h.commits.single.a - 0x80 / 0xFF).abs(),
      lessThan(0.01),
      reason: 'tones are hue/value choices — alpha stays the slider’s',
    );
  });

  testWidgets('the compare pill restores the colour the picker opened '
      'on — committed, never recents-worthy', (tester) async {
    final h = await pumpCustomLevel(tester);

    // Mix first so there is something to restore from.
    await tester.tap(find.byKey(const ValueKey('color-picker-tone-5')));
    await tester.pumpAndSettle();
    final mixed = h.commits.last;
    expect(mixed.toARGB32(), isNot(0xFFEF4444));

    await tester.tap(
      find.byKey(const ValueKey('color-picker-compare-restore')),
    );
    await tester.pumpAndSettle();

    expect(h.commits.last.toARGB32(), 0xFFEF4444);
    expect(h.changes.last.toARGB32(), 0xFFEF4444);
    expect(
      h.container.read(recentColorsControllerProvider).map((c) => c.toARGB32()),
      isNot(contains(0xFFEF4444)),
      reason: 'restoring the original is un-mixing — no recents slot',
    );
  });
}
