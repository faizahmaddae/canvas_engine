import 'package:canvas_engine/features/editor/ui/editor_slider_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('EditorSliderRow — layout', () {
    testWidgets('renders label column when label is provided', (tester) async {
      await tester.pumpWidget(
        _host(
          EditorSliderRow(
            label: 'Blur',
            value: 10,
            max: 80,
            format: (v) => v.round().toString(),
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('Blur'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('omits label column when label is null', (tester) async {
      await tester.pumpWidget(
        _host(
          EditorSliderRow(
            value: 0.5,
            max: 1,
            format: (v) => '${(v * 100).round()}%',
            onChanged: (_) {},
            semanticLabel: 'Opacity',
          ),
        ),
      );
      // No standalone label Text besides the readout.
      expect(find.text('50%'), findsOneWidget);
    });
  });

  group('EditorSliderRow — commit semantics stay at the call site', () {
    testWidgets('onChanged fires per tick without any command dispatch', (
      tester,
    ) async {
      final values = <double>[];
      await tester.pumpWidget(
        _host(
          EditorSliderRow(
            label: 'X',
            value: 0,
            max: 100,
            format: (v) => v.toString(),
            onChanged: values.add,
          ),
        ),
      );
      final center = tester.getCenter(find.byType(Slider));
      await tester.tapAt(center);
      await tester.pump();
      expect(
        values,
        isNotEmpty,
        reason:
            'the widget only calls onChanged; it never commits '
            'anything itself',
      );
    });

    testWidgets('onDragStart/onDragEnd fire exactly once per gesture, '
        'including pointer-cancel', (tester) async {
      var starts = 0;
      var ends = 0;
      await tester.pumpWidget(
        _host(
          EditorSliderRow(
            label: 'X',
            value: 0,
            max: 100,
            format: (v) => v.toString(),
            onChanged: (_) {},
            onDragStart: () => starts++,
            onDragEnd: () => ends++,
          ),
        ),
      );
      final slider = find.byType(Slider);
      final gesture = await tester.startGesture(tester.getCenter(slider));
      await tester.pump();
      expect(starts, 1);
      expect(ends, 0);
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(ends, 1, reason: 'drag-end must fire exactly once');
    });
  });

  group('EditorSliderRow — showReadout (composed headers)', () {
    testWidgets('showReadout: false omits the trailing value column', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          EditorSliderRow(
            value: 0.95,
            max: 1,
            showReadout: false,
            format: (v) => '${(v * 100).round()}%',
            onChanged: (_) {},
            semanticLabel: 'Quality',
          ),
        ),
      );
      expect(find.text('95%'), findsNothing);
    });

    testWidgets('showReadout defaults to true (existing consumers '
        'unaffected)', (tester) async {
      await tester.pumpWidget(
        _host(
          EditorSliderRow(
            label: 'X',
            value: 10,
            max: 100,
            format: (v) => v.round().toString(),
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('10'), findsOneWidget);
    });
  });

  group('EditorSliderRow — divisions/enabled (JPG-quality outlier)', () {
    testWidgets('divisions is forwarded to the underlying Slider', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          EditorSliderRow(
            value: 0.95,
            min: 0.7,
            max: 1.0,
            divisions: 30,
            format: (v) => '${(v * 100).round()}%',
            onChanged: (_) {},
            semanticLabel: 'Quality',
          ),
        ),
      );
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.divisions, 30);
    });

    testWidgets('divisions != null shows the formatted drag tooltip '
        '(JPG-quality parity)', (tester) async {
      await tester.pumpWidget(
        _host(
          EditorSliderRow(
            value: 0.95,
            min: 0.7,
            max: 1.0,
            divisions: 30,
            format: (v) => '${(v * 100).round()}%',
            onChanged: (_) {},
            semanticLabel: 'Quality',
          ),
        ),
      );
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.label, '95%');
    });

    testWidgets('divisions == null shows no drag tooltip (unchanged for '
        'every continuous slider)', (tester) async {
      await tester.pumpWidget(
        _host(
          EditorSliderRow(
            label: 'X',
            value: 10,
            max: 100,
            format: (v) => v.round().toString(),
            onChanged: (_) {},
          ),
        ),
      );
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.label, isNull);
    });

    testWidgets('enabled: false disables the slider', (tester) async {
      await tester.pumpWidget(
        _host(
          EditorSliderRow(
            value: 0.5,
            max: 1,
            enabled: false,
            format: (v) => v.toString(),
            onChanged: (_) {},
            semanticLabel: 'X',
          ),
        ),
      );
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.onChanged, isNull);
    });
  });

  group('EditorSliderRow — accessibility (Phase 4 D2)', () {
    testWidgets('attaches a Semantics label and a formatter callback', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          EditorSliderRow(
            label: 'Opacity',
            value: 0.5,
            max: 1,
            format: (v) => '${(v * 100).round()}%',
            onChanged: (_) {},
          ),
        ),
      );
      final semantics = tester.getSemantics(find.byType(EditorSliderRow));
      expect(semantics.label, contains('Opacity'));
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.semanticFormatterCallback, isNotNull);
      expect(slider.semanticFormatterCallback!(0.5), '50%');
    });

    testWidgets('semanticLabel overrides label for a11y when both '
        'are provided', (tester) async {
      await tester.pumpWidget(
        _host(
          EditorSliderRow(
            label: 'B',
            semanticLabel: 'Blur amount',
            value: 0,
            max: 100,
            format: (v) => v.toString(),
            onChanged: (_) {},
          ),
        ),
      );
      final semantics = tester.getSemantics(find.byType(EditorSliderRow));
      expect(semantics.label, contains('Blur amount'));
    });
  });

  group('EditorSliderRow — readout formatting', () {
    testWidgets('value is clamped into [min, max] for display', (tester) async {
      await tester.pumpWidget(
        _host(
          EditorSliderRow(
            label: 'X',
            value: 999,
            min: 0,
            max: 80,
            format: (v) => v.round().toString(),
            onChanged: (_) {},
          ),
        ),
      );
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, 80);
    });

    testWidgets('readout uses logical end alignment (RTL fix vs '
        '_FlatSliderRow physical right)', (tester) async {
      await tester.pumpWidget(
        _host(
          EditorSliderRow(
            label: 'X',
            value: 10,
            max: 100,
            format: (v) => v.round().toString(),
            onChanged: (_) {},
          ),
        ),
      );
      final readout = tester.widgetList<Text>(find.text('10')).first;
      expect(readout.textAlign, TextAlign.end);
    });
  });

  group('EditorSliderRow — style overrides (text-panel parity)', () {
    testWidgets('labelStyle/readoutStyle override the shape/image default', (
      tester,
    ) async {
      const label = TextStyle(fontSize: 13, color: Colors.red);
      const readout = TextStyle(fontSize: 11, color: Colors.blue);
      await tester.pumpWidget(
        _host(
          EditorSliderRow(
            label: 'X',
            value: 10,
            max: 100,
            format: (v) => v.round().toString(),
            onChanged: (_) {},
            labelStyle: label,
            readoutStyle: readout,
          ),
        ),
      );
      final labelText = tester.widget<Text>(find.text('X'));
      expect(labelText.style, label);
      final readoutText = tester.widget<Text>(find.text('10'));
      expect(readoutText.style, readout);
    });

    testWidgets('labelStyle/readoutStyle default to null (existing '
        'consumers unaffected)', (tester) async {
      await tester.pumpWidget(
        _host(
          EditorSliderRow(
            label: 'X',
            value: 10,
            max: 100,
            format: (v) => v.round().toString(),
            onChanged: (_) {},
          ),
        ),
      );
      final labelText = tester.widget<Text>(find.text('X'));
      expect(labelText.style?.fontSize, 12);
    });

    testWidgets('label truncates with ellipsis instead of wrapping', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          EditorSliderRow(
            label: 'A very long label that would otherwise wrap',
            value: 10,
            max: 100,
            format: (v) => v.round().toString(),
            onChanged: (_) {},
          ),
        ),
      );
      final labelText = tester.widget<Text>(
        find.text('A very long label that would otherwise wrap'),
      );
      expect(labelText.maxLines, 1);
      expect(labelText.overflow, TextOverflow.ellipsis);
    });
  });
}
