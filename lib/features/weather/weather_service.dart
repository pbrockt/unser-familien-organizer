import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Wetter eines Tages (aus der Open-Meteo-Tagesvorhersage).
class DayWeather {
  const DayWeather({
    required this.code,
    required this.tempMax,
    required this.tempMin,
  });
  final int code; // WMO weather code
  final double tempMax;
  final double tempMin;
}

/// Persistierte Postleitzahl fürs Wetter (leer = aus).
final weatherPlzProvider = AsyncNotifierProvider<WeatherPlzController, String>(
  WeatherPlzController.new,
);

class WeatherPlzController extends AsyncNotifier<String> {
  static const _key = 'weather_plz';

  @override
  Future<String> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) ?? '';
  }

  Future<void> set(String plz) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, plz.trim());
    state = AsyncData(plz.trim());
  }
}

/// Tages-Wettervorhersage je Datum (`yyyy-MM-dd`) für die eingestellte PLZ.
/// Ohne API-Schlüssel: PLZ→Koordinaten via zippopotam.us, Vorhersage via
/// Open-Meteo. Leere/ungültige PLZ → leere Map.
final weatherProvider = FutureProvider<Map<String, DayWeather>>((ref) async {
  final plz = (ref.watch(weatherPlzProvider).value ?? '').trim();
  if (plz.length < 4) return const {};

  try {
    final geo = await http.get(Uri.parse('https://api.zippopotam.us/de/$plz'));
    if (geo.statusCode != 200) return const {};
    final places = (jsonDecode(geo.body)['places'] as List?) ?? const [];
    if (places.isEmpty) return const {};
    final lat = places.first['latitude'];
    final lon = places.first['longitude'];

    final url =
        'https://api.open-meteo.com/v1/forecast?latitude=$lat'
        '&longitude=$lon&daily=weather_code,temperature_2m_max,'
        'temperature_2m_min&timezone=auto&forecast_days=10'
        // Deutsches DWD-ICON-Modell (europäisch/offiziell) statt Default-Mix.
        '&models=icon_seamless';
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode != 200) return const {};
    final daily = jsonDecode(resp.body)['daily'] as Map<String, dynamic>?;
    if (daily == null) return const {};

    final times = (daily['time'] as List).cast<String>();
    final codes = daily['weather_code'] as List;
    final tmax = daily['temperature_2m_max'] as List;
    final tmin = daily['temperature_2m_min'] as List;

    final out = <String, DayWeather>{};
    for (var i = 0; i < times.length; i++) {
      out[times[i]] = DayWeather(
        code: (codes[i] as num?)?.toInt() ?? 0,
        tempMax: (tmax[i] as num?)?.toDouble() ?? 0,
        tempMin: (tmin[i] as num?)?.toDouble() ?? 0,
      );
    }
    return out;
  } catch (_) {
    return const {};
  }
});

/// Emoji zu einem WMO-Wettercode (für Home-Screen-Widgets, die kein
/// Material-Icon rendern können).
String weatherEmoji(int code) {
  if (code == 0) return '☀️';
  if (code <= 2) return '🌤️'; // leicht/teilweise bewölkt
  if (code == 3) return '☁️';
  if (code == 45 || code == 48) return '🌫️';
  if (code >= 51 && code <= 67) return '🌧️'; // Niesel/Regen
  if (code >= 71 && code <= 77) return '❄️'; // Schnee
  if (code >= 80 && code <= 82) return '🌦️'; // Schauer
  if (code >= 85 && code <= 86) return '🌨️'; // Schneeschauer
  if (code >= 95) return '⛈️'; // Gewitter
  return '☁️';
}

/// Material-Icon zu einem WMO-Wettercode.
IconData weatherIcon(int code) {
  if (code == 0) return Icons.wb_sunny;
  if (code <= 2) return Icons.wb_cloudy; // leicht/teilweise bewölkt
  if (code == 3) return Icons.cloud;
  if (code == 45 || code == 48) return Icons.foggy;
  if (code >= 51 && code <= 67) return Icons.grain; // Niesel/Regen
  if (code >= 71 && code <= 77) return Icons.ac_unit; // Schnee
  if (code >= 80 && code <= 82) return Icons.umbrella; // Schauer
  if (code >= 85 && code <= 86) return Icons.ac_unit; // Schneeschauer
  if (code >= 95) return Icons.thunderstorm; // Gewitter
  return Icons.cloud;
}
