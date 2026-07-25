import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/utils/haptics.dart';
import '../../../l10n/l10n.dart';
import 'widgets/editor_modal_sheet.dart';
import '../../../app/theme/app_icons.dart';

/// Bottom-sheet emoji picker used by the Sticker tool.
///
/// Wraps [EmojiPicker] so the user gets the full Unicode set,
/// categorised tabs (Smileys, Animals, Food, …), live search, and
/// recent-emojis tracking — all backed by the package's own
/// `SharedPreferences` storage so recents survive across sessions.
///
/// Resolves to the chosen emoji glyph or `null` when dismissed.
/// Caller is still responsible for inserting the layer (the
/// presentation layer never touches the editor model).
Future<String?> showStickerPickerSheet(BuildContext context) {
  // FULL barrier (contract §9: pickers). Card + handle come from
  // the shared modal host (tb2 8/16).
  return showEditorSheet<String>(
    context,
    builder: (ctx) => const _StickerPickerSheet(),
  );
}

class _StickerPickerSheet extends StatefulWidget {
  const _StickerPickerSheet();

  @override
  State<_StickerPickerSheet> createState() => _StickerPickerSheetState();
}

class _StickerPickerSheetState extends State<_StickerPickerSheet> {
  // Resolved on the first frame so we can land on Smileys for new
  // users (empty Recent) and on Recent for returning users. Held
  // in state so `EmojiPicker`'s `initCategory` only sees a fully
  // resolved value and never flips after the first build.
  late final Future<Category> _initialCategory = EmojiPickerUtils()
      .getRecentEmojis()
      .then((recents) => recents.isEmpty ? Category.SMILEYS : Category.RECENT);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.55;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              context.l10n.stickersTitle.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: tokens.textSecondary,
                letterSpacing: 1.0,
              ),
            ),
          ),
          SizedBox(
            height: height,
            child: FutureBuilder<Category>(
              future: _initialCategory,
              builder: (ctx, snap) {
                // Hold the picker until the recents lookup resolves
                // so `initCategory` isn't applied with a stale value
                // on rebuild. The lookup is a single SharedPrefs
                // read — sub-frame on every device we ship to.
                if (!snap.hasData) {
                  return const SizedBox.shrink();
                }
                return _buildPicker(context, tokens, height, snap.data!);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPicker(
    BuildContext context,
    AppTokens tokens,
    double height,
    Category initCategory,
  ) {
    return EmojiPicker(
      onEmojiSelected: (category, emoji) {
        EditorHaptics.tap();
        Navigator.pop(context, emoji.emoji);
      },
      config: Config(
        height: height,
        emojiViewConfig: EmojiViewConfig(
          emojiSizeMax: 30,
          backgroundColor: tokens.surface,
          columns: 8,
          verticalSpacing: 2,
          horizontalSpacing: 2,
          gridPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          noRecents: _NoRecentsHint(tokens: tokens),
        ),
        viewOrderConfig: const ViewOrderConfig(
          top: EmojiPickerItem.searchBar,
          middle: EmojiPickerItem.categoryBar,
          bottom: EmojiPickerItem.emojiView,
        ),
        searchViewConfig: SearchViewConfig(
          backgroundColor: tokens.surface,
          buttonIconColor: tokens.textSecondary,
          hintText: context.l10n.searchEmojisHint,
        ),
        categoryViewConfig: CategoryViewConfig(
          backgroundColor: tokens.surface,
          iconColor: tokens.textSecondary,
          iconColorSelected: tokens.accent,
          indicatorColor: tokens.accent,
          dividerColor: tokens.border.withValues(alpha: 0.3),
          // Smileys for first-run users so the sheet never opens on
          // an empty Recent tab; Recent thereafter once they've used
          // at least one sticker.
          initCategory: initCategory,
        ),
        bottomActionBarConfig: BottomActionBarConfig(
          enabled: false,
          showBackspaceButton: false,
          backgroundColor: tokens.surface,
          buttonColor: tokens.surface,
          buttonIconColor: tokens.textSecondary,
        ),
        skinToneConfig: SkinToneConfig(
          dialogBackgroundColor: tokens.surfaceMuted,
          indicatorColor: tokens.accent,
        ),
        // The plugin's compatibility check goes through a
        // platform channel that isn't registered on a hot
        // restart and crashes on older Android targets.
        // The app already ships modern emoji fonts, so the
        // value of the filter is marginal and the failure
        // mode is severe — disable it.
        checkPlatformCompatibility: false,
      ),
    );
  }
}

/// Friendly placeholder shown when the user manually navigates to
/// the Recent tab and has not yet used any sticker. Replaces the
/// package's terse default ("No Recents") with a guiding line so
/// the empty state never reads as broken.
class _NoRecentsHint extends StatelessWidget {
  const _NoRecentsHint({required this.tokens});

  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.stickerTool,
              size: 36,
              color: tokens.textSecondary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 10),
            Text(
              context.l10n.noRecentStickersYet,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.recentStickersHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: tokens.textSecondary,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
