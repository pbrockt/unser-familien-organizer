import 'package:flutter/material.dart';

/// App-Theme im warmen „Planily"-Stil: cremefarbener Hintergrund, Orange als
/// Akzent, braune Schrift, weiche runde weiße Karten.
class AppTheme {
  AppTheme._();

  // Kernfarben.
  static const Color orange = Color(0xFFE8964F); // Akzent
  static const Color cream = Color(0xFFF3EEE4); // Hintergrund
  static const Color brown = Color(0xFF3E322A); // Text
  static const Color brownSoft = Color(0xFF8C7F73); // Sekundärtext
  static const Color peach = Color(0xFFF7DEC2); // Icon-Chips

  // Dekorative Blob-/Mitgliederfarben.
  static const Color sage = Color(0xFFA9C29B);
  static const Color sky = Color(0xFFAFC6DD);
  static const Color terracotta = Color(0xFFD89B79);

  /// Akzentfarbe (für Code, der noch `seed` referenziert).
  static const Color seed = orange;

  /// Pastell-Akzentfarben zur Auswahl (Einstellungen). Erste = Standard.
  static const List<Color> accentChoices = [
    orange, // warmes Orange (Standard)
    sage, // Salbeigrün
    sky, // Himmelblau
    terracotta, // Terracotta
    Color(0xFFB59BD0), // Lavendel
    Color(0xFFE8A0B6), // Rosé
    Color(0xFF7FB6A8), // Petrol
    Color(0xFFD9B362), // Senf
  ];

  /// Lesbare Vordergrundfarbe (schwarz/weiß) für eine Akzentfläche.
  static Color _onColor(Color c) =>
      ThemeData.estimateBrightnessForColor(c) == Brightness.dark
      ? Colors.white
      : Colors.black;

  static ThemeData light({Color seed = orange}) {
    // Container-/Sekundärtöne aus dem Seed ableiten → der Akzent ist überall
    // einheitlich (auch der Menü-Indikator), in weichem Pastell.
    final base = ColorScheme.fromSeed(seedColor: seed);
    final scheme = base.copyWith(
      primary: seed,
      onPrimary: _onColor(seed),
      surface: cream,
      onSurface: brown,
      onSurfaceVariant: brownSoft,
      outline: const Color(0xFFE0D6C6),
      outlineVariant: const Color(0xFFEBE3D6),
    );
    return _build(scheme, isLight: true, scaffold: cream, card: Colors.white);
  }

  static ThemeData dark({Color seed = orange, bool amoled = false}) {
    final bg = amoled ? const Color(0xFF000000) : const Color(0xFF241F1B);
    final card = amoled ? const Color(0xFF121212) : const Color(0xFF2E2823);
    final base = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    final scheme = base.copyWith(
      primary: seed,
      onPrimary: _onColor(seed),
      surface: bg,
      onSurface: const Color(0xFFEDE6DC),
      onSurfaceVariant: const Color(0xFFB6A99B),
    );
    return _build(scheme, isLight: false, scaffold: bg, card: card);
  }

  static ThemeData _build(
    ColorScheme scheme, {
    required bool isLight,
    required Color scaffold,
    required Color card,
  }) {
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scaffold,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scaffold,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: card,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.10),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isLight ? Colors.white : scheme.surfaceContainerHigh,
        elevation: 3,
        height: 68,
        surfaceTintColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  /// Vorschlags-Palette für Familienmitglieder / Kalender ohne eigene Farbe.
  static const List<Color> familyColors = [
    Color(0xFFEF5350),
    Color(0xFF42A5F5),
    Color(0xFF66BB6A),
    Color(0xFFFFA726),
    Color(0xFFAB47BC),
    Color(0xFF26C6DA),
    Color(0xFFEC407A),
    Color(0xFF8D6E63),
  ];
}
