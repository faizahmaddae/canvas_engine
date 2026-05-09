import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_engine/features/home/domain/project.dart';

void main() {
  group('Project JSON', () {
    test('round-trips all fields', () {
      final p = Project(
        id: 'abc-123',
        name: 'Birthday card',
        width: 1080,
        height: 1080,
        createdAt: DateTime.utc(2026, 4, 1, 9),
        lastModified: DateTime.utc(2026, 4, 18, 12, 30, 5),
        documentJson: '{"layers":[]}',
        thumbnailPath: '/tmp/x.png',
      );
      final back = Project.fromJson(p.toJson());
      expect(back.id, p.id);
      expect(back.name, p.name);
      expect(back.width, p.width);
      expect(back.height, p.height);
      expect(back.createdAt, p.createdAt);
      expect(back.lastModified, p.lastModified);
      expect(back.documentJson, p.documentJson);
      expect(back.thumbnailPath, p.thumbnailPath);
    });

    test('round-trips without thumbnail', () {
      final p = Project(
        id: 'a',
        name: 'No thumb',
        width: 100,
        height: 200,
        createdAt: DateTime.utc(2026, 1, 1),
        lastModified: DateTime.utc(2026, 1, 1),
        documentJson: '{}',
      );
      final back = Project.fromJson(p.toJson());
      expect(back.thumbnailPath, isNull);
    });
  });
}
