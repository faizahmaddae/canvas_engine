import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' as picker;

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../../../app/ui/app_modal_sheet.dart';
import '../../../../app/theme/app_icons.dart';

/// "Where should this photo come from?" — gallery or camera.
///
/// This used to live in `application/image_import_service.dart` and,
/// because the import-direction gate rightly forbids an application
/// file reaching into presentation, it could not use [showAppSheet]
/// and shipped as a bare stock `showModalBottomSheet` with two
/// unstyled `ListTile`s: no title, no token colours, no rhythm. tb2
/// 8/16 recorded the relocation as the real fix rather than papering
/// over it with a chrome swap; this is that relocation.
///
/// The two options are peers, so they get equal weight — a pair of
/// cards rather than a list where the first reads as the default.
Future<picker.ImageSource?> pickImageSource(BuildContext context) {
  final l10n = context.l10n;
  return showAppSheet<picker.ImageSource>(
    context,
    title: l10n.addImageTitle,
    titleIcon: AppIcons.photoTool,
    // The sheet host pads nothing for its child — each caller owns its
    // own gutters, so the cards need the page gutter here or they sit
    // flush against the card edge and the gesture bar.
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          Expanded(
            child: _SourceCard(
              key: const ValueKey('image-source-gallery'),
              icon: AppIcons.photoLibrary,
              label: l10n.galleryAction,
              onTap: () {
                EditorHaptics.tap();
                Navigator.pop(ctx, picker.ImageSource.gallery);
              },
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _SourceCard(
              key: const ValueKey('image-source-camera'),
              icon: AppIcons.camera,
              label: l10n.cameraAction,
              onTap: () {
                EditorHaptics.tap();
                Navigator.pop(ctx, picker.ImageSource.camera);
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Material(
      color: tokens.surfaceMuted,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: tokens.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.lg,
              horizontal: AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 26, color: tokens.accentDeep),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
