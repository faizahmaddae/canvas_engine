import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../templates/domain/template.dart';
import '../../../templates/presentation/template_preview.dart';

/// Single template tile rendered inside a category row.
///
/// Width is derived from each template's native aspect ratio (kept
/// within [minWidth] / [maxWidth]) so square posts read square and
/// stories read tall — matches the artboard the user will land in
/// after tapping it.
class TemplateCard extends StatelessWidget {
  const TemplateCard({
    super.key,
    required this.template,
    required this.onTap,
    this.height = 160,
    this.minWidth = 110,
    this.maxWidth = 180,
    this.aspectRatioOverride,
  });

  final Template template;
  final VoidCallback onTap;
  final double height;
  final double minWidth;
  final double maxWidth;

  /// When set, the thumbnail is rendered at this aspect ratio
  /// instead of the template's native artboard aspect. Used by the
  /// home rows to keep mixed-format categories (square + portrait)
  /// on a uniform rhythm. The artboard's real aspect still applies
  /// once the user enters the editor.
  final double? aspectRatioOverride;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final doc = template.build();
    final nativeAspect = doc.width / doc.height;
    final aspect = aspectRatioOverride ?? nativeAspect;
    final width = (height * aspect).clamp(minWidth, maxWidth);

    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        label: 'Open template ${template.name}',
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.card),
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: scheme.surfaceContainerHigh,
                  elevation: 1,
                  shadowColor: Colors.black.withValues(alpha: 0.4),
                  surfaceTintColor: scheme.surfaceTint,
                  clipBehavior: Clip.antiAlias,
                  // Hairline outline so light-fill template content
                  // (e.g. Quote/Greeting) doesn't punch a glaring
                  // bright rectangle into the dark surface.
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppRadii.card - 2),
                    side: BorderSide(
                      color:
                          scheme.outlineVariant.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: TemplatePreview(
                      template: template,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  template.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
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
