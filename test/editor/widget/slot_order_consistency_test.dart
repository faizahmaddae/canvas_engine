import 'package:canvas_engine/features/editor/image/application/image_tool_controller.dart';
import 'package:canvas_engine/features/editor/shape/application/shape_tool_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drift detector. The hand-written panel-order constants must
/// match the enum's `isPanel` filter. Mismatches would silently
/// desync the strip vs sibling-swipe.
void main() {
  test('image panel order matches ImageToolSlot.values where isPanel', () {
    final derived =
        ImageToolSlot.values.where((s) => s.isPanel).toList();
    expect(kImagePanelSlotOrder, derived);
  });

  test('shape panel order matches ShapeToolSlot.values where isPanel', () {
    final derived =
        ShapeToolSlot.values.where((s) => s.isPanel).toList();
    expect(kShapePanelSlotOrder, derived);
  });

  test('image strip order is the full enum (display order)', () {
    expect(kImageStripSlotOrder, ImageToolSlot.values);
  });

  test('shape strip order is the full enum (display order)', () {
    expect(kShapeStripSlotOrder, ShapeToolSlot.values);
  });
}
