import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Lexona design system: the tokens of docs/design-language.md. Change both together.
///
/// Dark (ink and teal) is the default; light uses the same roles.
class LexonaTheme {
  LexonaTheme._();

  static ThemeMode currentThemeMode = ThemeMode.dark;

  static bool get isDark {
    if (currentThemeMode == ThemeMode.system) {
      final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      return brightness == Brightness.dark;
    }
    return currentThemeMode == ThemeMode.dark;
  }

  // ── Surfaces: dark ──
  static const Color darkBackground = Color(0xFF0B132B); // ink
  static const Color darkSurface = Color(0xFF111B36);
  static const Color darkSurfaceRaised = Color(0xFF17233F);
  static const Color darkBorder = Color(0xFF22304D);

  // ── Surfaces: light ──
  static const Color lightBackground = Color(0xFFF5F9F8);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceRaised = Color(0xFFEEF5F3);
  static const Color lightBorder = Color(0xFFD7E3E0);

  static Color get background => isDark ? darkBackground : lightBackground;
  static Color get surface => isDark ? darkSurface : lightSurface;
  static Color get surfaceRaised => isDark ? darkSurfaceRaised : lightSurfaceRaised;
  static Color get border => isDark ? darkBorder : lightBorder;
  // Older names, same roles.
  static Color get cardBg => surface;
  static Color get surfaceLight => surfaceRaised;
  static Color get surfaceBorder => border;

  // ── Brand ──
  /// Teal: the main action, the active state, progress. Takes [onPrimary] text.
  static const Color primary = Color(0xFF14B8A6);
  static const Color primaryDark = Color(0xFF0D9488);
  static const Color onPrimary = Color(0xFF04211D);
  /// Teal for text and icons, readable on the background.
  static Color get primaryText => isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E);
  /// Coral: one highlight per screen at most, never a status.
  static const Color accent = Color(0xFFFB7185);
  // Older names: a lighter teal and the teal used for secondary icons.
  static const Color primaryLight = Color(0xFF5EEAD4);
  static const Color secondary = Color(0xFF5EEAD4);

  // ── Status ──
  static Color get success => isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
  static Color get warning => isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
  static Color get error => isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  // ── Text ──
  static const Color darkTextPrimary = Color(0xFFEEF4FF);
  static const Color darkTextSecondary = Color(0xFFA7B4CC);
  static const Color darkTextMuted = Color(0xFF7584A3);
  static const Color lightTextPrimary = Color(0xFF0B132B);
  static const Color lightTextSecondary = Color(0xFF3D4B66);
  static const Color lightTextMuted = Color(0xFF5B6982);

  static Color get textPrimary => isDark ? darkTextPrimary : lightTextPrimary;
  static Color get textSecondary => isDark ? darkTextSecondary : lightTextSecondary;
  static Color get textMuted => isDark ? darkTextMuted : lightTextMuted;
  static Color get textDim => textMuted;

  // ── Gradients (background only; panels stay solid) ──
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF14B8A6), Color(0xFF0D9488)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get backgroundGradient => isDark
      ? const LinearGradient(
          colors: [Color(0xFF0B132B), Color(0xFF0A1A2E)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        )
      : const LinearGradient(
          colors: [Color(0xFFF5F9F8), Color(0xFFE9F5F2)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );

  static LinearGradient get cardGradient => LinearGradient(
        colors: [surface, surface],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  // ── Shape and space ──
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;

  static const double spaceXs = 4.0;
  static const double spaceSm = 8.0;
  static const double spaceMd = 16.0;
  static const double spaceLg = 24.0;
  static const double spaceXl = 32.0;
  static const double space2xl = 48.0;

  static const Duration fast = Duration(milliseconds: 200);
  static const Duration enter = Duration(milliseconds: 350);

  // ── Type ──
  static TextStyle get display => GoogleFonts.inter(
        fontSize: 34, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -1.0);
  static TextStyle get title => GoogleFonts.inter(
        fontSize: 24, fontWeight: FontWeight.w700, color: textPrimary, letterSpacing: -0.3);
  static TextStyle get heading => GoogleFonts.inter(
        fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary);
  static TextStyle get subheading => GoogleFonts.inter(
        fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary);
  static TextStyle get body => GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w400, color: textSecondary, height: 1.5);
  static TextStyle get caption => GoogleFonts.inter(
        fontSize: 12, fontWeight: FontWeight.w400, color: textMuted, height: 1.4);
  static TextStyle get label => GoogleFonts.inter(
        fontSize: 11, fontWeight: FontWeight.w600, color: textMuted, letterSpacing: 1.2);
  static TextStyle get mono => GoogleFonts.jetBrainsMono(
        fontSize: 13, fontWeight: FontWeight.w400, color: textPrimary);
  static TextStyle get monoSm => GoogleFonts.jetBrainsMono(
        fontSize: 11, fontWeight: FontWeight.w400, color: textMuted);

  // Older names, mapped onto the scale above.
  static TextStyle get headingXl => title.copyWith(fontSize: 30, fontWeight: FontWeight.w800);
  static TextStyle get headingLg => title;
  static TextStyle get headingMd => heading;
  static TextStyle get headingSm => subheading;
  static TextStyle get bodyLg => body.copyWith(fontSize: 16, height: 1.6);
  static TextStyle get bodyMd => body;
  static TextStyle get bodySm => caption;

  // ── ThemeData ──
  static ThemeData get darkThemeData => _buildThemeData(brightness: Brightness.dark);
  static ThemeData get lightThemeData => _buildThemeData(brightness: Brightness.light);
  static ThemeData get themeData => isDark ? darkThemeData : lightThemeData;

  static ThemeData _buildThemeData({required Brightness brightness}) {
    final dark = brightness == Brightness.dark;
    final bg = dark ? darkBackground : lightBackground;
    final surf = dark ? darkSurface : lightSurface;
    final raised = dark ? darkSurfaceRaised : lightSurfaceRaised;
    final line = dark ? darkBorder : lightBorder;
    final text = dark ? darkTextPrimary : lightTextPrimary;
    final muted = dark ? darkTextMuted : lightTextMuted;
    final teal = dark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E);
    final err = dark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
    final buttonText = GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600);
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd));

    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      primaryColor: primary,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: onPrimary,
        secondary: teal,
        onSecondary: onPrimary,
        tertiary: accent,
        surface: surf,
        onSurface: text,
        surfaceContainerHighest: raised,
        outline: line,
        error: err,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: bg,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light.copyWith(statusBarColor: bg)
            : SystemUiOverlayStyle.dark.copyWith(statusBarColor: bg),
        titleTextStyle: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600, color: text),
        iconTheme: IconThemeData(color: text),
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      tabBarTheme: TabBarThemeData(labelColor: teal, unselectedLabelColor: muted, indicatorColor: primary),
      cardTheme: CardThemeData(
        color: surf,
        surfaceTintColor: surf,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: line),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surf,
        surfaceTintColor: surf,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: line),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surf,
        surfaceTintColor: surf,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: raised,
        contentTextStyle: GoogleFonts.inter(fontSize: 14, color: text),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary, linearTrackColor: raised),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? onPrimary : muted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? primary : raised),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? primary : muted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: teal,
          side: const BorderSide(color: primary),
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: teal, textStyle: buttonText),
      ),
    );
  }
}
