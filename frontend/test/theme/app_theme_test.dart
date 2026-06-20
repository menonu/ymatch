import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/theme/app_theme.dart';

/// Theme tests for the 中華フォント fix (#291).
///
/// On Android devices without Japanese system fonts, kanji render with
/// Chinese-style glyphs because Flutter falls back to a CJK-SC font.
/// Bundling Noto Sans JP and setting it as the theme font family forces
/// Japanese glyph variants regardless of the device's system fonts.
void main() {
  group('AppTheme font family (#291)', () {
    test('lightTheme sets a Japanese-capable font family', () {
      final theme = AppTheme.lightTheme;
      final fontFamily = theme.textTheme.bodyLarge?.fontFamily;

      // The theme's text style must use a Japanese font so that kanji
      // render in Japanese style (not Chinese style) on all platforms.
      expect(
        fontFamily,
        isNotNull,
        reason: 'fontFamily must be set to avoid 中華フォント on Android',
      );
      expect(
        fontFamily,
        'Noto Sans JP',
        reason: 'Expected "Noto Sans JP" (Google Fonts CSS family name '
            'loaded via <link> in web/index.html)',
      );
    });

    test('lightTheme provides fallback font families for CJK coverage', () {
      final theme = AppTheme.lightTheme;
      final fallback = theme.textTheme.bodyLarge?.fontFamilyFallback;

      // fontFamilyFallback ensures that if the primary Japanese font
      // fails to load on some platform, the device still falls back to
      // a Japanese-capable font before a generic CJK-SC font.
      expect(
        fallback,
        isNotNull,
        reason: 'fontFamilyFallback should be set for robust CJK fallback',
      );
      expect(
        fallback,
        contains('Noto Sans JP'),
        reason: 'Fallback list should include "Noto Sans JP" '
            '(the name registered in pubspec.yaml)',
      );
    });
  });
}
