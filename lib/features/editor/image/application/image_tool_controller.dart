import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../toolbar/domain/sibling_swipe_strategy.dart';

/// Every chip in `ImageModeToolbar`, in left→right strip order.
///
/// `isPanel: false` means the chip participates in the strip but
/// does not open a dock panel:
///   * [crop] — opens the full-screen `CropModeOverlay`.
///   * [replace] — one-shot picker action.
///
/// Sibling-swipe inside an open panel walks [kImagePanelSlotOrder]
/// (= panel-bearing values, in declaration order). Any non-panel
/// slot is automatically skipped because it is not in that list.
enum ImageToolSlot {
  style,
  crop(isPanel: false),
  shape,
  border,
  shadow,
  adjust,
  effects,
  filters,
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

/// Display order of every Image chip — including non-panel ones.
const List<ImageToolSlot> kImageStripSlotOrder = ImageToolSlot.values;

/// Panel-bearing slots only — drives sibling-swipe. Hand-written
/// rather than derived so it stays a `const`. Verified against
/// `ImageToolSlot.values.where((s) => s.isPanel)` by the drift test
/// in `test/editor/widget/slot_order_consistency_test.dart`.
const List<ImageToolSlot> kImagePanelSlotOrder = <ImageToolSlot>[
  ImageToolSlot.style,
  ImageToolSlot.shape,
  ImageToolSlot.border,
  ImageToolSlot.shadow,
  ImageToolSlot.adjust,
  ImageToolSlot.effects,
  ImageToolSlot.filters,
];

/// Slots intentionally skipped during sibling-swipe. Empty today;
/// add an entry to opt a single panel out of swipe without
/// reordering the strip.
const Set<ImageToolSlot> kImageSlotsExcludedFromSwipe = <ImageToolSlot>{};

/// Shared prev/next walker for the Image dock.
const SiblingSwipeStrategy<ImageToolSlot> kImageSwipeStrategy =
    SiblingSwipeStrategy<ImageToolSlot>(
  order: kImagePanelSlotOrder,
  excluded: kImageSlotsExcludedFromSwipe,
);

/// Snapshot of the in-dock state for the Image sub-tool. The
/// selected `ImageLayer` is owned by the document/selection
/// controllers — this state only tracks which Image sub-tab (Style,
/// Crop, Shape, …) is currently expanded above the strip.
@immutable
class ImageToolSession {
  const ImageToolSession({this.openSlot});

  static const ImageToolSession initial = ImageToolSession();

  /// Currently expanded panel, or `null` when only the chip strip
  /// is visible.
  final ImageToolSlot? openSlot;

  ImageToolSession copyWith({
    ImageToolSlot? openSlot,
    bool clearOpenSlot = false,
  }) {
    return ImageToolSession(
      openSlot: clearOpenSlot ? null : (openSlot ?? this.openSlot),
    );
  }
}

class ImageToolController extends Notifier<ImageToolSession> {
  @override
  ImageToolSession build() => ImageToolSession.initial;

  /// Toggle [slot] — if it's already open, close it; otherwise
  /// switch to it. Mirrors the text-tool sheet toggle so users can
  /// dismiss a panel by re-tapping its tab.
  void toggleSlot(ImageToolSlot slot) {
    if (state.openSlot == slot) {
      state = state.copyWith(clearOpenSlot: true);
    } else {
      state = state.copyWith(openSlot: slot);
    }
  }

  void closePanel() {
    if (state.openSlot == null) return;
    state = state.copyWith(clearOpenSlot: true);
  }

  /// Open the slot before the current one in
  /// [kImagePanelSlotOrder]. Wraps. No-op when no slot is open.
  void openPrevSlot() {
    final next = kImageSwipeStrategy.prev(state.openSlot);
    if (next != null) state = state.copyWith(openSlot: next);
  }

  /// Open the slot after the current one in
  /// [kImagePanelSlotOrder]. Wraps. No-op when no slot is open.
  void openNextSlot() {
    final next = kImageSwipeStrategy.next(state.openSlot);
    if (next != null) state = state.copyWith(openSlot: next);
  }
}

final imageToolControllerProvider =
    NotifierProvider<ImageToolController, ImageToolSession>(
  ImageToolController.new,
);
