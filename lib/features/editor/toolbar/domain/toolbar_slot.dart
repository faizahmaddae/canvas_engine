import 'package:flutter/widgets.dart';

/// How a slot reveals its sub-tool when tapped.
///
/// Phase 1 only renders [instantAction] (the main toolbar's tiles
/// behave that way today). The other values are declared up-front so
/// the registry / sub-tool host added in later phases doesn't need
/// to break this enum.
enum SlotPresentation {
  /// Tap performs an action immediately. No sub-tool body.
  instantAction,

  /// Tap opens the slot's [SubTool] body inside the dock's expanded
  /// region (canvas reflows). Default for value-editing slots.
  inlineSheet,

  /// Tap opens a full modal (font browser, custom color picker).
  /// Reserved for power-user surfaces.
  modalSheet,
}

/// Logical grouping inside a single mode's strip. The renderer
/// inserts a hairline divider whenever consecutive slots have a
/// different [SlotTier], so groups are derived from the data and
/// can't drift if items are reordered.
///
/// Used by the main editor toolbar to separate the three groups:
///   * [tier1] — Add (Text, Sticker, Shape, Paint, Image)
///   * [tier2] — Photo edits (Crop, Adjust, Filters)
///   * [tier3] — Document (Canvas)
///
/// Mode-specific toolbars (text, paint) currently use [tier1] and
/// [tier2] only; they remain unaffected by [tier3].
enum SlotTier { tier1, tier2, tier3 }

/// Builder for the optional value label rendered under a tile's
/// icon (e.g. "24pt", "Inter"). Returns `null` to fall back to
/// [ToolbarSlot.label].
typedef SlotValueLabelBuilder = String? Function();

/// Builder for the dynamic enabled state of a slot.
typedef SlotEnabledBuilder = bool Function();

/// Resolves the colour swatch rendered in place of the icon (e.g.
/// the current stroke/fill colour). `null` keeps the icon.
typedef SlotSwatchBuilder = Color? Function();

/// Resolves a font family the tile label previews in (the Font
/// tile renders its value in the selected face). `null` inherits.
typedef SlotFontFamilyBuilder = String? Function();

/// Declarative description of a single tool slot in a mode's strip.
///
/// This is the **shared toolbar item model** — every mode (main,
/// paint, text, and future modes) describes its tiles with this
/// type. Phase 1 uses it to back the main toolbar; later phases
/// migrate paint/text onto the same model so a single renderer
/// (`SlotStrip`) covers every mode.
@immutable
class ToolbarSlot {
  const ToolbarSlot({
    required this.id,
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.enabledBuilder,
    this.availableBuilder,
    this.valueLabel,
    this.swatchColor,
    this.fontFamily,
    this.presentation = SlotPresentation.instantAction,
    this.tier = SlotTier.tier1,
  });

  /// Stable id used for active-state computation, sibling-swipe
  /// navigation, and analytics. Must be unique within a mode.
  final String id;

  final IconData icon;

  /// Static label. Used when [valueLabel] is null or returns null.
  final String label;

  /// Action invoked when the tile is tapped. Value-editing slots
  /// typically delegate to their mode controller's toggle method.
  final VoidCallback onTap;

  /// Compile-time enabled flag. If [enabledBuilder] is provided it
  /// takes precedence.
  final bool enabled;

  /// Runtime enabled resolver. Allows a slot to disable itself based
  /// on selection / document state without rebuilding the registry.
  final SlotEnabledBuilder? enabledBuilder;

  /// Runtime resolver for whether the slot's PRECONDITION is met —
  /// distinct from [enabledBuilder], and deliberately so.
  ///
  /// A disabled slot is inert: it does not fire [onTap], so it can
  /// neither explain itself nor offer a way out. That is right for a
  /// control with nothing to act on (Clear effects with no effects).
  /// It is wrong for a tool the user could still WANT — Look and Crop
  /// in a document with no photo. Disabling those would trade a
  /// misleading tile for a dead one and take the recovery with it.
  ///
  /// An unavailable slot renders dimmed, exactly like a disabled one,
  /// but STAYS tappable: the tile is honest at a glance, and the tap
  /// still reaches the handler that offers to satisfy the
  /// precondition. Honesty and recovery, rather than one or the
  /// other.
  final SlotEnabledBuilder? availableBuilder;

  /// Resolves the dynamic value text shown under the icon (e.g.
  /// "24pt"). Phase 1 doesn't use this; the field exists so future
  /// phases don't have to edit this model.
  final SlotValueLabelBuilder? valueLabel;

  /// Resolves the colour swatch shown in place of the icon. Lets
  /// value-bearing tiles (stroke/fill/text colour) express their
  /// current value the way DockToolTile already renders it — the
  /// missing capability that kept paint/text on private item models.
  final SlotSwatchBuilder? swatchColor;

  /// Resolves the font family the tile's value label previews in.
  final SlotFontFamilyBuilder? fontFamily;

  final SlotPresentation presentation;

  final SlotTier tier;

  /// Effective enabled state at the moment of rendering.
  bool get isEnabled => enabledBuilder?.call() ?? enabled;

  /// Whether the slot's precondition holds. See [availableBuilder].
  bool get isAvailable => availableBuilder?.call() ?? true;
}
