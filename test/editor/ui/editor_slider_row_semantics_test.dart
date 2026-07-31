// What a screen reader is handed for an adjustment slider.
//
// Three independent reviewers, two of them reading a real
// `uiautomator` dump off the device, reported the same pair of defects
// here — and a round that "fixed" it fixed only `layer_opacity_control`
// (one bespoke slider) while this shared row, which every fine-tune,
// vignette, border-width, shadow, mask-feather, text and shape slider
// is built from, kept the broken shape. So the contract gets pinned at
// the widget, not at a call site.
//
// Two things have to hold at once:
//   * the SLIDER's own node carries the name — it is the node a screen
//     reader focuses and the one that owns increase/decrease. A
//     `Semantics` wrapper around the whole row produces a node ABOVE
//     it, leaving the SeekBar anonymous.
//   * the visible label and readout `Text`s are OUT of the tree — left
//     in, they concatenate onto the row and the parameter is announced
//     twice, then the number a third time (the slider already carries
//     it as `value`).

import 'package:canvas_engine/features/editor/ui/editor_slider_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  String? label,
  String? semanticLabel,
  double value = 0,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: EditorSliderRow(
        label: label,
        semanticLabel: semanticLabel,
        value: value,
        min: -100,
        max: 100,
        format: (v) => '${v.round()}',
        onChanged: (_) {},
      ),
    ),
  ),
);

/// Every semantics node in the tree, flattened, paired with its MERGED
/// data.
///
/// Two corrections an earlier draft of this test needed, both of which
/// made a WORKING fix look broken:
///   * `SemanticsNode.label` is the node's own contribution before
///     `MergeSemantics` is applied — the platform sees
///     `getSemanticsData()`, which folds merged descendants in;
///   * a node with `isMergedIntoParent` is not exposed to the platform
///     at all, so counting it double-counts. Only unmerged nodes are
///     what a screen reader can actually land on.
List<SemanticsData> _nodes(WidgetTester tester) {
  final out = <SemanticsData>[];
  void walk(SemanticsNode n) {
    if (!n.isMergedIntoParent) out.add(n.getSemanticsData());
    n.visitChildren((SemanticsNode c) {
      walk(c);
      return true;
    });
  }

  // `rootPipelineOwner` does not carry the widget tree's semantics
  // owner on the pinned SDK (3.41.7); this is the accessor that works.
  // ignore: deprecated_member_use
  walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return out;
}

void main() {
  testWidgets('the slider node itself carries the name', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, label: 'Brightness', value: 0);

    final slider = _nodes(tester).where((n) => n.flagsCollection.isSlider);
    expect(slider, hasLength(1));
    expect(
      slider.single.label,
      'Brightness',
      reason:
          'this is the node a screen reader focuses and adjusts; '
          'an unnamed one announces a bare number',
    );
    expect(slider.single.value, '0');
    handle.dispose();
  });

  testWidgets('the parameter name is spoken exactly once', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, label: 'Brightness', value: 0);

    // Count OCCURRENCES, not nodes. The old form put the name on the
    // row node AND left the visible Text in the tree, so one node's
    // merged label read «Brightness Brightness 0» — a node-level count
    // would have seen exactly one node and passed.
    final occurrences = _nodes(tester)
        .map((n) => 'Brightness'.allMatches(n.label).length)
        .fold<int>(0, (a, b) => a + b);
    expect(
      occurrences,
      1,
      reason:
          'the visible label Text must be excluded, or the row '
          'announces «Brightness Brightness 0»',
    );
    handle.dispose();
  });

  testWidgets('the readout does not repeat the slider value', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, label: 'Contrast', value: 42);

    // The number belongs to the slider's `value`, not to a second node.
    final carriers = _nodes(
      tester,
    ).where((n) => n.label.contains('42') || n.value.contains('42')).toList();
    expect(carriers, hasLength(1));
    expect(carriers.single.flagsCollection.isSlider, isTrue);
    handle.dispose();
  });

  testWidgets('a row with no visible label still names its slider', (
    tester,
  ) async {
    // shape-style's opacity/radius rows render no label and MUST pass
    // `semanticLabel`, or the control is unreachable by name.
    final handle = tester.ensureSemantics();
    await _pump(tester, semanticLabel: 'Opacity', value: 10);

    final slider = _nodes(tester).firstWhere((n) => n.flagsCollection.isSlider);
    expect(slider.label, 'Opacity');
    handle.dispose();
  });
}
