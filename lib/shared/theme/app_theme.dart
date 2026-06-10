import 'package:flutter/material.dart';

/// Zentrales App-Theme im Planily/FamilyWall-Stil: freundlich, klar, fokussiert.
class AppTheme {
  AppTheme._();

  /// Akzentfarbe der App. Familienmitglieder bekommen später eigene Farben
  /// (siehe [familyColors]), das hier ist die Marken-/UI-Farbe.
  static const Color seed = Color(0xFF4C6FFF);

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      appBarTheme: const AppBarTheme(centerTitle: false),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  /// Vorschlags-Palette für Familienmitglieder. Wird in Phase 7
  /// (Familiengruppen) genutzt, um Personen/Kalender farblich zu trennen.
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
