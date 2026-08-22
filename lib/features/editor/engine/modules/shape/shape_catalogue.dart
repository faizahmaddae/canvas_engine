import 'shape_layer.dart';

/// Display-time metadata for [ShapeKind]s used by the picker / replace
/// sheets and any future quick-insert UIs. Lives next to [ShapeLayer]
/// so adding a new kind only requires one file edit.
class ShapeKindCatalogueEntry {
  const ShapeKindCatalogueEntry(this.kind, this.label);
  final ShapeKind kind;
  final String label;
}

/// A named group of catalogue entries — drives the section headers in
/// the Add Shape sheet so the grid stays scannable as the catalogue
/// grows.
class ShapeKindCatalogueSection {
  const ShapeKindCatalogueSection(this.title, this.entries);
  final String title;
  final List<ShapeKindCatalogueEntry> entries;
}

/// Picker order, grouped into navigable sections. Reordering or
/// extending this list rearranges every shape sheet in the editor, so
/// adjust deliberately. The flat [kShapeCatalogue] is derived from
/// these sections so any consumer that just wants "all kinds in
/// display order" stays unchanged.
const List<ShapeKindCatalogueSection> kShapeCatalogueSections = [
  // Basic runs family-by-family (boxes → rounds → triangles →
  // polygons → quads → favourites) so related silhouettes sit next
  // to each other in the grid.
  ShapeKindCatalogueSection('Basic', [
    ShapeKindCatalogueEntry(ShapeKind.rectangle, 'Rectangle'),
    ShapeKindCatalogueEntry(ShapeKind.roundedRectangle, 'Rounded'),
    ShapeKindCatalogueEntry(ShapeKind.circle, 'Circle'),
    ShapeKindCatalogueEntry(ShapeKind.oval, 'Oval'),
    ShapeKindCatalogueEntry(ShapeKind.semicircle, 'Semicircle'),
    ShapeKindCatalogueEntry(ShapeKind.ring, 'Ring'),
    ShapeKindCatalogueEntry(ShapeKind.triangle, 'Triangle'),
    ShapeKindCatalogueEntry(ShapeKind.rightTriangle, 'Right triangle'),
    ShapeKindCatalogueEntry(ShapeKind.diamond, 'Diamond'),
    ShapeKindCatalogueEntry(ShapeKind.pentagon, 'Pentagon'),
    ShapeKindCatalogueEntry(ShapeKind.hexagon, 'Hexagon'),
    ShapeKindCatalogueEntry(ShapeKind.octagon, 'Octagon'),
    ShapeKindCatalogueEntry(ShapeKind.parallelogram, 'Parallelogram'),
    ShapeKindCatalogueEntry(ShapeKind.trapezoid, 'Trapezoid'),
    ShapeKindCatalogueEntry(ShapeKind.star, 'Star'),
    ShapeKindCatalogueEntry(ShapeKind.heart, 'Heart'),
  ]),
  ShapeKindCatalogueSection('Bubbles', [
    ShapeKindCatalogueEntry(ShapeKind.speechBubble, 'Speech'),
    ShapeKindCatalogueEntry(ShapeKind.quoteBubble, 'Quote'),
    ShapeKindCatalogueEntry(ShapeKind.thoughtBubble, 'Thought'),
  ]),
  ShapeKindCatalogueSection('Symbols', [
    ShapeKindCatalogueEntry(ShapeKind.plus, 'Plus'),
    ShapeKindCatalogueEntry(ShapeKind.check, 'Check'),
    ShapeKindCatalogueEntry(ShapeKind.cross, 'Cross'),
    ShapeKindCatalogueEntry(ShapeKind.sparkle, 'Sparkle'),
    ShapeKindCatalogueEntry(ShapeKind.seal, 'Badge'),
    ShapeKindCatalogueEntry(ShapeKind.bolt, 'Bolt'),
    ShapeKindCatalogueEntry(ShapeKind.shield, 'Shield'),
    ShapeKindCatalogueEntry(ShapeKind.crescent, 'Crescent'),
    ShapeKindCatalogueEntry(ShapeKind.cloud, 'Cloud'),
  ]),
  ShapeKindCatalogueSection('Lines & Arrows', [
    ShapeKindCatalogueEntry(ShapeKind.line, 'Line'),
    ShapeKindCatalogueEntry(ShapeKind.arrow, 'Arrow right'),
    ShapeKindCatalogueEntry(ShapeKind.arrowLeft, 'Arrow left'),
    ShapeKindCatalogueEntry(ShapeKind.arrowUp, 'Arrow up'),
    ShapeKindCatalogueEntry(ShapeKind.arrowDown, 'Arrow down'),
  ]),
];

/// Flattened catalogue in display order. Built once from
/// [kShapeCatalogueSections] so the two views can never drift.
final List<ShapeKindCatalogueEntry> kShapeCatalogue = [
  for (final section in kShapeCatalogueSections) ...section.entries,
];
