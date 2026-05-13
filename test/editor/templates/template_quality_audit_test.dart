import 'dart:convert';
import 'dart:io';

import 'package:canvas_engine/features/templates/data/asset_template_repository.dart';
import 'package:canvas_engine/features/templates/data/template_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

const _qualityAuditReportPath = 'docs/template-quality-audit.md';

void main() {
  test('template quality audit report covers every JSON template', () {
    final report = File(_qualityAuditReportPath);
    expect(report.existsSync(), isTrue);

    final reportText = report.readAsStringSync();
    expect(reportText, contains('## Ready'));
    expect(reportText, contains('## Needs Minor Polish'));
    expect(reportText, contains('## Needs Major Polish'));
    expect(reportText, contains('## Should Be Redesigned Later'));

    final manifest = TemplateAssetManifest.fromJson(
      _jsonObject(_assetText(AssetTemplateRepository.defaultManifestPath)),
    );
    for (final metadataPath in manifest.templates) {
      final metadata = TemplateAssetMetadata.fromJson(
        _jsonObject(_assetText(metadataPath)),
      );
      expect(reportText, contains('`${metadata.id}`'), reason: metadata.id);
    }
  });
}

String _assetText(String path) => File(path).readAsStringSync();

Map<String, dynamic> _jsonObject(String source) {
  return Map<String, dynamic>.from(jsonDecode(source) as Map);
}
