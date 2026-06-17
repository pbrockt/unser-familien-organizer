import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ein benanntes Filter-Preset: zeigt nur die enthaltenen Kalender an
/// (z. B. „Arbeit"). Gerätelokal gespeichert.
class CalendarPreset {
  const CalendarPreset({required this.name, required this.visibleHrefs});

  final String name;
  final Set<String> visibleHrefs;

  Map<String, dynamic> toJson() =>
      {'name': name, 'hrefs': visibleHrefs.toList()};

  factory CalendarPreset.fromJson(Map<String, dynamic> j) => CalendarPreset(
        name: j['name'] as String? ?? '',
        visibleHrefs: ((j['hrefs'] as List?) ?? const [])
            .map((e) => e.toString())
            .toSet(),
      );
}

/// Persistierte Filter-Presets für die Kalenderansicht.
final calendarPresetsProvider =
    AsyncNotifierProvider<CalendarPresetsController, List<CalendarPreset>>(
  CalendarPresetsController.new,
);

class CalendarPresetsController extends AsyncNotifier<List<CalendarPreset>> {
  static const _key = 'calendar_presets';

  @override
  Future<List<CalendarPreset>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => CalendarPreset.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<CalendarPreset> presets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(presets.map((p) => p.toJson()).toList()),
    );
    state = AsyncData(presets);
  }

  /// Legt ein Preset an oder überschreibt eines mit gleichem Namen.
  Future<void> addOrUpdate(String name, Set<String> visibleHrefs) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final current = List<CalendarPreset>.of(state.value ?? const [])
      ..removeWhere((p) => p.name.toLowerCase() == trimmed.toLowerCase());
    current.add(CalendarPreset(name: trimmed, visibleHrefs: visibleHrefs));
    current
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await _save(current);
  }

  Future<void> remove(String name) async {
    final current = List<CalendarPreset>.of(state.value ?? const [])
      ..removeWhere((p) => p.name == name);
    await _save(current);
  }
}
