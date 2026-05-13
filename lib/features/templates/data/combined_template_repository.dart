import 'package:flutter/foundation.dart';

import '../../editor/engine/serialization/document_codec.dart';
import '../domain/template.dart';
import 'asset_template_repository.dart';

@immutable
class CombinedTemplateResult {
  const CombinedTemplateResult({
    required this.templates,
    required this.warnings,
  });

  final List<Template> templates;
  final List<String> warnings;
}

class CombinedTemplateRepository {
  CombinedTemplateRepository({
    AssetTemplateRepository? assetRepository,
    Iterable<Template>? legacyTemplates,
    this.onWarning,
  }) : _assetRepository = assetRepository ?? AssetTemplateRepository(),
       _legacyTemplates = List.unmodifiable(
         legacyTemplates ?? const <Template>[],
       );

  final AssetTemplateRepository _assetRepository;
  final List<Template> _legacyTemplates;
  final void Function(String warning)? onWarning;

  Future<List<Template>> loadTemplates({String titleLocale = 'en'}) async {
    final result = await loadTemplateResult(titleLocale: titleLocale);
    return result.templates;
  }

  Future<CombinedTemplateResult> loadTemplateResult({
    String titleLocale = 'en',
  }) async {
    final warnings = <String>[];
    final assetTemplates = await _loadAssetTemplates(
      titleLocale: titleLocale,
      warnings: warnings,
    );

    final assetById = <String, Template>{};
    for (final template in assetTemplates) {
      assetById[template.id] = template;
    }

    final usedAssetIds = <String>{};
    final templates = <Template>[];
    for (final legacyTemplate in _legacyTemplates) {
      final assetTemplate = assetById[legacyTemplate.id];
      if (assetTemplate != null) {
        _warn(
          warnings,
          'Duplicate template id "${legacyTemplate.id}" found in asset and '
          'legacy catalogs; using the asset template.',
        );
        templates.add(assetTemplate);
        usedAssetIds.add(assetTemplate.id);
        continue;
      }
      templates.add(legacyTemplate);
    }

    for (final assetTemplate in assetTemplates) {
      if (usedAssetIds.contains(assetTemplate.id)) continue;
      templates.add(assetTemplate);
    }

    return CombinedTemplateResult(
      templates: List.unmodifiable(templates),
      warnings: List.unmodifiable(warnings),
    );
  }

  Future<List<Template>> _loadAssetTemplates({
    required String titleLocale,
    required List<String> warnings,
  }) async {
    try {
      return await _assetRepository.loadTemplates(titleLocale: titleLocale);
    } on FormatException {
      rethrow;
    } on DocumentDecodeException {
      rethrow;
    } catch (error) {
      final fallbackMessage = _legacyTemplates.isEmpty
          ? 'Asset template loading failed; no fallback templates available'
          : 'Asset template loading failed; using legacy templates only';
      _warn(warnings, '$fallbackMessage: $error');
      return const <Template>[];
    }
  }

  void _warn(List<String> warnings, String warning) {
    warnings.add(warning);
    onWarning?.call(warning);
    assert(() {
      debugPrint('CombinedTemplateRepository: $warning');
      return true;
    }());
  }
}
