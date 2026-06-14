import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Eine gespeicherte Termin-Vorlage (Titel + optionale Felder), zur
/// Autovervollständigung beim Anlegen neuer Termine.
class EventTemplate {
  const EventTemplate({
    required this.summary,
    this.location,
    this.description,
    this.allDay = false,
    this.durationMinutes,
  });

  final String summary;
  final String? location;
  final String? description;
  final bool allDay;

  /// Dauer in Minuten (zeitgebundene Termine) – setzt beim Übernehmen das Ende.
  final int? durationMinutes;

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'location': location,
        'description': description,
        'allDay': allDay,
        'durationMinutes': durationMinutes,
      };

  factory EventTemplate.fromJson(Map<String, dynamic> j) => EventTemplate(
        summary: j['summary'] as String? ?? '',
        location: j['location'] as String?,
        description: j['description'] as String?,
        allDay: (j['allDay'] as bool?) ?? false,
        durationMinutes: (j['durationMinutes'] as num?)?.toInt(),
      );
}

/// Persistierte Termin-Vorlagen (lokal auf dem Gerät).
final eventTemplatesProvider =
    AsyncNotifierProvider<EventTemplatesController, List<EventTemplate>>(
  EventTemplatesController.new,
);

class EventTemplatesController extends AsyncNotifier<List<EventTemplate>> {
  static const _key = 'event_templates';

  @override
  Future<List<EventTemplate>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => EventTemplate.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _persist(List<EventTemplate> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(list.map((e) => e.toJson()).toList()));
    state = AsyncData(list);
  }

  /// Speichert (oder ersetzt nach Titel) eine Vorlage.
  Future<void> save(EventTemplate t) async {
    if (t.summary.trim().isEmpty) return;
    final list = List<EventTemplate>.of(state.value ?? const [])
      ..removeWhere(
          (e) => e.summary.toLowerCase() == t.summary.toLowerCase());
    list.add(t);
    list.sort((a, b) =>
        a.summary.toLowerCase().compareTo(b.summary.toLowerCase()));
    await _persist(list);
  }

  Future<void> remove(String summary) async {
    final list = List<EventTemplate>.of(state.value ?? const [])
      ..removeWhere((e) => e.summary.toLowerCase() == summary.toLowerCase());
    await _persist(list);
  }
}

/// Ob Vorlagen-Vorschläge & -Speicherung aktiv sind (Standard: an).
final templatesEnabledProvider =
    AsyncNotifierProvider<TemplatesEnabledController, bool>(
  TemplatesEnabledController.new,
);

class TemplatesEnabledController extends AsyncNotifier<bool> {
  static const _key = 'templates_enabled';

  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  Future<void> set(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
    state = AsyncData(value);
  }
}
