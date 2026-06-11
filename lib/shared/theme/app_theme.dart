import 'package:flutter/material.dart';

/// Zentrales App-Theme im Planily/FamilyWall-Stil: freundlich, klar,
/// kartenbasiert mit weichen, runden Flächen.
class AppTheme {
  AppTheme._();

  /// Marken-/Akzentfarbe (modernes Violett). Familienmitglieder bekommen
  /// eigene Farben (siehe [familyColors]).
  static const Color seed = Color(0xFF6C5CE7);

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final isLight = brightness == Brightness.light;
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor:
          isLight ? const Color(0xFFF6F5FB) : scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: isLight ? const Color(0xFFF6F5FB) : scheme.surface,
        scrolledUnderElevation: 0,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isLight ? Colors.white : scheme.surfaceContainerHigh,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isLight ? Colors.white : scheme.surfaceContainer,
        elevation: 3,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  /// Vorschlags-Palette für Familienmitglieder / Kalender ohne eigene Farbe.
  static const List<Color> familyColors = [
    Color(0xFFEF5350), // rot
    Color(0xFF42A5F5), // blau
    Color(0xFF66BB6A), // grün
    Color(0xFFFFA726), // orange
    Color(0xFFAB47BC), // lila
    Color(0xFF26C6DA), // türkis
    Color(0xFFEC407A), // pink
    Color(0xFF8D6E63), // braun
  ];
}
