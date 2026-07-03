import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/core/layer_mask.dart';
import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 3.2a — engine helpers for the on-canvas mask editor
/// (docs/mask-edit-mode-design-2026-07.md §3).
void main() {
  const mask = RectMask(rect: Rect.fromLTWH(0, 0, 100, 50), feather: 12);

  group('EffectStack.withStackMask', () {
    test('sets, replaces, and clears the mask without touching effects', () {
      final stack = EffectStack(
        List<EditorEffect>.unmodifiable(
          <EditorEffect>[BrightnessEffect(amount: 10)],
        ),
      );
      final withMask = stack.withStackMask(mask);
      expect(withMask.stackMask, mask);
      expect(withMask.effects, same(stack.effects));

      const replacement = EllipseMask(bounds: Rect.fromLTWH(0, 0, 50, 50));
      expect(withMask.withStackMask(replacement).stackMask, replacement);
      expect(withMask.withStackMask(null).stackMask, isNull);
    });

    test('same mask returns the receiver (identity fast path)', () {
      final stack = const EffectStack(<EditorEffect>[], stackMask: mask);
      expect(identical(stack.withStackMask(mask), stack), isTrue);
    });

    test('fully-empty result canonicalises to the empty singleton — '
        'parity with SetStackMaskCommand', () {
      const maskOnly = EffectStack(<EditorEffect>[], stackMask: mask);
      expect(identical(maskOnly.withStackMask(null), EffectStack.empty),
          isTrue,
          reason: 'the sanctioned writer must canonicalise exactly like '
              'the command always has');
    });
  });

  group('mask copyWith', () {
    test('RectMask: omitted fields preserved, set fields replaced', () {
      const m = RectMask(
        rect: Rect.fromLTWH(1, 2, 3, 4),
        inverted: true,
        feather: 8,
      );
      final moved = m.copyWith(rect: const Rect.fromLTWH(5, 6, 3, 4));
      expect(moved.rect, const Rect.fromLTWH(5, 6, 3, 4));
      expect(moved.inverted, isTrue);
      expect(moved.feather, 8);
      expect(m.copyWith(feather: 0).feather, 0);
      expect(m.copyWith(inverted: false).inverted, isFalse);
    });

    test('EllipseMask: same contract', () {
      const m = EllipseMask(bounds: Rect.fromLTWH(1, 2, 3, 4), feather: 8);
      final grown = m.copyWith(bounds: const Rect.fromLTWH(1, 2, 30, 40));
      expect(grown.bounds, const Rect.fromLTWH(1, 2, 30, 40));
      expect(grown.feather, 8);
      expect(grown.inverted, isFalse);
    });
  });

  group('estimatedByteSize', () {
    test('rect/ellipse report a flat struct cost', () {
      expect(mask.estimatedByteSize, greaterThan(0));
      expect(
        const EllipseMask(bounds: Rect.fromLTWH(0, 0, 1, 1))
            .estimatedByteSize,
        greaterThan(0),
      );
    });

    test('PathMask grows with segment count', () {
      PathMask path(int segments) => PathMask(
            contours: [
              PathContour(
                start: Offset.zero,
                segments: List<PathSegment>.unmodifiable([
                  for (var i = 0; i < segments; i++)
                    LineSegment(end: Offset(i.toDouble(), 0)),
                ]),
              ),
            ],
          );
      expect(
        path(100).estimatedByteSize,
        greaterThan(path(2).estimatedByteSize),
        reason: 'the undo byte budget must see heavy paths as heavy',
      );
    });
  });
}
