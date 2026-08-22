import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../toolbar/application/dock_tool_controller.dart';
import '../../toolbar/domain/sibling_swipe_strategy.dart';

/// The image dock's panel-bearing slots — the two sheets the Image
/// Studio bench opens (image-studio §2/§3).
///
/// Everything else the old strip carried is a bench action now:
/// crop opens the full-screen `CropModeOverlay`, replace is the
/// specimen chip's one-shot picker, opacity is the shared
/// `ContextToolPanel`, and «بیشتر» is the layer overflow sheet.
enum ImageToolSlot {
  look,
  style;

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

/// Panel slots in rendered order — drives sibling-swipe. Matches the
/// aspect row's segment order (نما then سبک), so swipe follows what
/// the user sees.
const List<ImageToolSlot> kImagePanelSlotOrder = <ImageToolSlot>[
  ImageToolSlot.look,
  ImageToolSlot.style,
];

/// Slots intentionally skipped during sibling-swipe. Empty today;
/// add an entry to opt a single panel out of swipe without
/// reordering the walk.
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
