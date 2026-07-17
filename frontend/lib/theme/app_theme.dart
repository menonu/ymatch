import 'package:flutter/material.dart';

class AppTheme {
  // Primary Palette: Indigo & Pink
  static const Color primaryColor = Colors.indigo;
  static const Color secondaryColor = Colors.pinkAccent;

  // Neutral Colors for Minimalist look
  static const Color backgroundColor = Color(0xFFF8F9FA); // Very light gray
  static const Color surfaceColor = Colors.white;
  static const Color textPrimaryColor = Color(
    0xFF212529,
  ); // Dark gray, not pure black
  static const Color textSecondaryColor = Color(0xFF6C757D); // Muted gray

  // Status Colors
  static const Color haveColor = Colors.indigo; // Color for HAVE
  static const Color wantColor = Colors.pinkAccent; // Color for WANT
  static const Color tradeColor = Colors.teal; // Color for TRADE (OFFER)

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      // Japanese font (#291, subsetted to WOFF2 in #353). Bundled in fonts/
      // and declared in pubspec.yaml so Flutter Web's CanvasKit renderer
      // loads it from the asset bundle (FontManifest.json). CanvasKit does
      // NOT use CSS <link>-loaded fonts — it needs the font file registered
      // via the engine. This forces Japanese glyph variants for kanji/kana
      // on every platform, avoiding 中華フォント (Chinese-style glyphs) on
      // Android browsers without a Japanese system font.
      fontFamily: 'NotoSansJP',
      fontFamilyFallback: const [
        'Yu Gothic',
        'Hiragino Sans',
        'Meiryo',
        'sans-serif',
      ],
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        secondary: secondaryColor,
        surface: surfaceColor,
        onSurface: textPrimaryColor,
        error: Colors.redAccent,
      ),
      scaffoldBackgroundColor: backgroundColor,

      // Typography: Clean and minimal
      typography: Typography.material2021(
        colorScheme: const ColorScheme.light(),
      ),

      // App Bar: Flat and clean
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceColor,
        foregroundColor: textPrimaryColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimaryColor,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: textPrimaryColor),
      ),

      // Cards: Sharp, flat, subtle border instead of heavy shadow
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4), // Sharp corners
          side: const BorderSide(
            color: Color(0xFFDEE2E6),
            width: 1,
          ), // Subtle border
        ),
      ),

      // Buttons: Flat and sharp
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4), // Sharp corners
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      // Input Fields: Clean underlines or subtle boxes
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
          borderSide: BorderSide(color: Color(0xFFDEE2E6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
          borderSide: BorderSide(color: Color(0xFFDEE2E6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
        labelStyle: TextStyle(color: textSecondaryColor),
        hintStyle: TextStyle(color: textSecondaryColor),
      ),

      // Navigation Bar: Flat, clean icons
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceColor,
        elevation: 0,
        indicatorColor: primaryColor.withValues(alpha: 0.1),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: primaryColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            );
          }
          return const TextStyle(
            color: textSecondaryColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primaryColor);
          }
          return const IconThemeData(color: textSecondaryColor);
        }),
      ),

      // Floating Action Button
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(8),
          ), // Slightly rounded for FAB
        ),
      ),
    );
  }
}
