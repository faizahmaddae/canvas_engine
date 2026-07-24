import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../toolbar/application/dock_tool_controller.dart';
import '../../toolbar/domain/sibling_swipe_strategy.dart';

/// Every chip in `ImageModeToolbar` that drives the image dock.
///
/// `isPanel: false` means the chip participates in the strip but
/// does not open a dock panel:
///   * [crop] — opens the full-screen `CropModeOverlay`.
///   * [replace] — one-shot picker action.
///
/// Rendered strip order lives in [kImageStripOrder] — NOT in this
/// enum's declaration order. Sibling-swipe inside an open panel
/// walks [kImagePanelSlotOrder], which is derived from that same
/// list, so swipe always follows what the user sees.
enum ImageToolSlot {
  look,
  crop(isPanel: false),
  shape,
  border,
  shadow,
  effects,
  replace(isPanel: false);

  const ImageToolSlot({this.isPanel = true});

  /// Whether tapping this chip opens an inline dock panel.
  final bool isPanel;

  /// Safe lookup by enum name; returns `null` for unknown / legacy
  /// strings. Intended for boundaries that still receive untyped
  /// slot ids (e.g. semantic keys, snapshot restoration).
  static ImageToolSlot? tryByName(String? name) {
    if (name == null) return null;
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// Single source of truth for the Image strip: every chip, in
/// rendered left→right order. `ImageModeToolbar` builds its chips
/// by iterating THIS list, and [kImagePanelSlotOrder] (the
/// sibling-swipe walk) is derived from it — a change to one cannot
/// drift the other.
///
/// The two action entries are strip-only chips outside
/// [ImageToolSlot]:
///   * `'opacity'` stays EXCLUDED from the swipe walk for now — it
///     opens a `ContextToolPanel` hosted outside the dock (a
///     different host than the slot panels), so swipe cannot land
///     on it without teleporting the user between hosts.
///   * `'more'` opens the selected-layer actions sheet.
const List<DockStripEntry<ImageToolSlot>> kImageStripOrder =
    <DockStripEntry<ImageToolSlot>>[
      DockStripEntry.slot(ImageToolSlot.look),
      DockStripEntry.slot(ImageToolSlot.border),
      DockStripEntry.slot(ImageToolSlot.shadow),
      DockStripEntry.action('opacity'),
      DockStripEntry.slot(ImageToolSlot.replace),
      DockStripEntry.action('more'),
      DockStripEntry.slot(ImageToolSlot.crop),
      DockStripEntry.slot(ImageToolSlot.shape),
      DockStripEntry.slot(ImageToolSlot.effects),
    ];

/// Display order of every Image dock slot (action chips excluded)
/// — the [kImageStripOrder] projection.
final List<ImageToolSlot> kImageStripSlotOrder = List.unmodifiable(
  kImageStripOrder.map((e) => e.slot).whereType<ImageToolSlot>(),
);

/// Panel-bearing slots in RENDERED order — drives sibling-swipe.
/// Derived from [kImageStripOrder] so the walk follows the strip
/// the user sees: look → border → shadow → shape → effects (wrap).
/// Pinned against the pumped toolbar by
/// `test/editor/widget/slot_order_consistency_test.dart`.
final List<ImageToolSlot> kImagePanelSlotOrder = List.unmodifiable(
  kImageStripOrder
      .map((e) => e.slot)
      .whereType<ImageToolSlot>()
      .where((s) => s.isPanel),
);

/// Slots intentionally skipped during sibling-swipe. Empty today;
/// add an entry to opt a single panel out of swipe without
/// reordering the strip.
const Set<ImageToolSlot> kImageSlotsExcludedFromSwipe = <ImageToolSlot>{};

/// Shared prev/next walker for the Image dock.
final SiblingSwipeStrategy<ImageToolSlot> kImageSwipeStrategy =
    SiblingSwipeStrategy<ImageToolSlot>(
      order: kImagePanelSlotOrder,
      excluded: kImageSlotsExcludedFromSwipe,
    );

/// In-dock state for the Image sub-tool — see [DockToolSession].
typedef ImageToolSession = DockToolSession<ImageToolSlot>;

final imageToolControllerProvider =
    NotifierProvider<DockToolController<ImageToolSlot>, ImageToolSession>(
      () => DockToolController<ImageToolSlot>(swipe: kImageSwipeStrategy),
    );
