import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/theme/app_theme.dart';

/// Theme tests for the 中華フォント fix (#291).
///
/// On Android browsers without a Japanese system font, kanji render with
/// Chinese-style glyphs because Flutter falls back to a CJK-SC font.
/// Loading Noto Sans JP from Google Fonts CDN via <link> in web/index.html
/// makes Japanese glyph variants available to Flutter Web's renderer, and
/// setting it as the theme font family ensures it is used throughout the app.
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

      // fontFamilyFallback ensures that if the CDN font fails to load,
      // the device falls back to a Japanese-capable system font before
      // a generic sans-serif that may render CJK-SC glyphs.
      expect(
        fallback,
        isNotNull,
        reason: 'fontFamilyFallback should be set for robust CJK fallback',
      );
      expect(
        fallback,
        contains('sans-serif'),
        reason: 'Fallback list should end with generic sans-serif',
      );
      // No entry should have leading/trailing whitespace — a space-prefixed
      // generic like ' sans-serif' is a literal family name, not the keyword.
      for (final family in fallback!) {
        expect(
          family,
          family.trim(),
          reason: 'fontFamilyFallback entry "$family" has leading/trailing '
              'whitespace — this breaks CSS generic-family resolution',
        );
      }
    });
  });
}
