import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  // ── Brand palette ────────────────────────────────────────────
  static const Color primary      = Color(0xFF1A1F36);
  static const Color primaryLight = Color(0xFF2D3561);
  static const Color primaryDark  = Color(0xFF0F1224);

  static const Color gold         = Color(0xFFB8860B);
  static const Color goldLight    = Color(0xFFD4A017);
  static const Color goldPale     = Color(0xFFFDF6E3);
  static const Color goldBorder   = Color(0xFFE8D5A3);

  static const Color accent       = Color(0xFF2D7A5A);
  static const Color accentBg     = Color(0xFFEAF5EE);
  static const Color accentBorder = Color(0xFFA8D5BE);

  static const Color error        = Color(0xFFB91C1C);
  static const Color errorBg      = Color(0xFFFEF2F2);
  static const Color errorBorder  = Color(0xFFFECACA);

  static const Color warning      = Color(0xFFA16207);
  static const Color warningBg    = Color(0xFFFFFBEB);

  // ── File-type chips ──────────────────────────────────────────
  static const Color chipPdfFg     = Color(0xFFB91C1C);
  static const Color chipPdfBg     = Color(0xFFFEF0EE);
  static const Color chipImgFg     = Color(0xFF1D4ED8);
  static const Color chipImgBg     = Color(0xFFEFF6FF);
  static const Color chipDocFg     = Color(0xFF166534);
  static const Color chipDocBg     = Color(0xFFF0FDF4);
  static const Color chipZipFg     = Color(0xFFA16207);
  static const Color chipZipBg     = Color(0xFFFFFBEB);
  static const Color chipDefaultFg = Color(0xFF374151);
  static const Color chipDefaultBg = Color(0xFFF9FAFB);

  // ── Surfaces ─────────────────────────────────────────────────
  static const Color surface          = Color(0xFFF7F5F2);
  static const Color surfaceElevated  = Color(0xFFFFFFFF);
  static const Color surfaceCard      = Color(0xFFFFFFFF);
  static const Color surfaceHighlight = Color(0xFFF2EFE9);

  // ── Borders ──────────────────────────────────────────────────
  static const Color border      = Color(0xFFE2DDD5);
  static const Color borderMid   = Color(0xFFCEC9BE);
  static const Color borderFocus = Color(0xFF1A1F36);

  // ── Text ─────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF1A1F36);
  static const Color textSecondary = Color(0xFF4A5180);
  static const Color textMuted     = Color(0xFF8A90A8);

  // ── Theme ────────────────────────────────────────────────────
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: surface,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: accent,
        error: error,
        surface: surface,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceElevated,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: primary.withOpacity(0.35),
          disabledForegroundColor: Colors.white54,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: borderMid, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderFocus, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error, width: 1.5),
        ),
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: textMuted),
        errorStyle: const TextStyle(color: error, fontSize: 12),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      dividerTheme:
          const DividerThemeData(color: border, thickness: 0.5),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: primary,
        contentTextStyle:
            const TextStyle(color: Colors.white, fontSize: 13),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: primary),
    );
  }

  static ThemeData get dark => light;
}