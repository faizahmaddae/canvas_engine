import 'paint_tool_type.dart';

/// The seven fixed slots of the paint bench's tool rack
/// (`docs/paint-redesign-2026-08.md` §2). Order here is render order.
///
/// A rack slot is not a [PaintToolType]: the line and shape *families*
/// collapse to one slot each (the variant is chosen inside the slot's
/// sheet and remembered by the session), and [adjust] arms nothing at
/// all — it is the posture switch that returns the canvas to ordinary
/// selection so committed strokes can be picked and restyled.
enum PaintBenchSlot { pen, line, arrow, shape, blur, adjust, eraser }

/// Line-family variants the Line slot can arm (peers of one another —
/// a committed line kind restyles freely within this set).
const Set<PaintToolType> kLineFamilyTools = {
  PaintToolType.line,
  PaintToolType.dashLine,
  PaintToolType.dashDotLine,
};

/// Shape-family variants the Shape slot can arm (box-kind peers).
const Set<PaintToolType> kShapeFamilyTools = {
  PaintToolType.rectangle,
  PaintToolType.circle,
  PaintToolType.hexagon,
  PaintToolType.polygon,
};

/// The rack slot that owns [tool]. `null` (no armed tool) is the
/// adjust posture.
PaintBenchSlot benchSlotForTool(PaintToolType? tool) {
  if (tool == null) return PaintBenchSlot.adjust;
  if (kLineFamilyTools.contains(tool)) return PaintBenchSlot.line;
  if (kShapeFamilyTools.contains(tool)) return PaintBenchSlot.shape;
  return switch (tool) {
    PaintToolType.freestyle => PaintBenchSlot.pen,
    PaintToolType.arrow => PaintBenchSlot.arrow,
    PaintToolType.blur => PaintBenchSlot.blur,
    PaintToolType.eraser => PaintBenchSlot.eraser,
    // Families are handled above; switch stays exhaustive for the
    // compiler without a default that could hide a new tool.
    PaintToolType.line ||
    PaintToolType.dashLine ||
    PaintToolType.dashDotLine => PaintBenchSlot.line,
    PaintToolType.rectangle ||
    PaintToolType.circle ||
    PaintToolType.hexagon ||
    PaintToolType.polygon => PaintBenchSlot.shape,
  };
}
