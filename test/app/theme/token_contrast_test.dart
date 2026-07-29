// WCAG floors for the tokens whose whole job is to be seen.
//
// This exists because a fix round shipped an "accessible" boundary at
// 1.31:1 while its own comment cited the 3:1 bar, and a glyph stop was
// repointed at six call sites and missed at a seventh. Neither
// `flutter analyze` nor any widget test noticed. Arithmetic on the
// token values catches both without rendering anything.
//
// Scope is deliberately the TOKENS, not every call site: a call site
// that picks the wrong token is a review question, but a token that
// cannot clear its floor no matter where it is used is a bug in the
// palette itself.

import 'dart:math' as math;

import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.1 relative luminance of an opaque sRGB colour.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG 2.1 contrast ratio between two opaque colours (1.0–21.0).
double _ratio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// `fg` composited over `bg` at `alpha`, then measured against `bg`.
Color _over(Color fg, Color bg, double alpha) =>
    Color.alphaBlend(fg.withValues(alpha: alpha), bg);

void main() {
  for (final (name, t) in <(String, AppTokens)>[
    ('light', AppTokens.light),
    ('dark', AppTokens.dark),
  ]) {
    group('$name tokens', () {
      // 1.4.3 — normal text.
      test('accentText clears 4.5:1 on every surface it lands on', () {
        for (final (surfaceName, bg) in <(String, Color)>[
          ('surface', t.surface),
          ('pageBg', t.pageBg),
          ('workspace', t.workspace),
          // The active dock tile / selected option chip tint.
          ('accent@12% over surface', _over(t.accent, t.surface, 0.12)),
          ('accent@16% over surface', _over(t.accent, t.surface, 0.16)),
        ]) {
          expect(
            _ratio(t.accentText, bg),
            greaterThanOrEqualTo(4.5),
            reason:
                'accentText is the GLYPH stop; on $surfaceName it measures '
                '${_ratio(t.accentText, bg).toStringAsFixed(2)}:1',
          );
        }
      });

      // 1.4.11 — non-text contrast. `borderStrong` is the sole outline
      // of an option tile, so it has to clear the panel it sits on AND
      // the fill it encloses.
      test('borderStrong clears 3:1 against panel and tile fill', () {
        final tileFill = _over(t.surfaceMuted, t.surface, 0.35);
        for (final (againstName, bg) in <(String, Color)>[
          ('surface', t.surface),
          ('pageBg', t.pageBg),
          ('workspace', t.workspace),
          ('unselected tile fill', tileFill),
        ]) {
          expect(
            _ratio(t.borderStrong, bg),
            greaterThanOrEqualTo(3.0),
            reason:
                'borderStrong is a load-bearing boundary; against '
                '$againstName it measures '
                '${_ratio(t.borderStrong, bg).toStringAsFixed(2)}:1',
          );
        }
      });

      test('borderStrong is strictly stronger than the hairline', () {
        expect(
          _ratio(t.borderStrong, t.surface),
          greaterThan(_ratio(t.border, t.surface)),
          reason:
              'otherwise the two tokens are interchangeable and the '
              'distinction stops being enforceable',
        );
      });

      // Body copy.
      test('textPrimary and textSecondary clear 4.5:1 on surface', () {
        expect(_ratio(t.textPrimary, t.surface), greaterThanOrEqualTo(4.5));
        expect(_ratio(t.textSecondary, t.surface), greaterThanOrEqualTo(4.5));
      });

      test('brand pairs with onBrand at 4.5:1', () {
        expect(_ratio(t.onBrand, t.brand), greaterThanOrEqualTo(4.5));
      });
    });
  }
}
