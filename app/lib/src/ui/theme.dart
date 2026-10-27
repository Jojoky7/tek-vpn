import 'package:flutter/material.dart';

/// Tek's look: calm neutrals and one green that means "protected".
class TekColors {
  static const green = Color(0xFF19C37D);
  static const greenDark = Color(0xFF0E9F63);
  static const amber = Color(0xFFF5A524);
  static const red = Color(0xFFF04D4D);
  static const grey = Color(0xFF9AA3AF);
}

ThemeData tekTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final background = dark ? const Color(0xFF0E1116) : const Color(0xFFF5F6F8);
  final surface = dark ? const Color(0xFF171B22) : Colors.white;
  final onSurface = dark ? const Color(0xFFF2F4F7) : const Color(0xFF11151C);
  final muted = dark ? const Color(0xFF8B93A1) : const Color(0xFF6B7280);
  final outline = dark ? const Color(0xFF262C36) : const Color(0xFFE4E7EC);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: TekColors.green,
    onPrimary: Colors.white,
    secondary: TekColors.green,
    onSecondary: Colors.white,
    error: TekColors.red,
    onError: Colors.white,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: muted,
    outline: outline,
    outlineVariant: outline,
    surfaceContainerHighest: dark ? const Color(0xFF1E232C) : const Color(0xFFF0F2F5),
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: background,
    fontFamily: null,
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          color: onSurface, fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.2),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: outline),
      ),
    ),
    dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: muted,
      subtitleTextStyle: TextStyle(color: muted, fontSize: 13, height: 1.3),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? TekColors.green : null),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: TekColors.green,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: onSurface,
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: TekColors.green, width: 1.5),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF2A303B) : const Color(0xFF1F2430),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: background,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
  );
}
