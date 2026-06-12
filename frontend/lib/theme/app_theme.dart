import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Paleta base (compartilhada) ───────────────────────────────
  static const Color primary      = Color(0xFFFF781F);
  static const Color primaryDark  = Color(0xFFDC5800);
  static const Color primaryLight = Color(0xFFFF9A52);
  static const Color accent       = Color(0xFFDC5800);
  static const Color accentLight  = Color(0xFFFF781F);

  static const Color error   = Color(0xFFCC2200);
  static const Color success = Color(0xFF1E7E34);
  static const Color warning = Color(0xFFF59E0B);

  static const Color statusOk      = Color(0xFF16A34A);
  static const Color statusBaixo   = Color(0xFFD97706);
  static const Color statusCritico = Color(0xFFDC2626);

  // ── Paleta light ──────────────────────────────────────────────
  static const Color black          = Color(0xFF201E1E);
  static const Color background     = Color(0xFFF7F4F2);
  static const Color surface        = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF2EDE9);
  static const Color textPrimary    = Color(0xFF201E1E);
  static const Color textSecondary  = Color(0xFF5C524D);
  static const Color textHint       = Color(0xFFAA9E97);
  static const Color divider        = Color(0xFFE8DDD6);
  static const Color sidebar        = Color(0xFF201E1E);
  static const Color sidebarActive  = Color(0xFF2E2A2A);

  // ── Paleta dark ───────────────────────────────────────────────
  static const Color darkBackground     = Color(0xFF141212);
  static const Color darkSurface        = Color(0xFF1E1B1B);
  static const Color darkSurfaceVariant = Color(0xFF2A2626);
  static const Color darkTextPrimary    = Color(0xFFF0EBE8);
  static const Color darkTextSecondary  = Color(0xFFAA9E97);
  static const Color darkTextHint       = Color(0xFF8A7D76);
  static const Color darkDivider        = Color(0xFF2E2926);
  static const Color darkSidebar        = Color(0xFF0F0D0D);
  static const Color darkSidebarActive  = Color(0xFF1A1717);

  // ── Temas públicos ────────────────────────────────────────────
  static ThemeData get light => _buildTheme(Brightness.light);
  static ThemeData get dark  => _buildTheme(Brightness.dark);

  /// Alias legado
  static ThemeData get theme => light;

  // ─────────────────────────────────────────────────────────────
  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final bg            = isDark ? darkBackground     : background;
    final surf          = isDark ? darkSurface        : surface;
    final surfVar       = isDark ? darkSurfaceVariant : surfaceVariant;
    final txtPrimary    = isDark ? darkTextPrimary    : textPrimary;
    final txtSecondary  = isDark ? darkTextSecondary  : textSecondary;
    final txtHint       = isDark ? darkTextHint       : textHint;
    final div           = isDark ? darkDivider        : divider;

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: Colors.white,
        primaryContainer: primaryDark,
        onPrimaryContainer: Colors.white,
        secondary: accent,
        onSecondary: Colors.white,
        secondaryContainer: isDark ? const Color(0xFF3D1F00) : accentLight,
        onSecondaryContainer: isDark ? primaryLight : Colors.white,
        error: error,
        onError: Colors.white,
        errorContainer: isDark ? const Color(0xFF4D1000) : const Color(0xFFFFDAD6),
        onErrorContainer: isDark ? const Color(0xFFFFB4A2) : error,
        surface: surf,
        onSurface: txtPrimary,
        surfaceContainerHighest: surfVar,
        onSurfaceVariant: txtSecondary,
        outline: isDark ? darkTextHint : textHint,
        outlineVariant: div,
        shadow: isDark ? const Color(0x40000000) : const Color(0x1A201E1E),
        scrim: const Color(0x80000000),
        inverseSurface: isDark ? const Color(0xFFF0EBE8) : black,
        onInverseSurface: isDark ? black : Colors.white,
        inversePrimary: accentLight,
        surfaceTint: primary,
      ),
      textTheme: GoogleFonts.nunitoTextTheme().copyWith(
        displayLarge: GoogleFonts.raleway(
          fontSize: 32, fontWeight: FontWeight.w700,
          color: txtPrimary, letterSpacing: -0.5,
        ),
        displayMedium: GoogleFonts.raleway(
          fontSize: 26, fontWeight: FontWeight.w700,
          color: txtPrimary, letterSpacing: -0.3,
        ),
        headlineLarge: GoogleFonts.raleway(
          fontSize: 22, fontWeight: FontWeight.w700, color: txtPrimary,
        ),
        headlineMedium: GoogleFonts.raleway(
          fontSize: 18, fontWeight: FontWeight.w600, color: txtPrimary,
        ),
        headlineSmall: GoogleFonts.raleway(
          fontSize: 16, fontWeight: FontWeight.w600, color: txtPrimary,
        ),
        titleLarge: GoogleFonts.nunito(
          fontSize: 15, fontWeight: FontWeight.w700, color: txtPrimary,
        ),
        titleMedium: GoogleFonts.nunito(
          fontSize: 14, fontWeight: FontWeight.w600, color: txtPrimary,
        ),
        bodyLarge:  GoogleFonts.nunito(fontSize: 15, color: txtPrimary),
        bodyMedium: GoogleFonts.nunito(fontSize: 14, color: txtSecondary),
        bodySmall:  GoogleFonts.nunito(fontSize: 12, color: txtHint),
        labelLarge: GoogleFonts.nunito(
          fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5,
          color: txtPrimary,
        ),
      ),
      scaffoldBackgroundColor: bg,
      appBarTheme: AppBarTheme(
        backgroundColor: surf,
        foregroundColor: txtPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: isDark ? const Color(0x40000000) : const Color(0x1A201E1E),
        titleTextStyle: GoogleFonts.raleway(
          fontSize: 18, fontWeight: FontWeight.w700, color: txtPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: surf,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: div, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfVar,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: div),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: div),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: error),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle:         GoogleFonts.nunito(color: txtSecondary, fontSize: 14),
        floatingLabelStyle: GoogleFonts.nunito(color: primary,      fontSize: 12),
        hintStyle:          GoogleFonts.nunito(color: txtHint,      fontSize: 14),
      ),
      dividerTheme: DividerThemeData(color: div, space: 1, thickness: 1),
      chipTheme: ChipThemeData(
        backgroundColor: surfVar,
        labelStyle: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w600,
            color: txtPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? const Color(0xFF2A2626) : black,
        contentTextStyle: GoogleFonts.nunito(color: Colors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surf,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: GoogleFonts.raleway(
          fontSize: 18, fontWeight: FontWeight.w700, color: txtPrimary,
        ),
      ),
    );
  }
}