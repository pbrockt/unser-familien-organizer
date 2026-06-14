import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/theme/app_theme.dart';

/// Persistierte Akzentfarbe der App. Steuert das gesamte Farbschema.
final accentColorProvider =
    AsyncNotifierProvider<AccentColorController, Color>(
  AccentColorController.new,
);

class AccentColorController extends AsyncNotifier<Color> {
  static const _key = 'accent_color';

  @override
  Future<Color> build() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_key);
    return v == null ? AppTheme.orange : Color(v);
  }

  Future<void> set(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, color.toARGB32());
    state = AsyncData(color);
  }
}

/// Persistierte Theme-Wahl: System / Hell / Dunkel.
final themeModeProvider =
    AsyncNotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends AsyncNotifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  Future<ThemeMode> build() async {
    final prefs = await SharedPreferences.getInstance();
    return _parse(prefs.getString(_key));
  }

  Future<void> set(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
    state = AsyncData(mode);
  }

  ThemeMode _parse(String? value) => switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
