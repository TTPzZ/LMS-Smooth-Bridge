import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color _ink = Color(0xFF10223D);
  static const Color _mutedInk = Color(0xFF5A6882);
  static const Color _surface = Color(0xFFF4F7FC);
  static const Color _card = Color(0xFFFFFFFF);
  static const Color _brand = Color(0xFF1C4ED8);
  static const Color _success = Color(0xFF0F9D58);
  static const Color _danger = Color(0xFFC62828);
  static const List<String> _fontFallback = <String>[
    'Noto Sans',
    'Roboto',
    'Arial',
    'sans-serif',
  ];

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: _brand,
      onPrimary: Colors.white,
      secondary: Color(0xFF00A3A3),
      onSecondary: Colors.white,
      error: _danger,
      onError: Colors.white,
      surface: _card,
      onSurface: _ink,
    );

    final textTheme = GoogleFonts.manropeTextTheme().copyWith(
      headlineSmall: GoogleFonts.manrope(
        fontWeight: FontWeight.w800,
        fontSize: 24,
        color: _ink,
      ).copyWith(
        fontFamilyFallback: _fontFallback,
      ),
      titleLarge: GoogleFonts.manrope(
        fontWeight: FontWeight.w700,
        fontSize: 20,
        color: _ink,
      ).copyWith(
        fontFamilyFallback: _fontFallback,
      ),
      titleMedium: GoogleFonts.manrope(
        fontWeight: FontWeight.w700,
        fontSize: 16,
        color: _ink,
      ).copyWith(
        fontFamilyFallback: _fontFallback,
      ),
      bodyLarge: GoogleFonts.manrope(
        fontWeight: FontWeight.w500,
        fontSize: 15,
        color: _ink,
      ).copyWith(
        fontFamilyFallback: _fontFallback,
      ),
      bodyMedium: GoogleFonts.manrope(
        fontWeight: FontWeight.w500,
        fontSize: 14,
        color: _ink,
      ).copyWith(
        fontFamilyFallback: _fontFallback,
      ),
      bodySmall: GoogleFonts.manrope(
        fontWeight: FontWeight.w500,
        fontSize: 12,
        color: _mutedInk,
      ).copyWith(
        fontFamilyFallback: _fontFallback,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _surface,
      fontFamilyFallback: _fontFallback,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: _surface,
        foregroundColor: _ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: _card,
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.blueGrey.shade50),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.blueGrey.shade100),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.blueGrey.shade100),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _brand, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: textTheme.titleMedium?.copyWith(
            fontSize: 14,
            color: Colors.white,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: BorderSide(color: Colors.blueGrey.shade200),
          textStyle: textTheme.titleMedium?.copyWith(fontSize: 14),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFEAF0FF),
        selectedColor: const Color(0xFFD6E3FF),
        secondarySelectedColor: const Color(0xFFD6E3FF),
        disabledColor: Colors.blueGrey.shade100,
        labelStyle: textTheme.bodySmall!.copyWith(
          fontWeight: FontWeight.w700,
          color: _ink,
        ),
        secondaryLabelStyle: textTheme.bodySmall!.copyWith(
          fontWeight: FontWeight.w700,
          color: _ink,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        brightness: Brightness.light,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFD9E5FF),
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: _ink,
            );
          }
          return textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: _mutedInk,
          );
        }),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: DividerThemeData(
        color: Colors.blueGrey.shade100,
        thickness: 1,
      ),
      extensions: const <ThemeExtension<dynamic>>[
        AppAccentColors(
          ink: _ink,
          mutedInk: _mutedInk,
          success: _success,
          warning: Color(0xFFE89100),
        ),
      ],
    );
  }
}

@immutable
class AppAccentColors extends ThemeExtension<AppAccentColors> {
  final Color ink;
  final Color mutedInk;
  final Color success;
  final Color warning;

  const AppAccentColors({
    required this.ink,
    required this.mutedInk,
    required this.success,
    required this.warning,
  });

  @override
  AppAccentColors copyWith({
    Color? ink,
    Color? mutedInk,
    Color? success,
    Color? warning,
  }) {
    return AppAccentColors(
      ink: ink ?? this.ink,
      mutedInk: mutedInk ?? this.mutedInk,
      success: success ?? this.success,
      warning: warning ?? this.warning,
    );
  }

  @override
  AppAccentColors lerp(ThemeExtension<AppAccentColors>? other, double t) {
    if (other is! AppAccentColors) {
      return this;
    }
    return AppAccentColors(
      ink: Color.lerp(ink, other.ink, t) ?? ink,
      mutedInk: Color.lerp(mutedInk, other.mutedInk, t) ?? mutedInk,
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
    );
  }
}
